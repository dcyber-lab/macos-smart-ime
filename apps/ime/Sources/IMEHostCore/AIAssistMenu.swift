import AppKit
@preconcurrency import InputMethodKit

/// The AI 助手 section of the input menu (proof of concept).
enum AIAssistMenu {
    static let title = "AI 助手（POC）"
    static let toggleTag = 400

    static func enableTitle(_ appName: String) -> String {
        "在「\(appName)」中启用 AI 提示"
    }

    static func items(settings: AIAssistSettings, currentApp: (id: String, name: String)?, codexFound: Bool, action: Selector) -> [NSMenuItem] {
        let header = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        header.isEnabled = false
        var items = [header]
        if let currentApp {
            let toggle = NSMenuItem(title: enableTitle(currentApp.name), action: action, keyEquivalent: "")
            toggle.tag = toggleTag
            toggle.state = settings.chipApps.contains(currentApp.id) ? .on : .off
            toggle.isEnabled = codexFound
            toggle.indentationLevel = 1
            items.append(toggle)
        }
        let status = NSMenuItem(title: codexFound ? "Codex：\(settings.codexModel)，确认前会先把句子发给 OpenAI" : "未找到 Codex", action: nil, keyEquivalent: "")
        status.isEnabled = false
        status.indentationLevel = 1
        items.append(status)
        return items
    }

    static func isToggle(_ sender: Any?) -> Bool {
        let item = (sender as? [AnyHashable: Any])?[kIMKCommandMenuItemName as AnyHashable] as? NSMenuItem ?? sender as? NSMenuItem
        guard let item else {
            return false
        }
        return item.tag == toggleTag || item.title.hasSuffix("中启用 AI 提示")
    }
}
