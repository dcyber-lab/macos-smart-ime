import Foundation

/// Screenshot settings in the input method's defaults domain. The hotkeys are registered when the input
/// method starts and again whenever these settings change in this process.
struct ScreenshotSettings: Equatable {
    static let enabledKey = "ScreenshotEnabled"
    static let hotkeyKey = "ScreenshotHotkey"
    static let ocrHotkeyKey = "ScreenshotOCRHotkey"
    static let saveFolderKey = "ScreenshotSaveFolder"
    /// ⌃⌥A (A is ANSI key code 0): capture, then mark up, copy, save, pin, or recognize text.
    static let defaultHotkey = TranslationHotkey(keyCode: 0, modifiers: [.control, .option])
    /// ⌃⌥O (O is ANSI key code 31): select an area and copy the text in it.
    static let defaultOCRHotkey = TranslationHotkey(keyCode: 31, modifiers: [.control, .option])

    let isEnabled: Bool
    let hotkey: TranslationHotkey
    let ocrHotkey: TranslationHotkey
    let customSaveFolder: URL?
    /// Where macOS saves its own screenshots (`com.apple.screencapture location`), if set.
    let systemSaveFolder: URL?

    init(defaults: UserDefaults = .standard, systemDefaults: UserDefaults? = UserDefaults(suiteName: "com.apple.screencapture")) {
        isEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
        hotkey = defaults.string(forKey: Self.hotkeyKey).flatMap(TranslationHotkey.init(string:)) ?? Self.defaultHotkey
        ocrHotkey = defaults.string(forKey: Self.ocrHotkeyKey).flatMap(TranslationHotkey.init(string:)) ?? Self.defaultOCRHotkey
        customSaveFolder = defaults.string(forKey: Self.saveFolderKey).map(Self.folderURL(_:))
        systemSaveFolder = systemDefaults?.string(forKey: "location").map(Self.folderURL(_:))
    }

    /// The chosen folder, else the folder macOS screenshots go to, else the desktop.
    var saveFolder: URL {
        customSaveFolder ?? systemSaveFolder
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
    }

    static func setEnabled(_ enabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: enabledKey)
    }

    static func setSaveFolder(_ folder: URL?, defaults: UserDefaults = .standard) {
        defaults.set(folder?.path, forKey: saveFolderKey)
    }

    /// "Screenshot 2026-10-05 15.03.12.png", with " (2)" and up when the name is taken.
    static func fileName(at date: Date, existing: (String) -> Bool) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let base = "Screenshot \(formatter.string(from: date))"
        var name = base + ".png"
        var counter = 2
        while existing(name) {
            name = "\(base) (\(counter)).png"
            counter += 1
        }
        return name
    }

    private static func folderURL(_ path: String) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
    }
}
