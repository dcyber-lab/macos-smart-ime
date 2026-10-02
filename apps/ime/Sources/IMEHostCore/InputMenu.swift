import AppKit
@preconcurrency import InputMethodKit
import UserData

/// LinguaType's part of the input menu: the switches used while typing, and 设置… for the rest
/// (`SettingsWindow`). It is flat: the system's input menu shows submenus but never delivers their
/// items' actions.
enum InputMenu {
    enum Command: Int, CaseIterable {
        case learning = 300
        case excludeApp
        case aiHints
        case viewLearning
        case settings
    }

    static let learningTitle = "智能学习"
    static let viewLearningTitle = "查看学习记录…"
    static let settingsTitle = "设置…"

    static func excludeTitle(_ appName: String) -> String {
        "不在「\(appName)」中学习"
    }

    static func aiHintsTitle(_ appName: String) -> String {
        "在「\(appName)」中启用 AI 提示"
    }

    /// `currentApp` is the client being typed in, if known. `aiAvailable` says whether a model can
    /// run; AI hints can then be turned on, and can always be turned off.
    static func items(
        intelligence: IntelligenceSettings, ai: AIAssistSettings, currentApp: (id: String, name: String)?, aiAvailable: Bool, action: Selector
    ) -> [NSMenuItem] {
        var items = [item(learningTitle, .learning, action, isOn: intelligence.isLearningEnabled)]
        if let currentApp {
            items.append(item(excludeTitle(currentApp.name), .excludeApp, action, isOn: intelligence.isExcluded(currentApp.id)))
            let hints = ai.chipApps.contains(currentApp.id)
            items.append(item(aiHintsTitle(currentApp.name), .aiHints, action, isOn: hints, isEnabled: aiAvailable || hints))
        }
        items.append(item(viewLearningTitle, .viewLearning, action))
        items.append(item(settingsTitle, .settings, action))
        return items
    }

    /// InputMethodKit passes a dictionary holding the chosen item under `kIMKCommandMenuItemName`.
    /// The tag identifies the command; the title is a fallback in case the item arrives as a copy.
    static func command(from sender: Any?) -> Command? {
        let item = (sender as? [AnyHashable: Any])?[kIMKCommandMenuItemName as AnyHashable] as? NSMenuItem ?? sender as? NSMenuItem
        guard let item else {
            return nil
        }
        if let command = Command(rawValue: item.tag) {
            return command
        }
        switch item.title {
        case learningTitle: return .learning
        case viewLearningTitle: return .viewLearning
        case settingsTitle: return .settings
        case let title where title.hasPrefix("不在「") && title.hasSuffix("」中学习"): return .excludeApp
        case let title where title.hasSuffix("」中启用 AI 提示"): return .aiHints
        default: return nil
        }
    }

    private static func item(_ title: String, _ command: Command, _ action: Selector, isOn: Bool = false, isEnabled: Bool = true) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.tag = command.rawValue
        item.state = isOn ? .on : .off
        item.isEnabled = isEnabled
        item.indentationLevel = 1
        return item
    }
}

/// App names for the menu and the learning page.
enum AppNames {
    static func displayName(for bundleIdentifier: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return bundleIdentifier
        }
        let name = FileManager.default.displayName(atPath: url.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }
}
