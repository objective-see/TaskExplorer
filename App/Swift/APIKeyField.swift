//
//  APIKeyField.swift
//  TaskExplorer (app)
//
//  Created by Patrick Wardle on 9/13/26.
//  Copyright (c) 2026 Objective-See. All rights reserved.
//
//  note: an API key entry field with the feedback a pasted secret needs: reveal (eye), clear (x), and a live check
//        against the provider (valid / rejected / unreachable), run once typing pauses

import SwiftUI

//result of checking a key with its provider
enum APIKeyCheck: Equatable {
    case none
    case checking
    case valid(String)
    case invalid(String)
    case unreachable(String)
}

struct APIKeyField: View {

    //label
    let title: String

    //placeholder
    let placeholder: String

    //the key (bound to the owner's state)
    @Binding var key: String

    //check the key with its provider
    let validate: (String) async -> APIKeyCheck

    //save (debounced; called with "" when cleared)
    let onSave: (String) -> Void

    //plain (always visible, no eye button)? e.g. the welcome flow, where the key is being pasted for the first time
    var plain: Bool = false

    //show the label (LabeledContent) or just the field
    var labeled: Bool = true

    //reveal?
    @State private var revealed = false

    //status
    @State private var status: APIKeyCheck = .none

    //pending save/check
    @State private var pending: _Concurrency.Task<Void, Never>?

    //key as checked (so reopening Settings doesn't re-check an unchanged key)
    @State private var checkedKey: String?

    var body: some View {
        //note: LabeledContent, so the (grouped) Form lines the label up with the other rows; the status goes inside
        //      the content column (leading aligned, under the field), not the label column
        LabeledContent {
            VStack(alignment: .leading, spacing: 4) {
                field
                    //the Form aligns the label to the content's first text baseline, which a rounded-border field
                    //reports a few points high (the label ends up above the field's centerline); define it from the
                    //field's center instead (13pt system text: baseline sits ~4.5pt below center)
                    .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + 4.5 }

                //status (under the field)
                if status != .none {
                    HStack(spacing: 5) {
                        switch status {
                        case .checking:
                            ProgressView().controlSize(.mini)
                            Text("Checking key…").foregroundStyle(.secondary)
                        case .valid(let message):
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            Text(message).foregroundStyle(.secondary)
                        case .invalid(let message):
                            Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
                            Text(message).foregroundStyle(.red)
                        case .unreachable(let message):
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                            Text(message).foregroundStyle(.secondary)
                        case .none:
                            EmptyView()
                        }
                    }
                    .font(.callout)
                    .transition(.opacity)
                }
            }
        } label: {
            if labeled { Text(title) }
        }
        .onChange(of: key) { _, _ in commit(now: false) }
        .onAppear {
            //always start hidden (a key revealed last time must not stay on screen the next time the window opens)
            revealed = false
            //an existing key? check it once, so the user sees its state when opening Settings
            if !trimmed.isEmpty, checkedKey != trimmed { check(trimmed) }
        }
        .onDisappear { revealed = false }
        //note: the Settings window is kept alive when closed (its views never disappear), so also hide on window close
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { _ in revealed = false }
    }

    //the field, with its reveal & clear buttons
    private var field: some View {
        HStack(spacing: 6) {
            Group {
                if revealed || plain {
                    TextField("", text: $key, prompt: Text(placeholder))
                } else {
                    SecureField("", text: $key, prompt: Text(placeholder))
                }
            }
            .textFieldStyle(.roundedBorder)
            //note: a grouped Form right-aligns field content by default; keys (and their placeholders) read left-to-right
            .multilineTextAlignment(.leading)
            .font(.system(.body, design: .monospaced))
            .autocorrectionDisabled()
            //fixed width: a revealed key must not widen the field (and push the label onto its own line)
            .frame(width: plain ? 360 : 340)
            .onSubmit { commit(now: true) }

            if !plain {
                Button { revealed.toggle() } label: { Image(systemName: revealed ? "eye.slash" : "eye") }
                    .buttonStyle(.borderless)
                    .help(revealed ? "Hide key" : "Show key")
                    .accessibilityLabel(revealed ? "Hide key" : "Show key")
            }

            Button { key = ""; commit(now: true) } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Clear key")
                .accessibilityLabel("Clear key")
                .disabled(trimmed.isEmpty)
                .opacity(trimmed.isEmpty ? 0.3 : 1)
        }
    }

    //trimmed key
    private var trimmed: String { key.trimmingCharacters(in: .whitespacesAndNewlines) }

    //save (debounced unless 'now') & check
    private func commit(now: Bool) {
        pending?.cancel()
        let value = trimmed
        if value.isEmpty {
            status = .none
            checkedKey = nil
        }
        pending = _Concurrency.Task { @MainActor in
            if !now {
                try? await _Concurrency.Task.sleep(nanoseconds: 750_000_000)
                guard !_Concurrency.Task.isCancelled else { return }
            }
            onSave(value)
            if !value.isEmpty { check(value) }
        }
    }

    //check with the provider
    private func check(_ value: String) {
        status = .checking
        checkedKey = value
        _Concurrency.Task { @MainActor in
            let result = await validate(value)
            //still the same key?
            guard trimmed == value else { return }
            withAnimation { status = result }
        }
    }
}

//provider checks (cheap, read-only requests that only prove the key is accepted)
enum APIKeyValidation {

    //anthropic: list models
    static func anthropic(_ key: String) async -> APIKeyCheck {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/models?limit=1")!)
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        return await perform(request, provider: "Anthropic").0
    }

    //openai: list models
    static func openAI(_ key: String) async -> APIKeyCheck {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        return await perform(request, provider: "OpenAI").0
    }

    //virustotal: the key's own user record (also tells the daily quota)
    static func virusTotal(_ key: String) async -> APIKeyCheck {
        guard let encoded = key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed), let url = URL(string: "https://www.virustotal.com/api/v3/users/\(encoded)") else {
            return .invalid("That doesn't look like a VirusTotal API key.")
        }
        var request = URLRequest(url: url)
        request.setValue(key, forHTTPHeaderField: "x-apikey")
        let (result, body) = await perform(request, provider: "VirusTotal")
        //add the quota, if reported
        if case .valid = result, let json = body as? [String: Any],
           let quotas = ((json["data"] as? [String: Any])?["attributes"] as? [String: Any])?["quotas"] as? [String: Any],
           let daily = (quotas["api_requests_daily"] as? [String: Any])?["allowed"] as? Int {
            return .valid("Valid · \(daily) lookups per day")
        }
        return result
    }

    //perform & classify (also returns the parsed body, for provider-specific details)
    private static func perform(_ request: URLRequest, provider: String) async -> (APIKeyCheck, Any?) {
        var request = request
        request.timeoutInterval = 15
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = try? JSONSerialization.jsonObject(with: data)
            switch status {
            case 200..<300: return (.valid("Valid"), body)
            case 401, 403: return (.invalid("Rejected by \(provider) (HTTP \(status)): check the key."), body)
            case 429: return (.valid("Valid (rate limited right now)"), body)
            default: return (.unreachable("\(provider) answered HTTP \(status); try again later."), body)
            }
        } catch {
            return (.unreachable("Couldn't reach \(provider): \(error.localizedDescription)"), nil)
        }
    }
}
