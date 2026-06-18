import Foundation

public struct ProjectServiceDefinition: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var command: String
    public var port: Int?
    public var exposeOnLocalNetwork: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        command: String,
        port: Int? = nil,
        exposeOnLocalNetwork: Bool = false
    ) {
        self.id = id
        self.name = name
        self.command = command
        self.port = port
        self.exposeOnLocalNetwork = exposeOnLocalNetwork
    }
}

extension ProjectServiceDefinition {
    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case command
        case port
        case exposeOnLocalNetwork
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.command = try container.decode(String.self, forKey: .command)
        self.port = try container.decodeIfPresent(Int.self, forKey: .port)
        self.exposeOnLocalNetwork = try container.decodeIfPresent(Bool.self, forKey: .exposeOnLocalNetwork) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(command, forKey: .command)
        try container.encodeIfPresent(port, forKey: .port)
        if exposeOnLocalNetwork {
            try container.encode(exposeOnLocalNetwork, forKey: .exposeOnLocalNetwork)
        }
    }
}

public struct ProjectDefinition: Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var workingDirectory: String
    public var command: String
    public var port: Int?
    public var exposeOnLocalNetwork: Bool
    public var services: [ProjectServiceDefinition]

    public init(
        id: UUID = UUID(),
        name: String,
        workingDirectory: String,
        command: String,
        port: Int? = nil,
        exposeOnLocalNetwork: Bool = false,
        services: [ProjectServiceDefinition] = []
    ) {
        self.id = id
        self.name = name
        self.workingDirectory = workingDirectory
        self.command = command
        self.port = port
        self.exposeOnLocalNetwork = exposeOnLocalNetwork
        self.services = services
    }

    public var effectiveServices: [ProjectServiceDefinition] {
        if services.isEmpty == false {
            return services
        }

        return [
            ProjectServiceDefinition(
                id: id,
                name: "default",
                command: command,
                port: port,
                exposeOnLocalNetwork: exposeOnLocalNetwork
            )
        ]
    }
}

extension ProjectDefinition: Codable {
    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case workingDirectory
        case command
        case port
        case exposeOnLocalNetwork
        case services
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let services = try container.decodeIfPresent([ProjectServiceDefinition].self, forKey: .services) ?? []
        let fallbackService = services.first

        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.workingDirectory = try container.decode(String.self, forKey: .workingDirectory)
        self.command = try container.decodeIfPresent(String.self, forKey: .command) ?? fallbackService?.command ?? ""
        self.port = try container.decodeIfPresent(Int.self, forKey: .port) ?? fallbackService?.port
        self.exposeOnLocalNetwork = try container.decodeIfPresent(Bool.self, forKey: .exposeOnLocalNetwork) ?? fallbackService?.exposeOnLocalNetwork ?? false
        self.services = services
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(workingDirectory, forKey: .workingDirectory)
        try container.encode(command, forKey: .command)
        try container.encodeIfPresent(port, forKey: .port)
        if exposeOnLocalNetwork {
            try container.encode(exposeOnLocalNetwork, forKey: .exposeOnLocalNetwork)
        }
        if services.isEmpty == false {
            try container.encode(services, forKey: .services)
        }
    }
}

public enum ProjectStatus: String, Codable, Sendable {
    case stopped
    case starting
    case running
    case stopping
    case failed
}

public struct ProjectRuntime: Equatable, Sendable {
    public var status: ProjectStatus = .stopped
    public var pid: Int32?
    public var detectedPort: Int?
    public var startedAt: Date?
    public var lastExitCode: Int32?
    public var log: String = ""

    public init() {}

    public var isRunning: Bool {
        status == .starting || status == .running || status == .stopping
    }

    public func effectivePort(preferredPort: Int?) -> Int? {
        detectedPort ?? preferredPort
    }
}

public struct PortListener: Equatable, Sendable {
    public var port: Int
    public var pids: [Int32]

    public init(port: Int, pids: [Int32]) {
        self.port = port
        self.pids = pids
    }

    public var isOccupied: Bool {
        !pids.isEmpty
    }
}
