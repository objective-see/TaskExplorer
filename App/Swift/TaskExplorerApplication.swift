//
//  TaskExplorerApplication.swift
//  TaskExplorer (app)
//
//  Created by Patrick Wardle on 9/13/26.
//  Copyright (c) 2026 Objective-See. All rights reserved.
//
//  note: the app has no Edit menu (kept minimal, on purpose), so the standard editing shortcuts (⌘X/C/V/A/Z) are
//        routed to the first responder here, as AppKit only dispatches key equivalents through the main menu
//        ...same approach as the (pre-3.0) NSApplicationKeyEvents

import AppKit

@objc(TaskExplorerApplication)
final class TaskExplorerApplication: NSApplication {

    //the modifiers that matter (caps lock, numeric pad, fn are not part of a shortcut)
    private func modifiers(of event: NSEvent) -> NSEvent.ModifierFlags {
        event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
    }

    override func sendEvent(_ event: NSEvent) {
        //command (only) + a key?
        if event.type == .keyDown, modifiers(of: event) == .command,
           let key = event.charactersIgnoringModifiers?.lowercased() {
            let selector: Selector?
            switch key {
            case "x": selector = #selector(NSText.cut(_:))
            case "c": selector = #selector(NSText.copy(_:))
            case "v": selector = #selector(NSText.paste(_:))
            case "a": selector = #selector(NSText.selectAll(_:))
            case "z": selector = Selector(("undo:"))
            default: selector = nil
            }
            //handled by the first responder (text field, table, ...)? done
            if let selector, sendAction(selector, to: nil, from: self) { return }
        }
        //shift-command-z: redo
        if event.type == .keyDown, modifiers(of: event) == [.command, .shift],
           event.charactersIgnoringModifiers?.lowercased() == "z", sendAction(Selector(("redo:")), to: nil, from: self) {
            return
        }
        super.sendEvent(event)
    }
}
