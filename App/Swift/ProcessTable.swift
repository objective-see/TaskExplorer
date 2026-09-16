//
//  ProcessTable.swift
//  TaskExplorer (app)
//
//  Created by Patrick Wardle on 9/12/26.
//  Copyright (c) 2026 Objective-See. All rights reserved.
//
//  note: top pane; all processes (flat, sortable) or hierarchical (tree)

import SwiftUI
import os

//ui log
let uiLog = Logger(subsystem: "com.objective-see.taskexplorer", category: "ui")

struct ProcessTable: View {

    @EnvironmentObject var store: Store

    //sort
    @State private var sortOrder: [KeyPathComparator<ProcessItem>] = [KeyPathComparator(\.name, comparator: .localizedStandard)]

    //rows (flat & tree), cached
    // ->recomputed only when their inputs change; computing them in 'body' re-filtered and re-sorted ~1000 rows
    //   several times per store publish (i.e. several times per second under live monitoring)
    @State private var rows: [ProcessItem] = []
    @State private var treeRows: [ProcessItem] = []

    private func recomputeRows() {
        //note: pid as final tiebreaker, so rows w/ equal keys (e.g. same name) keep a stable order across rebuilds
        let flat = store.visibleProcesses.sorted(using: sortOrder + [KeyPathComparator(\.id)])
        if flat != rows { rows = flat }
        let tree = (store.viewMode == .tree && !store.isFiltering) ? store.visibleTreeRows : []
        if tree != treeRows { treeRows = tree }
    }

    //row to reveal (index into the current rows) + a token so repeated reveals of the same row still fire
    @State private var revealIndex: Int?
    @State private var revealToken: Int = 0

