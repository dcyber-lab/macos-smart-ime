import Foundation

public enum IMEHostConfiguration {
    public static let connectionName = "lab.dcyber.inputmethod.smartime_Connection"
    public static let bundleIdentifier = "lab.dcyber.inputmethod.smartime"
    public static let defaultSchemaID = "smartime_pinyin"

    /// Schemas and dictionaries ship in the app (`Contents/Resources/RimeData`).
    public static func rimeSharedDataDirectory(bundle: Bundle = .main) -> String {
        (bundle.resourceURL ?? bundle.bundleURL)
            .appendingPathComponent("RimeData", isDirectory: true)
            .path
    }

    /// Precompiled tables built with the app, so a fresh install does not compile them on first use.
    public static func rimePrebuiltDataDirectory(bundle: Bundle = .main) -> String {
        URL(fileURLWithPath: rimeSharedDataDirectory(bundle: bundle), isDirectory: true)
            .appendingPathComponent("build", isDirectory: true)
            .path
    }

    /// The user's candidate picks (`CandidateHistory`); deleting the file resets what English candidates learned.
    public static func candidateHistoryURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/SmartIMEHost/candidate-history.json")
    }

    /// Chinese words committed without a translation (`TranslationMisses`); deleting it resets translation learning.
    public static func translationMissesURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/SmartIMEHost/translation-misses.json")
    }

    /// The user's own and learned Chinese-to-English translations (`UserTranslations`), editable by hand.
    public static func userTranslationsURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/SmartIMEHost/user-translations.tsv")
    }

    /// Intelligence hub statistics (`InputMemory`): per-app language counts and sentence fingerprints.
    public static func inputMemoryURL() -> URL {
        supportDirectory().appendingPathComponent("input-memory.json")
    }

    /// The optional input journal (`InputJournal`), one file per day.
    public static func inputJournalDirectoryURL() -> URL {
        supportDirectory().appendingPathComponent("journal", isDirectory: true)
    }

    /// The page View Learning Data writes and opens.
    public static func learningPageURL() -> URL {
        supportDirectory().appendingPathComponent("learning-summary.html")
    }

    /// The clipboard history (`ClipboardHistoryStore`): an index and the copied images.
    public static func clipboardHistoryDirectoryURL() -> URL {
        supportDirectory().appendingPathComponent("clipboard", isDirectory: true)
    }

    private static func supportDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/SmartIMEHost", isDirectory: true)
    }

    public static func rimeUserDataDirectory() -> String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/SmartIMEHost/Rime", isDirectory: true)
            .path
    }

    public static func rimeBuildDirectory() -> String {
        URL(fileURLWithPath: rimeUserDataDirectory(), isDirectory: true)
            .appendingPathComponent("build", isDirectory: true)
            .path
    }
}
