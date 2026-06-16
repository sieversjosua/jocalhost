import Darwin
import Foundation

public enum ControlAction: String, Codable, Sendable {
    case ping
    case reload
    case list
    case status
    case start
    case stop
    case restart
    case open
    case config
    case quit
}

public struct ControlRequest: Codable, Sendable {
    public var action: ControlAction
    public var project: String?
    public var service: String?

    public init(action: ControlAction, project: String? = nil, service: String? = nil) {
        self.action = action
        self.project = project
        self.service = service
    }
}

public struct ControlServiceSnapshot: Codable, Sendable {
    public var id: UUID
    public var name: String
    public var command: String
    public var port: Int?
    public var detectedPort: Int?
    public var exposeOnLocalNetwork: Bool?
    public var localURL: String?
    public var networkURL: String?
    public var status: ProjectStatus
    public var pid: Int32?
    public var startedAt: Date?
    public var lastExitCode: Int32?
    public var recentLog: String?
    public var portPids: [Int32]

    public init(
        id: UUID,
        name: String,
        command: String,
        port: Int?,
        detectedPort: Int? = nil,
        exposeOnLocalNetwork: Bool? = nil,
        localURL: String? = nil,
        networkURL: String? = nil,
        status: ProjectStatus,
        pid: Int32?,
        startedAt: Date?,
        lastExitCode: Int32?,
        recentLog: String? = nil,
        portPids: [Int32]
    ) {
        self.id = id
        self.name = name
        self.command = command
        self.port = port
        self.detectedPort = detectedPort
        self.exposeOnLocalNetwork = exposeOnLocalNetwork
        self.localURL = localURL
        self.networkURL = networkURL
        self.status = status
        self.pid = pid
        self.startedAt = startedAt
        self.lastExitCode = lastExitCode
        self.recentLog = recentLog
        self.portPids = portPids
    }
}

public struct ControlProjectSnapshot: Codable, Sendable {
    public var id: UUID
    public var name: String
    public var workingDirectory: String
    public var command: String
    public var port: Int?
    public var detectedPort: Int?
    public var exposeOnLocalNetwork: Bool?
    public var localURL: String?
    public var networkURL: String?
    public var status: ProjectStatus
    public var pid: Int32?
    public var startedAt: Date?
    public var lastExitCode: Int32?
    public var recentLog: String?
    public var portPids: [Int32]
    public var services: [ControlServiceSnapshot]

    public init(
        id: UUID,
        name: String,
        workingDirectory: String,
        command: String,
        port: Int?,
        detectedPort: Int? = nil,
        exposeOnLocalNetwork: Bool? = nil,
        localURL: String? = nil,
        networkURL: String? = nil,
        status: ProjectStatus,
        pid: Int32?,
        startedAt: Date?,
        lastExitCode: Int32?,
        recentLog: String? = nil,
        portPids: [Int32],
        services: [ControlServiceSnapshot] = []
    ) {
        self.id = id
        self.name = name
        self.workingDirectory = workingDirectory
        self.command = command
        self.port = port
        self.detectedPort = detectedPort
        self.exposeOnLocalNetwork = exposeOnLocalNetwork
        self.localURL = localURL
        self.networkURL = networkURL
        self.status = status
        self.pid = pid
        self.startedAt = startedAt
        self.lastExitCode = lastExitCode
        self.recentLog = recentLog
        self.portPids = portPids
        self.services = services
    }
}

public struct ControlResponse: Codable, Sendable {
    public var ok: Bool
    public var message: String?
    public var projects: [ControlProjectSnapshot]
    public var configPath: String?
    public var hostName: String?
    public var hostAddress: String?
    public var lanStatusURL: String?

    public init(
        ok: Bool,
        message: String? = nil,
        projects: [ControlProjectSnapshot] = [],
        configPath: String? = nil,
        hostName: String? = nil,
        hostAddress: String? = nil,
        lanStatusURL: String? = nil
    ) {
        self.ok = ok
        self.message = message
        self.projects = projects
        self.configPath = configPath
        self.hostName = hostName
        self.hostAddress = hostAddress
        self.lanStatusURL = lanStatusURL
    }
}

public enum ControlSocket {
    public static var socketURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local", isDirectory: true)
            .appendingPathComponent("share", isDirectory: true)
            .appendingPathComponent("jocalhost", isDirectory: true)
            .appendingPathComponent("control.sock")
    }

    public static func ensureDirectoryExists() throws {
        let directoryURL = socketURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directoryURL.path
        )
    }
}

public enum ControlClient {
    public static func send(_ request: ControlRequest) throws -> ControlResponse {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }

        defer {
            close(fd)
        }

        try withUnixSocketAddress(path: ControlSocket.socketURL.path) { address, length in
            let result = Darwin.connect(fd, address, length)
            guard result == 0 else {
                throw POSIXError(.init(rawValue: errno) ?? .ECONNREFUSED)
            }
        }

        let encoder = JSONEncoder()
        let requestData = try encoder.encode(request) + Data([0x0A])
        try writeAll(requestData, to: fd)

        let responseData = try readLine(from: fd, maxBytes: 1024 * 1024)
        return try JSONDecoder().decode(ControlResponse.self, from: responseData)
    }
}

public func withUnixSocketAddress<T>(
    path: String,
    _ body: (UnsafePointer<sockaddr>, socklen_t) throws -> T
) throws -> T {
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)

    let maxPathLength = MemoryLayout.size(ofValue: address.sun_path)
    let copied = path.withCString { source in
        withUnsafeMutablePointer(to: &address.sun_path) { destination in
            destination.withMemoryRebound(to: CChar.self, capacity: maxPathLength) { buffer in
                strlcpy(buffer, source, maxPathLength)
            }
        }
    }

    guard copied < maxPathLength else {
        throw POSIXError(.ENAMETOOLONG)
    }

    return try withUnsafePointer(to: &address) { pointer in
        try pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
            try body(socketAddress, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
}

public func writeAll(_ data: Data, to fd: Int32) throws {
    try data.withUnsafeBytes { rawBuffer in
        guard let baseAddress = rawBuffer.baseAddress else {
            return
        }

        var offset = 0
        while offset < rawBuffer.count {
            let written = Darwin.write(fd, baseAddress.advanced(by: offset), rawBuffer.count - offset)
            if written < 0 {
                if errno == EINTR {
                    continue
                }
                throw POSIXError(.init(rawValue: errno) ?? .EIO)
            }
            offset += written
        }
    }
}

public func readLine(from fd: Int32, maxBytes: Int) throws -> Data {
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)

    while data.count < maxBytes {
        let count = Darwin.read(fd, &buffer, buffer.count)

        if count == 0 {
            break
        }

        if count < 0 {
            if errno == EINTR {
                continue
            }
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }

        if let newlineIndex = buffer[..<count].firstIndex(of: 0x0A) {
            data.append(contentsOf: buffer[..<newlineIndex])
            return data
        }

        data.append(contentsOf: buffer[..<count])
    }

    return data
}