    var body: some View {
        table
            //note: ScrollViewReader.scrollTo is a no-op for Table on macOS, so an AppKit hook scrolls the NSTableView
            .background(TableScroller(rowIndex: revealIndex, token: revealToken, ids: currentIDs, selectedID: store.selectedPID))
            .background(TableSelectionKeeper(ids: currentIDs, selectedID: store.selectedPID, select: { pid in
                if store.selectedPID != pid { store.selectedPID = pid }
            }))
            .onAppear { selection = store.selectedPID }
            .onChange(of: selection) { _, new in
                uiLog.debug("table selection: \(String(describing: store.selectedPID)) -> \(String(describing: new))")
                if store.selectedPID != new { store.selectedPID = new }
            }
            .onChange(of: store.selectedPID) { _, new in
                if selection != new { selection = new }
            }
            .onAppear {
                recomputeRows()
                //a selection made while this table wasn't showing (e.g. from the 'Everything' results)
                if let request = store.scrollTarget { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { reveal(request.pid) } }
            }
            .onChange(of: store.processes) { _, _ in recomputeRows() }
            .onChange(of: store.processTree) { _, _ in recomputeRows() }
            .onChange(of: store.collapsedPIDs) { _, _ in recomputeRows() }
            .onChange(of: store.tokens) { _, _ in recomputeRows() }
            .onChange(of: store.appliedQuery) { _, _ in recomputeRows() }
            .onChange(of: store.viewMode) { _, _ in recomputeRows() }
            .onChange(of: sortOrder) { _, _ in recomputeRows() }
            .onChange(of: store.scrollTarget) { _, request in
                guard let request else { return }
                reveal(request.pid)
            }
            .onChange(of: structureKey) { _, _ in
                //view mode / tokens changed (table is rebuilt): keep the selected row in view
                // ->twice, as the rebuilt table may not have laid out all its rows yet on the first try
                guard let pid = store.selectedPID else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { reveal(pid) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { reveal(pid) }
            }
    }

    //ids of the rows currently shown (in table order)
    private var currentIDs: [Int] {
        ((store.viewMode == .tree && !store.isFiltering) ? treeRows : rows).map(\.id)
    }

    //reveal (scroll to) row for pid
    private func reveal(_ pid: Int) {
        let current = (store.viewMode == .tree && !store.isFiltering) ? treeRows : rows
        guard let index = current.firstIndex(where: { $0.id == pid }) else { return }
        revealIndex = index
        revealToken += 1
    }

    //table (flat or tree)
    private var table: some View {
        Group {
            if store.viewMode == .tree, !store.isFiltering {
                //note: flattened (w/ depth + chevrons) rather than SwiftUI's outline table, so it can start fully expanded
                //note: sort headers are inert in tree view (rows keep their tree order)
                Table(treeRows, selection: $selection, sortOrder: .constant(sortOrder)) { columns }
                    .contextMenu {
                        Button("Expand All") { store.expandAll() }
                        Button("Collapse All") { store.collapseAll() }
                    }
            } else {
                Table(rows, selection: $selection, sortOrder: sortBinding) { columns }
            }
        }
        //note: a filter change swaps (nearly) the whole row set; diffing that as row insert/removes is very slow
        //      (AppKit tears down every hosted cell view), so key the table on the filter to force a (fast) reload instead
        .id(tableKey)
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .contextMenu(forSelectionType: ProcessItem.ID.self) { pids in
            if let pid = pids.first, let item = store.process(pid) { ProcessMenuItems(item: item) }
        } primaryAction: { pids in
            if let pid = pids.first { store.selectedPID = pid; store.showInspector = true }
        }
        .overlay {
            if store.processes.isEmpty, store.status == nil {
                ContentUnavailableView("Enumerating Processes…", systemImage: "cpu")
            } else if store.isFiltering, rows.isEmpty {
                ContentUnavailableView("No Matches", systemImage: "magnifyingglass", description: Text("No processes match \(store.filterDescription)."))
            }
        }
    }

    //table identity (view mode + filter)
    // ->the (debounced) applied query, so typing doesn't rebuild the table per keystroke
    private var tableKey: String {
        "\(store.viewMode.rawValue)|\(store.tokens.map { $0.keyword }.joined(separator: ","))|\(store.appliedQuery.trimmingCharacters(in: .whitespaces))"
    }

    //structure key (no text): a change here is worth scrolling the selection back into view
    private var structureKey: String { "\(store.viewMode.rawValue)|\(store.tokens.map { $0.keyword }.joined(separator: ","))" }


    //sort binding
    // ->ignores sorting by the VirusTotal column while VT is off (nothing to sort by)
    private var sortBinding: Binding<[KeyPathComparator<ProcessItem>]> {
        Binding(get: { sortOrder }, set: { new in
            if !store.vtEnabled, new.first?.keyPath == \ProcessItem.vt { return }
            sortOrder = new
        })
    }

    //selection (local state, synced with the store)
    // ->the Table owns its selection via plain @State, decoupled from the store's multi-property publishes:
    //   with a Binding straight into the store, a click's mouse-up sometimes re-applied the previous selection
    @State private var selection: ProcessItem.ID?

    //columns
    @TableColumnBuilder<ProcessItem, KeyPathComparator<ProcessItem>>
    private var columns: some TableColumnContent<ProcessItem, KeyPathComparator<ProcessItem>> {
        TableColumn("Process", value: \.name) { item in
            HStack(spacing: 8) {
                if item.vt.isFlagged { Image(systemName: "flag.fill").foregroundStyle(.red).font(.caption).accessibilityLabel("Flagged by VirusTotal") }
                if store.viewMode == .tree, !store.isFiltering {
                    //indent + disclosure chevron
                    Color.clear.frame(width: CGFloat(item.depth) * 14, height: 1)
                    if !(item.children ?? []).isEmpty {
                        Button { store.toggleCollapsed(item.id) } label: {
                            Image(systemName: "chevron.right")
                                .accessibilityLabel(store.collapsedPIDs.contains(item.id) ? "Expand" : "Collapse")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .rotationEffect(.degrees(store.collapsedPIDs.contains(item.id) ? 0 : 90))
                                .frame(width: 12)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Color.clear.frame(width: 12, height: 1)
                    }
                }
                Image(nsImage: item.icon ?? NSWorkspace.shared.icon(for: .unixExecutable))
                    .resizable().frame(width: 20, height: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.name)
                        .foregroundStyle(item.vt.isFlagged ? Color.red : Color.primary)
                        .fontWeight(item.vt.isFlagged ? .semibold : .regular)
                    Text(item.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
            }
            .help(item.path)
        }
        .width(min: 160, ideal: 380)

        TableColumn("PID", value: \.id) { item in
            Text(String(item.id)).monospacedDigit()
        }
        .width(min: 50, ideal: 64, max: 90)

        TableColumn("User", value: \.user) { item in
            Text(item.user)
        }
        .width(min: 60, ideal: 90, max: 160)

        TableColumn("Signing", value: \.signer) { item in
            SignerLabel(signer: item.signer, isApple: item.isApple, notFound: item.notFound, error: item.signingError, pending: item.signingPending, isProcess: true)
        }
        .width(min: 80, ideal: 120, max: 160)

        TableColumn("VirusTotal", value: \.vt) { item in
            if store.vtEnabled { VTLabel(status: item.vt) } else { VTOffLabel(reason: store.vtDisabledReason) }
        }
        .width(min: 60, ideal: 84, max: 110)

        TableColumn("") { item in
            Menu { ProcessMenuItems(item: item) } label: { Image(systemName: "ellipsis.circle").accessibilityLabel("Actions") }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
        }
        .width(28)
    }
}

//scrolls the (AppKit) table view backing a SwiftUI Table to a row (centered)
struct TableScroller: NSViewRepresentable {
    let rowIndex: Int?
    let token: Int

    //row ids (in table order) + selection: to keep the view anchored while rows come and go (live monitoring)
    // ->NSTableView keeps its scroll offset in points, so rows removed/inserted above the visible ones shift the content
    let ids: [Int]
    let selectedID: Int?

    func makeNSView(context: Context) -> NSView { NSView(frame: .zero) }

    func updateNSView(_ view: NSView, context: Context) {
        let coordinator = context.coordinator

        //(re)anchor after the rows changed
        if coordinator.ids != ids {
            coordinator.ids = ids
            coordinator.selectedID = selectedID
            coordinator.updating = true
            DispatchQueue.main.async {
                guard let table = Self.findTable(near: view), let scrollView = table.enclosingScrollView else { coordinator.updating = false; return }
                coordinator.observe(scrollView, table: table)
                coordinator.restoreAnchor(table: table, scrollView: scrollView)
                coordinator.updating = false
            }
        } else if coordinator.selectedID != selectedID {
            coordinator.selectedID = selectedID
        }

        //explicit reveal (scroll to row)
        guard let index = rowIndex, coordinator.lastToken != token else { return }
        coordinator.lastToken = token
        DispatchQueue.main.async {
            guard let table = Self.findTable(near: view), index < table.numberOfRows, let scrollView = table.enclosingScrollView else { return }
            coordinator.observe(scrollView, table: table)
            table.layoutSubtreeIfNeeded()
            let rowRect = table.rect(ofRow: index)
            let clip = scrollView.contentView
            let (minY, maxY) = Coordinator.scrollRange(table: table, clip: clip)
            let y = max(minY, min(rowRect.midY - clip.bounds.height / 2, maxY))
            clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: y))
            scrollView.reflectScrolledClipView(clip)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var lastToken = -1
        var ids: [Int] = []
        var selectedID: Int?
        var updating = false

        //anchor: a row id + its offset from the top of the visible area
        private var anchorID: Int?
        private var anchorOffset: CGFloat = 0
        private var observer: NSObjectProtocol?
        private weak var observedClip: NSClipView?

        deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

        //record the anchor whenever the user scrolls (or the view resizes)
        func observe(_ scrollView: NSScrollView, table: NSTableView) {
            let clip = scrollView.contentView
            guard observedClip !== clip else { return }
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observedClip = clip
            clip.postsBoundsChangedNotifications = true
            observer = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: .main) { [weak self, weak table, weak clip] _ in
                guard let self, let table, let clip, !self.updating else { return }
                self.recordAnchor(table: table, clip: clip)
            }
            recordAnchor(table: table, clip: clip)
        }

        private func recordAnchor(table: NSTableView, clip: NSClipView) {
            let visible = clip.bounds
            guard table.numberOfRows > 0, visible.height > 0 else { anchorID = nil; return }
            //prefer the selected row (if visible), else the first (fully) visible row
            var index = -1
            if let selectedID, let selectedIndex = ids.firstIndex(of: selectedID), selectedIndex < table.numberOfRows, table.rect(ofRow: selectedIndex).intersects(visible) {
                index = selectedIndex
            } else {
                index = table.row(at: NSPoint(x: visible.minX, y: visible.minY + 1))
                if index >= 0, table.rect(ofRow: index).minY < visible.minY - 0.5, index + 1 < table.numberOfRows { index += 1 }
            }
            guard index >= 0, index < ids.count else { anchorID = nil; return }
            anchorID = ids[index]
            anchorOffset = table.rect(ofRow: index).minY - visible.minY
        }

        //after a data change: scroll so the anchor row sits where it was
        func restoreAnchor(table: NSTableView, scrollView: NSScrollView) {
            let clip = scrollView.contentView
            defer { if anchorID == nil || !ids.contains(anchorID!) { recordAnchor(table: table, clip: clip) } }
            guard let anchorID, let index = ids.firstIndex(of: anchorID), index < table.numberOfRows else { return }
            table.layoutSubtreeIfNeeded()
            let rowRect = table.rect(ofRow: index)
            let (minY, maxY) = Coordinator.scrollRange(table: table, clip: clip)
            let y = max(minY, min(rowRect.minY - anchorOffset, maxY))
            guard abs(y - clip.bounds.minY) > 0.5 else { return }
            uiLog.debug("anchor: scrolling \(clip.bounds.minY) -> \(y) (range \(minY)...\(maxY), rows=\(table.numberOfRows))")
            clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: y))
            scrollView.reflectScrolledClipView(clip)
        }

