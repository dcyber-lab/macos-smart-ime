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
