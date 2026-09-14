//
//  Snapshots.swift
//  TaskExplorer (app)
//
//  Created by Patrick Wardle on 9/12/26.
//  Copyright (c) 2026 Objective-See. All rights reserved.
//
//  note: immutable (value) snapshots of the (objective-c) model, for the (swift) UI
//        ...each keeps a reference to its model object, for actions (keyword filters, finder, etc)

import AppKit
import Foundation

//signer
enum SignerKind: Int, Comparable {
    case none = 0, apple, appStore, devID, adHoc

    static func < (lhs: SignerKind, rhs: SignerKind) -> Bool { lhs.rawValue < rhs.rawValue }

    //label
    var label: String {
        switch self {
        case .none: return "unsigned"
        case .apple: return "Apple"
        case .appStore: return "App Store"
        case .devID: return "Developer ID"
        case .adHoc: return "ad-hoc"
        }
    }

    //symbol
    var symbol: String {
        switch self {
        case .none: return "xmark.seal"
        case .apple: return "apple.logo"
        case .appStore: return "bag"
        case .devID: return "checkmark.seal"
        case .adHoc: return "seal"
        }
    }
}

//virus total status
enum VTStatus: Hashable, Comparable {
    case disabled
    case skipped
    case pending
    case unknown
    case error
    case known(positives: Int, total: Int, url: String)

    //sort rank (flagged first)
    var rank: Int {
        switch self {
        case .known(let positives, _, _): return positives > 0 ? 0 : 1
        case .unknown: return 2
        case .error: return 3
        case .pending: return 4
        case .skipped: return 5
        case .disabled: return 6
        }
    }

    static func < (lhs: VTStatus, rhs: VTStatus) -> Bool {
        if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
        if case .known(let lp, _, _) = lhs, case .known(let rp, _, _) = rhs { return lp > rp }
        return false
    }

    //flagged?
    var isFlagged: Bool {
        if case .known(let positives, _, _) = self { return positives > 0 }
        return false
    }

    //label
    var label: String {
        switch self {
        case .disabled: return ""
        case .skipped: return "—"
        case .pending: return "…"
        case .unknown: return "?"
        case .error: return "!"
        case .known(let positives, let total, _): return "\(positives)/\(total)"
        }
    }

    //report url
    var url: URL? {
        if case .known(_, _, let url) = self { return URL(string: url) }
        return nil
    }

    //build from binary
    static func from(_ binary: Binary) -> VTStatus {
        guard virusTotal?.isEnabled() == true else { return .disabled }
        //note: a failed signing check (extension hiccup) is retried by the lookup: pending, or an error, but not 'skipped'
        let signingFailed = ((binary.signingInfo as? [String: Any])?[KEY_SIGNATURE_STATUS] as? NSNumber)?.intValue == Int(SIGNING_STATUS_XPC_FAILED)
        guard signingFailed || !binary.isExcludedFromVT else { return .skipped }
        guard let info = binary.vtInfo as? [String: Any] else { return .pending }
        if info[VT_ERROR] != nil { return .error }
        guard let url = info[VT_RESULTS_URL] as? String else { return .unknown }
        let positives = (info[VT_RESULTS_POSITIVES] as? NSNumber)?.intValue ?? 0
        let total = (info[VT_RESULTS_TOTAL] as? NSNumber)?.intValue ?? 0
        return .known(positives: positives, total: total, url: url)
    }
}

//process (task)
struct ProcessItem: Identifiable, Hashable {

    //pid
    let id: Int
    let ppid: Int
    let name: String
    let path: String
    let user: String
    let uid: Int
    let signer: SignerKind
    let isApple: Bool
    let signingError: Bool
    let signingPending: Bool
    let vt: VTStatus
    let teamID: String
    let startTime: Date?
    let arguments: [String]
    let isPlatformBinary: Bool
    let dylibCount: Int
    let connectionCount: Int
    let notFound: Bool

    //children (tree view)
    // note: nil for leaf nodes (required by hierarchical Table)
    var children: [ProcessItem]?

    //depth (tree view; set when the tree is flattened for display)
    var depth: Int = 0