        //valid scroll offsets (clip bounds origin y) for the table
        // ->note: the table's scroll view extends under the toolbar (and the header): "scrolled to top" is a NEGATIVE
        //   origin (-contentInsets.top, e.g. -80, or -116 with the search scope bar). Clamping to 0 dragged the rows up
        //   under the toolbar on every rows change: invisible with hundreds of rows, but a filtered handful vanished
        static func scrollRange(table: NSTableView, clip: NSClipView) -> (CGFloat, CGFloat) {
            let insets = clip.contentInsets
            let minY = -insets.top
            let contentHeight = table.numberOfRows > 0 ? table.rect(ofRow: table.numberOfRows - 1).maxY : 0
            let maxY = max(minY, contentHeight + insets.bottom - clip.bounds.height)
            return (minY, maxY)
        }
    }

    //find the table view this background view belongs to (by geometry; see TableSelectionKeeper)
    private static func findTable(near view: NSView) -> NSTableView? { TableSelectionKeeper<Int>.findTable(near: view) }
}

//signer label (icon + text)
struct SignerLabel: View {
    let signer: SignerKind
    let isApple: Bool
    var notFound: Bool = false
    var error: Bool = false
    var pending: Bool = false
    var isProcess: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(text).foregroundStyle(color)
        }
        .font(.callout)
        .help(help)
    }

    private var symbol: String {
        if pending { return "ellipsis" }
        if error { return "exclamationmark.triangle" }
        if notFound { return "questionmark.circle" }
        return isApple ? "apple.logo" : signer.symbol
    }

    private var text: String {
        if pending { return "" }
        if error { return "error" }
        if notFound { return "not found" }
        return isApple ? "Apple" : signer.label
    }

    private var help: String {
        if pending { return "Checking code signature…" }
        if error { return "Code signing check failed (the extension did not respond)" }
        if notFound { return "Binary not found on disk" }
        return isApple ? (isProcess ? "Signed by Apple" : "Signed by Apple (or in the dyld shared cache)") : "Signer: \(signer.label)"
    }

    private var color: Color {
        if pending { return .secondary }
        if error { return .orange }
        if notFound { return .secondary }
        if isApple { return .secondary }
        switch signer {
        case .none: return .red
        case .adHoc: return .orange
        default: return .primary
        }
    }
}

