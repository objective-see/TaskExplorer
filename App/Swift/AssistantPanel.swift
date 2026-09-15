//
//  AssistantPanel.swift
//  TaskExplorer (app)
//
//  Created by Patrick Wardle on 9/12/26.
//  Copyright (c) 2026 Objective-See. All rights reserved.
//
//  note: left (full height) panel; chat w/ an agent (Apple Intelligence on-device, or Claude/ChatGPT w/ the user's own API key)
//        ...the assistant is given read-only query tools plus a few UI actions (see AssistantTools)

import SwiftUI

struct AssistantPanel: View {

    @EnvironmentObject var store: Store
    @StateObject private var assistant = Assistant.shared
    @State private var prompt: String = ""
    @FocusState private var promptFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            //header
            HStack {
                Picker("", selection: $assistant.provider) {
                    ForEach(AssistantProvider.allCases) { provider in Text(provider.label).tag(provider) }
                }
                .labelsHidden()
                .frame(width: 160)
                Spacer()
                Button { assistant.clear() } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .help("Clear conversation")
                    .disabled(assistant.messages.isEmpty)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)

            Divider()

            //transcript
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if assistant.messages.isEmpty { intro }
                        ForEach(assistant.messages) { message in
                            MessageRow(message: message)
                                .id(message.id)
                        }
                        if assistant.isBusy {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text(assistant.activity ?? "thinking…").font(.callout).foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .id("busy")
                        }
                    }
                    .padding(.vertical, 10)
                }
                .onChange(of: assistant.messages.count) { _, _ in
                    withAnimation { proxy.scrollTo(assistant.messages.last?.id, anchor: .bottom) }
                }
                .onChange(of: assistant.activity) { _, _ in
                    if assistant.isBusy { proxy.scrollTo("busy", anchor: .bottom) }
                }
            }

            Divider()

            //prompt
            VStack(spacing: 6) {
                if !assistant.isReady {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: assistant.provider.isLocal ? "apple.intelligence" : "key").foregroundStyle(.secondary)
                        Text(assistant.unavailableMessage ?? "\(assistant.provider.label) isn't available.").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        if assistant.provider.isLocal {
                            //note: only worth a button when the user can fix it (turn Apple Intelligence on)
                            if Assistant.appleEligible {
                                Button("System Settings…") { if let url = URL(string: URL_SYSTEM_SETTINGS_APPLE_INTELLIGENCE) { NSWorkspace.shared.open(url) } }.controlSize(.small)
                            }
                        } else {
                            Button("Settings…") { (NSApp.delegate as? AppDelegate)?.showPreferences(nil) }.controlSize(.small)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(alignment: .bottom, spacing: 8) {
                    TextField("Ask about running processes, dylibs, files, or connections…", text: $prompt, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...6)
                        .focused($promptFocused)
                        .onSubmit { send() }
                    if assistant.isBusy {
                        Button { assistant.cancel() } label: { Image(systemName: "stop.circle.fill") }
                            .buttonStyle(.borderless)
                            .help("Stop")
                    } else {
                        Button { send() } label: { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                            .buttonStyle(.borderless)
                            .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !assistant.isReady)
                            .keyboardShortcut(.return, modifiers: [.command])
                    }
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor)))
            }
            .padding(10)
        }
        .navigationTitle("AI Assistant")
        .onAppear { assistant.reloadKey() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in assistant.reloadKey() }
    }

    //intro (empty transcript)
    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ask the assistant about what's running.").font(.callout).foregroundStyle(.secondary)
            ForEach(["Which processes are ad-hoc signed, or not signed by Apple?",
                     "List non-Apple dylibs loaded into Apple processes",
                     "What's listening on the network?",
                     "Is anything flagged by VirusTotal?"], id: \.self) { suggestion in
                Button {
                    prompt = suggestion
                    send()
                } label: {
                    Text(suggestion).font(.callout).multilineTextAlignment(.leading)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .disabled(!assistant.isReady)
            }
            Text(privacyNote).font(.caption).foregroundStyle(.tertiary).padding(.top, 6)
        }
        .padding(.horizontal, 12)
    }

    //what happens to the data (per provider)
    private var privacyNote: String {
        let scope = "The assistant can query TaskExplorer's live data and drive the UI, but nothing else on your Mac."
        if assistant.provider.isLocal {
            return "Runs on-device with Apple Intelligence: no account, no key, and nothing leaves your Mac. \(scope) The on-device model is small, so keep questions focused (it works best with #keyword filters)."
        }
        return "Uses your own API key (stored in your keychain). \(scope) Whatever it queries (process names, paths, and command lines) is sent to the provider you select."
    }

    //send prompt
    private func send() {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !assistant.isBusy, assistant.isReady else { return }
        prompt = ""
        assistant.send(text)
        promptFocused = true
    }
}

//one transcript row
struct MessageRow: View {
    let message: AssistantMessage

    var body: some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 40)
                Text(message.text)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.accentColor.opacity(0.18)))
            }
            .padding(.horizontal, 12)
        case .assistant:
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "sparkles").foregroundStyle(.secondary).padding(.top, 3)
                Text(markdown(message.text))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
        case .tool:
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "wrench.and.screwdriver").font(.caption).foregroundStyle(.secondary)
                Text(message.text).font(.caption).foregroundStyle(.secondary).lineLimit(3).textSelection(.enabled)
            }
            .padding(.horizontal, 24)
        case .error:
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                Text(message.text).font(.callout).foregroundStyle(.orange).textSelection(.enabled)
            }
            .padding(.horizontal, 12)
        }
    }

    //(best effort) markdown
    private func markdown(_ text: String) -> AttributedString {
        var attributed = (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
        //no live links: the model echoes process names/paths, which are attacker-controlled (a process named [Finder](https://evil…) must not become a clickable link)
        for run in attributed.runs where run.link != nil { attributed[run.range].link = nil }
        return attributed
    }
}
