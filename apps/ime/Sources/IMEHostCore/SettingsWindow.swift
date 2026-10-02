import AppKit
import SwiftUI

/// The settings the input menu leaves out (`InputMenu`): commit effects, learning details, and the
/// AI model. One window per process, with toolbar tabs; closing it hands focus back to the app the
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

    var rewriteHotkey: String {
        AIAssistSettings(defaults: defaults).hotkey.displayString
    }

    var readHotkey: String {
        AIAssistSettings(defaults: defaults).readHotkey.displayString
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
            Section("快捷键") {
                LabeledContent("改写选中文字或当前行", value: model.rewriteHotkey)
                LabeledContent("读取其他地方选中的文字", value: model.readHotkey)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
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