//virus total label
struct VTLabel: View {
    let status: VTStatus

    var body: some View {
        Group {
            if let url = status.url {
                Button { NSWorkspace.shared.open(url) } label: {
                    Text(status.label).underline().monospacedDigit()
                        .foregroundStyle(status.isFlagged ? Color.red : Color.primary)
                        .fontWeight(status.isFlagged ? .bold : .regular)
                }
                .buttonStyle(.plain)
                .help("Open VirusTotal report")
            } else {
                Text(status.label).foregroundStyle(.secondary).monospacedDigit()
                    .help(help)
            }
        }
        .font(.callout)
    }

    private var help: String {
        switch status {
        case .pending: return "VirusTotal lookup pending"
        case .unknown: return "Unknown to VirusTotal"
        case .error: return "VirusTotal lookup failed"
        case .disabled: return "VirusTotal disabled (set an API key in Settings)"
        case .skipped: return "Not checked: Apple/platform binaries (and dylibs in the dyld shared cache) are skipped to conserve your VirusTotal quota"
        default: return ""
        }
    }
}

//virus total 'off' label (no key, disabled, offline)
struct VTOffLabel: View {
    let reason: String

    var body: some View {
        Text(reason)
            .font(.callout)
            .foregroundStyle(.tertiary)
            .help(reason == "no API key" ? "VirusTotal lookups are off: add your (personal) VirusTotal API key in Settings" :
                  reason == "disabled" ? "VirusTotal lookups are disabled (see Settings)" : "VirusTotal lookups are off: no network connection")
    }
}

//per-process menu items (hamburger / context menu)
struct ProcessMenuItems: View {
    @EnvironmentObject var store: Store
    let item: ProcessItem

    var body: some View {
        Button("More Info") { store.selectedPID = item.id; store.showInspector = true }
        Button("Show in Finder") { store.showInFinder(item.path) }
        Button("Copy Path") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(item.path, forType: .string) }
        Divider()
        VTMenuItems(binary: item.task.binary, status: item.vt)
    }
}

//virus total menu items
struct VTMenuItems: View {
    @EnvironmentObject var store: Store
    let binary: Binary
    let status: VTStatus

    var body: some View {
        if let url = status.url {
            Button("VirusTotal Report") { NSWorkspace.shared.open(url) }
        }
        if case .unknown = status {
            Button("Submit to VirusTotal…") {
                store.submitToVirusTotal(binary) { error in
                    if let error {
                        showAlert(.warning, "VirusTotal submission failed", error, ["OK"])
                    }
                }
            }
        }
    }
}
