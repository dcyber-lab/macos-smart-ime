import AppKit
import SwiftUI

/// The settings the input menu leaves out (`InputMenu`): commit effects, learning details, the
/// AI model, screenshots, and hotkeys. One window per process, with toolbar tabs; closing it hands focus back to the app the
/// user was typing in.
@MainActor
enum SettingsWindow {
    private static var controller: SettingsWindowController?

    static func show(actions: SettingsModel.Actions) {
        let controller = controller ?? SettingsWindowController(model: SettingsModel(actions: actions))
        self.controller = controller
        controller.show()
    }
}

/// What the settings window shows and changes. The settings live in the defaults domain and are
/// read on every refresh; any change there, from the input menu or from this window, refreshes it.
@MainActor
final class SettingsModel: ObservableObject {
    /// What needs the input controller's shared state rather than the defaults alone.
    struct Actions {
        var setLearning: @MainActor (Bool) -> Void
        var openLearningPage: @MainActor () -> Void
        var clearLearning: @MainActor () -> Void
    }

    let actions: Actions
    let defaults: UserDefaults
    /// Checked in the background: looking for Ollama can take up to 0.6 s.
    @Published private(set) var aiStatus = "Current: checking…"

    /// The window, and with it the model, lives as long as the process, so the observer is never removed.
    init(actions: Actions, defaults: UserDefaults = .standard) {
        self.actions = actions
        self.defaults = defaults
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.objectWillChange.send() }
        }
    }

    // MARK: Appearance

    var motion: CommitEffectMotionChoice {
        get { CommitEffectSettings(defaults: defaults).motion }
        set {
            CommitEffectSettings(defaults: defaults).motion = newValue
            previewEffect()
        }
    }

    var palette: CommitEffectPaletteChoice {
        get { CommitEffectSettings(defaults: defaults).palette }
        set {
            CommitEffectSettings(defaults: defaults).palette = newValue
            previewEffect()
        }
    }

    var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// Plays the effect below the pointer, ignoring Reduce Motion: the user asked to see it.
    func previewEffect() {
        var generator = SystemRandomNumberGenerator()
        guard let skin = CommitEffectSettings(defaults: defaults).resolve(reduceMotion: false, using: &generator) else {
            return
        }
        CandidatePanel.shared.previewCommitEffect(style: skin.style, palette: skin.palette, below: NSEvent.mouseLocation)
    }

    // MARK: Learning

    var isLearningEnabled: Bool {
        get { IntelligenceSettings(defaults: defaults).isLearningEnabled }
        set { actions.setLearning(newValue) }
    }

    var isJournalEnabled: Bool {
        get { IntelligenceSettings(defaults: defaults).isJournalEnabled }
        set { IntelligenceSettings(defaults: defaults).isJournalEnabled = newValue }
    }

    var isWindowTitlesEnabled: Bool {
        get { IntelligenceSettings(defaults: defaults).isWindowTitlesEnabled }
        set {
            IntelligenceSettings(defaults: defaults).isWindowTitlesEnabled = newValue
            if newValue, !WindowTitleReader.isTrusted {
                WindowTitleReader.requestTrust()
            }
        }
    }

    var retentionDays: Int {
        IntelligenceSettings(defaults: defaults).retentionDays
    }

    var isAccessibilityTrusted: Bool {
        WindowTitleReader.isTrusted
    }

    // MARK: AI

    var provider: AIAssistSettings.Provider {
        get { AIAssistSettings(defaults: defaults).provider }
        set {
            AIAssistSettings(defaults: defaults).provider = newValue
            refreshAIStatus()
        }
    }

    var aiHintApps: [String] {
        AIAssistSettings(defaults: defaults).chipApps.map(AppNames.displayName(for:)).sorted()
    }

    func refreshAIStatus() {
        Task.detached(priority: .userInitiated) {
            let status = Self.currentAIStatus()
            await MainActor.run { [weak self] in self?.aiStatus = status }
        }
    }

    nonisolated private static func currentAIStatus() -> String {
        let settings = AIAssistSettings()
        return AIAssistSettings.statusText(settings.activeProvider(), codexModel: settings.codexModel, ollamaModel: settings.ollamaModel)
    }

    // MARK: Hotkeys

    func hotkey(for action: HotkeyAction) -> TranslationHotkey {
        action.hotkey(defaults: defaults)
    }

    /// Returns what to tell the user when `hotkey` cannot be used.
    func setHotkey(_ hotkey: TranslationHotkey?, for action: HotkeyAction) -> String? {
        action.set(hotkey, defaults: defaults).map { "Already used by \"\($0.title)\"" }
    }

    // MARK: Clipboard

    var isClipboardEnabled: Bool {
        get { ClipboardSettings(defaults: defaults).isEnabled }
        set { ClipboardSettings.setEnabled(newValue, defaults: defaults) }
    }

    var clipboardKeepsImages: Bool {
        get { ClipboardSettings(defaults: defaults).keepsImages }
        set { ClipboardSettings.setKeepsImages(newValue, defaults: defaults) }
    }

    var clipboardRetentionDays: Int {
        get { ClipboardSettings(defaults: defaults).retentionDays }
        set { ClipboardSettings.setRetentionDays(newValue, defaults: defaults) }
    }

    var clipboardCount: Int {
        ClipboardService.shared.store.items.count
    }

    func clearClipboardHistory() {
        let alert = NSAlert()
        alert.messageText = "Clear clipboard history?"
        alert.informativeText = "Pinned items are kept."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            ClipboardService.shared.store.clear()
            objectWillChange.send()
        }
    }

    // MARK: Screenshot

    var isScreenshotEnabled: Bool {
        get { ScreenshotSettings(defaults: defaults).isEnabled }
        set { ScreenshotSettings.setEnabled(newValue, defaults: defaults) }
    }

    var screenshotFolder: String {
        FileManager.default.displayName(atPath: ScreenshotSettings(defaults: defaults).saveFolder.path)
    }

    var hasScreenRecordingAccess: Bool {
        ScreenshotCapture.hasPermission
    }

    func chooseScreenshotFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.directoryURL = ScreenshotSettings(defaults: defaults).saveFolder
        if panel.runModal() == .OK, let url = panel.url {
            ScreenshotSettings.setSaveFolder(url, defaults: defaults)
        }
    }
}

