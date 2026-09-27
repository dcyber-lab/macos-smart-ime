import Foundation

public struct RimeBridgeConfiguration: Sendable {
    public let sharedDataDirectory: String
    public let userDataDirectory: String
    public let prebuiltDataDirectory: String
    public let stagingDirectory: String
    public let appName: String
    public let distributionName: String
    public let distributionCodeName: String
    public let distributionVersion: String
    public let defaultSchemaID: String

    public init(
        sharedDataDirectory: String,
        userDataDirectory: String,
        prebuiltDataDirectory: String,
        stagingDirectory: String,
        appName: String,
        distributionName: String,
        distributionCodeName: String,
        distributionVersion: String,
        defaultSchemaID: String = "smartime_pinyin"
    ) {
        self.sharedDataDirectory = sharedDataDirectory
        self.userDataDirectory = userDataDirectory
        self.prebuiltDataDirectory = prebuiltDataDirectory
        self.stagingDirectory = stagingDirectory
        self.appName = appName
        self.distributionName = distributionName
        self.distributionCodeName = distributionCodeName
        self.distributionVersion = distributionVersion
        self.defaultSchemaID = defaultSchemaID
    }
}
