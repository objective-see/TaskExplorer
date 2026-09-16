//
//  ItemsPane.swift
//  TaskExplorer (app)
//
//  Created by Patrick Wardle on 9/12/26.
//  Copyright (c) 2026 Objective-See. All rights reserved.
//
//  note: bottom pane; selected process' dylibs, files, or network connections

import SwiftUI

struct ItemsPane: View {

    @EnvironmentObject var store: Store

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("", selection: $store.itemsTab) {
                    ForEach(ItemsTab.allCases) { tab in Text(tab.rawValue).tag(tab) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()

                if store.itemsTab == .dylibs {
                    Toggle("Include shared cache dylibs", isOn: $store.showCacheDylibs)
                        .toggleStyle(.checkbox)
                        .font(.callout)
                        .fixedSize()
                        .layoutPriority(1)
                        .padding(.leading, 14)
                        .disabled(store.selectionIsESClient)
                        .help("Also list dylibs loaded from the dyld shared cache (enumerated via vmmap for this process; enable indexing for all processes in Settings › Dylibs)")
                    if store.selectionIsESClient {
                        Text("not for Endpoint Security clients (vmmap would suspend it)").font(.caption).foregroundStyle(.secondary).fixedSize()
                            .help("vmmap suspends the process it inspects; an Endpoint Security client that misses an auth deadline while suspended is killed by the kernel. Dylibs mapped from disk are still listed.")
                    }
                }

                Spacer()

                if let pid = store.selectedPID, let process = store.process(pid) {
                    Text(verbatim: "\(process.name) (\(pid))").font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).layoutPriority(-1)
                }

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(store.itemsTab == .dylibs ? "Filter dylibs (or #keyword)" : "Filter \(store.itemsTab.rawValue.lowercased())", text: $store.itemsQuery)
                        .textFieldStyle(.plain)
                        .onSubmit { NSApp.keyWindow?.makeFirstResponder(nil) }
                        .onExitCommand { store.itemsQuery = ""; NSApp.keyWindow?.makeFirstResponder(nil) }
                    if !store.itemsQuery.isEmpty {
                        Button { store.itemsQuery = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary).accessibilityLabel("Clear filter") }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
                .frame(minWidth: 120, idealWidth: 260, maxWidth: 260)
            }
            .padding(.leading, 16)
            .padding(.trailing, 8)
            .padding(.vertical, 6)
            .background(.bar)

            Divider()

            if store.selectedPID == nil {
                ContentUnavailableView("Select a Process", systemImage: "arrow.up", description: Text("Its dylibs, files, and network connections will be shown here."))
            } else {
                switch store.itemsTab {
                case .dylibs: DylibTable()
                case .files: FileTable()
                case .network: ConnectionTable()
                }
            }
        }
    }
}

//dylibs
struct DylibTable: View {
    @EnvironmentObject var store: Store
    @State private var sortOrder: [KeyPathComparator<DylibItem>] = [KeyPathComparator(\.name, comparator: .localizedStandard)]

