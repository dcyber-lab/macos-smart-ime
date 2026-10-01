import Foundation

/// Files only the user can read (0600 in a 0700 directory), kept out of Time Machine.
public enum PrivateFiles {
    public static func prepareDirectory(_ url: URL) {
        let manager = FileManager.default
        try? manager.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var directory = url
        try? directory.setResourceValues(values)
    }

    /// Replaces the file atomically, then restricts it.
    public static func write(_ data: Data, to url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard (try? data.write(to: url, options: .atomic)) != nil else {
            return
        }
        restrict(url)
    }

    public static func restrict(_ url: URL) {
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var file = url
        try? file.setResourceValues(values)
    }
}
