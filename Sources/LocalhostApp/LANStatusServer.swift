import Darwin
import Dispatch
import Foundation
import LocalhostCore

final class LANStatusServer: @unchecked Sendable {
    private weak var store: ProjectStore?
    private let token: String
    let port: Int

    private var socketFD: Int32 = -1
    private var source: DispatchSourceRead?
    private let queue = DispatchQueue(label: "de.josuasievers.jocalhost.lan-status")
    private let requestTimeoutMilliseconds: Int32 = 5_000

    init(store: ProjectStore, token: String, port: Int) {
        self.store = store
        self.token = token
        self.port = port
    }

    var statusURL: String? {
        LANRemoteAccess.statusURL(address: LocalNetwork.preferredIPv4Address(), port: port)
    }

    func start() throws {
        guard socketFD == -1 else {
            return
        }

        signal(SIGPIPE, SIG_IGN)

        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }

        do {
            var reuse: Int32 = 1
            guard setsockopt(
                fd,
                SOL_SOCKET,
                SO_REUSEADDR,
                &reuse,
                socklen_t(MemoryLayout.size(ofValue: reuse))
            ) == 0 else {
                throw POSIXError(.init(rawValue: errno) ?? .EIO)
            }

            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = in_port_t(port).bigEndian
            address.sin_addr = in_addr(s_addr: in_addr_t(INADDR_ANY))

            try withUnsafePointer(to: &address) { pointer in
                try pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                    guard Darwin.bind(fd, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0 else {
                        throw POSIXError(.init(rawValue: errno) ?? .EADDRINUSE)
                    }
                }
            }

            guard listen(fd, 16) == 0 else {
                throw POSIXError(.init(rawValue: errno) ?? .EIO)
            }

            setNonBlocking(fd)

            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            source.setEventHandler { [weak self] in
                self?.acceptAvailableConnections()
            }
            source.setCancelHandler {
                close(fd)
            }

            socketFD = fd
            self.source = source
            source.resume()
        } catch {
            close(fd)
            throw error
        }
    }

    func stop() {
        source?.cancel()
        source = nil
        socketFD = -1
    }

    private func acceptAvailableConnections() {
        while socketFD >= 0 {
            let clientFD = accept(socketFD, nil, nil)

            if clientFD < 0 {
                if errno == EAGAIN || errno == EWOULDBLOCK {
                    return
                }
                return
            }

            handle(clientFD: clientFD)
        }
    }

    private func handle(clientFD: Int32) {
        setBlocking(clientFD)

        do {
            let requestData = try readRequestWithTimeout(
                from: clientFD,
                maxBytes: 64 * 1024,
                timeoutMilliseconds: requestTimeoutMilliseconds
            )
            let request = try HTTPRequest(data: requestData)

            guard isAuthorized(request) else {
                try writeJSON(
                    ControlResponse(ok: false, message: "unauthorized"),
                    status: 401,
                    to: clientFD
                )
                close(clientFD)
                return
            }

            switch (request.method, request.path) {
            case ("GET", "/v1/ping"):
                try writeJSON(
                    ControlResponse(
                        ok: true,
                        message: "pong",
                        hostName: hostName(),
                        hostAddress: LocalNetwork.preferredIPv4Address(),
                        lanStatusURL: statusURL
                    ),
                    status: 200,
                    to: clientFD
                )
                close(clientFD)

            case ("GET", "/v1/status"):
                Task { @MainActor [weak self] in
                    let response = self?.store?.lanStatusResponse() ??
                        ControlResponse(ok: false, message: "app store unavailable")
                    self?.writeAndClose(response, status: response.ok ? 200 : 503, to: clientFD)
                }

            case ("POST", "/v1/control"):
                let controlRequest = try JSONDecoder().decode(ControlRequest.self, from: request.body)
                if controlRequest.action == .start || controlRequest.action == .stop || controlRequest.action == .restart {
                    Task { @MainActor [weak self] in
                        _ = self?.store?.handleControl(controlRequest)
                    }
                    try writeJSON(
                        ControlResponse(ok: true, message: "accepted"),
                        status: 202,
                        to: clientFD
                    )
                    close(clientFD)
                    return
                }

                Task { @MainActor [weak self] in
                    let response = self?.store?.handleControl(controlRequest) ??
                        ControlResponse(ok: false, message: "app store unavailable")
                    self?.writeAndClose(response, status: response.ok ? 200 : 400, to: clientFD)
                }

            default:
                try writeJSON(
                    ControlResponse(ok: false, message: request.method == "GET" ? "not found" : "method not allowed"),
                    status: request.method == "GET" ? 404 : 405,
                    to: clientFD
                )
                close(clientFD)
            }
        } catch {
            let response = ControlResponse(ok: false, message: error.localizedDescription)
            try? writeJSON(response, status: 400, to: clientFD)
            close(clientFD)
        }
    }

    private func isAuthorized(_ request: HTTPRequest) -> Bool {
        request.headers["authorization"] == "Bearer \(token)"
    }

    private func writeAndClose(_ response: ControlResponse, status: Int, to fd: Int32) {
        try? writeJSON(response, status: status, to: fd)
        close(fd)
    }

    private func writeJSON(_ response: ControlResponse, status: Int, to fd: Int32) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let body = try encoder.encode(response)
        let header = "HTTP/1.1 \(status) \(reasonPhrase(for: status))\r\n" +
            "Content-Type: application/json\r\n" +
            "Content-Length: \(body.count)\r\n" +
            "Cache-Control: no-store\r\n" +
            "Connection: close\r\n" +
            "\r\n"
        try writeAll(Data(header.utf8) + body, to: fd)
    }

    private func reasonPhrase(for status: Int) -> String {
        switch status {
        case 200:
            return "OK"
        case 400:
            return "Bad Request"
        case 401:
            return "Unauthorized"
        case 404:
            return "Not Found"
        case 405:
            return "Method Not Allowed"
        case 503:
            return "Service Unavailable"
        default:
            return "HTTP"
        }
    }

    private func hostName() -> String {
        Host.current().localizedName ?? ProcessInfo.processInfo.hostName
    }

    private func setNonBlocking(_ fd: Int32) {
        let flags = fcntl(fd, F_GETFL, 0)
        guard flags >= 0 else {
            return
        }

        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
    }

    private func setBlocking(_ fd: Int32) {
        let flags = fcntl(fd, F_GETFL, 0)
        guard flags >= 0 else {
            return
        }

        _ = fcntl(fd, F_SETFL, flags & ~O_NONBLOCK)
    }

    private func readRequestWithTimeout(
        from fd: Int32,
        maxBytes: Int,
        timeoutMilliseconds: Int32
    ) throws -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)

        while data.count < maxBytes {
            var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let pollResult = poll(&descriptor, 1, timeoutMilliseconds)

            if pollResult == 0 {
                throw LANStatusServerError.requestTimedOut
            }

            if pollResult < 0 {
                if errno == EINTR {
                    continue
                }
                throw POSIXError(.init(rawValue: errno) ?? .EIO)
            }

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

            data.append(contentsOf: buffer[..<count])
            if let headerEnd = data.range(of: Data([13, 10, 13, 10]))?.upperBound ??
                data.range(of: Data([10, 10]))?.upperBound,
               data.count >= headerEnd + contentLength(in: data[..<headerEnd]) {
                return data
            }
        }

        if data.count >= maxBytes {
            throw LANStatusServerError.requestTooLarge
        }

        return data
    }

    private func contentLength(in headerData: Data) -> Int {
        let text = String(decoding: headerData, as: UTF8.self)
        for line in text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2,
                  parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "content-length" else {
                continue
            }

            return Int(parts[1].trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        }

        return 0
    }
}