    var body: some View {
        let rows = store.visibleDylibs.sorted(using: sortOrder + [KeyPathComparator(\.id)])
        let sortBinding = Binding<[KeyPathComparator<DylibItem>]>(get: { sortOrder }, set: { new in
            //ignore sorting by VirusTotal while VT is off
            if !store.vtEnabled, new.first?.keyPath == \DylibItem.vt { return }
            sortOrder = new
        })
        Table(rows, selection: $selection, sortOrder: sortBinding) {
            TableColumn("Dylib", value: \.name) { item in
                HStack(spacing: 8) {
                    Image(nsImage: item.icon ?? NSWorkspace.shared.icon(for: .unixExecutable)).resizable().frame(width: 18, height: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.name).foregroundStyle(item.vt.isFlagged ? Color.red : Color.primary)
                        Text(item.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                }
                .help(item.path)
            }
            .width(min: 240, ideal: 420)
            TableColumn("Signing", value: \.signer) { item in
                SignerLabel(signer: item.signer, isApple: item.isApple, notFound: item.notFound, error: item.signingError, pending: item.signingPending)
            }
            .width(min: 90, ideal: 120, max: 160)
            TableColumn("Team ID", value: \.teamID) { item in Text(item.teamID).font(.callout).foregroundStyle(.secondary) }
                .width(min: 80, ideal: 100, max: 140)
            TableColumn("Loaded in", value: \.hostCount) { item in Text(String(item.hostCount)).monospacedDigit() }
                .width(min: 60, ideal: 70, max: 90)
            TableColumn("VirusTotal", value: \.vt) { item in
                if store.vtEnabled { VTLabel(status: item.vt) } else { VTOffLabel(reason: store.vtDisabledReason) }
            }
            .width(min: 70, ideal: 84, max: 110)
            TableColumn("") { item in
                Menu { DylibMenuItems(item: item) } label: { Image(systemName: "ellipsis.circle").accessibilityLabel("Actions") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }
            .width(28)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .background(TableSelectionKeeper(ids: rows.map(\.id), selectedID: selection, select: { id in selection = id }))
        .onAppear { selection = storeSelection }
        .onChange(of: selection) { _, new in
            uiLog.debug("dylibs table selection -> \(new == nil ? "nil" : "row")")
            let wanted: SelectedItem? = new.map { .dylib($0) } ?? store.selectedPID.map { .process($0) }
            if store.selectedItem != wanted { store.selectedItem = wanted }
        }
        .onChange(of: store.selectedItem) { _, _ in if selection != storeSelection { selection = storeSelection } }
        //note: keyed, so a new selection / cache toggle / filter reloads the table rather than diffing ~1000 row inserts
        //      (which stalls the main thread for seconds); live updates for the same selection still diff incrementally
        .id("dylibs|\(store.selectedPID ?? 0)|\(store.showCacheDylibs)|\(store.appliedItemsQuery)")
        .contextMenu(forSelectionType: DylibItem.ID.self) { ids in
            if let id = ids.first, let item = rows.first(where: { $0.id == id }) { DylibMenuItems(item: item) }
        } primaryAction: { ids in
            if let id = ids.first { store.selectedItem = .dylib(id); store.showInspector = true }
        }
        .overlay { if rows.isEmpty { ItemsEmptyState(kind: "dylibs", symbol: "shippingbox") } }
    }

    //selection (local state, synced with the store; see TableSelectionKeeper)
    @State private var selection: DylibItem.ID?
    private var storeSelection: DylibItem.ID? {
        if case .dylib(let id) = store.selectedItem { return id }
        return nil
    }
}

struct DylibMenuItems: View {
    @EnvironmentObject var store: Store
    let item: DylibItem
    var body: some View {
        Button("More Info") { store.selectedItem = .dylib(item.id); store.showInspector = true }
        Button("Show in Finder") { store.showInFinder(item.path) }
        Button("Copy Path") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(item.path, forType: .string) }
        Divider()
        VTMenuItems(binary: item.binary, status: item.vt)
    }
}

//files
struct FileTable: View {
    @EnvironmentObject var store: Store
    @State private var sortOrder: [KeyPathComparator<FileItem>] = [KeyPathComparator(\.name, comparator: .localizedStandard)]

    var body: some View {
        let rows = store.visibleFiles.sorted(using: sortOrder + [KeyPathComparator(\.id)])
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("File", value: \.name) { item in
                HStack(spacing: 8) {
                    Image(nsImage: item.icon ?? NSWorkspace.shared.icon(for: .data)).resizable().frame(width: 18, height: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.name)
                        Text(item.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                }
                .help(item.path)
            }
            .width(min: 240, ideal: 520)
            TableColumn("Type", value: \.typeLabel) { item in
                Text(item.typeLabel).foregroundStyle(item.type == FILE_TYPE_FILE ? .primary : .secondary)
            }
            .width(min: 60, ideal: 80, max: 100)
            TableColumn("Open in", value: \.hostCount) { item in Text(String(item.hostCount)).monospacedDigit() }
                .width(min: 60, ideal: 70, max: 90)
            TableColumn("") { item in
                Menu {
                    Button("More Info") { store.selectedItem = .file(item.id); store.showInspector = true }
                    Button("Show in Finder") { store.showInFinder(item.path) }
                    Button("Copy Path") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(item.path, forType: .string) }
                } label: { Image(systemName: "ellipsis.circle").accessibilityLabel("Actions") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }
            .width(28)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .background(TableSelectionKeeper(ids: rows.map(\.id), selectedID: selection, select: { id in selection = id }))
        .onAppear { selection = storeSelection }
        .onChange(of: selection) { _, new in
            uiLog.debug("files table selection -> \(new == nil ? "nil" : "row")")
            let wanted: SelectedItem? = new.map { .file($0) } ?? store.selectedPID.map { .process($0) }
            if store.selectedItem != wanted { store.selectedItem = wanted }
        }
        .onChange(of: store.selectedItem) { _, _ in if selection != storeSelection { selection = storeSelection } }
        .id("files|\(store.selectedPID ?? 0)|\(store.appliedItemsQuery)")
        .contextMenu(forSelectionType: FileItem.ID.self) { ids in
            if let id = ids.first, let item = rows.first(where: { $0.id == id }) {
                Button("Show in Finder") { store.showInFinder(item.path) }
                Button("Copy Path") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(item.path, forType: .string) }
            }
        } primaryAction: { ids in
            if let id = ids.first { store.selectedItem = .file(id); store.showInspector = true }
        }
        .overlay { if rows.isEmpty { ItemsEmptyState(kind: "files", symbol: "doc") } }
    }

    //selection (local state, synced with the store; see TableSelectionKeeper)
    @State private var selection: FileItem.ID?
    private var storeSelection: FileItem.ID? {
        if case .file(let id) = store.selectedItem { return id }
        return nil
    }
}

//network connections
struct ConnectionTable: View {
    @EnvironmentObject var store: Store
    @State private var sortOrder: [KeyPathComparator<ConnectionItem>] = [KeyPathComparator(\.proto), KeyPathComparator(\.local)]

    var body: some View {
        let rows = store.visibleConnections.sorted(using: sortOrder + [KeyPathComparator(\.id)])
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Proto", value: \.proto) { item in Text(item.proto).font(.callout) }
                .width(min: 50, ideal: 60, max: 80)
            TableColumn("Local", value: \.local) { item in Text(item.local).font(.callout).monospacedDigit() }
                .width(min: 140, ideal: 200)
            TableColumn("Remote", value: \.remote) { item in Text(item.remote).font(.callout).monospacedDigit() }
                .width(min: 140, ideal: 200)
            TableColumn("State", value: \.state) { item in
                HStack(spacing: 4) {
                    Image(systemName: stateSymbol(item.state)).foregroundStyle(stateColor(item.state))
                    Text(item.state.isEmpty ? "—" : item.state)
                }
                .font(.callout)
            }
            .width(min: 90, ideal: 110, max: 140)
            TableColumn("Interface", value: \.interface) { item in Text(item.interface).font(.callout).foregroundStyle(.secondary) }
                .width(min: 60, ideal: 70, max: 100)
            TableColumn("Sent", value: \.bytesUp) { item in Text(ByteCountFormatter.string(fromByteCount: Int64(item.bytesUp), countStyle: .file)).font(.callout).monospacedDigit() }
                .width(min: 60, ideal: 80, max: 110)
            TableColumn("Received", value: \.bytesDown) { item in Text(ByteCountFormatter.string(fromByteCount: Int64(item.bytesDown), countStyle: .file)).font(.callout).monospacedDigit() }
                .width(min: 60, ideal: 80, max: 110)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .background(TableSelectionKeeper(ids: rows.map(\.id), selectedID: selection, select: { id in selection = id }))
        .onAppear { selection = storeSelection }
        .onChange(of: selection) { _, new in
            uiLog.debug("connections table selection -> \(new == nil ? "nil" : "row")")
            let wanted: SelectedItem? = new.map { .connection($0) } ?? store.selectedPID.map { .process($0) }
            if store.selectedItem != wanted { store.selectedItem = wanted }
        }
        .onChange(of: store.selectedItem) { _, _ in if selection != storeSelection { selection = storeSelection } }
        .id("net|\(store.selectedPID ?? 0)|\(store.appliedItemsQuery)")
        .contextMenu(forSelectionType: ConnectionItem.ID.self) { ids in
            if let id = ids.first, let item = rows.first(where: { $0.id == id }) {
                Button("Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString("\(item.proto) \(item.endpoints)", forType: .string) }
            }
        } primaryAction: { ids in
            if let id = ids.first { store.selectedItem = .connection(id); store.showInspector = true }
        }
        .overlay { if rows.isEmpty { ItemsEmptyState(kind: "connections", symbol: "network") } }
    }

    //selection (local state, synced with the store; see TableSelectionKeeper)
    @State private var selection: ConnectionItem.ID?
    private var storeSelection: ConnectionItem.ID? {
        if case .connection(let id) = store.selectedItem { return id }
        return nil
    }
}

//empty state for the items pane: enumerating, no matches, or (genuinely) nothing
struct ItemsEmptyState: View {
    @EnvironmentObject var store: Store
    let kind: String
    let symbol: String

    var body: some View {
        if store.itemsLoading && store.appliedItemsQuery.isEmpty {
            VStack(spacing: 10) {
                ProgressView().controlSize(.regular)
                Text("Enumerating \(kind)…").foregroundStyle(.secondary)
            }
        } else if !store.appliedItemsQuery.isEmpty {
            ContentUnavailableView("No Matches", systemImage: "magnifyingglass", description: Text("No \(kind) match “\(store.appliedItemsQuery)”."))
        } else {
            switch kind {
            case "dylibs":
                if store.selectedPID == 0 {
                    ContentUnavailableView("No Dylibs", systemImage: symbol, description: Text("The kernel doesn't load dylibs (kernel extensions aren't listed)."))
                } else if store.showCacheDylibs && store.selectionHasCacheDylibs {
                    ContentUnavailableView("No Dylibs", systemImage: symbol, description: Text("This process has no dylibs loaded."))
                } else if store.showCacheDylibs {
                    ContentUnavailableView("Shared Cache Dylibs Unavailable", systemImage: symbol,
                                           description: Text("vmmap could not enumerate this process (it may have exited). Select it again to retry."))
                } else {
                    ContentUnavailableView("No Dylibs Mapped From Disk", systemImage: symbol,
                                           description: Text("Dylibs loaded from the dyld shared cache aren't listed by default. Check “Include shared cache dylibs” above to list them (via vmmap)."))
                }
            case "files":
                ContentUnavailableView("No Open Files", systemImage: symbol, description: Text("This process has no regular files or unix domain sockets open."))
            default:
                ContentUnavailableView("No Network Connections", systemImage: symbol, description: Text("This process has no TCP or UDP sockets."))
            }
        }
    }
}

//connection state -> symbol/color
func stateSymbol(_ state: String) -> String {
    switch state {
    case "listening": return "antenna.radiowaves.left.and.right"
    case "established": return "arrow.left.arrow.right"
    case "closed": return "xmark.circle"
    case "": return "dot.radiowaves.up.forward"
    default: return "clock"
    }
}
func stateColor(_ state: String) -> Color {
    switch state {
    case "listening": return .blue
    case "established": return .green
    case "closed": return .secondary
    default: return .orange
    }
}
