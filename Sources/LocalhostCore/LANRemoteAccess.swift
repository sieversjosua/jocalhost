import Foundation
import Security

public enum LANRemoteAccess {
    public static let defaultPort = 48_231
    public static let portEnvironmentKey = "JOCALHOST_LAN_PORT"
    public static let tokenEnvironmentKey = "JOCALHOST_LAN_TOKEN"

    public static var defaultTokenURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("jocalhost", isDirectory: true)
            .appendingPathComponent("lan-token")
    }

    public static func configuredPort(environment: [String: String] = ProcessInfo.processInfo.environment) -> Int {
        guard let value = environment[portEnvironmentKey],
              let port = Int(value),
              (1...65_535).contains(port) else {
            return defaultPort
        }

        return port
    }

    public static func statusURL(address: String?, port: Int) -> String? {
        address.map { "http://\($0):\(port)/v1/status" }
    }

    public static func endpointURL(host: String, port: Int = defaultPort, path: String = "/v1/status") throws -> URL {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedHost.isEmpty == false else {
            throw LANRemoteAccessError.invalidHost(host)
        }

        let normalized = trimmedHost.contains("://") ? trimmedHost : "http://\(trimmedHost)"
        guard var components = URLComponents(string: normalized),
              components.host?.isEmpty == false else {
            throw LANRemoteAccessError.invalidHost(host)
        }

        if components.scheme == nil {
            components.scheme = "http"
        }
        if components.port == nil {
            components.port = port
        }
        components.path = path
        components.query = nil
        components.fragment = nil

        guard let url = components.url else {
            throw LANRemoteAccessError.invalidHost(host)
        }

        return url
    }

    public static func ensureToken(at tokenURL: URL = defaultTokenURL) throws -> String {
        let directoryURL = tokenURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directoryURL.path
        )

        if FileManager.default.fileExists(atPath: tokenURL.path) {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: tokenURL.path
            )
            let token = try String(contentsOf: tokenURL, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard token.isEmpty == false else {
                throw LANRemoteAccessError.emptyToken(path: tokenURL.path)
            }
            return token
        }

        let token = try generateToken()
        try token.write(to: tokenURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: tokenURL.path
        )
        return token
    }

    public static func requestToken(
        explicitToken: String?,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> String {
        if let explicitToken = explicitToken?.trimmingCharacters(in: .whitespacesAndNewlines),
           explicitToken.isEmpty == false {
            return explicitToken
        }

        if let environmentToken = environment[tokenEnvironmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
           environmentToken.isEmpty == false {
            return environmentToken
        }

        throw LANRemoteAccessError.missingToken
    }

    private static func generateToken() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let byteCount = bytes.count
        let result = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, byteCount, buffer.baseAddress!)
        }

        guard result == errSecSuccess else {
            throw LANRemoteAccessError.randomGenerationFailed
        }

        return Data(bytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

public enum LANStatusClient {
    public static func fetchStatus(from url: URL, token: String) async throws -> ControlResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 5
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LANRemoteAccessError.invalidHTTPResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw LANRemoteAccessError.httpStatus(httpResponse.statusCode, body)
        }

        return try JSONDecoder().decode(ControlResponse.self, from: data)
    }

    public static func sendControl(_ controlRequest: ControlRequest, to url: URL, token: String) async throws -> ControlResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(controlRequest)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LANRemoteAccessError.invalidHTTPResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw LANRemoteAccessError.httpStatus(httpResponse.statusCode, body)
        }

        return try JSONDecoder().decode(ControlResponse.self, from: data)
    }
}

public enum LANRemoteAccessError: LocalizedError, Equatable, Sendable {
    case emptyToken(path: String)
    case missingToken
    case randomGenerationFailed
    case invalidHost(String)
    case invalidHTTPResponse
    case httpStatus(Int, String)

    public var errorDescription: String? {
        switch self {
        case let .emptyToken(path):
            return "LAN token at \(path) is empty"
        case .missingToken:
            return "LAN remote token is required. Pass --token or set JOCALHOST_LAN_TOKEN."
        case .randomGenerationFailed:
            return "Secure random token generation failed"
        case let .invalidHost(host):
            return "Invalid LAN remote host: \(host)"
        case .invalidHTTPResponse:
            return "LAN remote did not return a valid HTTP response"
        case let .httpStatus(status, body):
            if body.isEmpty {
                return "LAN remote returned HTTP \(status)"
            }
            return "LAN remote returned HTTP \(status): \(body)"
        }
    }
}
