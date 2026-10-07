import Foundation

/// Every hotkey the input method has, with the defaults key each one is stored under. The settings
/// structs of each feature read the same keys, so a change here applies where the feature reads it.
enum HotkeyAction: CaseIterable {
    case translate, rewrite, read, screenshot, screenshotOCR, screenRecording, clipboard

    var title: String {
        switch self {
        case .translate: return "Translate selected text"
        case .rewrite: return "Rewrite selected text or current line"
        case .read: return "Read text selected elsewhere"
        case .screenshot: return "Screenshot and annotate"
        case .screenshotOCR: return "Screenshot OCR"
        case .screenRecording: return "Record screen"
        case .clipboard: return "Clipboard history"
        }
    }

    var key: String {
        switch self {
        case .translate: return SelectionTranslationSettings.hotkeyKey
        case .rewrite: return AIAssistSettings.hotkeyKey
        case .read: return AIAssistSettings.readHotkeyKey
        case .screenshot: return ScreenshotSettings.hotkeyKey
        case .screenshotOCR: return ScreenshotSettings.ocrHotkeyKey
        case .screenRecording: return ScreenshotSettings.recordHotkeyKey
        case .clipboard: return ClipboardSettings.hotkeyKey
        }
    }

    var defaultHotkey: TranslationHotkey {
        switch self {
        case .translate: return .default
        case .rewrite: return AIAssistSettings.defaultHotkey
        case .read: return AIAssistSettings.defaultReadHotkey
        case .screenshot: return ScreenshotSettings.defaultHotkey
        case .screenshotOCR: return ScreenshotSettings.defaultOCRHotkey
        case .screenRecording: return ScreenshotSettings.defaultRecordHotkey
        case .clipboard: return ClipboardSettings.defaultHotkey
        }
    }

    func hotkey(defaults: UserDefaults = .standard) -> TranslationHotkey {
        defaults.string(forKey: key).flatMap(TranslationHotkey.init(string:)) ?? defaultHotkey
    }

    /// The other action that already uses `hotkey`, if any.
    func conflict(with hotkey: TranslationHotkey, defaults: UserDefaults = .standard) -> HotkeyAction? {
        Self.allCases.first { $0 != self && $0.hotkey(defaults: defaults) == hotkey }
    }

    /// Stores `hotkey`, or the default again when nil. Returns the action in the way when it is taken.
    @discardableResult
    func set(_ hotkey: TranslationHotkey?, defaults: UserDefaults = .standard) -> HotkeyAction? {
        if let taken = conflict(with: hotkey ?? defaultHotkey, defaults: defaults) {
            return taken
        }
        if let hotkey {
            defaults.set(hotkey.storageString, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
        return nil
    }
}
