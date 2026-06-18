import Foundation

public struct ProjectConfigStore: Sendable {
    public let configURL: URL
    public let legacyJSONURL: URL?
    public let legacyPropertyListURL: URL?

    public static var defaultConfigURL: URL {
        configURL(supportDirectory: "jocalhost", fileName: "projects.plist")
    }

    public static var defaultLegacyJSONURL: URL {
        configURL(supportDirectory: "localhost-app", fileName: "projects.json")
    }

    public static var defaultLegacyPropertyListURL: URL {
        configURL(supportDirectory: "localhost-app", fileName: "projects.plist")
    }

    public init(
        configURL: URL = Self.defaultConfigURL,
        legacyJSONURL: URL? = nil,
        legacyPropertyListURL: URL? = nil
    ) {
        let usesDefaultConfig = configURL.path == Self.defaultConfigURL.path
        self.configURL = configURL
        self.legacyJSONURL = legacyJSONURL ?? (usesDefaultConfig ? Self.defaultLegacyJSONURL : nil)
        self.legacyPropertyListURL = legacyPropertyListURL ?? (usesDefaultConfig ? Self.defaultLegacyPropertyListURL : nil)
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
            archiveLegacyJSONIfPresent()
            return
        }

        if try migrateLegacyPropertyListIfPresent() {
            archiveLegacyJSONIfPresent()
            return
        }

        if let legacyJSONURL,
           FileManager.default.fileExists(atPath: legacyJSONURL.path) {
            let projects = try loadLegacyJSON(from: legacyJSONURL)
            let data = try encodePropertyList(projects)
            try data.write(to: configURL, options: .atomic)
            archiveLegacyJSONIfPresent()
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

    private func loadLegacyJSON(from url: URL) throws -> [ProjectDefinition] {
        let data = try Data(contentsOf: url)
        guard data.contains(where: { !$0.isASCIIWhitespace }) else {
            return []
        }

        do {
            return try JSONDecoder().decode([ProjectDefinition].self, from: data)
        } catch {
            throw ProjectConfigStoreError.invalidLegacyJSON(
                path: url.path,
                underlying: error.localizedDescription
            )
        }
    }

    private func migrateLegacyPropertyListIfPresent() throws -> Bool {
        guard let legacyPropertyListURL,
              legacyPropertyListURL.path != configURL.path,
              FileManager.default.fileExists(atPath: legacyPropertyListURL.path) else {
            return false
        }

        let data = try Data(contentsOf: legacyPropertyListURL)
        let projects: [ProjectDefinition]

        if data.contains(where: { !$0.isASCIIWhitespace }) {
            do {
                projects = try PropertyListDecoder().decode([ProjectDefinition].self, from: data)
            } catch {
                throw ProjectConfigStoreError.invalidConfig(
                    path: legacyPropertyListURL.path,
                    backupPath: nil,
                    underlying: error.localizedDescription
                )
            }
        } else {
            projects = []
        }

        let migratedData = try encodePropertyList(projects)
        try migratedData.write(to: configURL, options: .atomic)
        archiveLegacyPropertyListIfPresent()
        return true
    }

    private func archiveLegacyJSONIfPresent() {
        guard let legacyJSONURL,
              legacyJSONURL.path != configURL.path,
              FileManager.default.fileExists(atPath: legacyJSONURL.path) else {
            return
        }

        let archiveURL = legacyJSONURL
            .deletingLastPathComponent()
            .appendingPathComponent("projects.legacy-json-\(UUID().uuidString).backup")

        try? FileManager.default.moveItem(at: legacyJSONURL, to: archiveURL)
    }

    private func archiveLegacyPropertyListIfPresent() {
        guard let legacyPropertyListURL,
              legacyPropertyListURL.path != configURL.path,
              FileManager.default.fileExists(atPath: legacyPropertyListURL.path) else {
            return
        }

        let archiveURL = legacyPropertyListURL
            .deletingLastPathComponent()
            .appendingPathComponent("projects.legacy-localhost-app-\(UUID().uuidString).backup")

        try? FileManager.default.moveItem(at: legacyPropertyListURL, to: archiveURL)
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
    case invalidLegacyJSON(path: String, underlying: String)

    public var errorDescription: String? {
        switch self {
        case let .invalidConfig(path, backupPath, underlying):
            var message = "Invalid project config at \(path): \(underlying)"
            if let backupPath {
                message += " Backup: \(backupPath)"
            }
            return message
        case let .invalidLegacyJSON(path, underlying):
            return "Legacy JSON config at \(path) could not be migrated: \(underlying)"
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
