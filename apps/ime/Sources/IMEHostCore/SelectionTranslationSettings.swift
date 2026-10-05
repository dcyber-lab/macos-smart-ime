import AppKit

/// A hotkey written as `modifier+…+letter`, e.g. "ctrl+option+t".
struct TranslationHotkey: Equatable {
    static let `default` = TranslationHotkey(keyCode: 17, modifiers: [.control, .option])

    private static let relevantModifiers: NSEvent.ModifierFlags = [.control, .option, .command, .shift]
    private static let modifierNames: [String: NSEvent.ModifierFlags] = [
        "ctrl": .control, "control": .control,
        "option": .option, "alt": .option,
        "cmd": .command, "command": .command,
        "shift": .shift,
    ]
    // ANSI virtual key codes for a–z.
    private static let letterKeyCodes: [Character: UInt16] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12,
        "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38,
        "k": 40, "n": 45, "m": 46,
    ]

    let keyCode: UInt16
    let modifiers: NSEvent.ModifierFlags

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Nil unless the string has at least one of ctrl, option, or cmd and ends with a single letter,
    /// so plain typing can never be captured.
    init?(string: String) {
        let parts = string.lowercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let last = parts.last, last.count == 1, let keyCode = Self.letterKeyCodes[Character(last)] else {
            return nil
        }
        var modifiers: NSEvent.ModifierFlags = []
        for part in parts.dropLast() {
            guard let modifier = Self.modifierNames[part] else {
                return nil
            }
            modifiers.insert(modifier)
        }
        guard !modifiers.isDisjoint(with: [.control, .option, .command]) else {
            return nil
        }
        self.init(keyCode: keyCode, modifiers: modifiers)
    }

    /// A key pressed while recording a new hotkey; nil unless it is a letter with ⌃, ⌥, or ⌘ held.
    init?(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) {
        let modifiers = modifierFlags.intersection(Self.relevantModifiers)
        guard Self.letterKeyCodes.values.contains(keyCode), !modifiers.isDisjoint(with: [.control, .option, .command]) else {
            return nil
        }
        self.init(keyCode: keyCode, modifiers: modifiers)
    }

    /// The `modifier+…+letter` form stored in defaults, e.g. "ctrl+option+r"; `init?(string:)` reads it back.
    var storageString: String {
        let names: [(NSEvent.ModifierFlags, String)] = [(.control, "ctrl"), (.option, "option"), (.shift, "shift"), (.command, "cmd")]
        let letter = Self.letterKeyCodes.first { $0.value == keyCode }.map { String($0.key) } ?? ""
        return (names.filter { modifiers.contains($0.0) }.map(\.1) + [letter]).joined(separator: "+")
    }

    /// The hotkey as macOS menus write it, e.g. "⌃⌥R".
    var displayString: String {
        let symbols: [(NSEvent.ModifierFlags, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        let letter = Self.letterKeyCodes.first { $0.value == keyCode }.map { String($0.key).uppercased() } ?? "?"
        return symbols.filter { modifiers.contains($0.0) }.map(\.1).joined() + letter
    }

    func matches(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) -> Bool {
        keyCode == self.keyCode && modifierFlags.intersection(Self.relevantModifiers) == modifiers
    }
}

/// Selection translation settings in the input method's defaults domain, read on every use so that
/// `defaults write lab.dcyber.inputmethod.smartime …` applies without restarting the input method.
struct SelectionTranslationSettings {
    static let enabledKey = "SelectionTranslationEnabled"
    static let hotkeyKey = "SelectionTranslationHotkey"

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isEnabled: Bool {
        defaults.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    var hotkey: TranslationHotkey {
        defaults.string(forKey: Self.hotkeyKey).flatMap(TranslationHotkey.init(string:)) ?? .default
    }
}
