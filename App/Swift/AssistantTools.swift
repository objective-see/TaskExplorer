//
//  AssistantTools.swift
//  TaskExplorer (app)
//
//  Created by Patrick Wardle on 9/12/26.
//  Copyright (c) 2026 Objective-See. All rights reserved.
//
//  note: tools the in-app assistant (LLM) can call: read-only queries over the live model, plus a few UI actions
//        ...also served by the (DEBUG-only) MCP test server, which drives automated UI testing

import AppKit
import Foundation
import os

//a tool (name, description, JSON schema for its input)
struct AssistantTool {
    let name: String
    let description: String
    let schema: [String: Any]

    //as (MCP-style) dictionary
    var dictionary: [String: Any] { ["name": name, "description": description, "inputSchema": schema] }
}

//tool error
struct AssistantToolError: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum AssistantTools {

    //max rows (unless caller asks for more)
    static let defaultLimit = 200

    //all tools
    static let all: [AssistantTool] = [
        AssistantTool(name: "list_processes",
                description: "List running processes. Optional text filter (matches name or path, case-insensitive) and/or #keyword filters (see list_keywords, e.g. '#3rdparty', '#adhoc', '#network', '#flagged'). Returns pid, ppid, name, path, user, signer, team id, VirusTotal result, and counts of dylibs/connections.",
                schema: schema(["filter": ["type": "string", "description": "Text to match against process name or path"],
                                "keywords": ["type": "array", "items": ["type": "string"], "description": "#keyword filters; all must match"],
                                "limit": ["type": "integer", "description": "Max results (default \(defaultLimit))"]])),
        AssistantTool(name: "get_process",
                description: "Get full details for one process by pid: binary/signing info, hashes, arguments, start time, parent, children, plus all loaded dylibs, open files, and network connections.",
                schema: schema(["pid": ["type": "integer", "description": "Process id"]], required: ["pid"])),
        AssistantTool(name: "list_dylibs",
                description: "List loaded dylibs (across all processes, or for one pid). Optional text and #keyword filters. Each result includes which pids have it loaded. Note: dylibs from the dyld shared cache (inDyldCache) are only attributed to processes when shared-cache indexing is enabled (see get_status); otherwise only dylibs mapped from disk are listed.",
                schema: schema(["pid": ["type": "integer", "description": "Only dylibs loaded in this process"],
                                "filter": ["type": "string", "description": "Text to match against dylib name or path"],
                                "keywords": ["type": "array", "items": ["type": "string"], "description": "#keyword filters (e.g. '#3rdparty', '#adhoc', '#obfuscated')"],
                                "limit": ["type": "integer"]])),
        AssistantTool(name: "list_files",
                description: "List open files (across all processes, or for one pid), with the pids that have each open.",
                schema: schema(["pid": ["type": "integer"],
                                "filter": ["type": "string", "description": "Text to match against file path"],
                                "limit": ["type": "integer"]])),
        AssistantTool(name: "list_connections",
                description: "List network connections (across all processes, or for one pid). Optional state filter (e.g. 'listening', 'established') and text filter (matches addresses, ports, protocol, interface).",
                schema: schema(["pid": ["type": "integer"],
                                "state": ["type": "string", "description": "e.g. listening, established"],
                                "filter": ["type": "string"],
                                "limit": ["type": "integer"]])),
        AssistantTool(name: "list_flagged",
                description: "List all processes and dylibs flagged (detected) by VirusTotal.",
                schema: schema([:])),
        AssistantTool(name: "list_keywords",
                description: "List the available #keyword filters and what each matches.",
                schema: schema([:])),
        AssistantTool(name: "get_status",
                description: "Get TaskExplorer's status: process/dylib counts, enumeration state, whether live (Endpoint Security) monitoring is active, and whether VirusTotal lookups are enabled.",
                schema: schema([:])),
        AssistantTool(name: "ui_select_process",
                description: "Select a process in the TaskExplorer UI (and show its details in the inspector).",
                schema: schema(["pid": ["type": "integer"]], required: ["pid"])),
        AssistantTool(name: "ui_set_filter",
                description: "Set the process filter in the TaskExplorer UI: free text and/or #keyword tokens. Pass empty values to clear.",
                schema: schema(["filter": ["type": "string"],
                                "keywords": ["type": "array", "items": ["type": "string"]]])),
        AssistantTool(name: "ui_set_view",
                description: "Switch the TaskExplorer process list between a flat list and a hierarchical (parent/child) tree.",
                schema: schema(["view": ["type": "string", "enum": ["flat", "tree"]]], required: ["view"])),
        AssistantTool(name: "ui_show_tab",
                description: "Switch the bottom pane of the TaskExplorer UI to dylibs, files, or network.",
                schema: schema(["tab": ["type": "string", "enum": ["dylibs", "files", "network"]]], required: ["tab"]))
    ]

