import Foundation

nonisolated enum AppConstants {
    static let defaultPort = 23333
    static let appSupportName = "OpenMeow"
    static let bundleID = "dev.pidan.openmeow"
    static let version = "0.1.0"
    static let serverPortKey = "serverPort"
    static let listenAddressKey = "listenAddress"
    static let disabledModelsKey = "disabledModelIDs"
    static let authEnabledKey = "apiAuthEnabled"
    static let authTokenKey = "apiAuthToken"
    static let userAliasesKey = "userModelAliases"
    static let corsEnabledKey = "apiCorsEnabled"
    static let corsOriginsKey = "apiCorsAllowedOrigins"
    static let defaultTTSFormatKey = "defaultTTSResponseFormat"
    static let mimoApiKeyKey = "mimoApiKey"
    static let openaiCloudApiKeyKey = "openaiCloudApiKey"
    static let dashscopeApiKeyKey = "dashscopeApiKey"

    /// Default CORS allowed IPs (plain IP, hostname, or CIDR notation)
    static let corsLocalOrigins = ["127.0.0.1", "localhost", "[::1]"]
    static let corsLANOrigins = corsLocalOrigins + [
        "192.168.0.0/16",
        "10.0.0.0/8",
        "172.16.0.0/12",
    ]

    static let registryRemoteURL = ""

    static let appSupportURL: URL = {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(appSupportName)
    }()

    static let modelsDirectory: URL = {
        appSupportURL.appendingPathComponent("models")
    }()

    static let configDirectory: URL = {
        appSupportURL.appendingPathComponent("config")
    }()
}
