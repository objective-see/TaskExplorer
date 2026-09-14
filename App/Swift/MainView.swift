//
//  MainView.swift
//  TaskExplorer (app)
//
//  Created by Patrick Wardle on 9/12/26.
//  Copyright (c) 2026 Objective-See. All rights reserved.
//
//  note: main window layout: [assistant panel] | [processes / items] + inspector

import SwiftUI

struct MainView: View {

    @EnvironmentObject var store: Store

    //sidebar (assistant) visibility
    @State private var columns: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            AssistantPanel()
                .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 520)
        } detail: {
            content
                .inspector(isPresented: $store.showInspector) {
                    InspectorView()
                        .inspectorColumnWidth(min: 280, ideal: 340, max: 520)
                }
        }
        .navigationSplitViewStyle(.balanced)
        .searchable(text: $store.query, tokens: $store.tokens, suggestedTokens: .constant(suggestedTokens), placement: .toolbar, prompt: "Filter (name, path, pid, or #keyword)") { token in
            Text(token.keyword)
        }
        .onSubmit(of: .search) {
            //hand focus back to the window on return
            // ->otherwise the search field stays active, and the next click (e.g. on a row) is swallowed just to end the search
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
        .searchScopes($store.scope, activation: .onTextEntry) {
            ForEach(SearchScope.allCases) { scope in Text(scope.rawValue).tag(scope) }
        }
        .onChange(of: store.query) { _, newValue in
            //typing a complete keyword? convert to token
            let text = newValue.trimmingCharacters(in: .whitespaces)
            if text.hasPrefix("#"), store.filter.isKeyword(text), !store.tokens.contains(where: { $0.keyword == text.lowercased() }) {
                store.tokens.append(FilterToken(keyword: text.lowercased()))
                store.query = ""
            }
        }
        .onChange(of: store.showAssistant) { _, show in columns = show ? .all : .detailOnly }
        .onChange(of: columns) { _, visibility in store.showAssistant = (visibility != .detailOnly) }
        .onExitCommand { store.clearFilter(); NSApp.keyWindow?.makeFirstResponder(nil) }
        .toolbar { toolbarContent }
        .sheet(isPresented: $store.showFlagged) { FlaggedSheet() }
        .overlay { statusOverlay }
        .onAppear { columns = store.showAssistant ? .all : .detailOnly }
    }

    //main content (processes + items, or global search results)
    @ViewBuilder private var content: some View {
        VStack(spacing: 0) {
            if store.scope == .everything, store.isFiltering {
                GlobalSearchView()
            } else {
                //note: not a VSplitView, as that resets its divider whenever the (top) table is rebuilt (filter / view changes)
                VerticalSplit(minTop: 200, minBottom: 160) {
                    ProcessTable()
                } bottom: {
                    ItemsPane()
                }
            }
            Divider()
            BottomBar()
        }
    }

    //suggested (keyword) tokens
    private var suggestedTokens: [FilterToken] {
        let text = store.query.trimmingCharacters(in: .whitespaces).lowercased()
        //note: only once the user types '#'; showing them for an empty field pops a list under the toolbar
        //      that also swallows the next click elsewhere
        guard text.hasPrefix("#") else { return [] }
        let tokens = store.tokens
        let keywords = store.keywords.filter { keyword in !tokens.contains(where: { $0.keyword == keyword }) }
        return keywords.filter { $0.hasPrefix(text) }.map { FilterToken(keyword: $0) }
    }

    //toolbar
    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Picker("View", selection: Binding(get: { store.isFiltering ? .flat : store.viewMode }, set: { store.viewMode = $0 })) {
                Image(systemName: "list.bullet").tag(ViewMode.flat).accessibilityLabel("Flat view")
                Image(systemName: "list.bullet.indent").tag(ViewMode.tree).accessibilityLabel("Tree view")
            }
            .pickerStyle(.segmented)
            .disabled(store.isFiltering)
            .help(store.isFiltering ? "Tree view is unavailable while filtering" : "Flat or hierarchical (tree) view of processes")

            Button { store.showFlagged = true } label: {
                HStack(spacing: 3) {
                    Image(systemName: store.flagged.isEmpty ? "flag" : "flag.fill")
                        .foregroundStyle(store.flagged.isEmpty ? Color.primary : Color.red)
                    if !store.flagged.isEmpty {
                        Text(String(store.flagged.count)).font(.caption2.bold()).foregroundStyle(.red)
                    }
                }
            }
            .help("Flagged items (VirusTotal)")
            .accessibilityLabel(store.flagged.isEmpty ? "Flagged items" : "\(store.flagged.count) flagged items")

            Button { store.showInspector.toggle() } label: { Image(systemName: "sidebar.trailing") }
                .help("Show/hide inspector")
                .accessibilityLabel(store.showInspector ? "Hide inspector" : "Show inspector")

            //keyword filters
            // ->a menu (rather than a suggestions popover on an empty search field, which swallowed the next click)
            Menu {
                ForEach(store.keywords, id: \.self) { keyword in
                    Button {
                        if !store.tokens.contains(where: { $0.keyword == keyword }) {
                            store.scope = .processes
                            store.tokens.append(FilterToken(keyword: keyword))
                        }
                    } label: {
                        Text(verbatim: keyword + "  —  " + (store.filter.keywordDescription(keyword) ?? ""))
                    }
                }
                if !store.tokens.isEmpty {
                    Divider()
                    Button("Clear Filters") { store.clearFilter() }
                }
            } label: {
                Image(systemName: "number")
            }
            .help("Keyword filters (or type # in the filter box)")
            .accessibilityLabel("Keyword filters")
        }
    }

    //status overlay (extension starting, awaiting approval, etc)
    @ViewBuilder private var statusOverlay: some View {
        if let status = store.status {
            ZStack {
                Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
                VStack(spacing: 14) {
                    ProgressView().controlSize(.large)
                    Text(status)
                        .multilineTextAlignment(.center)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 420)
                }
                .padding(28)
                .background(RoundedRectangle(cornerRadius: 16).fill(.regularMaterial))
                .shadow(radius: 12)
            }
            .transition(.opacity)
        }
    }
}