    //json schema helper
    private static func schema(_ properties: [String: Any], required: [String] = []) -> [String: Any] {
        var dict: [String: Any] = ["type": "object", "properties": properties]
        if !required.isEmpty { dict["required"] = required }
        return dict
    }

    //invoke a tool
    // ->always on main actor (model is main-thread mutated)
    //keywords that only apply to processes (their predicates use task-only keys)
    static let processOnlyKeywords: Set<String> = ["#network", "#listening", "#root"]

    @MainActor static func call(_ name: String, arguments: [String: Any]) throws -> Any {
        guard let enumerator = taskEnumerator else { throw AssistantToolError(message: "TaskExplorer is still starting up (no data yet)") }
        let store = Store.shared
        let filter = store.filter
        let limit = min(max((arguments["limit"] as? Int) ?? defaultLimit, 0), 5000)
        let text = (arguments["filter"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        let keywords = ((arguments["keywords"] as? [String]) ?? []).map { $0.hasPrefix("#") ? $0.lowercased() : "#" + $0.lowercased() }
        for keyword in keywords where !filter.isKeyword(keyword) {
            throw AssistantToolError(message: "unknown keyword '\(keyword)'; use list_keywords")
        }

        switch name {

        case "list_processes":
            var tasks = (enumerator.allTasks() as? [TETask]) ?? []
            tasks = tasks.filter { task in
                for k in keywords where !filter.taskFulfillsKeyword(k, task: task) { return false }
                if text.isEmpty { return true }
                return (task.binary.name ?? "").localizedCaseInsensitiveContains(text) || (task.binary.path ?? "").localizedCaseInsensitiveContains(text) || task.pid.stringValue == text
            }
            tasks.sort { $0.pid.intValue < $1.pid.intValue }
            return ["count": tasks.count, "processes": tasks.prefix(limit).map { summary($0) }]

        case "get_process":
            guard let pid = arguments["pid"] as? Int else { throw AssistantToolError(message: "'pid' is required") }
            guard let task = (enumerator.allTasks() as? [TETask])?.first(where: { $0.pid.intValue == pid }) else {
                throw AssistantToolError(message: "no process with pid \(pid)")
            }
            var dict = JSONExport.process(task)
            dict["children"] = (task.childrenSnapshot() as? [NSNumber] ?? []).map { $0.intValue }
            if let parent = (enumerator.allTasks() as? [TETask])?.first(where: { $0.pid == task.ppid }) {
                dict["parent"] = ["pid": parent.pid.intValue, "name": parent.binary.name ?? ""]
            }
            dict["dylibs"] = (task.dylibsSnapshot() ?? []).map { dylib($0) }
            dict["mismatchedDylibs"] = (task.mismatchedDylibs as? [Binary] ?? []).map { $0.path ?? "" }
            return dict

        case "list_dylibs":
            //note: some keywords only make sense for processes (evaluated against a dylib they'd silently match nothing)
            if let bad = keywords.first(where: { AssistantTools.processOnlyKeywords.contains($0) }) {
                throw AssistantToolError(message: "keyword '\(bad)' applies to processes, not dylibs (see list_keywords)")
            }
            var binaries: [Binary]
            if let pid = arguments["pid"] as? Int {
                guard let task = (enumerator.allTasks() as? [TETask])?.first(where: { $0.pid.intValue == pid }) else { throw AssistantToolError(message: "no process with pid \(pid)") }
                binaries = (task.dylibsSnapshot()) ?? []
            } else {
                binaries = (enumerator.allDylibs() as? [Binary]) ?? []
            }
            binaries = binaries.filter { binary in
                for k in keywords where !filter.binaryFulfillsKeyword(k, binary: binary) { return false }
                if text.isEmpty { return true }
                return (binary.name ?? "").localizedCaseInsensitiveContains(text) || (binary.path ?? "").localizedCaseInsensitiveContains(text)
            }
            binaries.sort { ($0.path ?? "") < ($1.path ?? "") }
            return ["count": binaries.count, "dylibs": binaries.prefix(limit).map { dylib($0) }]

        case "list_files":
            var files: [File]
            if let pid = arguments["pid"] as? Int {
                guard let task = (enumerator.allTasks() as? [TETask])?.first(where: { $0.pid.intValue == pid }) else { throw AssistantToolError(message: "no process with pid \(pid)") }
                files = (task.filesSnapshot()) ?? []
            } else {
                files = (enumerator.allFiles() as? [File]) ?? []
            }
            if !text.isEmpty { files = files.filter { ($0.path ?? "").localizedCaseInsensitiveContains(text) } }
            files.sort { ($0.path ?? "") < ($1.path ?? "") }
            return ["count": files.count, "files": files.prefix(limit).map { file in
                ["path": file.path ?? "", "type": file.type ?? FILE_TYPE_UNKNOWN, "openIn": (file.hostTasks() ?? []).map { ["pid": $0.pid.intValue, "name": $0.binary.name ?? ""] }]
            }]

        case "list_connections":
            var rows: [(TETask, Connection)] = []
            let tasks = (enumerator.allTasks() as? [TETask]) ?? []
            for task in tasks {
                if let pid = arguments["pid"] as? Int, task.pid.intValue != pid { continue }
                for c in task.connectionsSnapshot() ?? [] { rows.append((task, c)) }
            }
            if let state = (arguments["state"] as? String)?.lowercased(), !state.isEmpty {
                rows = rows.filter { ($0.1.state ?? "").lowercased() == state }
            }
            if !text.isEmpty {
                rows = rows.filter { String($0.1.endpoints ?? "").localizedCaseInsensitiveContains(text) || ($0.1.proto ?? "").localizedCaseInsensitiveContains(text) || ($0.1.interface ?? "").localizedCaseInsensitiveContains(text) || ($0.1.state ?? "").localizedCaseInsensitiveContains(text) }
            }
            return ["count": rows.count, "connections": rows.prefix(limit).map { task, c in
                var dict = JSONExport.connection(c)
                dict["pid"] = task.pid.intValue
                dict["process"] = task.binary.name ?? ""
                return dict
            }]

        case "list_flagged":
            let flagged = (enumerator.flaggedItemsSnapshot() as? [Binary]) ?? []
            return ["count": flagged.count, "flagged": flagged.map { binary in
                var dict = dylib(binary)
                dict["kind"] = binary.isTaskBinary ? "process" : "dylib"
                return dict
            }]

        case "list_keywords":
            return ["keywords": store.keywords.map { ["keyword": $0, "description": filter.keywordDescription($0) ?? "", "appliesTo": AssistantTools.processOnlyKeywords.contains($0) ? ["process"] : ["process", "dylib"]] }]

        case "get_status":
            return ["processes": enumerator.allTasks().count,
                    "dylibs": enumerator.allDylibs().count,
                    "files": enumerator.allFiles().count,
                    "connections": enumerator.allConnections().count,
                    "flagged": enumerator.flaggedItemsSnapshot().count,
                    "enumerationState": stateName(Int(enumerator.state)),
                    "monitoring": enumerator.isMonitoring,
                    "sharedCacheDylibsIndexed": getPreferenceBool(PREF_INDEX_CACHE_DYLIBS) && enumerator.cacheIndexComplete && !enumerator.cacheIndexing,
                    "sharedCacheDylibsIndexing": enumerator.cacheIndexing,
                    "virusTotalEnabled": virusTotal?.isEnabled() ?? false,
                    "version": getAppVersion() ?? ""]

        case "ui_select_process":
            guard let pid = arguments["pid"] as? Int else { throw AssistantToolError(message: "'pid' is required") }
            guard store.process(pid) != nil else { throw AssistantToolError(message: "no process with pid \(pid)") }
            store.scope = .processes
            store.select(pid: pid)
            store.showInspector = true
            return ["ok": true]

        case "ui_set_filter":
            store.scope = .processes
            store.query = text
            store.applyQueryNow()
            store.tokens = Array(NSOrderedSet(array: keywords)).compactMap { $0 as? String }.map { FilterToken(keyword: $0) }
            return ["ok": true, "matching": store.visibleProcesses.count]

        case "ui_set_view":
            switch (arguments["view"] as? String)?.lowercased() {
            case "flat": store.viewMode = .flat
            case "tree": store.viewMode = .tree
            default: throw AssistantToolError(message: "'view' must be flat or tree")
            }
            return ["ok": true]

        case "ui_show_tab":
            switch (arguments["tab"] as? String)?.lowercased() {
            case "dylibs": store.itemsTab = .dylibs
            case "files": store.itemsTab = .files
            case "network": store.itemsTab = .network
            default: throw AssistantToolError(message: "'tab' must be dylibs, files, or network")
            }
            return ["ok": true]

        default:
            throw AssistantToolError(message: "unknown tool '\(name)'")
        }
    }

    //process summary
    private static func summary(_ task: TETask) -> [String: Any] {
        let vt = VTStatus.from(task.binary)
        var dict: [String: Any] = ["pid": task.pid.intValue,
                                   "ppid": task.ppid?.intValue ?? 0,
                                   "name": task.binary.name ?? "",
                                   "path": task.binary.path ?? "",
                                   "user": userName(for: task.uid),
                                   "signer": task.binary.isApple ? "Apple" : (SignerKind(rawValue: task.binary.signer?.intValue ?? 0) ?? .none).label,
                                   "teamID": task.teamID ?? "",
                                   "platformBinary": task.isPlatformBinary,
                                   "esClient": task.isESClient,
                                   "dylibs": task.dylibsSnapshot().count,
                                   "connections": task.connectionsSnapshot().count]
        if case .known(let positives, let total, let url) = vt { dict["virusTotal"] = ["positives": positives, "total": total, "report": url] }
        else if vt == .skipped { dict["virusTotal"] = "skipped (Apple/platform binary)" }
        else if vt == .error { dict["virusTotal"] = "error" }
        else if vt != .disabled { dict["virusTotal"] = vt == .unknown ? "unknown" : "pending" }
        return dict
    }

    //dylib summary
    private static func dylib(_ binary: Binary) -> [String: Any] {
        var dict = JSONExport.binary(binary: binary, hosts: true)
        dict["loadedIn"] = (binary.hostTasks() ?? []).map { ["pid": $0.pid.intValue, "name": $0.binary.name ?? ""] }
        return dict
    }

    //enumeration state name
    private static func stateName(_ state: Int) -> String {
        switch state {
        case Int(ENUMERATION_STATE_TASKS): return "enumerating processes"
        case Int(ENUMERATION_STATE_DYLIBS): return "enumerating dylibs"
        case Int(ENUMERATION_STATE_FILES): return "enumerating files"
        case Int(ENUMERATION_STATE_NETWORK): return "enumerating network"
        case Int(ENUMERATION_STATE_COMPLETE): return "complete"
        default: return "idle"
        }
    }

    //result -> text (for tool result content)
    static func text(_ result: Any) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), let string = String(data: data, encoding: .utf8) {
            return string
        }
        return "\(result)"
    }
}
