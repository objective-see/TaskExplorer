//
//  PreferencesWindowController.swift
//  TaskExplorer (app)
//
//  Created by Patrick Wardle on 9/12/26.
//  Copyright (c) 2026 Objective-See. All rights reserved.
//
//  note: preferences; VirusTotal (api key, enable/disable) & assistant (api keys)
//        ...all keys are stored in the keychain

import AppKit
import SwiftUI

//keychain services (api keys)
enum APIKeyService {
    static let virusTotal = VT_API_KEYCHAIN_ATTR
    static let anthropic = ANTHROPIC_API_KEYCHAIN_ATTR
    static let openAI = OPENAI_API_KEYCHAIN_ATTR
}

//preferences window controller
// ->exposed to objective-c (app delegate)
@objc(PreferencesWindowController)
@objcMembers
final class PreferencesWindowController: NSWindowController {

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 620),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        //size to content
        let hosting = NSHostingController(rootView: PreferencesView())
        hosting.sizingOptions = [.preferredContentSize]
        window.contentViewController = hosting
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

struct PreferencesView: View {

    //virus total
    @State private var vtKey: String = loadKeychainItem(APIKeyService.virusTotal) ?? ""
    @State private var vtDisabled: Bool = getPreferenceBool(PREF_DISABLE_VT_QUERIES)

    //assistant
    @State private var anthropicKey: String = loadKeychainItem(APIKeyService.anthropic) ?? ""
    @State private var openAIKey: String = loadKeychainItem(APIKeyService.openAI) ?? ""

    //shared cache index
    @State private var indexCache: Bool = getPreferenceBool(PREF_INDEX_CACHE_DYLIBS)


    var body: some View {
        Form {
            Section("VirusTotal") {
                APIKeyField(title: "API key", placeholder: "paste your (personal) VirusTotal API key", key: $vtKey, validate: APIKeyValidation.virusTotal) { _ in saveVT() }
                //note: without an API key lookups are off regardless; the toggle shows that (off + locked)
                Toggle("VirusTotal lookups", isOn: Binding(get: { !vtDisabled && !vtKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }, set: { vtDisabled = !$0 }))
                    .disabled(vtKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .onChange(of: vtDisabled) { _, _ in saveVT() }
                Link("How do I get a (free) VirusTotal API key?", destination: URL(string: VT_API_KEY_URL)!)
                    .font(.callout)
            }
            Section("Assistant") {
                APIKeyField(title: "Anthropic API key", placeholder: "paste your Anthropic API key (sk-ant-…)", key: $anthropicKey, validate: APIKeyValidation.anthropic) { new in
                    _ = saveKeychainItem(APIKeyService.anthropic, new); Assistant.shared.reloadKey()
                }
                APIKeyField(title: "OpenAI API key", placeholder: "paste your OpenAI API key (sk-…)", key: $openAIKey, validate: APIKeyValidation.openAI) { new in
                    _ = saveKeychainItem(APIKeyService.openAI, new); Assistant.shared.reloadKey()
                }
                Text("The assistant uses your own account with either provider (pick one in the assistant panel). Keys are stored in your keychain and only sent to the provider you select.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Dylibs") {
                Toggle("Index dyld shared cache dylibs for all processes", isOn: $indexCache)
                    .onChange(of: indexCache) { _, on in
                        setPreference(PREF_INDEX_CACHE_DYLIBS, on)
                        if on { taskEnumerator?.indexCacheDylibs() }
                    }
                Text("Runs vmmap on every process (several minutes, in the background) so shared cache dylibs are attributed to processes: needed for global search and assistant queries such as “which processes load X”. Off, they're only enumerated on demand via the “Include shared cache dylibs” checkbox.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 620)
        .padding(.bottom, 8)
    }

    //save virus total prefs
    private func saveVT() {
        let wasEnabled = virusTotal?.isEnabled() ?? false
        let newKey = vtKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let keyChanged = (newKey != (loadKeychainItem(APIKeyService.virusTotal) ?? ""))
        setPreference(PREF_DISABLE_VT_QUERIES, vtDisabled)
        if keyChanged { _ = saveKeychainItem(APIKeyService.virusTotal, newKey) }
        virusTotal?.reloadAPIKey()
        //re-queue lookups when VT just became usable, or the key actually changed
        if virusTotal?.isEnabled() == true, (!wasEnabled || keyChanged) { virusTotal?.requeueAll() }
        Store.shared.refreshVTState()
        Store.shared.rebuildProcesses()
        Store.shared.rebuildItems()
    }
}