private struct HTTPRequest {
    var method: String
    var path: String
    var headers: [String: String]
    var body: Data

    init(data: Data) throws {
        guard let headerRange = data.range(of: Data([13, 10, 13, 10])) ??
            data.range(of: Data([10, 10])) else {
            throw LANStatusServerError.invalidRequest
        }

        let headerData = data[..<headerRange.lowerBound]
        body = data[headerRange.upperBound...]
        let text = String(decoding: headerData, as: UTF8.self)
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        guard let requestLine = lines.first else {
            throw LANStatusServerError.invalidRequest
        }

        let requestParts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard requestParts.count >= 2 else {
            throw LANStatusServerError.invalidRequest
        }

        method = requestParts[0]
        path = requestParts[1].split(separator: "?", maxSplits: 1).first.map(String.init) ?? requestParts[1]
        headers = [:]

        for line in lines.dropFirst() {
            guard line.isEmpty == false,
                  let separator = line.firstIndex(of: ":") else {
                continue
            }

            let key = String(line[..<separator])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let value = String(line[line.index(after: separator)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            headers[key] = value
        }
    }
}

private enum LANStatusServerError: LocalizedError {
    case invalidRequest
    case requestTimedOut
    case requestTooLarge

    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            return "Invalid HTTP request"
        case .requestTimedOut:
            return "LAN status request timed out before headers were received"
        case .requestTooLarge:
            return "LAN status request exceeded the maximum allowed size"
        }
    }
}
