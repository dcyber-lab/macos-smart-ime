import AppKit
@preconcurrency import InputMethodKit

/// The AI 助手 section of the input menu (proof of concept).
enum AIAssistMenu {
    static let title = "AI 助手（POC）"
    private static let toggleTag = 400
    private static let providerTagBase = 410

    enum Command: Equatable {
        case toggleChips
        case provider(AIAssistSettings.Provider)
    }

    static func enableTitle(_ appName: String) -> String {
        "在「\(appName)」中启用 AI 提示"
    }

    /// `active` is the provider rewrites would use now (nil when none can run).
    static func items(
        settings: AIAssistSettings, currentApp: (id: String, name: String)?, active: AIAssistSettings.Provider?, action: Selector
    ) -> [NSMenuItem] {
        let header = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        header.isEnabled = false
        var items = [header]
        if let currentApp {
            let toggle = item(enableTitle(currentApp.name), tag: toggleTag, action: action)
            toggle.state = settings.chipApps.contains(currentApp.id) ? .on : .off
            toggle.isEnabled = active != nil
            items.append(toggle)
        }
        for (index, provider) in AIAssistSettings.Provider.allCases.enumerated() {
            let choice = item(provider.title, tag: providerTagBase + index, action: action)
            choice.state = settings.provider == provider ? .on : .off
            items.append(choice)
        }
        let status = item(statusText(active, codexModel: settings.codexModel), tag: 0, action: nil)
        status.isEnabled = false
        items.append(status)
        return items
    }

    static func statusText(_ active: AIAssistSettings.Provider?, codexModel: String) -> String {
        switch active {
        case .apple: "当前：Apple Intelligence，在本机运行，不会发出"
        case .codex: "当前：Codex（\(codexModel)），启用的应用里句子会先发给 OpenAI"
        case .auto, nil: "当前：没有可用的模型（打开 Apple Intelligence 或安装 Codex）"
        }
    }

    static func command(from sender: Any?) -> Command? {
        let item = (sender as? [AnyHashable: Any])?[kIMKCommandMenuItemName as AnyHashable] as? NSMenuItem ?? sender as? NSMenuItem
        guard let item else {
            return nil
        }
        if item.tag == toggleTag || item.title.hasSuffix("中启用 AI 提示") {
            return .toggleChips
        }
        let providers = AIAssistSettings.Provider.allCases
        let index = item.tag - providerTagBase
        if providers.indices.contains(index) {
            return .provider(providers[index])
        }
        return providers.first { $0.title == item.title }.map { .provider($0) }
    }

    private static func item(_ title: String, tag: Int, action: Selector?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.tag = tag
        item.indentationLevel = 1
        return item
    }
}
