//
//  Store.swift
//  TaskExplorer (app)
//
//  Created by Patrick Wardle on 9/12/26.
//  Copyright (c) 2026 Objective-See. All rights reserved.
//
//  note: observable store for the (swift) UI
//        ...rebuilds (value) snapshots from the (objective-c) model whenever it posts a change notification
//        the same snapshots are what the assistant (tools) query

import AppKit
import Combine
import Foundation
import SwiftUI

//view mode (top pane)
enum ViewMode: String, CaseIterable, Identifiable {
    case flat, tree
    var id: String { rawValue }
}

//bottom pane tab
enum ItemsTab: String, CaseIterable, Identifiable {
    case dylibs = "Dylibs", files = "Files", network = "Network"
    var id: String { rawValue }

    //model's view constant
    var modelView: UInt {
        switch self {
        case .dylibs: return UInt(DYLIBS_VIEW)
        case .files: return UInt(FILES_VIEW)
        case .network: return UInt(NETWORKING_VIEW)
        }
    }
}

//search scope
enum SearchScope: String, CaseIterable, Identifiable {
    case processes = "Processes", everything = "Everything"
    var id: String { rawValue }
}

//filter (keyword) token
struct FilterToken: Identifiable, Hashable {
    let keyword: String
    var id: String { keyword }
}

//selected (bottom pane / inspector) item
enum SelectedItem: Hashable {
    case process(Int)
    case dylib(String)
    case file(String)
    case connection(String)
}

@MainActor
final class Store: ObservableObject {

    //shared
    static let shared = Store()

    /* PROCESSES */

    //all processes (flat)
    @Published private(set) var processes: [ProcessItem] = []

    //process tree (roots)
    @Published private(set) var processTree: [ProcessItem] = []

    //collapsed nodes (tree view); everything is expanded by default
    @Published var collapsedPIDs: Set<Int> = []

    //tree, flattened for display (respecting collapsed nodes), w/ depth set on each row
    var visibleTreeRows: [ProcessItem] {
        var rows: [ProcessItem] = []
        func walk(_ items: [ProcessItem], depth: Int) {
            for var item in items {
                item.depth = depth
                rows.append(item)
                if let kids = item.children, !kids.isEmpty, !collapsedPIDs.contains(item.id) {
                    walk(kids, depth: depth + 1)
                }
            }
        }
        walk(processTree, depth: 0)
        return rows
    }

    //toggle (tree) node
    func toggleCollapsed(_ pid: Int) {
        if collapsedPIDs.contains(pid) { collapsedPIDs.remove(pid) } else { collapsedPIDs.insert(pid) }
    }

    //expand / collapse all
    func expandAll() { collapsedPIDs = [] }
    func collapseAll() {
        var all = Set<Int>()
        func walk(_ items: [ProcessItem]) { for item in items where !(item.children ?? []).isEmpty { all.insert(item.id); walk(item.children ?? []) } }
        walk(processTree)
        collapsedPIDs = all
    }

    //by pid
    private var processesByPID: [Int: ProcessItem] = [:]

    /* ITEMS (of selected process) */

    @Published private(set) var dylibs: [DylibItem] = []
    @Published private(set) var files: [FileItem] = []
    @Published private(set) var connections: [ConnectionItem] = []

    /* FLAGGED */

    @Published private(set) var flagged: [FlaggedItem] = []

    /* STATE */

    //status (e.g. "starting system extension..."), shown as an overlay
    // ->only after a grace period (a fast start must not flash it), and then for a minimum time (no flicker)
    @Published private(set) var status: String?
    private var statusTask: _Concurrency.Task<Void, Never>?
    private var statusShownAt: Date?
    private static let statusGrace: TimeInterval = 0.5
    private static let statusMinimum: TimeInterval = 1.0

