//
//  GlobalSearchView.swift
//  TaskExplorer (app)
//
//  Created by Patrick Wardle on 9/12/26.
//  Copyright (c) 2026 Objective-See. All rights reserved.
//
//  note: 'everything' search scope; results across processes, dylibs, files, & connections

import SwiftUI

struct GlobalSearchView: View {

    @EnvironmentObject var store: Store

    //results, cached (the scan walks every dylib/file/connection; not something to redo per body evaluation)
    @State private var results: [SearchResult] = []
    private func recompute() { results = store.searchEverything() }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(verbatim: "Everything matching \(store.filterDescription) · \(results.count) result\(results.count == 1 ? "" : "s")")
                    .font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                Spacer()
                if !store.cacheIndexEnabled {
                    Text("Shared cache dylibs are not indexed (Settings › Dylibs)").font(.caption).foregroundStyle(.tertiary)
                }
                //the default button (return), so a search is dismissed from the keyboard
                Button("Done") { store.scope = .processes }
                    .keyboardShortcut(.defaultAction)
            }
            //note: the height of the process table's column header (which the sidebar's header lines up with too)
            .padding(.horizontal, 12).padding(.top, 1).padding(.bottom, 2)
            .background(.bar)
            Rectangle().fill(Color(nsColor: .separatorColor)).frame(height: 1)
            if results.isEmpty {
                ContentUnavailableView("No Matches", systemImage: "magnifyingglass", description: Text("Nothing matches \(store.filterDescription)."))
                    //fill the view (else its content is centered vertically, and the header drifts down)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(results) { result in
                    switch result {
                    case .process(let p):
                        ResultRow(icon: p.icon, kind: "process", title: "\(p.name) (\(p.id))", subtitle: p.path, flagged: p.vt.isFlagged) {
                            store.scope = .processes; store.select(pid: p.id); store.showInspector = true
                        }
                    case .dylib(let d):
                        ResultRow(icon: d.icon, kind: "dylib", title: d.name, subtitle: "\(d.path) · loaded in \(d.hostCount)", flagged: d.vt.isFlagged) {
                            if let host = (d.binary.hostTasks())?.first {
                                store.scope = .processes; store.select(pid: host.pid.intValue); store.itemsTab = .dylibs
                                //note: after selecting (the toggle acts on the selected process)
                                if d.inCache { store.showCacheDylibs = true }
                                store.selectedItem = .dylib(d.id); store.showInspector = true
                            } else {
                                NSSound.beep()
                            }
                        }
                    case .file(let f):
                        ResultRow(icon: f.icon, kind: "file", title: f.name, subtitle: "\(f.path) · open in \(f.hostCount)", flagged: false) {
                            if let host = (f.file.hostTasks())?.first {
                                store.scope = .processes; store.select(pid: host.pid.intValue); store.itemsTab = .files; store.selectedItem = .file(f.id); store.showInspector = true
                            }
                        }
                    case .connection(let c):
                        ResultRow(icon: nil, kind: "connection", title: "\(c.proto) \(c.endpoints)", subtitle: (store.process(c.pid)?.name ?? "?") + " (\(c.pid)) · \(c.state)", flagged: false) {
                            store.scope = .processes; store.select(pid: c.pid); store.itemsTab = .network; store.selectedItem = .connection(c.id); store.showInspector = true
                        }
                    }
                }
            }
        }
        .onAppear { recompute() }
        .onChange(of: store.appliedQuery) { _, _ in recompute() }
        .onChange(of: store.tokens) { _, _ in recompute() }
        .onChange(of: store.processes) { _, _ in recompute() }
        .onChange(of: store.dylibs) { _, _ in recompute() }
    }
}

struct ResultRow: View {
    let icon: NSImage?
    let kind: String
    let title: String
    let subtitle: String
    let flagged: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(nsImage: icon ?? NSWorkspace.shared.icon(for: .unixExecutable)).resizable().frame(width: 20, height: 20)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(title).foregroundStyle(flagged ? Color.red : Color.primary)
                        Text(kind).font(.caption).padding(.horizontal, 5).padding(.vertical, 1).background(Capsule().fill(Color.secondary.opacity(0.2)))
                    }
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
