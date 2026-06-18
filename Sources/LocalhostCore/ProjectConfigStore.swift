import Foundation

public struct ProjectConfigStore: Sendable {
    public let configURL: URL

    public static var defaultConfigURL: URL {
        configURL(supportDirectory: "jocalhost", fileName: "projects.plist")
    }

    public init(configURL: URL = Self.defaultConfigURL) {
        self.configURL = configURL
    }

    public func load() throws -> [ProjectDefinition] {
        try ensureExists()

        let data = try Data(contentsOf: configURL)
        guard data.contains(where: { !$0.isASCIIWhitespace }) else {
            return []
        }

        do {
            return try PropertyListDecoder().decode([ProjectDefinition].self, from: data)
        } catch {
            let backupURL = backupInvalidConfig()
            throw ProjectConfigStoreError.invalidConfig(
                path: configURL.path,
                backupPath: backupURL?.path,
                underlying: error.localizedDescription
            )
        }
    }

    public func save(_ projects: [ProjectDefinition]) throws {
        try ensureExists()

        let data = try encodePropertyList(projects)
        try data.write(to: configURL, options: .atomic)
    }

    public func registerProject(
        workingDirectory rawWorkingDirectory: String,
        name rawName: String? = nil,
        command rawCommand: String? = nil,
        port: Int? = nil,
        exposeOnLocalNetwork: Bool = true
    ) throws -> ProjectRegistrationResult {
        let workingDirectory = URL(fileURLWithPath: rawWorkingDirectory).standardizedFileURL.path
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: workingDirectory, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw ProjectRegistrationError.workingDirectoryNotFound(workingDirectory)
        }

        var projects = try load()
        if let existing = projects.first(where: { URL(fileURLWithPath: $0.workingDirectory).standardizedFileURL.path == workingDirectory }) {
            return ProjectRegistrationResult(project: existing, created: false, configPath: configURL.path)
        }

        let detection = ProjectDetection.detect(in: workingDirectory)
        let name = rawName?.trimmedNonEmpty ?? detection?.name ?? URL(fileURLWithPath: workingDirectory).lastPathComponent
        guard let command = rawCommand?.trimmedNonEmpty ?? detection?.command?.trimmedNonEmpty else {
            throw ProjectRegistrationError.missingCommand(workingDirectory)
        }
        let projectPort = port ?? detection?.port
        let detectedServices = detection?.services.map {
            ProjectServiceDefinition(
                name: $0.name,
                command: $0.command,
                port: $0.port,
                exposeOnLocalNetwork: exposeOnLocalNetwork
            )
        } ?? []

        let project = ProjectDefinition(
            name: name,
            workingDirectory: workingDirectory,
            command: command,
            port: projectPort,
            exposeOnLocalNetwork: exposeOnLocalNetwork,
            services: detectedServices.count > 1 ? detectedServices : []
        )
        projects.append(project)
        try save(projects)
        return ProjectRegistrationResult(project: project, created: true, configPath: configURL.path)
    }

    public func ensureExists() throws {
        let directoryURL = configURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        guard !FileManager.default.fileExists(atPath: configURL.path) else {
            return
        }

        let data = try encodePropertyList([])
        try data.write(to: configURL, options: .atomic)
    }

    private static func configURL(supportDirectory: String, fileName: String) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent(supportDirectory, isDirectory: true)
            .appendingPathComponent(fileName)
    }

    private func backupInvalidConfig() -> URL? {
        let backupURL = configURL
            .deletingLastPathComponent()
            .appendingPathComponent("projects.invalid-\(UUID().uuidString).plist")

        do {
            try FileManager.default.copyItem(at: configURL, to: backupURL)
            return backupURL
        } catch {
            return nil
        }
    }

    private func encodePropertyList(_ projects: [ProjectDefinition]) throws -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        return try encoder.encode(projects)
    }

}

public struct ProjectRegistrationResult: Equatable, Sendable {
    public var project: ProjectDefinition
    public var created: Bool
    public var configPath: String
}

public enum ProjectRegistrationError: LocalizedError, Equatable, Sendable {
    case workingDirectoryNotFound(String)
    case missingCommand(String)

    public var errorDescription: String? {
        switch self {
        case let .workingDirectoryNotFound(path):
            return "Working directory not found: \(path)"
        case let .missingCommand(path):
            return "Could not detect a dev command for \(path). Provide command explicitly."
        }
    }
}

public enum ProjectConfigStoreError: LocalizedError, Equatable, Sendable {
    case invalidConfig(path: String, backupPath: String?, underlying: String)

    public var errorDescription: String? {
        switch self {
        case let .invalidConfig(path, backupPath, underlying):
            var message = "Invalid project config at \(path): \(underlying)"
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

private extension String {
    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
