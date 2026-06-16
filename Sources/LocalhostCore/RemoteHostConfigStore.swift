import Foundation

public struct RemoteHostConfigStore: Sendable {
    public let configURL: URL

    public static var defaultConfigURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("jocalhost", isDirectory: true)
            .appendingPathComponent("remote-hosts.plist")
    }

    public init(configURL: URL = Self.defaultConfigURL) {
        self.configURL = configURL
    }

    public func load() throws -> [RemoteHostDefinition] {
        try ensureExists()

        let data = try Data(contentsOf: configURL)
        guard data.contains(where: { !$0.isASCIIWhitespace }) else {
            return []
        }

        do {
            return try PropertyListDecoder().decode([RemoteHostDefinition].self, from: data)
        } catch {
            let backupURL = backupInvalidConfig()
            throw RemoteHostConfigStoreError.invalidConfig(
                path: configURL.path,
                backupPath: backupURL?.path,
                underlying: error.localizedDescription
            )
        }
    }

    public func save(_ hosts: [RemoteHostDefinition]) throws {
        try ensureExists()

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(hosts)
        try data.write(to: configURL, options: .atomic)
        try setPrivateFilePermissions()
    }

    public func ensureExists() throws {
        let directoryURL = configURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directoryURL.path
        )

        guard FileManager.default.fileExists(atPath: configURL.path) == false else {
            try setPrivateFilePermissions()
            return
        }

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode([RemoteHostDefinition]())
        try data.write(to: configURL, options: .atomic)
        try setPrivateFilePermissions()
    }

    private func setPrivateFilePermissions() throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: configURL.path
        )
    }

    private func backupInvalidConfig() -> URL? {
        let backupURL = configURL
            .deletingLastPathComponent()
            .appendingPathComponent("remote-hosts.invalid-\(UUID().uuidString).plist")

        do {
            try FileManager.default.copyItem(at: configURL, to: backupURL)
            return backupURL
        } catch {
            return nil
        }
    }
}

public enum RemoteHostConfigStoreError: LocalizedError, Equatable, Sendable {
    case invalidConfig(path: String, backupPath: String?, underlying: String)

    public var errorDescription: String? {
        switch self {
        case let .invalidConfig(path, backupPath, underlying):
            var message = "Invalid remote host config at \(path): \(underlying)"
            if let backupPath {
                message += " Backup: \(backupPath)"
            }
            return message
        }
    }
}

private extension UInt8 {
    var isASCIIWhitespace: Bool {
        self == 0x20 || self == 0x09 || self == 0x0A || self == 0x0D
    }
}
