import AppKit
@preconcurrency import InputMethodKit
import UserData

/// The 智能中心 section of the input menu, flat like the commit effect section.
enum IntelligenceMenu {
    static let title = "智能中心"

    enum Command: Int, CaseIterable {
        case learning = 300
        case journal
        case excludeApp
        case view
        case clear
    }

    static let learningTitle = "智能学习"
    static let journalTitle = "保存输入原文"
    static let viewTitle = "查看学习记录…"
    static let clearTitle = "清除学习记录…"

    static func excludeTitle(_ appName: String) -> String {
        "不在「\(appName)」中学习"
    }

    /// `currentApp` is the client being typed in, if known.
    static func items(settings: IntelligenceSettings, currentApp: (id: String, name: String)?, action: Selector) -> [NSMenuItem] {
        let header = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        header.isEnabled = false
        var items = [header]

        let learning = settings.isLearningEnabled
        items.append(item(learningTitle, .learning, action, isOn: learning))
        items.append(item(journalTitle, .journal, action, isOn: settings.isJournalEnabled, isEnabled: learning))
        if let currentApp {
            items.append(item(excludeTitle(currentApp.name), .excludeApp, action, isOn: settings.isExcluded(currentApp.id)))
        }
        items.append(item(viewTitle, .view, action))
        items.append(item(clearTitle, .clear, action))
        return items
    }

    /// InputMethodKit passes a dictionary holding the chosen item under `kIMKCommandMenuItemName`.
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
        case journalTitle: return .journal
        case viewTitle: return .view
        case clearTitle: return .clear
        default: return item.title.hasPrefix("不在「") ? .excludeApp : nil
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
