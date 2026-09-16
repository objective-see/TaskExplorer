//
//  WelcomeWindowController.swift
//  TaskExplorer (app)
//
//  Created by Patrick Wardle on 9/12/26.
//  Copyright (c) 2026 Objective-See. All rights reserved.
//
//  note: first-launch walkthru; welcome -> approve extension (if needed) -> full disk access (extension, if needed) -> api keys (virus total, assistant) -> done

import AppKit
import Combine
import SwiftUI

//welcome window controller
// ->exposed to objective-c (app delegate)
@objc(WelcomeWindowController)
@objcMembers
final class WelcomeWindowController: NSWindowController, NSWindowDelegate {

    let model = WelcomeModel()

    init() {
        //note: not closable (no close button): the user is meant to click through to the end
        // ->quitting (⌘Q) still works, and exits without marking the first run as done
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: WelcomeView.size(for: .welcome)),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "TaskExplorer v\(getAppVersion() ?? "")"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.contentView = NSHostingView(rootView: WelcomeView(model: model))
        window.center()

        //resize (animated, keeping the center) when a page needs a different size
        stepObserver = model.$step.receive(on: DispatchQueue.main).sink { [weak self] step in
            guard let self, let window = self.window else { return }
            let size = WelcomeView.size(for: step)
            let current = window.contentRect(forFrameRect: window.frame).size
            guard size != current else { return }
            var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
            frame.origin.x = window.frame.midX - frame.width / 2
            frame.origin.y = window.frame.midY - frame.height / 2
            window.setFrame(frame, display: true, animate: true)
        }
    }

    private var stepObserver: AnyCancellable?

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    //closed (quit) before completing? exit
    func windowWillClose(_ notification: Notification) {
        if model.step != .done { NSApp.terminate(nil) }
    }
}

//welcome steps
enum WelcomeStep: Int, CaseIterable {
    case welcome, permissions, apiKeys, done
}

//state of one permission (system extension approval, full disk access)
enum PermissionState: Equatable {
    case pending          //not checked yet
    case checking         //being checked / activated
    case waiting(String)  //needs the user (message)
    case granted
    case failed(String)   //gave up (message); user can retry
}

@MainActor
final class WelcomeModel: ObservableObject {
    @Published var step: WelcomeStep = .welcome {
        didSet { uiLog.debug("welcome step: \(String(describing: oldValue)) -> \(String(describing: self.step))") }
    }
    @Published var extensionState: PermissionState = .pending
    @Published var fdaState: PermissionState = .pending
    @Published var vtKey: String = ""
    @Published var anthropicKey: String = ""
    @Published var openAIKey: String = ""

    //any key entered? (the primary button reads "Skip" otherwise)
    var hasAnyKey: Bool { ![vtKey, anthropicKey, openAIKey].allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }

    //both permissions in place?
    var permissionsGranted: Bool { extensionState == .granted && fdaState == .granted }
    var extensionReady: Bool { extensionState == .granted }
    var fdaGranted: Bool { fdaState == .granted }

    //retained: delegate for the (async) activation request
    private var extensionObj: Extension?

    private var appDelegate: AppDelegate? { NSApp.delegate as? AppDelegate }

