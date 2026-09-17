//
//  PreferencesWindowController.swift
//  TaskExplorer (app)
//
//  Created by Patrick Wardle on 9/12/26.
//  Copyright (c) 2026 Objective-See. All rights reserved.
//
//  note: preferences; VirusTotal (api key, enable/disable) & assistant (Apple Intelligence status, Ollama model, api keys)
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

    //ollama (nil: not running; checked on appear)
    @State private var ollamaModels: [String]?
    @State private var ollamaModel: String = UserDefaults.standard.string(forKey: PREF_OLLAMA_MODEL) ?? ""

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
            Section("AI Assistant") {
                //note: statuses are as wide as a key row (field + its two buttons, see APIKeyField) & leading-aligned,
                //      so they line up with the fields below
                LabeledContent("Apple Intelligence") {
                    Group {
                        if let reason = Assistant.appleUnavailableReason {
                            VStack(alignment: .leading, spacing: 4) {
                                Label("Not available", systemImage: "xmark.circle").foregroundStyle(.secondary)
                                Text(reason).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                if Assistant.appleEligible {
                                    Link("Open System Settings…", destination: URL(string: URL_SYSTEM_SETTINGS_APPLE_INTELLIGENCE)!).font(.callout)
                                }
                            }
                        } else {
                            Label("Available (on-device)", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                    }
                    .frame(width: 386, alignment: .leading)
                }
                LabeledContent("Ollama") {
                    Group {
                        if let models = ollamaModels, !models.isEmpty {
                            //note: no saved choice (or it's gone)? the first installed model is what the assistant uses
                            Picker("", selection: $ollamaModel) {
                                ForEach(models, id: \.self) { Text($0).tag($0) }
                            }
                            .labelsHidden()
                            .onChange(of: ollamaModel) { _, model in
                                setPreference(PREF_OLLAMA_MODEL, model)
                                Assistant.shared.reloadKey()
                            }
                            .onAppear { if !models.contains(ollamaModel) { ollamaModel = models[0] } }
                        } else {
                            VStack(alignment: .leading, spacing: 4) {
                                Label(ollamaModels == nil ? "Not running" : "No models", systemImage: "xmark.circle").foregroundStyle(.secondary)
                                Text(ollamaModels == nil ? "Install and start Ollama, then pull a model that supports tools (e.g. llama3.2)." : "Pull a model that supports tools (e.g. ollama pull llama3.2).")
                                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                if ollamaModels == nil {
                                    Link("Get Ollama…", destination: URL(string: OLLAMA_DOWNLOAD_URL)!).font(.callout)
                                }
                            }
                        }
                    }
                    .frame(width: 386, alignment: .leading)
                }
                APIKeyField(title: "Anthropic API key", placeholder: "paste your Anthropic API key (sk-ant-…)", key: $anthropicKey, validate: APIKeyValidation.anthropic, onSave: { new in
                    _ = saveKeychainItem(APIKeyService.anthropic, new); Assistant.shared.reloadKey()
                }, link: ("Get an Anthropic API key", URL(string: ANTHROPIC_API_KEY_URL)!))
                APIKeyField(title: "OpenAI API key", placeholder: "paste your OpenAI API key (sk-…)", key: $openAIKey, validate: APIKeyValidation.openAI, onSave: { new in
                    _ = saveKeychainItem(APIKeyService.openAI, new); Assistant.shared.reloadKey()
                }, link: ("Get an OpenAI API key", URL(string: OPENAI_API_KEY_URL)!))
                Text("Apple Intelligence and Ollama run on your Mac (no key; nothing leaves it). To use Claude or ChatGPT instead, add your own API key and pick the provider in the assistant panel. Keys are stored in your keychain and only sent to the provider you select.")
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
        .onAppear {
            //ollama: ask (off the main thread) what's installed
            DispatchQueue.global(qos: .userInitiated).async {
                let models = Assistant.ollamaModels()
                DispatchQueue.main.async { ollamaModels = models }
            }
        }
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

