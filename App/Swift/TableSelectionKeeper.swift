//
//  TableSelectionKeeper.swift
//  TaskExplorer (app)
//
//  Created by Patrick Wardle on 9/13/26.
//  Copyright (c) 2026 Objective-See. All rights reserved.
//
//  note: keeps a (SwiftUI) Table's selection honest while its rows change underneath it (live monitoring)
//
//        SwiftUI's Table re-applies the selection it last recorded whenever its rows change, and NSTableView only
//        commits a click at mouse-up (cancelling it, silently, if the rows change in between). With rows changing every
//        few hundred ms, clicks "didn't take" or flipped back to the previous row. So, as a background of the table:
//         1. remember the row under every left mouse-down; once the button is up, make sure that row is the selection
//         2. after every rows change, re-assert the (model's) selection on the NSTableView
//         3. make the columns fit the width (NSTableView only squeezes columns on a resize, not on creation)

import AppKit
import SwiftUI

struct TableSelectionKeeper<ID: Hashable>: NSViewRepresentable {

    //row ids (in table order)
    let ids: [ID]

    //(model's) selection
    let selectedID: ID?

    //select a row (by id)
    let select: (ID) -> Void

    func makeNSView(context: Context) -> NSView { NSView(frame: .zero) }

    func updateNSView(_ view: NSView, context: Context) {
        let coordinator = context.coordinator
        coordinator.select = select

        //rows changed?
        if coordinator.ids != ids {
            coordinator.ids = ids
            coordinator.selectedID = selectedID
            DispatchQueue.main.async {
                guard let table = TableSelectionKeeper.findTable(near: view) else { return }
                coordinator.attach(table)
                coordinator.reconcileSelection()
                //once more, in case the table applied the row changes a beat later
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { coordinator.reconcileSelection() }
            }
        } else if coordinator.selectedID != selectedID {
            coordinator.selectedID = selectedID
        }

        //first time: attach (click monitor, column fit)
        if coordinator.table == nil {
            DispatchQueue.main.async {
                guard let table = TableSelectionKeeper.findTable(near: view) else { return }
                coordinator.attach(table)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var ids: [ID] = []
        var selectedID: ID?
        var select: ((ID) -> Void)?
        private(set) weak var table: NSTableView?
        private var clickMonitor: Any?
        private var clickToken = 0

        deinit { if let clickMonitor { NSEvent.removeMonitor(clickMonitor) } }

        func attach(_ table: NSTableView) {
            //new table? fit its columns once (NOT on every rows change: that snapped user-resized columns back)
            if self.table !== table {
                uiLog.debug("selection keeper attached to table with \(table.numberOfRows) rows (\(table.tableColumns.first?.title ?? "?")), model has \(self.ids.count) ids")
                fitColumns(table)
            }
            self.table = table
            installClickMonitor()
        }

        //make the columns fit the table's width
        private func fitColumns(_ table: NSTableView) {
            guard let scrollView = table.enclosingScrollView else { return }
            let available = scrollView.contentView.bounds.width
            guard available > 0 else { return }
            let total = table.tableColumns.filter { !$0.isHidden }.reduce(CGFloat(0)) { $0 + $1.width + table.intercellSpacing.width }
            if total > available + 1 { table.sizeToFit() }
        }

        private func installClickMonitor() {
            guard clickMonitor == nil else { return }
            clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
                guard let self, let table = self.table, event.window === table.window,
                      !event.modifierFlags.contains(.command), !event.modifierFlags.contains(.shift) else { return event }
                //only clicks that land on this table's (visible) rows
                // ->note: a table's bounds span the whole (scrolled) document, so a plain bounds check also matches
                //   clicks outside the scroll view (and would hijack them)
                let point = table.convert(event.locationInWindow, from: nil)
                guard table.visibleRect.contains(point),
                      let hit = table.window?.contentView?.hitTest(event.locationInWindow), hit.isDescendant(of: table) else { return event }
                let row = table.row(at: point)
                guard row >= 0, row < self.ids.count else { return event }
                let id = self.ids[row]
                let downLocation = NSEvent.mouseLocation
                self.clickToken += 1
                self.awaitMouseUp(token: self.clickToken, since: Date()) { [weak self, weak table] in
                    guard let self, let table else { return }
                    //a click, not a drag? (a window/split-view resize starts with a mouse-down on a divider that
                    //overlaps the table's edge; hit-testing lands on a row, but the mouse then moves away)
                    let upLocation = NSEvent.mouseLocation
                    guard abs(upLocation.x - downLocation.x) < 4, abs(upLocation.y - downLocation.y) < 4 else {
                        uiLog.debug("ignoring drag (not a click) on row \(row)")
                        return
                    }
                    //released over the same row?
                    guard let window = table.window else { return }
                    let upPoint = table.convert(window.convertPoint(fromScreen: upLocation), from: nil)
                    guard table.row(at: upPoint) == row else { return }
                    self.reconcileClick(id)
                }
                return event
            }
        }

        //poll for the button's release (AppKit's tracking loops swallow the mouse-up event)
        private func awaitMouseUp(token: Int, since: Date, then: @escaping () -> Void) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
                guard let self, self.clickToken == token else { return }
                if NSEvent.pressedMouseButtons == 0 || Date().timeIntervalSince(since) > 2 {
                    //one more tick: let the table's own commit (and SwiftUI's update) run first
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                        guard let self, self.clickToken == token else { return }
                        then()
                    }
                } else {
                    self.awaitMouseUp(token: token, since: since, then: then)
                }
            }
        }

        //after a click: make sure the clicked row is the selection (model + table)
        private func reconcileClick(_ id: ID) {
            guard let table, let index = ids.firstIndex(of: id) else { return }
            if selectedID != id || table.selectedRow != index {
                uiLog.debug("reconciling click: row \(index) (table row: \(table.selectedRow), model selection matched: \(self.selectedID == id))")
                select?(id)
                if table.selectedRow != index { table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false) }
            }
        }

        //after the rows changed: make sure the table still highlights the (model's) selected row
        func reconcileSelection() {
            //a click in progress (button down, selection not yet committed)? leave it alone: 'reconcileClick' checks after the release
            guard NSEvent.pressedMouseButtons == 0, let table else { return }
            guard let selectedID, let index = ids.firstIndex(of: selectedID) else { return }
            guard table.numberOfRows == ids.count else { return }
            if table.selectedRow != index {
                uiLog.debug("re-applying selection after rows changed: row \(index) (table row: \(table.selectedRow))")
                table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            }
        }
    }

    //find the table view this background view belongs to
    // ->by geometry: SwiftUI hosts every representable of a window in one AppKit hierarchy, so a plain subtree search
    //   from this view's ancestors can return another table (e.g. the process table for a keeper of the dylibs table);
    //   the background view has the same frame as its Table, so pick the scroll view that overlaps it the most
    static func findTable(near view: NSView) -> NSTableView? {
        guard let window = view.window, let root = window.contentView else { return nil }
        let mine = view.convert(view.bounds, to: nil)
        guard mine.width > 0, mine.height > 0 else { return nil }
        var best: (table: NSTableView, overlap: CGFloat)?
        for table in allTables(in: root) {
            guard let scrollView = table.enclosingScrollView else { continue }
            let frame = scrollView.convert(scrollView.bounds, to: nil)
            let overlap = frame.intersection(mine)
            let area = overlap.isNull ? 0 : overlap.width * overlap.height
            if area > 0, area > (best?.overlap ?? 0) { best = (table, area) }
        }
        return best?.table
    }

    private static func allTables(in view: NSView) -> [NSTableView] {
        var found: [NSTableView] = []
        if let table = view as? NSTableView { found.append(table) }
        for subview in view.subviews { found += allTables(in: subview) }
        return found
    }
}