    //activate extension & wait for check-in
    // ->drives 'extensionState'; once running, the full disk access check starts
    func activateExtension() {
        guard extensionState != .checking else { return }
        extensionState = .checking
        let ext = Extension()
        extensionObj = ext
        ext.toggleExtension(UInt(ACTION_ACTIVATE)) { [weak self] error in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if let error {
                    self.extensionState = .failed("Activation failed: \(error.localizedDescription)")
                    return
                }
                self.appDelegate?.waitForExtension { ready in
                    DispatchQueue.main.async {
                        guard ready else {
                            //not (yet): let the user retry rather than quitting on them
                            self.extensionState = .failed("The extension isn't running yet. Approve it in System Settings, then retry.")
                            return
                        }
                        self.extensionState = .granted
                        self.enterFullDiskAccess()
                    }
                }
            }
        }
        //needs approval? say so (polled: the request's delegate sets the flag asynchronously)
        pollApproval(ext)
    }

    private func pollApproval(_ ext: Extension, attempt: Int = 0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, self.extensionState == .checking else { return }
            if ext.needsApproval {
                self.extensionState = .waiting("Approve “TaskExplorer” under Endpoint Security Extensions.")
                return
            }
            self.pollApproval(ext, attempt: attempt + 1)
        }
    }

    //full disk access (extension only: the app itself doesn't need it)
    private var fdaPolling = false
    func enterFullDiskAccess() {
        guard !fdaPolling else { return }
        fdaPolling = true
        fdaState = .checking
        //(objective-c) xpc client; safe to poll from the background queue
        nonisolated(unsafe) let client = appDelegate?.xpcClient
        DispatchQueue.global().async { [weak self] in
            defer { DispatchQueue.main.async { self?.fdaPolling = false } }
            //poll (the user might need to find the setting, so wait a long time)
            for attempt in 0..<(60 * 30) {
                let granted = client?.extensionHasFullDiskAccess() ?? false
                let done = DispatchQueue.main.sync { () -> Bool in
                    guard let self else { return true }
                    if granted { self.fdaState = .granted; return true }
                    //missing: tell the user (after the first check, so an already-granted one never flashes 'waiting')
                    if attempt >= 1 || self.fdaState != .checking { self.fdaState = .waiting("Enable “TaskExplorer Extension” under Full Disk Access.") }
                    return false
                }
                if done { return }
                Thread.sleep(forTimeInterval: 1.0)
            }
            //gave up (for now): let the user retry
            DispatchQueue.main.async { self?.fdaState = .failed("Still waiting for Full Disk Access. Grant it in System Settings, then retry.") }
        }
    }

    //(re)start whichever permission isn't in place
    func retryPermissions() {
        if extensionState != .granted { activateExtension() } else if fdaState != .granted { enterFullDiskAccess() }
    }

    //next step
    func advance() {
        switch step {
        case .welcome:
            //permissions page: shows the state of both (already granted ones show as such, rather than being skipped)
            step = .permissions
            activateExtension()
        case .permissions:
            //proceed (both granted), else retry whichever isn't
            permissionsGranted ? (step = .apiKeys) : retryPermissions()
        case .apiKeys:
            //save whatever was entered (each is optional)
            let vt = vtKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !vt.isEmpty {
                _ = saveKeychainItem(APIKeyService.virusTotal, vt)
                virusTotal?.reloadAPIKey()
            }
            let anthropic = anthropicKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !anthropic.isEmpty { _ = saveKeychainItem(APIKeyService.anthropic, anthropic) }
            let openAI = openAIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !openAI.isEmpty { _ = saveKeychainItem(APIKeyService.openAI, openAI) }
            //a key for a cloud provider, but no (usable) apple intelligence? make that provider the default
            if !anthropic.isEmpty || !openAI.isEmpty {
                if Assistant.appleUnavailableReason != nil { Assistant.shared.provider = anthropic.isEmpty ? .chatGPT : .claude }
                Assistant.shared.reloadKey()
            }
            step = .done
        case .done:
            break
        }
    }

    //finish
    func finish() {
        //note: main window first, then close this one (the app quits when its last window closes)
        // ->grab the controller first: 'completeInitialization' releases the delegate's reference, so closing via
        //   the delegate afterwards was a no-op (the welcome window stayed open behind the main window)
        let welcome = appDelegate?.welcomeWindowController
        appDelegate?.completeInitialization()
        welcome?.close()
    }

    func openSettings(_ url: String) {
        if let u = URL(string: url) { NSWorkspace.shared.open(u) }
    }
}

struct WelcomeView: View {

    @ObservedObject var model: WelcomeModel