//vertical split w/ a draggable divider; bottom pane height is remembered (across launches)
struct VerticalSplit<Top: View, Bottom: View>: View {
    let minTop: CGFloat
    let minBottom: CGFloat
    @ViewBuilder let top: () -> Top
    @ViewBuilder let bottom: () -> Bottom

    @AppStorage("itemsPaneHeight") private var bottomHeight: Double = 280
    @State private var dragStart: Double?
    @State private var hovering = false

    var body: some View {
        GeometryReader { geo in
            let dividerHeight: CGFloat = 1
            let maxBottom = max(minBottom, geo.size.height - minTop - dividerHeight)
            let height = min(max(CGFloat(bottomHeight), minBottom), maxBottom)
            let topHeight = max(0, geo.size.height - height - dividerHeight)
            VStack(spacing: 0) {
                top()
                    .frame(height: topHeight)
                    .clipped()
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(height: dividerHeight)
                    .overlay {
                        //(invisible) drag handle, slightly taller than the line
                        Color.clear
                            .frame(height: 9)
                            .contentShape(Rectangle())
                            .onHover { inside in
                                if inside, !hovering { NSCursor.resizeUpDown.push(); hovering = true }
                                else if !inside, hovering { NSCursor.pop(); hovering = false }
                            }
                            .onDisappear { if hovering { NSCursor.pop(); hovering = false } }
                            .gesture(
                                DragGesture(minimumDistance: 1)
                                    .onChanged { value in
                                        if dragStart == nil { dragStart = Double(height) }
                                        let proposed = CGFloat(dragStart ?? Double(height)) - value.translation.height
                                        bottomHeight = Double(min(max(proposed, minBottom), maxBottom))
                                    }
                                    .onEnded { _ in dragStart = nil }
                            )
                    }
                    .zIndex(1)
                bottom()
                    .frame(height: height)
                    .clipped()
            }
        }
    }
}

//bottom (status) bar
struct BottomBar: View {

    @EnvironmentObject var store: Store

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: store.isMonitoring ? "dot.radiowaves.left.and.right" : "pause.circle")
                .foregroundStyle(store.isMonitoring ? Color.green : Color.secondary)
                .help(store.isMonitoring ? "Live monitoring (via Endpoint Security)" : "Not monitoring")
                .accessibilityLabel(store.isMonitoring ? "Monitoring" : "Not monitoring")
            Text(statusText).font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail).layoutPriority(-1)
                .help(store.cacheIndexing ? "Indexing dyld shared cache dylibs for all processes (via vmmap)" : "")
            Spacer()
            Button {
                JSONExport.save(window: NSApp.keyWindow)
            } label: {
                Label("Save", systemImage: "square.and.arrow.up")
            }
            .disabled(store.processes.isEmpty)
            .help("Save all processes, dylibs, files, and connections as JSON")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private var statusText: String {
        let base = "\(store.processes.count) processes"
        switch store.enumerationState {
        case Int(ENUMERATION_STATE_TASKS): return "\(base) · enumerating processes…"
        case Int(ENUMERATION_STATE_DYLIBS): return "\(base) · enumerating dylibs…"
        case Int(ENUMERATION_STATE_FILES): return "\(base) · enumerating files…"
        case Int(ENUMERATION_STATE_NETWORK): return "\(base) · enumerating network connections…"
        default:
            let flagged = store.flagged.isEmpty ? "" : " · \(store.flagged.count) flagged"
            let indexing = store.cacheIndexing ? " · indexing \(store.cacheIndexProgress.done)/\(store.cacheIndexProgress.total)" : ""
            return base + flagged + (store.isMonitoring ? " · monitoring" : "") + indexing
        }
    }
}