    //show/hide the status overlay (see 'status')
    private func setStatus(_ new: String?) {
        statusTask?.cancel()
        statusTask = nil
        if let new {
            //already showing? just swap the text
            if status != nil { withAnimation { status = new }; return }
            statusTask = _Concurrency.Task { @MainActor [weak self] in
                try? await _Concurrency.Task.sleep(nanoseconds: UInt64(Store.statusGrace * 1_000_000_000))
                guard let self, !_Concurrency.Task.isCancelled else { return }
                withAnimation { self.status = new }
                self.statusShownAt = Date()
            }
        } else {
            guard status != nil else { return }
            let remaining = Store.statusMinimum - Date().timeIntervalSince(statusShownAt ?? .distantPast)
            guard remaining > 0 else { withAnimation { status = nil }; return }
            statusTask = _Concurrency.Task { @MainActor [weak self] in
                try? await _Concurrency.Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
                guard let self, !_Concurrency.Task.isCancelled else { return }
                withAnimation { self.status = nil }
            }
        }
    }

    //enumeration state (ENUMERATION_STATE_*)
    @Published private(set) var enumerationState: Int = 0

    //live monitoring?
    @Published private(set) var isMonitoring: Bool = false

    //virus total enabled?
    // ->when not, 'vtDisabledReason' says why (no key / disabled / offline); shown (light gray) in the VT column
    @Published private(set) var vtEnabled: Bool = false
    @Published private(set) var vtDisabledReason: String = ""

    /* UI STATE */

