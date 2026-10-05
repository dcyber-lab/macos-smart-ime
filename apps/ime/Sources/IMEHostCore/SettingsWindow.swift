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
    @Published private(set) var aiStatus = "当前：正在检查…"

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
        action.set(hotkey, defaults: defaults).map { "已被「\($0.title)」使用" }
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
        alert.messageText = "清空剪贴板历史？"
        alert.informativeText = "置顶的条目会保留。"
        alert.addButton(withTitle: "清空")
        alert.addButton(withTitle: "取消")
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
        panel.prompt = "选择"
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
        tabs.addTabViewItem(Self.pane("外观", symbol: "sparkles", AppearancePane(model: model)))
        tabs.addTabViewItem(Self.pane("智能中心", symbol: "brain", LearningPane(model: model)))
        tabs.addTabViewItem(Self.pane("AI 助手", symbol: "wand.and.stars", AIPane(model: model)))
        tabs.addTabViewItem(Self.pane("截图", symbol: "camera.viewfinder", ScreenshotPane(model: model)))
        tabs.addTabViewItem(Self.pane("剪贴板", symbol: "doc.on.clipboard", ClipboardPane(model: model)))
        tabs.addTabViewItem(Self.pane("快捷键", symbol: "keyboard", HotkeyPane(model: model)))
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
                Picker("选词动效", selection: $model.motion) {
                    ForEach(CommitEffectMotionChoice.allChoices, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("碎片配色", selection: $model.palette) {
                    ForEach(CommitEffectPaletteChoice.allChoices, id: \.self) { Text($0.title).tag($0) }
                }
                .disabled(model.motion == .off)
                LabeledContent("预览") {
                    Button("播放") { model.previewEffect() }
                        .disabled(model.motion == .off)
                }
            } footer: {
                Text(model.reduceMotion ? "系统已打开「减弱动态效果」，选词时不会播放动效。" : "选中候选词后，那一行会碎开消失。")
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
                    SettingLabel("智能学习", "按应用统计中英文用法和常打的句子，只存在这台 Mac 上")
                }
                Toggle(isOn: $model.isJournalEnabled) {
                    SettingLabel("保存输入原文", "保存打过的句子（链接、邮箱、长数字会被遮盖），保留 \(model.retentionDays) 天")
                }
                .disabled(!model.isLearningEnabled)
                Toggle(isOn: $model.isWindowTitlesEnabled) {
                    SettingLabel("读取窗口标题", "记下每句话写在哪个窗口里")
                }
                .disabled(!model.isLearningEnabled)
                if model.isWindowTitlesEnabled && !model.isAccessibilityTrusted {
                    LabeledContent("需要授权「辅助功能」才能读取窗口标题") {
                        Button("打开系统设置…") { WindowTitleReader.requestTrust() }
                    }
                }
            } footer: {
                Text("在某个应用里打开输入法菜单，可以单独停止在那个应用里学习。")
                    .foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("学习记录") {
                    HStack {
                        Button("查看…") { model.actions.openLearningPage() }
                        Button("清除…") { model.actions.clearLearning() }
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
                Picker("模型", selection: $model.provider) {
                    ForEach(AIAssistSettings.Provider.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Text(model.aiStatus)
                    .foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("已启用 AI 提示", value: model.aiHintApps.isEmpty ? "没有" : model.aiHintApps.joined(separator: "、"))
            } footer: {
                Text("在某个应用里打开输入法菜单，勾选“在「…」中启用 AI 提示”：在那里打完一句中文后会出现 ✨ 改写建议，按 Tab 或 → 替换。")
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
                    SettingLabel("截图快捷键", "在任何应用里都能用，与当前输入法无关；按键在「快捷键」里设置")
                }
            } footer: {
                Text("拖动框选区域，或点击选择整个窗口。框选后可以标注、复制（⏎）、保存（⌘S）、贴图到屏幕、识别文字；右键重选，Esc 取消。文字识别在本机完成。")
                    .foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("保存到") {
                    HStack {
                        Text(model.screenshotFolder)
                        Button("更改…") { model.chooseScreenshotFolder() }
                    }
                }
                if model.hasScreenRecordingAccess {
                    LabeledContent("屏幕录制权限", value: "已授权")
                } else {
                    LabeledContent("需要授权「屏幕录制」才能截图") {
                        Button("打开系统设置…") { ScreenshotCapture.openPermissionSettings() }
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
                    SettingLabel("剪贴板历史", "记下复制过的文字和图片，按快捷键搜索、预览、粘贴；只存在这台 Mac 上，快捷键在「快捷键」里设置")
                }
                Toggle(isOn: $model.clipboardKeepsImages) {
                    SettingLabel("记录图片", "截图和复制的图片也进入历史")
                }
                .disabled(!model.isClipboardEnabled)
                Picker("保留", selection: $model.clipboardRetentionDays) {
                    ForEach(ClipboardSettings.retentionChoices, id: \.self) { Text($0 == 1 ? "1 天" : "\($0) 天").tag($0) }
                }
                .disabled(!model.isClipboardEnabled)
            } footer: {
                Text("密码管理器里复制的内容、标记为机密的复制不会被记录。选中后按 ⏎ 粘贴到当前应用，需要「辅助功能」授权；没有授权时只复制，自己按 ⌘V。")
                    .foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("已记录 \(model.clipboardCount) 条") {
                    Button("清空…") { model.clearClipboardHistory() }
                }
                if !model.isAccessibilityTrusted {
                    LabeledContent("需要授权「辅助功能」才能直接粘贴") {
                        Button("打开系统设置…") { WindowTitleReader.requestTrust() }
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
                Text("点按键位后按下新的组合，需要包含 ⌃、⌥、⌘ 之一和一个字母；Esc 取消。这些快捷键在任何应用里都能用，改后立即生效。")
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
                Button(recorder.isRecording ? "按下新的快捷键…" : model.hotkey(for: action).displayString) {
                    recorder.toggle { model.setHotkey($0, for: action) }
                }
                Button("恢复默认") {
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
            message = "需要 ⌃、⌥、⌘ 之一加字母键"
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
