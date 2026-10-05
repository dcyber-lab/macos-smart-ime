import Foundation

/// Every hotkey the input method has, with the defaults key each one is stored under. The settings
/// structs of each feature read the same keys, so a change here applies where the feature reads it.
enum HotkeyAction: CaseIterable {
    case translate, rewrite, read, screenshot, screenshotOCR, clipboard

    var title: String {
        switch self {
        case .translate: return "翻译选中文字"
        case .rewrite: return "改写选中文字或当前行"
        case .read: return "读取其他地方选中的文字"
        case .screenshot: return "截图并标注"
        case .screenshotOCR: return "截图识字"
        case .clipboard: return "剪贴板历史"
        }
    }

    var key: String {
        switch self {
        case .translate: return SelectionTranslationSettings.hotkeyKey
        case .rewrite: return AIAssistSettings.hotkeyKey
        case .read: return AIAssistSettings.readHotkeyKey
        case .screenshot: return ScreenshotSettings.hotkeyKey
        case .screenshotOCR: return ScreenshotSettings.ocrHotkeyKey
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