    var body: some View {
        VStack(spacing: 16) {
            if model.step == .welcome {
                //splash: big icon, tagline, and what the app does at a glance (the details come on the next pages)
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 128, height: 128)
                    .shadow(color: .black.opacity(0.25), radius: 10, y: 6)
                Text("TaskExplorer").font(.system(size: 34, weight: .bold))
                Text("See everything that's running on your Mac.")
                    .font(.system(size: 18)).foregroundStyle(.secondary)
                    .padding(.bottom, 10)
                VStack(alignment: .leading, spacing: 26) {
                    WelcomeFeature(symbol: "cpu", color: .blue, title: "Every process, live",
                                   detail: "Dylibs, open files, and network connections for each process, updated as they change.")
                    WelcomeFeature(symbol: "checkmark.seal", color: .green, title: "Code signing & VirusTotal",
                                   detail: "Spot unsigned or ad-hoc code, Apple vs. third-party binaries, and known malware.")
                    WelcomeFeature(symbol: "sparkles", color: .purple, title: "Built-in AI assistant",
                                   detail: "Ask questions like “what's listening on the network?”: on-device via Apple Intelligence, or with your own Claude or ChatGPT key.")
                }
                .frame(maxWidth: 480)
            } else {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 84, height: 84)
                Text(title).font(.title).fontWeight(.semibold)
                Text(message).font(.system(size: 15)).multilineTextAlignment(.center).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).frame(maxWidth: model.step == .done ? 580 : 500)
            }

            if model.step == .permissions {
                VStack(alignment: .leading, spacing: 18) {
                    PermissionRow(symbol: "puzzlepiece.extension", title: "System extension", detail: "Monitors processes, dylibs, files, and network connections via Endpoint Security.",
                                  state: model.extensionState, settingsURL: URL_SYSTEM_SETTINGS_EXTENSIONS, model: model)
                    PermissionRow(symbol: "lock.shield", title: "Full Disk Access", detail: "Required by macOS for the extension to read every process and file.",
                                  state: model.fdaState, settingsURL: URL_SYSTEM_SETTINGS_FDA, model: model)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
            }

            if model.step == .apiKeys {
                VStack(alignment: .leading, spacing: 14) {
                    WelcomeFeature(symbol: "checkmark.shield", color: .green, title: "VirusTotal",
                                   detail: "Processes and dylibs are looked up by hash, using your own (free) VirusTotal API key.")
                    WelcomeKeyRow(label: "VirusTotal:", placeholder: "paste your (personal) VirusTotal API key", key: $model.vtKey, validate: APIKeyValidation.virusTotal,
                                  linkTitle: "Get a free VirusTotal API key", url: VT_API_KEY_URL)
                    WelcomeFeature(symbol: "sparkles", color: .purple, title: "AI Assistant",
                                   detail: assistantDetail)
                        .padding(.top, 22)
                    WelcomeKeyRow(label: "Anthropic:", placeholder: "paste your Anthropic API key (sk-ant-…)", key: $model.anthropicKey, validate: APIKeyValidation.anthropic,
                                  linkTitle: "Get an Anthropic API key", url: ANTHROPIC_API_KEY_URL)
                    WelcomeKeyRow(label: "OpenAI:", placeholder: "paste your OpenAI API key (sk-…)", key: $model.openAIKey, validate: APIKeyValidation.openAI,
                                  linkTitle: "Get an OpenAI API key", url: OPENAI_API_KEY_URL)
                }
                .frame(maxWidth: 540)
                .padding(.top, 4)
            }

            if model.step == .done {
                Button {
                    model.openSettings(PATREON_URL)
                } label: {
                    Label("Support Us", systemImage: "heart.fill").font(.system(size: 15, weight: .semibold)).padding(.horizontal, 10).padding(.vertical, 2)
                }
                .buttonStyle(.borderedProminent).tint(.pink).controlSize(.large)
                .padding(.bottom, 8)
                FriendsView()
            }

            Spacer(minLength: 0)


            HStack {
                Spacer()
                Button(primaryTitle) { model.step == .done ? model.finish() : model.advance() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(primaryDisabled)
            }
        }
        .padding(24)
        .frame(width: WelcomeView.size(for: model.step).width, height: WelcomeView.size(for: model.step).height)
        //note: no transition animation: pages switch in place
    }

    //page size: the splash and the last page (sponsor logos) are taller
    //note: one size for every page (the tallest, the API keys page): the window never resizes, and the icon, title,
    //      and buttons stay put from page to page, rather than sliding around as the layout re-flows
    static func size(for step: WelcomeStep) -> CGSize { CGSize(width: 640, height: 670) }

    private var title: String {
        switch model.step {
        case .welcome: return "Welcome to TaskExplorer"
        case .permissions: return "Permissions"
        case .apiKeys: return "API Keys (Optional)"
        case .done: return "All Set!"
        }
    }

    private var message: String {
        switch model.step {
        case .welcome:
            return "TaskExplorer explores and monitors all running processes, and their dylibs, files, and network connections.\n\nTo do so, it uses a system extension and needs a few permissions, which macOS asks you to grant in System Settings. The next steps walk you through this."
        case .permissions:
            return "To monitor and inspect processes, please approve TaskExplorer's system extension and grant it Full Disk Access."
        case .apiKeys:
            return "Flag known malware via VirusTotal, and pick how the assistant runs. All keys are optional, stored in your keychain, and can be added later in Settings."
        case .done:
            return "TaskExplorer is free, open-source, and written by a single (Mac-loving) coder!\nPlease consider supporting Objective-See."
        }
    }

    private var primaryTitle: String {
        switch model.step {
        case .apiKeys: return model.hasAnyKey ? "Next" : "Skip"
        case .done: return "Start"
        case .permissions:
            if model.permissionsGranted { return "Next" }
            if case .failed = model.extensionState { return "Retry" }
            if case .failed = model.fdaState { return "Retry" }
            return "Next"
        default: return "Next"
        }
    }

    private var primaryDisabled: Bool {
        switch model.step {
        case .welcome: return false
        //enabled once both are granted (Next), or once a wait gave up (Retry)
        case .permissions:
            if model.permissionsGranted { return false }
            if case .failed = model.extensionState { return false }
            if case .failed = model.fdaState { return false }
            return true
        default: return false
        }
    }

    //assistant blurb: depends on whether apple intelligence can run here
    private var assistantDetail: String {
        if Assistant.appleUnavailableReason == nil {
            return "Runs on-device with Apple Intelligence (no key needed). To use Claude or ChatGPT instead, add your own API key."
        }
        if Assistant.appleEligible {
            return "Can run on-device once Apple Intelligence is turned on in System Settings. Or, to use Claude or ChatGPT, add your own API key."
        }
        return "Apple Intelligence isn't available on this Mac, so the assistant needs your own Claude (Anthropic) or ChatGPT (OpenAI) API key."
    }
}

