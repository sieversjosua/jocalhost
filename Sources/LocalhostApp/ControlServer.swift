import Darwin
import Dispatch
import Foundation
import LocalhostCore

final class ControlServer: @unchecked Sendable {
    private weak var store: ProjectStore?
    private var socketFD: Int32 = -1
    private var source: DispatchSourceRead?
    private let queue = DispatchQueue(label: "de.josuasievers.jocalhost.control")
    private let requestTimeoutMilliseconds: Int32 = 5_000

    init(store: ProjectStore) {
        self.store = store
    }

    func start() {
        guard socketFD == -1 else {
            return
        }

        do {
            signal(SIGPIPE, SIG_IGN)
            try ControlSocket.ensureDirectoryExists()
            try? FileManager.default.removeItem(at: ControlSocket.socketURL)

            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0 else {
                throw POSIXError(.init(rawValue: errno) ?? .EIO)
            }

            try withUnixSocketAddress(path: ControlSocket.socketURL.path) { address, length in
                guard Darwin.bind(fd, address, length) == 0 else {
                    throw POSIXError(.init(rawValue: errno) ?? .EADDRINUSE)
                }
            }
            chmod(ControlSocket.socketURL.path, S_IRUSR | S_IWUSR)

            guard listen(fd, 16) == 0 else {
                throw POSIXError(.init(rawValue: errno) ?? .EIO)
            }

            fd.setNonBlocking()

            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            source.setEventHandler { [weak self] in
                self?.acceptAvailableConnections()
            }
            source.setCancelHandler {
                close(fd)
                try? FileManager.default.removeItem(at: ControlSocket.socketURL)
            }

            socketFD = fd
            self.source = source
            source.resume()
        } catch {
            Task { @MainActor [weak self] in
                self?.store?.errorMessage = "Control socket could not start: \(error.localizedDescription)"
            }
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

                let message = "Control socket accept failed: \(String(cString: strerror(errno)))"
                Task { @MainActor [weak self] in
                    self?.store?.errorMessage = message
                }
                return
            }

            handle(clientFD: clientFD)
        }
    }

    private func handle(clientFD: Int32) {
        clientFD.setBlocking()

        do {
            let requestData = try readLineWithTimeout(
                from: clientFD,
                maxBytes: 64 * 1024,
                timeoutMilliseconds: requestTimeoutMilliseconds
            )
            let request = try JSONDecoder().decode(ControlRequest.self, from: requestData)
            Task { @MainActor [weak self] in
                let response = self?.store?.handleControl(request) ?? ControlResponse(ok: false, message: "app store unavailable")
                self?.writeAndClose(response, to: clientFD)
            }
        } catch {
            let response = ControlResponse(ok: false, message: error.localizedDescription)
            try? write(response, to: clientFD)
            close(clientFD)
        }
    }

    private func write(_ response: ControlResponse, to fd: Int32) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(response) + Data([0x0A])
        try writeAll(data, to: fd)
    }

    private func writeAndClose(_ response: ControlResponse, to fd: Int32) {
        try? write(response, to: fd)

        close(fd)
    }

    private func readLineWithTimeout(
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
                throw ControlServerError.requestTimedOut
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

            if let newlineIndex = buffer[..<count].firstIndex(of: 0x0A) {
                data.append(contentsOf: buffer[..<newlineIndex])
                return data
            }

            data.append(contentsOf: buffer[..<count])
        }

        if data.count >= maxBytes {
            throw ControlServerError.requestTooLarge
        }

        return data
    }
}

private enum ControlServerError: LocalizedError {
    case requestTimedOut
    case requestTooLarge

    var errorDescription: String? {
        switch self {
        case .requestTimedOut:
            "Control request timed out before a full line was received"
        case .requestTooLarge:
            "Control request exceeded the maximum allowed size"
        }
    }
}