    //model object
    let task: TETask

    //(sortable) start time
    var started: TimeInterval { startTime?.timeIntervalSince1970 ?? 0 }

    //icon
    var icon: NSImage? { task.binary.icon }

    //hash/equality on (value) fields only
    static func == (lhs: ProcessItem, rhs: ProcessItem) -> Bool {
        lhs.id == rhs.id && lhs.ppid == rhs.ppid && lhs.name == rhs.name && lhs.path == rhs.path
            && lhs.user == rhs.user && lhs.signer == rhs.signer && lhs.signingPending == rhs.signingPending && lhs.vt == rhs.vt && lhs.teamID == rhs.teamID
            && lhs.dylibCount == rhs.dylibCount && lhs.connectionCount == rhs.connectionCount
            && lhs.notFound == rhs.notFound && lhs.children == rhs.children
    }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    //init (from task)
    init(task: TETask, children: [ProcessItem]? = nil) {
        self.task = task
        self.id = task.pid.intValue
        self.ppid = task.ppid?.intValue ?? 0
        self.name = task.binary.name ?? task.binary.path.lastPathComponent
        self.path = task.binary.path ?? ""
        self.uid = Int(task.uid)
        self.user = userName(for: task.uid)
        self.signer = SignerKind(rawValue: task.binary.signer?.intValue ?? 0) ?? .none
        self.isApple = task.binary.isApple
        self.signingError = signingFailed(task.binary)
        self.signingPending = (task.binary.signingInfo == nil)
        self.vt = VTStatus.from(task.binary)
        self.teamID = task.teamID ?? ""
        self.startTime = task.startTime
        self.arguments = (task.arguments as? [String]) ?? []
        self.isPlatformBinary = task.isPlatformBinary
        self.dylibCount = Int(task.dylibCount())
        self.connectionCount = task.connectionsSnapshot().count
        self.notFound = task.binary.notFound
        self.children = children
    }
}

//dylib (binary)
struct DylibItem: Identifiable, Hashable {

    //path
    let id: String
    let name: String
    let path: String
    let signer: SignerKind
    let isApple: Bool
    let signingError: Bool
    let signingPending: Bool
    let inCache: Bool
    let vt: VTStatus
    let teamID: String
    let hostCount: Int
    let notFound: Bool

    //model object
    let binary: Binary

    //icon
    var icon: NSImage? { binary.icon }

    static func == (lhs: DylibItem, rhs: DylibItem) -> Bool {
        lhs.id == rhs.id && lhs.signer == rhs.signer && lhs.signingPending == rhs.signingPending && lhs.vt == rhs.vt && lhs.hostCount == rhs.hostCount && lhs.teamID == rhs.teamID
    }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    init(binary: Binary) {
        self.binary = binary
        self.id = binary.path
        self.name = binary.name ?? binary.path.lastPathComponent
        self.path = binary.path
        self.signer = SignerKind(rawValue: binary.signer?.intValue ?? 0) ?? .none
        self.isApple = binary.isApple
        self.signingError = signingFailed(binary)
        self.signingPending = (binary.signingInfo == nil)
        self.inCache = binary.inCache
        self.vt = VTStatus.from(binary)
        self.teamID = binary.teamID ?? ""
        self.hostCount = Int(binary.hostCount())
        self.notFound = binary.notFound
    }
}

//(open) file
struct FileItem: Identifiable, Hashable {

    //path
    let id: String
    let name: String
    let path: String
    let hostCount: Int

    //type (raw, from the extension: file/socket/directory/...) + label
    let type: String
    var typeLabel: String { FileItem.label(for: type) }

    //model object
    let file: File

    //icon
    var icon: NSImage? { file.icon }

    static func label(for type: String) -> String {
        switch type {
        case FILE_TYPE_FILE: return "File"
        case FILE_TYPE_SOCKET: return "Socket"
        case FILE_TYPE_DIRECTORY: return "Directory"
        case FILE_TYPE_DEVICE: return "Device"
        case FILE_TYPE_FIFO: return "FIFO"
        case FILE_TYPE_LINK: return "Link"
        default: return "Unknown"
        }
    }