    @Published var viewMode: ViewMode = .flat
    @Published var itemsTab: ItemsTab = .dylibs {
        didSet {
            if itemsTab != oldValue {
                //an item selected in another tab no longer applies; fall back to the process
                if let pid = selectedPID { selectedItem = .process(pid) }
                refreshSelectedItems(); ensureCacheDylibs()
            }
        }
    }
    @Published var selectedPID: Int? {
        didSet {
            if selectedPID != oldValue {
                uiLog.debug("store selectedPID: \(String(describing: oldValue)) -> \(String(describing: self.selectedPID))")
                selectedItem = selectedPID.map { .process($0) }
                //clear the (previous selection's) items & show 'enumerating' right away
                // ->so neither stale rows nor an empty state flash before the refresh completes
                dylibs = []; files = []; connections = []
                itemsLoading = (selectedPID != nil && processesByPID[selectedPID!] != nil)
                //note: deferred, so the table's selection change is committed before any (heavy) work / further publishes
                DispatchQueue.main.async { [weak self] in
                    self?.rebuildItems()
                    self?.refreshSelectedItems()
                    self?.ensureCacheDylibs()
                }
            }
        }
    }
    @Published var selectedItem: SelectedItem?
    @Published var query: String = "" {
        didSet {
            //debounce the applied (text) filter, so the tables aren't rebuilt per keystroke
            queryDebounce?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.appliedQuery = self?.query ?? "" }
            queryDebounce = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
        }
    }

    //applied (debounced) text filter
    @Published private(set) var appliedQuery: String = "" {
        didSet { if appliedQuery != oldValue { filterChanged() } }
    }
    private var queryDebounce: DispatchWorkItem?

    //the (process) filter changed: a new (non-empty) filter resets the selection, so the bottom pane starts over
    // ->('Select a Process'), rather than showing the items of a process that may not even be in the filtered list;
    //   clearing the filter keeps whatever was selected meanwhile (Patrick's call)
    private func filterChanged() {
        guard isFiltering, !clearingFilter else { return }
        if selectedPID != nil { selectedPID = nil }
        collapseInspectorIfNoMatches()
    }

    //a filter that matches nothing? nothing to inspect either, so collapse the inspector
    private func collapseInspectorIfNoMatches() {
        if showInspector, isFiltering, visibleProcesses.isEmpty { showInspector = false }
    }

    //clear the filter (text & tokens)
    // ->as one change, so 'filterChanged' sees no filter at all (and keeps the selection), rather than the half-cleared state
    func clearFilter() {
        clearingFilter = true
        tokens = []
        query = ""
        applyQueryNow()
        clearingFilter = false
    }
    private var clearingFilter = false

    //apply the (text) filter right away (programmatic changes, e.g. the assistant's 'ui_set_filter' tool)
    func applyQueryNow() {
        queryDebounce?.cancel(); queryDebounce = nil
        if appliedQuery != query { appliedQuery = query }
    }
    @Published var tokens: [FilterToken] = [] {
        didSet { if tokens != oldValue { filterChanged() } }
    }
    @Published var scope: SearchScope = .processes
    @Published var itemsQuery: String = "" {
        didSet {
            itemsQueryDebounce?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.appliedItemsQuery = self?.itemsQuery ?? "" }
            itemsQueryDebounce = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
        }
    }

    //applied (debounced) items filter
    @Published private(set) var appliedItemsQuery: String = ""
    private var itemsQueryDebounce: DispatchWorkItem?

    //shared cache (dylib) index progress
    @Published private(set) var cacheIndexing: Bool = false
    @Published private(set) var cacheIndexProgress: (done: Int, total: Int) = (0, 0)

    //show dyld shared cache dylibs in the dylibs tab
    // ->turning it on (without the global index) enumerates them for the selected process via vmmap
    @Published var showCacheDylibs: Bool = UserDefaults.standard.bool(forKey: "showCacheDylibs") {
        didSet {
            UserDefaults.standard.set(showCacheDylibs, forKey: "showCacheDylibs")
            guard showCacheDylibs, !oldValue else { return }
            //not enumerated yet (vmmap needed)? clear the (disk-only) list right away, so the pane shows
            //'enumerating' until the full list arrives, rather than the old list then a jump
            if itemsTab == .dylibs, !selectionHasCacheDylibs, selectedPID != 0 { dylibs = [] }
            ensureCacheDylibs()
        }
    }

    //global index (pref) on?
    var cacheIndexEnabled: Bool { getPreferenceBool(PREF_INDEX_CACHE_DYLIBS) }

    //selected task has its shared cache dylibs enumerated?
    var selectionHasCacheDylibs: Bool {
        guard let pid = selectedPID, let item = processesByPID[pid] else { return false }
        return item.task.cacheDylibsEnumerated
    }

    //make sure the selected task's shared cache dylibs are enumerated (vmmap), if the user wants to see them
    func ensureCacheDylibs() {
        guard showCacheDylibs, let pid = selectedPID, pid != 0, let item = processesByPID[pid], !item.task.cacheDylibsEnumerated else { return }
        item.task.includeCacheDylibs = true
        if itemsTab == .dylibs { refreshSelectedItems() }
    }

    //items pane is (re)enumerating the selected process' items
    // ->set when a refresh is requested, cleared when the model posts the corresponding 'items changed' (or after a timeout)
    @Published private(set) var itemsLoading: Bool = false
    private var itemsLoadingToken = 0
    //inspector (right side panel): closed at launch (Patrick's call)
    @Published var showInspector: Bool = false
    @Published var showAssistant: Bool = true
    @Published var showFlagged: Bool = false

    //keyword filter
    let filter = Filter()

    //all keywords (for token suggestions)
    var keywords: [String] { (filter.binaryFilters as? [String]) ?? [] }

    //coalescing
    private var rebuildPending = false
    private var itemsPending = false
    private var observers: [NSObjectProtocol] = []

    //init
    // ->observe model notifications
    private init() {
        let center = NotificationCenter.default
        installMouseMonitor()
        //note: the observer closures aren't main-actor isolated (even with 'queue: .main'), so each hops back onto
        //      the main actor via 'assumeIsolated' (safe: the queue guarantees they run on the main thread)
        observers.append(center.addObserver(forName: .TETasksChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRebuild() }
        })
        observers.append(center.addObserver(forName: .TETaskChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRebuild() }
        })
        observers.append(center.addObserver(forName: .TEBinaryChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.scheduleRebuild()
                self?.scheduleItemsRebuild()
            }
        })
        observers.append(center.addObserver(forName: .TEItemsChanged, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, let task = note.object as? TETask else { return }
                //note: only the items pane; rebuilding the process list here made a click's own refresh churn the table
                if task.pid.intValue == self.selectedPID {
                    let view = (note.userInfo?["view"] as? NSNumber)?.intValue ?? -1
                    if view == Int(self.itemsTab.modelView), self.itemsLoading {
                        //end of an enumeration we were waiting on: rebuild now (not coalesced), then clear the flag,
                        //so the list appears in the same pass (no 'nothing found' flash in between)
                        self.rebuildItems()
                        self.itemsLoading = false
                        self.resolveSelectedItem(pid: task.pid.intValue)
                    } else {
                        self.scheduleItemsRebuild()
                    }
                }
            }
        })
        observers.append(center.addObserver(forName: .TEStatusChanged, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated { self?.setStatus(note.object as? String) }
        })
        observers.append(center.addObserver(forName: .TEEnumerationStateChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.enumerationState = Int(taskEnumerator?.state ?? 0)
                self?.isMonitoring = taskEnumerator?.isMonitoring ?? false
                self?.cacheIndexing = taskEnumerator?.cacheIndexing ?? false
                self?.cacheIndexProgress = (Int(taskEnumerator?.cacheIndexDone ?? 0), Int(taskEnumerator?.cacheIndexTotal ?? 0))
            }
        })
    }

    //schedule (coalesced) rebuild of processes
    private func scheduleRebuild() {
        guard !rebuildPending else { return }
        rebuildPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            //mouse down (e.g. a click on a row)? hold off until it's up
            // ->NSTableView reverts a provisional (mouse-down) selection if the row is reloaded before mouse-up,
            //   so a live update landing mid-click used to make clicks "not take" or flip back to the old row
            if self.mouseDown { self.rebuildHeld = true; self.rebuildPending = false; return }
            self.rebuildPending = false
            self.rebuildProcesses()
        }
    }

    //schedule (coalesced) rebuild of (selected process') items
    private func scheduleItemsRebuild() {
        guard !itemsPending else { return }
        itemsPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }
            if self.mouseDown { self.itemsRebuildHeld = true; self.itemsPending = false; return }
            self.itemsPending = false
            self.rebuildItems()
        }
    }

    //mouse button state (any window of the app)
    // ->model-driven table rebuilds are held while a button is down (see 'scheduleRebuild')
    private var mouseDown = false
    private var rebuildHeld = false
    private var itemsRebuildHeld = false
    private var mouseMonitor: Any?
    private var mouseDownSince: Date?

    private func installMouseMonitor() {
        //note: only mouse-downs are seen here; the mouse-up is swallowed by AppKit's tracking loops (NSTableView etc.),
        //      so the release is detected by polling the button state
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            guard let self else { return event }
            uiLog.debug("mouse down")
            self.mouseDown = true
            let since = Date()
            self.mouseDownSince = since
            self.pollMouseUp(since: since)
            return event
        }
    }

    private func pollMouseUp(since: Date) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, self.mouseDown, self.mouseDownSince == since else { return }
            //released (or held for 3s: e.g. a context menu, a drag to another app)?
            if NSEvent.pressedMouseButtons == 0 || Date().timeIntervalSince(since) > 3 {
                //one more tick, so the table's own selection commit runs before any held rebuild
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    guard let self, self.mouseDown, self.mouseDownSince == since else { return }
                    self.mouseReleased()
                }
            } else {
                self.pollMouseUp(since: since)
            }
        }
    }

    private func mouseReleased() {
        uiLog.debug("mouse up (held: processes \(self.rebuildHeld), items \(self.itemsRebuildHeld))")
        mouseDown = false
        mouseDownSince = nil
        //apply what was held (after the click's own selection change has settled)
        if rebuildHeld { rebuildHeld = false; scheduleRebuild() }
        if itemsRebuildHeld { itemsRebuildHeld = false; scheduleItemsRebuild() }
    }

    //rebuild processes (flat + tree) & flagged
    func rebuildProcesses() {
        guard let enumerator = taskEnumerator else { return }
        let tasks = (enumerator.allTasks() as? [TETask]) ?? []

        //flat
        var byPID: [Int: ProcessItem] = [:]
        for task in tasks {
            let item = ProcessItem(task: task)
            byPID[item.id] = item
        }
        processesByPID = byPID
        let sorted = byPID.values.sorted {
            let order = $0.name.localizedCaseInsensitiveCompare($1.name)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }

        //tree
        // ->root is kernel (pid 0); children from task's (sorted) child pids
        var visited = Set<Int>()
        func node(_ pid: Int, depth: Int) -> ProcessItem? {
            guard var item = byPID[pid], depth < 64, !visited.contains(pid) else { return nil }
            visited.insert(pid)
            let childPIDs = (item.task.childrenSnapshot() as? [NSNumber] ?? []).map { $0.intValue }.filter { $0 != pid }
            let kids = childPIDs.compactMap { node($0, depth: depth + 1) }
            item.children = kids.isEmpty ? nil : kids
            return item
        }
        let tree = node(0, depth: 0).map { [$0] } ?? sorted

        //publish (without animation)
        // ->animated row inserts/removes (the default) swallow clicks that land mid-animation: with live monitoring the
        //   list changes every few hundred ms, so clicks on a row often "didn't take" or fell back to the old selection
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            //note: only publish what changed; every publish re-evaluates all views observing the store
            if processes != sorted { processes = sorted }
            if processTree != tree { processTree = tree }
            //(still) filtering, and the matches are gone (e.g. the last one exited)? collapse the inspector
            collapseInspectorIfNoMatches()
        }
        uiLog.debug("rebuilt processes (\(sorted.count))")

        //flagged
        let flaggedBinaries = (enumerator.flaggedItemsSnapshot() as? [Binary]) ?? []
        let newFlagged = flaggedBinaries.map { FlaggedItem(binary: $0) }
        if flagged != newFlagged { flagged = newFlagged }

        //selection gone?
        if let pid = selectedPID, byPID[pid] == nil {
            selectedPID = nil
        }
        let state = Int(enumerator.state)
        if enumerationState != state { enumerationState = state }
        if isMonitoring != enumerator.isMonitoring { isMonitoring = enumerator.isMonitoring }
        refreshVTState()
    }

    //refresh virus total state
    func refreshVTState() {
        let enabled = virusTotal?.isEnabled() ?? false
        //note: no API key == disabled (Settings shows the toggle off, and locked, until a key is entered)
        let reason = enabled ? "" : "disabled"
        //publish only on change (called every rebuild)
        if vtEnabled != enabled { vtEnabled = enabled }
        if vtDisabledReason != reason { vtDisabledReason = reason }
    }

    //rebuild (selected process') items
    func rebuildItems() {
        uiLog.debug("rebuild items")
        guard let pid = selectedPID, let item = processesByPID[pid] ?? processes.first(where: { $0.id == pid }) else {
            dylibs = []; files = []; connections = []
            return
        }
        let task = item.task
        //dylibs: while the shared cache dylibs are being enumerated (vmmap) for display, keep the list empty
        // ->so the pane shows 'enumerating' rather than the (disk-only) list, then a jump to the full one
        if itemsTab == .dylibs, showCacheDylibs, itemsLoading, !task.cacheDylibsEnumerated, pid != 0 {
            dylibs = []
        } else {
            dylibs = (task.dylibsSnapshot() ?? []).map { DylibItem(binary: $0) }
        }
        files = (task.filesSnapshot() ?? []).map { FileItem(file: $0) }
        connections = (task.connectionsSnapshot() ?? []).map { ConnectionItem(connection: $0, pid: pid) }

        //selected item gone? fall back to the process (not while still loading: the lists are empty meanwhile)
        if !itemsLoading { resolveSelectedItem(pid: pid) }
    }

    //selected item gone (dylib unloaded, file closed, connection gone)? fall back to the process
    private func resolveSelectedItem(pid: Int) {
        switch selectedItem {
        case .dylib(let id) where !dylibs.contains(where: { $0.id == id }): selectedItem = .process(pid)
        case .file(let id) where !files.contains(where: { $0.id == id }): selectedItem = .process(pid)
        case .connection(let id) where !connections.contains(where: { $0.id == id }): selectedItem = .process(pid)
        default: break
        }
    }

    //process for pid
    func process(_ pid: Int) -> ProcessItem? { processesByPID[pid] }

    //(re)enumerate the selected process' items for the current tab
    // ->so what's shown is always fresh (e.g. unloaded dylibs, closed files)
    func refreshSelectedItems() {
        guard let pid = selectedPID, let item = processesByPID[pid] else { return }
        let view: UInt
        switch itemsTab {
        case .dylibs: view = UInt(DYLIBS_VIEW)
        case .files: view = UInt(FILES_VIEW)
        case .network: view = UInt(NETWORKING_VIEW)
        }
        //mark loading (cleared by the matching 'items changed' notification, or after 10s)
        itemsLoading = true
        itemsLoadingToken += 1
        let token = itemsLoadingToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            //timed out (e.g. extension gone): show what's known, rather than an emptied list
            if let self, self.itemsLoadingToken == token { self.itemsLoading = false; self.rebuildItems() }
        }
        taskEnumerator?.refreshItems(item.task, view: view)
    }

    /* FILTERING */

    //does task match (text + tokens)?
    func matches(_ item: ProcessItem) -> Bool {
        for token in tokens where !filter.taskFulfillsKeyword(token.keyword, task: item.task) { return false }
        let text = appliedQuery.trimmingCharacters(in: .whitespaces)
        if text.isEmpty { return true }
        //a #keyword (or one still being typed: '#', '#ad'...): match by keyword, or don't filter on text yet
        if text.hasPrefix("#") { return filter.isKeyword(text) ? filter.taskFulfillsKeyword(text, task: item.task) : true }
        return item.name.localizedCaseInsensitiveContains(text) || item.path.localizedCaseInsensitiveContains(text) || String(item.id) == text
    }

    //filtering active?
    var isFiltering: Bool { !tokens.isEmpty || !appliedQuery.trimmingCharacters(in: .whitespaces).isEmpty }

    //(human readable) description of the current filter, e.g. '#adhoc "foo"'
    var filterDescription: String {
        var parts = tokens.map { $0.keyword }
        let text = appliedQuery.trimmingCharacters(in: .whitespaces)
        if !text.isEmpty { parts.append("“\(text)”") }
        return parts.joined(separator: " ")
    }

    //visible processes (flat)
    var visibleProcesses: [ProcessItem] { isFiltering ? processes.filter(matches) : processes }

    //visible dylibs (bottom pane filter)
    var visibleDylibs: [DylibItem] {
        //shared cache dylibs are hidden unless asked for (they're ~1200 Apple dylibs in nearly every process)
        // ->except when filtering for them explicitly
        let base = showCacheDylibs ? dylibs : dylibs.filter { !$0.inCache }
        return filterItems(base, query: appliedItemsQuery) { $0.name.localizedCaseInsensitiveContains($1) || $0.path.localizedCaseInsensitiveContains($1) } keyword: { filter.binaryFulfillsKeyword($1, binary: $0.binary) }
    }
    var visibleFiles: [FileItem] { filterItems(files, query: appliedItemsQuery) { $0.name.localizedCaseInsensitiveContains($1) || $0.path.localizedCaseInsensitiveContains($1) } keyword: { _, _ in true } }
    var visibleConnections: [ConnectionItem] { filterItems(connections, query: appliedItemsQuery) { c, t in c.local.localizedCaseInsensitiveContains(t) || c.remote.localizedCaseInsensitiveContains(t) || c.proto.localizedCaseInsensitiveContains(t) || c.state.localizedCaseInsensitiveContains(t) || c.interface.localizedCaseInsensitiveContains(t) } keyword: { _, _ in true } }

    private func filterItems<T>(_ items: [T], query: String, text: (T, String) -> Bool, keyword: (T, String) -> Bool) -> [T] {
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return items }
        if q.hasPrefix("#") { return filter.isKeyword(q) ? items.filter { keyword($0, q) } : [] }
        return items.filter { text($0, q) }
    }

    /* GLOBAL SEARCH */

    //search everything (processes, dylibs, files, connections)
    func searchEverything() -> [SearchResult] {
        guard let enumerator = taskEnumerator else { return [] }
        let text = appliedQuery.trimmingCharacters(in: .whitespaces)
        var results: [SearchResult] = []
        let keywordOnly = text.hasPrefix("#")

        //processes
        results += visibleProcesses.map { .process($0) }

        //dylibs
        let allDylibs = (enumerator.allDylibs() as? [Binary]) ?? []
        for binary in allDylibs {
            var ok = true
            for token in tokens where !filter.binaryFulfillsKeyword(token.keyword, binary: binary) { ok = false; break }
            guard ok else { continue }
            if keywordOnly {
                if filter.isKeyword(text), !filter.binaryFulfillsKeyword(text, binary: binary) { continue }
            } else if !text.isEmpty, !(binary.name ?? "").localizedCaseInsensitiveContains(text), !binary.path.localizedCaseInsensitiveContains(text) { continue }
            results.append(.dylib(DylibItem(binary: binary)))
        }

        //files & connections (text only)
        if !keywordOnly, tokens.isEmpty, !text.isEmpty {
            for file in (enumerator.allFiles() as? [File]) ?? [] where file.path.localizedCaseInsensitiveContains(text) {
                results.append(.file(FileItem(file: file)))
            }
            for connection in (enumerator.allConnections() as? [Connection]) ?? [] {
                let pid = (connection.hosts?.anyObject() as? NSNumber)?.intValue ?? 0
                let item = ConnectionItem(connection: connection, pid: pid)
                if item.local.localizedCaseInsensitiveContains(text) || item.remote.localizedCaseInsensitiveContains(text) || item.proto.localizedCaseInsensitiveContains(text) {
                    results.append(.connection(item))
                }
            }
        }
        return results
    }

    /* ACTIONS */

    //scroll request (pid + token, so repeated requests for the same pid still fire)
    // ->set only for programmatic selection (inspector host list, assistant), so the table doesn't jump under the user's own clicks
    struct ScrollRequest: Equatable { let pid: Int; let token: Int }
    @Published var scrollTarget: ScrollRequest?

    //select process (and show in table)
    func select(pid: Int) {
        //gone (e.g. a host task that just exited)? nothing to select
        guard processesByPID[pid] != nil else { NSSound.beep(); return }
        selectedPID = pid
        scrollTarget = ScrollRequest(pid: pid, token: (scrollTarget?.token ?? 0) + 1)
    }

    //show in finder
    func showInFinder(_ path: String) {
        //no such file (deleted binary, dyld shared cache dylib, unlinked socket)? reveal its folder instead
        if !FileManager.default.fileExists(atPath: path) {
            let folder = (path as NSString).deletingLastPathComponent
            if !folder.isEmpty, FileManager.default.fileExists(atPath: folder) { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder) } else { NSSound.beep() }
            return
        }
        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
    }

    //refresh (re-enumerate)
    func refresh() {
        (NSApp.delegate as? AppDelegate)?.refreshTasks(nil)
    }

    //submit binary to VT
    // ->confirms first (it's an upload), then waits for the analysis to complete before the (normal) lookup, so the
    //   result isn't a premature 'unknown' (which would be cached)
    func submitToVirusTotal(_ binary: Binary, completion: @escaping (String?) -> Void) {
        let name = (binary.path as NSString?)?.lastPathComponent ?? "this file"
        guard showAlert(.informational, "Upload “\(name)” to VirusTotal?", binary.path ?? "", ["Upload", "Cancel"]) == .alertFirstButtonReturn else { return }
        //(objective-c) model object; the completion only touches it back on the main queue
        nonisolated(unsafe) let binary = binary
        virusTotal?.submit(binary) { result in
            DispatchQueue.main.async {
                if let error = result?[VT_ERROR] {
                    completion((error as? NSError)?.localizedDescription ?? "\(error)")
                } else {
                    binary.vtInfo = nil
                    virusTotal?.forgetResult(binary)
                    //refresh (the row now shows 'pending' rather than the old result)
                    self.rebuildProcesses(); self.rebuildItems()
                    if let url = result?[VT_RESULTS_URL] as? String, let reportURL = URL(string: url) {
                        NSWorkspace.shared.open(reportURL)
                    }
                    //look up once the analysis is done (polls in the background; times out into a plain lookup)
                    if let analysisID = result?[VT_ANALYSIS_ID] as? String {
                        virusTotal?.wait(forAnalysis: analysisID) { _ in virusTotal?.addItem(binary) }
                    }
                    completion(nil)
                }
            }
        }
    }
}