//an api key row on the api keys page: label (left aligned, fixed column so the fields line up), field, and a "get a key" link under it
struct WelcomeKeyRow: View {
    let label: String
    let placeholder: String
    @Binding var key: String
    let validate: (String) async -> APIKeyCheck
    let linkTitle: String
    let url: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label).font(.system(size: 14, weight: .semibold)).frame(width: 90, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                APIKeyField(title: label, placeholder: placeholder, key: $key, validate: validate, onSave: { _ in }, plain: true, labeled: false)
                Link(linkTitle, destination: URL(string: url)!).font(.system(size: 12)).padding(.leading, 6)
            }
        }
        .padding(.leading, 50)
    }
}

//"friends of objective-see" (sponsors) logos
// ->shown on the welcome flow's last page; assets carry light/dark variants
struct FriendsView: View {

    //a logo, with the box it may fill (points); the caps even out the visual weight of wide wordmarks vs. compact marks
    struct Logo: Identifiable {
        let name: String
        let width: CGFloat
        let height: CGFloat
        var id: String { name }
    }

    //rows (3 / 4 / 3), like a sponsor wall
    // ->rendered monochrome (template + one tone): the assets are mixed colors and not all have dark variants
    private let rows: [[Logo]] = [
        [Logo(name: "FriendsHuntress", width: 128, height: 30), Logo(name: "FriendsJamf", width: 80, height: 30), Logo(name: "FriendsiVerify", width: 72, height: 26)],
        [Logo(name: "FriendsMacPaw", width: 122, height: 24), Logo(name: "FriendsMalwarebytes", width: 112, height: 24),
         Logo(name: "FriendsPANW", width: 112, height: 26), Logo(name: "FriendsIru", width: 60, height: 22)],
        [Logo(name: "FriendsNorthPole", width: 196, height: 34), Logo(name: "FriendsRippling", width: 136, height: 24), Logo(name: "FriendsThreatLocker", width: 150, height: 18)]
    ]

    var body: some View {
        VStack(spacing: 18) {
            Text("Mahalo to the Friends of Objective-See, who make this possible")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            VStack(spacing: 22) {
                ForEach(rows.indices, id: \.self) { row in
                    HStack(spacing: 30) {
                        ForEach(rows[row]) { logo in
                            Image(logo.name)
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .foregroundStyle(.primary.opacity(0.7))
                                .frame(maxWidth: logo.width, maxHeight: logo.height)
                                .frame(height: 34)
                                .accessibilityLabel(logo.name.replacingOccurrences(of: "Friends", with: ""))
                        }
                    }
                }
            }
        }
        .padding(.vertical, 18).padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)))
    }
}

//a feature row on the splash page
struct WelcomeFeature: View {
    let symbol: String
    let color: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 9).fill(color.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 16, weight: .semibold))
                Text(detail).font(.system(size: 14)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

//a permission row on the permissions page: badge, title/detail, and the status as a trailing column (checklist style)
struct PermissionRow: View {
    let symbol: String
    let title: String
    let detail: String
    let state: PermissionState
    let settingsURL: String
    @ObservedObject var model: WelcomeModel

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.blue)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color.blue.opacity(0.12)))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 16, weight: .semibold))
                Text(detail).font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let message = userMessage {
                    Text(message).font(.system(size: 13)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true).padding(.top, 2)
                }
            }
            Spacer(minLength: 12)
            //status
            VStack(alignment: .trailing, spacing: 6) {
                switch state {
                case .pending:
                    Label("Waiting", systemImage: "circle.dashed").foregroundStyle(.tertiary)
                case .checking:
                    HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Checking").foregroundStyle(.secondary) }
                case .waiting:
                    Label("Needs approval", systemImage: "exclamationmark.circle.fill").foregroundStyle(.orange)
                case .granted:
                    Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                case .failed:
                    Label("Not granted", systemImage: "xmark.octagon.fill").foregroundStyle(.red)
                }
                if needsUser {
                    Button("Open System Settings…") { model.openSettings(settingsURL) }.controlSize(.small)
                }
            }
            .font(.system(size: 14, weight: .semibold))
            .fixedSize()
        }
        .padding(.vertical, 10).padding(.horizontal, 14)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
    }

    private var needsUser: Bool {
        switch state {
        case .waiting, .failed: return true
        default: return false
        }
    }

    private var userMessage: String? {
        switch state {
        case .waiting(let message), .failed(let message): return message
        default: return nil
        }
    }
}
