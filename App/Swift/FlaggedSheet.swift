//
//  FlaggedSheet.swift
//  TaskExplorer (app)
//
//  Created by Patrick Wardle on 9/12/26.
//  Copyright (c) 2026 Objective-See. All rights reserved.
//
//  note: sheet listing all (VirusTotal) flagged items; processes & dylibs

import SwiftUI

struct FlaggedSheet: View {

    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "flag.fill").foregroundStyle(.red)
                Text("Flagged Items").font(.title3).fontWeight(.semibold)
                Spacer()
                Text(String(store.flagged.count)).foregroundStyle(.secondary)
            }
            .padding(16)

            Divider()

            if store.flagged.isEmpty {
                ContentUnavailableView("Nothing Flagged", systemImage: "checkmark.shield", description: Text(store.vtEnabled ? "No processes or dylibs have been flagged by VirusTotal." : (store.vtDisabledReason == "offline" ? "VirusTotal is unreachable (offline)." : "VirusTotal lookups are off. Enter an API key in Settings and turn them on.")))
                    .frame(maxHeight: .infinity)
            } else {
                List(store.flagged) { item in
                    HStack(spacing: 10) {
                        Image(nsImage: item.binary.icon ?? NSWorkspace.shared.icon(for: .unixExecutable)).resizable().frame(width: 28, height: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(item.name).fontWeight(.semibold).foregroundStyle(.red)
                                Text(item.isTaskBinary ? "process" : "dylib").font(.caption).padding(.horizontal, 5).padding(.vertical, 1).background(Capsule().fill(Color.secondary.opacity(0.2)))
                            }
                            Text(item.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                            if !item.hosts.isEmpty {
                                Text((item.isTaskBinary ? "running as: " : "Loaded in: ") + item.hosts.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                        Spacer()
                        VTLabel(status: item.vt)
                        Menu {
                            Button("Show in Finder") { store.showInFinder(item.path) }
                            if let url = item.vt.url { Button("VirusTotal Report") { NSWorkspace.shared.open(url) } }
                            if let host = (item.binary.hostTasks())?.first {
                                Button("Select Process") { store.select(pid: host.pid.intValue); dismiss() }
                            }
                        } label: { Image(systemName: "ellipsis.circle").accessibilityLabel("Actions") }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    }
                    .padding(.vertical, 4)
                }
                .frame(minHeight: 300)
            }

            Divider()
            HStack {
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.defaultAction)
                Button("") { dismiss() }.keyboardShortcut(.cancelAction).hidden().frame(width: 0, height: 0)
            }
            .padding(12)
        }
        .frame(minWidth: 620, idealWidth: 620, maxWidth: 900, minHeight: 440, idealHeight: 440, maxHeight: 800)
    }
}
