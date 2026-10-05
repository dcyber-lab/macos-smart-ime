import Foundation
import UserData

/// Intelligence hub settings in the input method's defaults domain, read on every use so that
/// `defaults write lab.dcyber.inputmethod.smartime …` applies without restarting the input method.
struct IntelligenceSettings {
    static let learningKey = "IntelligenceLearningEnabled"
    static let journalKey = "IntelligenceJournalEnabled"
    static let retentionKey = "IntelligenceJournalRetentionDays"
    static let excludedAppsKey = "IntelligenceExcludedApps"
    static let allowedAppsKey = "IntelligenceAllowedApps"
    static let windowTitlesKey = "IntelligenceWindowTitlesEnabled"
    static let defaultRetentionDays = 30

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Off until the user turns on Intelligence Learning.
    var isLearningEnabled: Bool {
        get { defaults.object(forKey: Self.learningKey) as? Bool ?? false }
        nonmutating set { defaults.set(newValue, forKey: Self.learningKey) }
    }

    /// The raw-text journal; on by default, only used while learning is on.
    var isJournalEnabled: Bool {
        get { defaults.object(forKey: Self.journalKey) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Self.journalKey) }
    }

    /// Reading the focused window's title (needs Accessibility access); off by default.
    var isWindowTitlesEnabled: Bool {
        get { defaults.object(forKey: Self.windowTitlesKey) as? Bool ?? false }
        nonmutating set { defaults.set(newValue, forKey: Self.windowTitlesKey) }
    }

    var retentionDays: Int {
        let days = defaults.object(forKey: Self.retentionKey) as? Int ?? Self.defaultRetentionDays
        return min(max(days, 1), 365)
    }

    /// Apps the user excluded, on top of `PrivacyFilter.defaultExcludedApps`.
    var excludedApps: Set<String> {
        get { Set(defaults.stringArray(forKey: Self.excludedAppsKey) ?? []) }
        nonmutating set { defaults.set(newValue.sorted(), forKey: Self.excludedAppsKey) }
    }

    /// Default exclusions (`PrivacyFilter.defaultExcludedApps`) the user chose to learn in anyway.
    var allowedApps: Set<String> {
        get { Set(defaults.stringArray(forKey: Self.allowedAppsKey) ?? []) }
        nonmutating set { defaults.set(newValue.sorted(), forKey: Self.allowedAppsKey) }
    }

    func allows(app: String?) -> Bool {
        PrivacyFilter.allowsApp(app, userExcluded: excludedApps, userAllowed: allowedApps)
    }

    func isExcluded(_ app: String) -> Bool {
        !allows(app: app)
    }

    /// Every app currently not learned: defaults the user did not allow, plus the user's own.
    var effectiveExcludedApps: Set<String> {
        PrivacyFilter.defaultExcludedApps.subtracting(allowedApps).union(excludedApps)
    }

    /// Default exclusions flip in `allowedApps`; other apps flip in `excludedApps`.
    func toggleExcluded(_ app: String) {
        if PrivacyFilter.defaultExcludedApps.contains(app) {
            allowedApps = allowedApps.symmetricDifference([app])
        } else {
            excludedApps = excludedApps.symmetricDifference([app])
        }
    }
}
