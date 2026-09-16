//
//  MainWindowController.swift
//  TaskExplorer (app)
//
//  Created by Patrick Wardle on 9/12/26.
//  Copyright (c) 2026 Objective-See. All rights reserved.
//
//  note: hosts the (swift ui) main window; also the app's (main) menu

import AppKit
import SwiftUI

//main window controller
// ->exposed to objective-c (app delegate)
@objc(MainWindowController)
@objcMembers
final class MainWindowController: NSWindowController, NSWindowDelegate {

    //store
    let store = Store.shared

    //init
    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "TaskExplorer"
        window.titlebarAppearsTransparent = false
        window.toolbarStyle = .unified
        window.minSize = NSSize(width: 900, height: 560)
        //saved frame? else (first launch) wide enough for the inspector (sidebar + detail minimum + inspector; see
        //MainView), but well within the screen (small laptops), so a window that grows for the inspector stays movable
        let restored = window.setFrameUsingName("TaskExplorerMainWindow")
        window.setFrameAutosaveName("TaskExplorerMainWindow")
        if !restored, let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame {
            window.setContentSize(NSSize(width: min(1360, visible.width - 120), height: min(760, visible.height - 80)))
        }
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.contentView = NSHostingView(rootView: MainView().environmentObject(store))
        window.center()

        //start mcp server (if enabled)
        #if DEBUG
        //test server (debug builds only; see MCPServer.swift)
        MCPServer.shared.startIfEnabled()
        #endif
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

}

//target for the (main window) menu items
// ->an explicit target (rather than the responder chain), so the items work even when no window is key
@MainActor @objc final class MenuActions: NSObject, NSMenuItemValidation {
    static let shared = MenuActions()
    private var store: Store { Store.shared }

    @objc func showFlatView(_ sender: Any?) { store.viewMode = .flat }
    @objc func showTreeView(_ sender: Any?) { store.viewMode = .tree }
    @objc func showFlaggedItems(_ sender: Any?) { store.showFlagged = true }
    @objc func refresh(_ sender: Any?) { store.refresh() }
    @objc func saveResults(_ sender: Any?) { JSONExport.save(window: NSApp.keyWindow ?? (NSApp.delegate as? AppDelegate)?.mainWindowController?.window) }
    @objc func showDylibs(_ sender: Any?) { store.itemsTab = .dylibs }
    @objc func showFiles(_ sender: Any?) { store.itemsTab = .files }
    @objc func showNetwork(_ sender: Any?) { store.itemsTab = .network }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        //nothing to refresh/save before the first enumeration
        case #selector(refresh(_:)), #selector(saveResults(_:)): return taskEnumerator != nil && !store.processes.isEmpty
        case #selector(showFlatView(_:)): menuItem.state = (store.viewMode == .flat) ? .on : .off
        case #selector(showTreeView(_:)): menuItem.state = (store.viewMode == .tree) ? .on : .off
        case #selector(showDylibs(_:)): menuItem.state = (store.itemsTab == .dylibs) ? .on : .off
        case #selector(showFiles(_:)): menuItem.state = (store.itemsTab == .files) ? .on : .off
        case #selector(showNetwork(_:)): menuItem.state = (store.itemsTab == .network) ? .on : .off
        default: break
        }
        return true
    }
}

//builds the app's (main) menu programmatically
// ->exposed to objective-c (app delegate)
@objc(MenuBuilder)
@objcMembers
final class MenuBuilder: NSObject {

    //install main menu
    // ->main-actor, as it targets MenuActions and sets NSApp.mainMenu (called from the app delegate on the main thread)
    @MainActor static func install() {
        //note: minimal menu (Patrick's call): no Edit (see TaskExplorerApplication for ⌘X/C/V/A), Window, or Help menus
        //no window tabbing (else AppKit injects 'Show Tab Bar' / 'Show All Tabs' into the View menu)
        NSWindow.allowsAutomaticWindowTabbing = false

        let main = NSMenu()

        //app menu
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About TaskExplorer", action: #selector(AppDelegate.about(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings…", action: #selector(AppDelegate.showPreferences(_:)), keyEquivalent: ",")
        appMenu.addItem(withTitle: "Check for Updates…", action: #selector(AppDelegate.check4Update(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Uninstall TaskExplorer…", action: #selector(AppDelegate.uninstall(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit TaskExplorer", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        //file menu
        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Save Results…", action: #selector(MenuActions.saveResults(_:)), keyEquivalent: "s")
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileItem.submenu = fileMenu
        main.addItem(fileItem)

        //view menu
        let viewItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(withTitle: "Flat View", action: #selector(MenuActions.showFlatView(_:)), keyEquivalent: "1")
        viewMenu.addItem(withTitle: "Tree View", action: #selector(MenuActions.showTreeView(_:)), keyEquivalent: "2")
        viewMenu.addItem(.separator())
        for (title, sel, key) in [("Dylibs", #selector(MenuActions.showDylibs(_:)), "1"), ("Files", #selector(MenuActions.showFiles(_:)), "2"), ("Network", #selector(MenuActions.showNetwork(_:)), "3")] {
            let item = viewMenu.addItem(withTitle: title, action: sel, keyEquivalent: key)
            item.keyEquivalentModifierMask = [.command, .option]
        }
        viewMenu.addItem(.separator())
        viewMenu.addItem(withTitle: "Flagged Items…", action: #selector(MenuActions.showFlaggedItems(_:)), keyEquivalent: "")
        viewMenu.addItem(.separator())
        viewMenu.addItem(withTitle: "Refresh", action: #selector(MenuActions.refresh(_:)), keyEquivalent: "r")
        viewItem.submenu = viewMenu
        main.addItem(viewItem)

        //explicit target for the window-level actions
        let menuActions = MenuActions.shared
        for menu in [fileMenu, viewMenu] {
            for item in menu.items where item.action != nil && menuActions.responds(to: item.action!) {
                item.target = menuActions
            }
        }

        NSApp.mainMenu = main
    }

}
