import AppKit
@preconcurrency import InputMethodKit

/// The commit effect section of the input menu. It is flat, with disabled section titles: the
/// system's input menu did not deliver actions from submenu items.
enum CommitEffectMenu {
    static let motionTitle = "选词动效"
    static let paletteTitle = "碎片配色"
    private static let motionTagBase = 100
    private static let paletteTagBase = 200

    static func items(
        motion: CommitEffectMotionChoice, palette: CommitEffectPaletteChoice, motionAction: Selector, paletteAction: Selector
    ) -> [NSMenuItem] {
        section(motionTitle, CommitEffectMotionChoice.allChoices.map { ($0.title, $0 == motion) }, tagBase: motionTagBase, action: motionAction)
            + [.separator()]
            + section(paletteTitle, CommitEffectPaletteChoice.allChoices.map { ($0.title, $0 == palette) }, tagBase: paletteTagBase, action: paletteAction)
    }

    static func motionChoice(from sender: Any?) -> CommitEffectMotionChoice? {
        choice(from: sender, tagBase: motionTagBase, in: CommitEffectMotionChoice.allChoices, title: \.title)
    }

    static func paletteChoice(from sender: Any?) -> CommitEffectPaletteChoice? {
        choice(from: sender, tagBase: paletteTagBase, in: CommitEffectPaletteChoice.allChoices, title: \.title)
    }

    private static func section(_ title: String, _ entries: [(title: String, isOn: Bool)], tagBase: Int, action: Selector) -> [NSMenuItem] {
        let header = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        header.isEnabled = false
        return [header] + entries.enumerated().map { index, entry in
            let item = NSMenuItem(title: entry.title, action: action, keyEquivalent: "")
            item.tag = tagBase + index
            item.state = entry.isOn ? .on : .off
            item.indentationLevel = 1
            return item
        }
    }

    /// InputMethodKit passes a dictionary holding the chosen item under `kIMKCommandMenuItemName`.
    /// The tag identifies the choice; the title is a fallback in case the item arrives as a copy.
    private static func choice<Choice>(from sender: Any?, tagBase: Int, in choices: [Choice], title: (Choice) -> String) -> Choice? {
        let item = (sender as? [AnyHashable: Any])?[kIMKCommandMenuItemName as AnyHashable] as? NSMenuItem ?? sender as? NSMenuItem
        guard let item else {
            return nil
        }
        let index = item.tag - tagBase
        if choices.indices.contains(index) {
            return choices[index]
        }
        return choices.first { title($0) == item.title }
    }
}