// MARK: - Window

@MainActor
private final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let model: SettingsModel
    /// The app the user was typing in; it gets focus back when the window closes.
    private var previousApp: NSRunningApplication?

    init(model: SettingsModel) {
        self.model = model
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.addTabViewItem(Self.pane("Appearance", symbol: "sparkles", AppearancePane(model: model)))
        tabs.addTabViewItem(Self.pane("Intelligence", symbol: "brain", LearningPane(model: model)))
        tabs.addTabViewItem(Self.pane("AI Assistant", symbol: "wand.and.stars", AIPane(model: model)))
        tabs.addTabViewItem(Self.pane("Screenshot", symbol: "camera.viewfinder", ScreenshotPane(model: model)))
        tabs.addTabViewItem(Self.pane("Clipboard", symbol: "doc.on.clipboard", ClipboardPane(model: model)))
        tabs.addTabViewItem(Self.pane("Shortcuts", symbol: "keyboard", HotkeyPane(model: model)))
        let window = SettingsPanelWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func show() {
        if let frontmost = NSWorkspace.shared.frontmostApplication, frontmost != .current {
            previousApp = frontmost
        }
        model.refreshAIStatus()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Accessibility access and the AI model can change while the window is in the background.
    func windowDidBecomeKey(_ notification: Notification) {
        model.objectWillChange.send()
        model.refreshAIStatus()
    }

    func windowWillClose(_ notification: Notification) {
        previousApp?.activate(options: [])
        previousApp = nil
    }

    private static func pane(_ label: String, symbol: String, _ view: some View) -> NSTabViewItem {
        let host = NSHostingController(rootView: view.padding(.bottom, 12).frame(width: 480).fixedSize(horizontal: false, vertical: true))
        host.sizingOptions = .preferredContentSize
        // The tab controller passes the selected pane's title on to the window.
        host.title = label
        let item = NSTabViewItem(viewController: host)
        item.label = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        return item
    }
}

/// The input method has no main menu, so ⌘W and Esc are handled here.
private final class SettingsPanelWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command, event.charactersIgnoringModifiers == "w" {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        performClose(nil)
    }
}

// MARK: - Panes

