import Foundation

public struct RemoteHostDefinition: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var host: String
    public var port: Int
    public var token: String
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        host: String,
        port: Int = LANRemoteAccess.defaultPort,
        token: String,
        isEnabled: Bool = true
    ) {
        let normalized = Self.normalized(host: host, fallbackPort: port)
        self.id = id
        self.name = name
        self.host = normalized.host
        self.port = normalized.port
        self.token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        self.isEnabled = isEnabled
    }

    public var statusURL: URL? {
        try? LANRemoteAccess.endpointURL(host: host, port: port, path: "/v1/status")
    }

    public var pingURL: URL? {
        try? LANRemoteAccess.endpointURL(host: host, port: port, path: "/v1/ping")
    }

    public var controlURL: URL? {
        try? LANRemoteAccess.endpointURL(host: host, port: port, path: "/v1/control")
    }

    public var displayAddress: String {
        "\(host):\(port)"
    }

    private static func normalized(host rawHost: String, fallbackPort: Int) -> (host: String, port: Int) {
        let trimmedHost = rawHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmedHost.contains("://") ? trimmedHost : "http://\(trimmedHost)"

        if let components = URLComponents(string: normalized),
           let host = components.host,
           host.isEmpty == false {
            return (host, components.port ?? fallbackPort)
        }

        return (trimmedHost, fallbackPort)
    }
}
