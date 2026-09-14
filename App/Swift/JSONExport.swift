//
//  JSONExport.swift
//  TaskExplorer (app)
//
//  Created by Patrick Wardle on 9/12/26.
//  Copyright (c) 2026 Objective-See. All rights reserved.
//
//  note: export all processes (w/ dylibs, files, connections) as JSON

import AppKit
import Foundation

enum JSONExport {

    //build (json-serializable) dictionary for the whole model
    static func snapshot() -> [String: Any] {
        guard let enumerator = taskEnumerator else { return [:] }
        let tasks = (enumerator.allTasks() as? [TETask]) ?? []
        var processes: [[String: Any]] = []
        for task in tasks.sorted(by: { $0.pid.intValue < $1.pid.intValue }) {
            processes.append(process(task))
        }
        let dylibs = ((enumerator.allDylibs() as? [Binary]) ?? []).sorted { $0.path < $1.path }.map { binary(binary: $0, hosts: true) }
        return ["generated": ISO8601DateFormatter().string(from: Date()),
                "version": getAppVersion() ?? "",
                "virusTotalEnabled": virusTotal?.isEnabled() ?? false,
                "processes": processes,
                "dylibs": dylibs]
    }

    //process
    static func process(_ task: TETask) -> [String: Any] {
        var dict = binary(binary: task.binary, hosts: false)
        dict["pid"] = task.pid.intValue
        dict["ppid"] = task.ppid?.intValue ?? 0
        dict["uid"] = Int(task.uid)
        dict["user"] = userName(for: task.uid)
        dict["arguments"] = (task.arguments as? [String]) ?? []
        if let started = task.startTime { dict["started"] = ISO8601DateFormatter().string(from: started) }
        dict["platformBinary"] = task.isPlatformBinary
        dict["dylibs"] = (task.dylibsSnapshot() as? [Binary] ?? []).map { $0.path }
        dict["files"] = (task.filesSnapshot() as? [File] ?? []).map { ["path": $0.path ?? "", "type": $0.type ?? FILE_TYPE_UNKNOWN] }
        dict["connections"] = (task.connectionsSnapshot() as? [Connection] ?? []).map { connection($0) }
        return dict
    }

    //binary (process or dylib)
    static func binary(binary: Binary, hosts: Bool) -> [String: Any] {
        var dict: [String: Any] = ["name": binary.name ?? "", "path": binary.path ?? ""]
        if let hashes = binary.hashes as? [String: String] { dict["hashes"] = hashes }
        if let signing = binary.signingInfo as? [String: Any] {
            var info: [String: Any] = [:]
            info["status"] = (signing[KEY_SIGNATURE_STATUS] as? NSNumber)?.intValue ?? -1
            info["signer"] = (SignerKind(rawValue: (signing[KEY_SIGNATURE_SIGNER] as? NSNumber)?.intValue ?? 0) ?? .none).label
            if let id = signing[KEY_SIGNATURE_IDENTIFIER] { info["identifier"] = id }
            if let team = signing[KEY_SIGNATURE_TEAM_ID] { info["teamID"] = team }
            if let cdHash = signing[KEY_SIGNATURE_CDHASH_SHA256] { info["cdHashSHA256"] = cdHash }
            if let cdHash = signing[KEY_SIGNATURE_CDHASH_SHA1] { info["cdHashSHA1"] = cdHash }
            if let auths = signing[KEY_SIGNATURE_AUTHORITIES] { info["authorities"] = auths }
            dict["signing"] = info
        }
        dict["isApple"] = binary.isApple
        dict["inDyldCache"] = binary.inCache
        dict["encrypted"] = binary.isEncrypted
        dict["packed"] = binary.isPacked
        dict["notFound"] = binary.notFound
        let vt = VTStatus.from(binary)
        switch vt {
        case .known(let positives, let total, let url): dict["virusTotal"] = ["positives": positives, "total": total, "report": url]
        case .unknown: dict["virusTotal"] = "unknown"
        case .error: dict["virusTotal"] = "error"
        case .skipped: dict["virusTotal"] = "skipped"
        case .pending: dict["virusTotal"] = "pending"
        default: break
        }
        if hosts {
            dict["loadedIn"] = (binary.hostTasks() as? [TETask] ?? []).map { $0.pid.intValue }
        }
        return dict
    }

    //connection
    static func connection(_ connection: Connection) -> [String: Any] {
        var dict: [String: Any] = [:]
        dict["protocol"] = connection.proto ?? ""
        dict["family"] = connection.family ?? ""
        dict["localAddress"] = connection.localIPAddr ?? ""
        dict["localPort"] = connection.localPort?.intValue ?? 0
        dict["remoteAddress"] = connection.remoteIPAddr ?? ""
        dict["remotePort"] = connection.remotePort?.intValue ?? 0
        dict["state"] = connection.state ?? ""
        dict["interface"] = connection.interface ?? ""
        dict["bytesUp"] = connection.bytesUp
        dict["bytesDown"] = connection.bytesDown
        return dict
    }

    //save (via save panel)
    @MainActor static func save(window: NSWindow?) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "TaskExplorer.json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        let handler: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            //build & write in the background (tens of thousands of dylibs with the shared cache indexed; the model accessors are lock-protected)
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let data = try JSONSerialization.data(withJSONObject: snapshot(), options: [.prettyPrinted, .sortedKeys])
                    try data.write(to: url)
                } catch {
                    DispatchQueue.main.async { showAlert(.warning, "Failed to save", error.localizedDescription, ["OK"]) }
                }
            }
        }
        if let window { panel.beginSheetModal(for: window, completionHandler: handler) } else { handler(panel.runModal()) }
    }
}
