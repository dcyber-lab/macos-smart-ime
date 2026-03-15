import Foundation

public enum IMEHostConfiguration {
    public static let connectionName = "lab.dcyber.inputmethod.smartime_Connection"
    public static let bundleIdentifier = "lab.dcyber.inputmethod.smartime"
    public static let defaultSchemaID = "luna_pinyin"

    public static func rimeSharedDataDirectory(bundle: Bundle = .main) -> String {
        if let configuredValue = bundle.object(forInfoDictionaryKey: "RimeSharedDataDirectory") as? String,
           !configuredValue.isEmpty {
            return configuredValue
        }

        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("third_party/librime-data/minimal", isDirectory: true)
            .path
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