private struct AppearancePane: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section {
                Picker("Selection effect", selection: $model.motion) {
                    ForEach(CommitEffectMotionChoice.allChoices, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("Fragment colors", selection: $model.palette) {
                    ForEach(CommitEffectPaletteChoice.allChoices, id: \.self) { Text($0.title).tag($0) }
                }
                .disabled(model.motion == .off)
                LabeledContent("Preview") {
                    Button("Play") { model.previewEffect() }
                        .disabled(model.motion == .off)
                }
            } footer: {
                Text(model.reduceMotion ? "Reduce Motion is on in System Settings, so the effect will not play." : "After you pick a candidate, the row breaks apart and disappears.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
    }
}

private struct LearningPane: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $model.isLearningEnabled) {
                    SettingLabel("Intelligence learning", "Tracks Chinese/English usage and frequent sentences per app. Stored only on this Mac")
                }
                Toggle(isOn: $model.isJournalEnabled) {
                    SettingLabel("Save typed text", "Keeps sentences you typed (links, emails, and long numbers are masked) for \(model.retentionDays) days")
                }
                .disabled(!model.isLearningEnabled)
                Toggle(isOn: $model.isWindowTitlesEnabled) {
                    SettingLabel("Read window titles", "Records which window each sentence was typed in")
                }
                .disabled(!model.isLearningEnabled)
                if model.isWindowTitlesEnabled && !model.isAccessibilityTrusted {
                    LabeledContent("Accessibility permission is required to read window titles") {
                        Button("Open System Settings…") { WindowTitleReader.requestTrust() }
                    }
                }
            } footer: {
                Text("Open the input method menu in an app to stop learning in that app only.")
                    .foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("Learning data") {
                    HStack {
                        Button("View…") { model.actions.openLearningPage() }
                        Button("Clear…") { model.actions.clearLearning() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
    }
}

private struct AIPane: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section {
                Picker("Model", selection: $model.provider) {
                    ForEach(AIAssistSettings.Provider.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Text(model.aiStatus)
                    .foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("AI hints enabled in", value: model.aiHintApps.isEmpty ? "None" : model.aiHintApps.joined(separator: ", "))
            } footer: {
                Text("Open the input method menu in an app and check \"Enable AI Hints in …\": after you finish a Chinese sentence there, a ✨ rewrite suggestion appears. Press Tab or → to replace.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
    }
}

private struct ScreenshotPane: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $model.isScreenshotEnabled) {
                    SettingLabel("Screenshot shortcut", "Works in any app, regardless of the current input method. Set the keys in Shortcuts")
                }
            } footer: {
                Text("Drag to select an area, or click to pick a whole window. Then annotate, copy (⏎), save (⌘S), pin to the screen, or recognize text; right-click to reselect, Esc to cancel. Text recognition runs on this Mac.")
                    .foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("Save to") {
                    HStack {
                        Text(model.screenshotFolder)
                        Button("Change…") { model.chooseScreenshotFolder() }
                    }
                }
                if model.hasScreenRecordingAccess {
                    LabeledContent("Screen Recording permission", value: "Granted")
                } else {
                    LabeledContent("Screen Recording permission is required for screenshots") {
                        Button("Open System Settings…") { ScreenshotCapture.openPermissionSettings() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
    }
}

private struct ClipboardPane: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $model.isClipboardEnabled) {
                    SettingLabel("Clipboard history", "Remembers copied text and images; search, preview, and paste with the shortcut. Stored only on this Mac. Set the shortcut in Shortcuts")
                }
                Toggle(isOn: $model.clipboardKeepsImages) {
                    SettingLabel("Record images", "Screenshots and copied images are added to the history too")
                }
                .disabled(!model.isClipboardEnabled)
                Picker("Keep for", selection: $model.clipboardRetentionDays) {
                    ForEach(ClipboardSettings.retentionChoices, id: \.self) { Text($0 == 1 ? "1 day" : "\($0) days").tag($0) }
                }
                .disabled(!model.isClipboardEnabled)
            } footer: {
                Text("Content copied from password managers or marked confidential is not recorded. Press ⏎ to paste the selected item into the current app, which needs Accessibility permission; without it the item is only copied and you press ⌘V yourself.")
                    .foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("\(model.clipboardCount) items recorded") {
                    Button("Clear…") { model.clearClipboardHistory() }
                }
                if !model.isAccessibilityTrusted {
                    LabeledContent("Accessibility permission is required to paste directly") {
                        Button("Open System Settings…") { WindowTitleReader.requestTrust() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
    }
}

private struct HotkeyPane: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section {
                ForEach(HotkeyAction.allCases, id: \.self) { action in
                    HotkeyRow(model: model, action: action)
                }
            } footer: {
                Text("Click a key, then press the new combination. It needs one of ⌃, ⌥, ⌘ plus a letter; Esc cancels. These shortcuts work in any app and take effect immediately.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
    }
}

private struct HotkeyRow: View {
    @ObservedObject var model: SettingsModel
    let action: HotkeyAction
    @StateObject private var recorder = HotkeyRecorder()

    var body: some View {
        LabeledContent(action.title) {
            HStack {
                if let message = recorder.message {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
                Button(recorder.isRecording ? "Press new shortcut…" : model.hotkey(for: action).displayString) {
                    recorder.toggle { model.setHotkey($0, for: action) }
                }
                Button("Restore Default") {
                    recorder.message = model.setHotkey(nil, for: action)
                }
                .disabled(model.hotkey(for: action) == action.defaultHotkey)
            }
        }
        .onDisappear { recorder.stop() }
    }
}

/// Listens for the next key combination while a hotkey button is armed. The system hotkeys are released
/// meanwhile, since a registered combination never reaches the window.
@MainActor
private final class HotkeyRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    @Published var message: String?
    private var monitor: Any?

    /// `apply` stores the recorded hotkey and returns why it was refused, if it was.
    func toggle(apply: @escaping @MainActor (TranslationHotkey) -> String?) {
        if isRecording {
            stop()
            return
        }
        message = nil
        isRecording = true
        GlobalHotkeys.shared.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event, apply: apply) }
            return nil
        }
    }

    private func handle(_ event: NSEvent, apply: (TranslationHotkey) -> String?) {
        if event.keyCode == 53 {
            stop()
            return
        }
        guard let hotkey = TranslationHotkey(keyCode: event.keyCode, modifierFlags: event.modifierFlags) else {
            message = "Needs one of ⌃, ⌥, ⌘ plus a letter key"
            return
        }
        message = apply(hotkey)
        stop()
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        guard isRecording else {
            return
        }
        isRecording = false
        GlobalHotkeys.shared.resume()
    }
}

/// A setting's name with a one-line explanation under it.
private struct SettingLabel: View {
    let title: String
    let detail: String

    init(_ title: String, _ detail: String) {
        self.title = title
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}
