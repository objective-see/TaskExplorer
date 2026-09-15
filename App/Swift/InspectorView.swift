//
//  InspectorView.swift
//  TaskExplorer (app)
//
//  Created by Patrick Wardle on 9/12/26.
//  Copyright (c) 2026 Objective-See. All rights reserved.
//
//  note: (trailing) inspector; details for the selected process, dylib, file, or connection

import SwiftUI

struct InspectorView: View {

    @EnvironmentObject var store: Store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                switch store.selectedItem {
                case .process(let pid):
                    if let item = store.process(pid) { ProcessDetails(item: item) } else { none }
                case .dylib(let id):
                    if let item = store.dylibs.first(where: { $0.id == id }) { BinaryDetails(binary: item.binary, title: item.name, subtitle: "Dylib", icon: item.icon) } else { none }
                case .file(let id):
                    if let item = store.files.first(where: { $0.id == id }) { FileDetails(item: item) } else { none }
                case .connection(let id):
                    if let item = store.connections.first(where: { $0.id == id }) { ConnectionDetails(item: item) } else { none }
                case nil:
                    none
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var none: some View {
        ContentUnavailableView("No Selection", systemImage: "sidebar.trailing", description: Text("Select a process, dylib, file, or connection."))
    }
}

//key/value row
struct DetailRow: View {
    let label: String
    let value: String
    var mono: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value.isEmpty ? "—" : value)
                .font(mono ? .system(.callout, design: .monospaced) : .callout)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

//header (icon + name + subtitle)
struct DetailHeader: View {
    let icon: NSImage?
    let title: String
    let subtitle: String
    var flagged: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: icon ?? NSWorkspace.shared.icon(for: .unixExecutable)).resizable().frame(width: 40, height: 40)
            VStack(alignment: .leading) {
                Text(title).font(.title3).fontWeight(.semibold).foregroundStyle(flagged ? Color.red : Color.primary).textSelection(.enabled)
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

//process details
struct ProcessDetails: View {
    @EnvironmentObject var store: Store
    let item: ProcessItem

    var body: some View {
        DetailHeader(icon: item.icon, title: item.name, subtitle: "Process · PID \(item.id)", flagged: item.vt.isFlagged)
        Divider()
        DetailRow(label: "Path", value: item.path, mono: true)
        DetailRow(label: "Arguments", value: item.arguments.joined(separator: " "), mono: true)
        HStack(alignment: .top, spacing: 24) {
            DetailRow(label: "PID", value: "\(item.id)")
            DetailRow(label: "Parent", value: parentText)
            DetailRow(label: "User", value: "\(item.user) (\(item.uid))")
        }
        if let started = item.startTime {
            DetailRow(label: "Started", value: started.formatted(date: .abbreviated, time: .standard))
        }
        Divider()
        BinarySigningDetails(binary: item.task.binary)
        Divider()
        HStack(alignment: .top, spacing: 24) {
            DetailRow(label: "Dylibs", value: "\(item.dylibCount)")
            DetailRow(label: "Connections", value: "\(item.connectionCount)")
            DetailRow(label: "Platform Binary", value: item.isPlatformBinary ? "yes" : "no")
        }
        let mismatched = (item.task.mismatchedDylibs as? [Binary]) ?? []
        if !mismatched.isEmpty {
            Divider()
            Text("Dylibs with a different Team ID").font(.caption).foregroundStyle(.secondary)
            ForEach(mismatched, id: \.path) { dylib in
                HStack {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                    Text(dylib.path).font(.system(.caption, design: .monospaced)).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                }
            }
        }
        Divider()
        HStack {
            Button("Show in Finder") { store.showInFinder(item.path) }
            if let url = item.vt.url { Button("VirusTotal Report") { NSWorkspace.shared.open(url) } }
        }
    }

    private var parentText: String {
        if item.id == 0 { return "—" }
        if let parent = store.process(item.ppid) { return "\(parent.name) (\(item.ppid))" }
        return "\(item.ppid)"
    }
}

//binary (dylib) details
struct BinaryDetails: View {
    @EnvironmentObject var store: Store
    let binary: Binary
    let title: String
    let subtitle: String
    let icon: NSImage?

    var body: some View {
        let vt = VTStatus.from(binary)
        DetailHeader(icon: icon, title: title, subtitle: subtitle, flagged: vt.isFlagged)
        Divider()
        DetailRow(label: "Path", value: binary.path, mono: true)
        HStack(alignment: .top, spacing: 24) {
            DetailRow(label: "In dyld cache", value: binary.inCache ? "yes" : "no")
            DetailRow(label: "On disk", value: binary.notFound ? "no" : "yes")
            DetailRow(label: "Loaded in", value: "\(binary.hostCount())")
        }
        Divider()
        BinarySigningDetails(binary: binary)
        let hosts = binary.hostTasks() ?? []
        if !hosts.isEmpty {
            Divider()
            Text("Loaded in").font(.caption).foregroundStyle(.secondary)
            ForEach(hosts, id: \.pid) { task in
                Button {
                    store.select(pid: task.pid.intValue)
                } label: {
                    HStack(spacing: 6) {
                        Image(nsImage: task.binary.icon ?? NSWorkspace.shared.icon(for: .unixExecutable)).resizable().frame(width: 16, height: 16)
                        Text(verbatim: "\(task.binary.name ?? "?") (\(task.pid.intValue))").font(.callout)
                    }
                }
                .buttonStyle(.link)
            }
        }
        Divider()
        HStack {
            Button("Show in Finder") { store.showInFinder(binary.path) }
            if let url = vt.url { Button("VirusTotal Report") { NSWorkspace.shared.open(url) } }
        }
    }
}

//signing / hashes (shared by process & dylib)
struct BinarySigningDetails: View {
    @EnvironmentObject var store: Store
    let binary: Binary

    var body: some View {
        let signing = binary.signingInfo as? [String: Any] ?? [:]
        let status = (signing[KEY_SIGNATURE_STATUS] as? NSNumber)?.intValue
        let signer = SignerKind(rawValue: (signing[KEY_SIGNATURE_SIGNER] as? NSNumber)?.intValue ?? 0) ?? .none
        let hashes = binary.hashes as? [String: String] ?? [:]

        Text("Code Signing").font(.caption).foregroundStyle(.secondary)
        if status == nil {
            Text("generating…").font(.callout).foregroundStyle(.secondary)
        } else if status == Int(SIGNING_STATUS_XPC_FAILED) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                Text("Code signing check failed (the extension did not respond)").font(.callout).foregroundStyle(.orange)
            }
        } else if status == 0 {
            DetailRow(label: "Signer", value: binary.isApple ? "Apple" : signer.label)
            if let identifier = signing[KEY_SIGNATURE_IDENTIFIER] as? String { DetailRow(label: "Identifier", value: identifier, mono: true) }
            if let team = signing[KEY_SIGNATURE_TEAM_ID] as? String { DetailRow(label: "Team ID", value: team, mono: true) }
            //cdhash: the canonical (20-byte) form as codesign/ES/notarization report it, plus the full SHA-256 digest
            if let full = signing[KEY_SIGNATURE_CDHASH_SHA256] as? String {
                DetailRow(label: "CDHash", value: String(full.prefix(40)), mono: true)
                DetailRow(label: "CDHash (full SHA-256)", value: full, mono: true)
            } else if let cdHash = signing[KEY_SIGNATURE_CDHASH_SHA1] as? String {
                DetailRow(label: "CDHash (SHA-1)", value: cdHash, mono: true)
            }
            if let auths = signing[KEY_SIGNATURE_AUTHORITIES] as? [String], !auths.isEmpty {
                DetailRow(label: "Authorities", value: auths.joined(separator: "\n"))
            }
            if let entitlements = signing[KEY_SIGNATURE_ENTITLEMENTS] as? [String: Any], !entitlements.isEmpty {
                DisclosureGroup {
                    Text(entitlements.keys.sorted().joined(separator: "\n"))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                } label: {
                    Text(verbatim: "Entitlements (\(entitlements.count))").font(.caption).foregroundStyle(.secondary)
                }
            }
        } else if binary.inCache {
            DetailRow(label: "Signer", value: "Apple (dyld shared cache)")
        } else if binary.isApple {
            //e.g. the kernel: Apple's, but not a code-signed Mach-O the usual way (status -67062, 'unsigned')
            DetailRow(label: "Signer", value: "Apple (kernel; no code signature to check)")
        } else {
            DetailRow(label: "Signer", value: binary.formatSigningInfo() ?? "unsigned")
        }
        if !hashes.isEmpty {
            DetailRow(label: "SHA-256", value: hashes[KEY_HASH_SHA256] ?? "", mono: true)
            DetailRow(label: "SHA-1", value: hashes[KEY_HASH_SHA1] ?? "", mono: true)
            DetailRow(label: "MD5", value: hashes[KEY_HASH_MD5] ?? "", mono: true)
        }
        HStack(spacing: 24) {
            DetailRow(label: "Encrypted", value: binary.isEncrypted ? "yes" : "no")
            DetailRow(label: "Packed", value: binary.isPacked ? "yes" : "no")
            DetailRow(label: "VirusTotal", value: vtDescription(VTStatus.from(binary), reason: store.vtDisabledReason))
        }
    }
}

