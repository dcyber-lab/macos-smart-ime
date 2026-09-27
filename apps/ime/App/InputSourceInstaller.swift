import Carbon
import Foundation

/// `SmartIMEHost --install`: registers and enables the input source for the current user, so installing
/// needs no Swift toolchain.
enum InputSourceInstaller {
    private static let keyboardInputMethod = "Keyboard Input Method"

    static func install() -> Int32 {
        let bundle = Bundle.main
        guard let bundleID = bundle.bundleIdentifier else {
            fputs("The app has no bundle identifier\n", stderr)
            return 1
        }

        let status = TISRegisterInputSource(bundle.bundleURL as CFURL)
        guard status == noErr else {
            fputs("TISRegisterInputSource failed with status \(status) for \(bundle.bundlePath)\n", stderr)
            return Int32(status)
        }

        normalizeInputSourceLists(bundleID: bundleID)

        // Include installed but disabled sources: a fresh install is not enabled yet.
        guard let source = inputSource(bundleID: bundleID, includeAllInstalled: true) else {
            fputs("The input source was not found after registration\n", stderr)
            return 1
        }
        let enableStatus = TISEnableInputSource(source)
        guard enableStatus == noErr else {
            fputs("TISEnableInputSource failed with status \(enableStatus)\n", stderr)
            return Int32(enableStatus)
        }

        guard let enabled = inputSource(bundleID: bundleID, includeAllInstalled: false),
              boolProperty(enabled, kTISPropertyInputSourceIsSelectCapable) else {
            fputs("Verification failed: the input source is not enabled and selectable\n", stderr)
            return 1
        }
        let name = stringProperty(enabled, kTISPropertyLocalizedName) ?? bundleID
        print("Verified: \(name) is enabled and selectable.")
        return 0
    }

    /// Drops malformed "Keyboard Input Method" entries without a bundle ID and duplicate entries for this input
    /// method from the HIToolbox lists; both kept it out of the input source switcher.
    private static func normalizeInputSourceLists(bundleID: String) {
        let domain = "com.apple.HIToolbox" as CFString
        for key in ["AppleEnabledInputSources", "AppleInputSourceHistory"] {
            let entries = CFPreferencesCopyAppValue(key as CFString, domain) as? [[String: Any]] ?? []
            var normalized: [[String: Any]] = []
            var hasEntry = false
            for entry in entries {
                let kind = entry["InputSourceKind"] as? String
                let entryBundleID = entry["Bundle ID"] as? String
                if kind == keyboardInputMethod && (entryBundleID == nil || entryBundleID == bundleID) {
                    if entryBundleID == bundleID && !hasEntry {
                        hasEntry = true
                        normalized.append(entry)
                    }
                    continue
                }
                normalized.append(entry)
            }
            if !hasEntry {
                normalized.append(["Bundle ID": bundleID, "InputSourceKind": keyboardInputMethod])
            }
            CFPreferencesSetAppValue(key as CFString, normalized as CFArray, domain)
        }
        CFPreferencesAppSynchronize(domain)
    }

    private static func inputSource(bundleID: String, includeAllInstalled: Bool) -> TISInputSource? {
        let filter = [kTISPropertyBundleID: bundleID] as CFDictionary
        let list = TISCreateInputSourceList(filter, includeAllInstalled)?.takeRetainedValue() as? [TISInputSource]
        return list?.first
    }

    private static func boolProperty(_ source: TISInputSource, _ key: CFString) -> Bool {
        guard let value = TISGetInputSourceProperty(source, key) else { return false }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(value).takeUnretainedValue())
    }

    private static func stringProperty(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let value = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(value).takeUnretainedValue() as String
    }
}