    static func == (lhs: FileItem, rhs: FileItem) -> Bool { lhs.id == rhs.id && lhs.hostCount == rhs.hostCount && lhs.type == rhs.type }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    init(file: File) {
        self.file = file
        self.id = file.path
        self.name = file.path.lastPathComponent
        self.path = file.path
        self.hostCount = Int(file.hostCount())
        self.type = file.type ?? FILE_TYPE_UNKNOWN
    }
}

//network connection
struct ConnectionItem: Identifiable, Hashable {

    //id (pid + proto + endpoints)
    let id: String
    let pid: Int
    let proto: String
    let family: String
    let local: String
    let remote: String
    let state: String
    let interface: String
    let bytesUp: UInt64
    let bytesDown: UInt64
    let endpoints: String

    //model object
    let connection: Connection

    static func == (lhs: ConnectionItem, rhs: ConnectionItem) -> Bool {
        lhs.id == rhs.id && lhs.state == rhs.state && lhs.bytesUp == rhs.bytesUp && lhs.bytesDown == rhs.bytesDown
    }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    init(connection: Connection, pid: Int) {
        self.connection = connection
        self.pid = pid
        self.proto = (connection.proto ?? "").uppercased()
        self.family = connection.family ?? ""
        self.local = "\(connection.localIPAddr ?? "?"):\(connection.localPort?.intValue ?? 0)"
        if let remoteAddr = connection.remoteIPAddr, let port = connection.remotePort?.intValue, port != 0 {
            self.remote = "\(remoteAddr):\(port)"
        } else {
            self.remote = ""
        }
        self.state = connection.state ?? ""
        self.interface = connection.interface ?? ""
        self.bytesUp = connection.bytesUp
        self.bytesDown = connection.bytesDown
        self.endpoints = String(connection.endpoints)
        self.id = "\(pid)|\(self.proto)|\(self.local)|\(self.remote)"
    }
}

//flagged item (task binary or dylib)
struct FlaggedItem: Identifiable, Hashable {
    let id: String
    let name: String
    let path: String
    let vt: VTStatus
    let isTaskBinary: Bool
    let hosts: [String]
    let binary: Binary

    static func == (lhs: FlaggedItem, rhs: FlaggedItem) -> Bool { lhs.id == rhs.id && lhs.vt == rhs.vt && lhs.hosts == rhs.hosts }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    init(binary: Binary) {
        self.binary = binary
        self.id = binary.path
        self.name = binary.name ?? binary.path.lastPathComponent
        self.path = binary.path
        self.vt = VTStatus.from(binary)
        self.isTaskBinary = binary.isTaskBinary
        self.hosts = (binary.hostTasks() as? [TETask] ?? []).map { "\($0.binary.name ?? "?") (\($0.pid))" }
    }
}

//global search result
enum SearchResult: Identifiable, Hashable {
    case process(ProcessItem)
    case dylib(DylibItem)
    case file(FileItem)
    case connection(ConnectionItem)

    var id: String {
        switch self {
        case .process(let p): return "p:\(p.id)"
        case .dylib(let d): return "d:\(d.id)"
        case .file(let f): return "f:\(f.id)"
        case .connection(let c): return "c:\(c.id)"
        }
    }
}

//did the (extension's) code signing check fail (XPC error)?
func signingFailed(_ binary: Binary) -> Bool {
    ((binary.signingInfo as? [String: Any])?[KEY_SIGNATURE_STATUS] as? NSNumber)?.intValue == Int(SIGNING_STATUS_XPC_FAILED)
}

//uid -> user name (cached)
private var userNames: [uid_t: String] = [:]
private let userNamesLock = NSLock()
func userName(for uid: uid_t) -> String {
    userNamesLock.lock(); defer { userNamesLock.unlock() }
    if let cached = userNames[uid] { return cached }
    var name = "\(uid)"
    if let entry = getpwuid(uid), let cName = entry.pointee.pw_name {
        name = String(cString: cName)
    }
    userNames[uid] = name
    return name
}

//string helpers
extension String {
    var lastPathComponent: String { (self as NSString).lastPathComponent }
}