//virus total status, for the inspector
// ->'reason' is why lookups are off (no API key / disabled / offline), matching the VT column
func vtDescription(_ status: VTStatus, reason: String = "disabled") -> String {
    switch status {
    case .disabled: return reason.isEmpty ? "disabled" : reason
    case .skipped: return "not checked (Apple/platform binary)"
    case .pending: return "pending"
    case .unknown: return "unknown to VirusTotal"
    case .error: return "lookup failed"
    case .known(let positives, let total, _): return "\(positives)/\(total)"
    }
}

//file details
struct FileDetails: View {
    @EnvironmentObject var store: Store
    let item: FileItem

    var body: some View {
        DetailHeader(icon: item.icon, title: item.name, subtitle: item.type == FILE_TYPE_SOCKET ? "Unix domain socket" : (item.type == FILE_TYPE_FILE ? "Open file" : "Open \(item.typeLabel.lowercased())"))
        Divider()
        DetailRow(label: "Path", value: item.path, mono: true)
        let attributes = item.file.attributes as? [FileAttributeKey: Any] ?? [:]
        if let size = attributes[.size] as? NSNumber {
            DetailRow(label: "Size", value: ByteCountFormatter.string(fromByteCount: size.int64Value, countStyle: .file))
        }
        if let modified = attributes[.modificationDate] as? Date {
            DetailRow(label: "Modified", value: modified.formatted(date: .abbreviated, time: .standard))
        }
        if let owner = attributes[.ownerAccountName] as? String {
            DetailRow(label: "Owner", value: owner)
        }
        let hosts = item.file.hostTasks() ?? []
        if !hosts.isEmpty {
            Divider()
            Text("Open in").font(.caption).foregroundStyle(.secondary)
            ForEach(hosts, id: \.pid) { task in
                Button { store.select(pid: task.pid.intValue) } label: {
                    Text(verbatim: "\(task.binary.name ?? "?") (\(task.pid.intValue))").font(.callout)
                }
                .buttonStyle(.link)
            }
        }
        Divider()
        Button("Show in Finder") { store.showInFinder(item.path) }
    }
}

//connection details
struct ConnectionDetails: View {
    @EnvironmentObject var store: Store
    let item: ConnectionItem

    var body: some View {
        DetailHeader(icon: NSImage(systemSymbolName: "network", accessibilityDescription: nil), title: item.endpoints, subtitle: "\(item.proto) connection", flagged: false)
        Divider()
        HStack(alignment: .top, spacing: 24) {
            DetailRow(label: "Protocol", value: item.proto)
            DetailRow(label: "Family", value: item.family)
            DetailRow(label: "Interface", value: item.interface)
        }
        DetailRow(label: "Local", value: item.local, mono: true)
        DetailRow(label: "Remote", value: item.remote, mono: true)
        DetailRow(label: "State", value: item.state)
        HStack(alignment: .top, spacing: 24) {
            DetailRow(label: "Sent", value: ByteCountFormatter.string(fromByteCount: Int64(item.bytesUp), countStyle: .file))
            DetailRow(label: "Received", value: ByteCountFormatter.string(fromByteCount: Int64(item.bytesDown), countStyle: .file))
        }
        if let process = store.process(item.pid) {
            Divider()
            DetailRow(label: "Process", value: "\(process.name) (\(process.id))")
        }
    }
}
