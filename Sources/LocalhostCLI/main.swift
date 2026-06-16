import Foundation
import LocalhostCore

@main
struct LocalhostCLI {
    static func main() async {
        do {
            let invocation = try Invocation(arguments: Array(CommandLine.arguments.dropFirst()))
            if invocation.isLANInfo {
                try printLANInfo(isJSON: invocation.isJSON)
                return
            }
            if invocation.isRemoteHostCommand {
                try handleRemoteHostCommand(invocation)
                return
            }

            let request = try invocation.request()
            let response = try await invocation.send(request)

            if invocation.isJSON {
                try printJSON(response)
            } else {
                printHuman(response, for: request.action)
            }

            if response.ok == false {
                exit(1)
            }
        } catch let error as CLIRuntimeError {
            FileHandle.standardError.write(Data((error.message + "\n").utf8))
            exit(1)
        } catch let error as CLIError {
            FileHandle.standardError.write(Data((error.message + "\n").utf8))
            exit(2)
        } catch {
            let message = """
            jocalhostctl: \(error.localizedDescription)
            Is jocalhost.app running? Expected socket: \(ControlSocket.socketURL.path)
            """
            FileHandle.standardError.write(Data((message + "\n").utf8))
            exit(1)
        }
    }

    private static func printJSON<T: Encodable>(_ response: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(response)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    private static func printHuman(_ response: ControlResponse, for action: ControlAction) {
        if let message = response.message {
            print(message)
        }

        if action == .list || action == .status,
           let hostName = response.hostName {
            let url = response.lanStatusURL ?? response.hostAddress ?? "-"
            print("Host: \(hostName) \(url)")
        }

        switch action {
        case .list, .status, .start, .stop, .restart, .open:
            guard response.projects.isEmpty == false else {
                if action == .list || action == .status {
                    print("No projects configured.")
                }
                return
            }

            for project in response.projects {
                let url = project.networkURL ?? project.localURL ?? (project.port ?? project.detectedPort).map { ":\($0)" } ?? "-"
                let pid = project.pid.map(String.init) ?? "-"
                let occupied = project.portPids.isEmpty ? "" : " port-pids=\(project.portPids.map(String.init).joined(separator: ","))"
                print("\(project.status.rawValue.padding(toLength: 9, withPad: " ", startingAt: 0)) \(column(url, width: 26)) pid=\(pid.padding(toLength: 7, withPad: " ", startingAt: 0)) \(project.name)\(occupied)")
                if project.services.count > 1 {
                    for service in project.services {
                        let serviceURL = service.networkURL ?? service.localURL ?? (service.port ?? service.detectedPort).map { ":\($0)" } ?? "-"
                        let servicePid = service.pid.map(String.init) ?? "-"
                        print("  \(service.status.rawValue.padding(toLength: 9, withPad: " ", startingAt: 0)) \(column(serviceURL, width: 26)) pid=\(servicePid.padding(toLength: 7, withPad: " ", startingAt: 0)) \(service.name)")
                    }
                }
            }

        case .config:
            if let configPath = response.configPath {
                print(configPath)
            }

        case .ping, .reload, .quit:
            break
        }
    }

    private static func printLANInfo(isJSON: Bool) throws {
        let port = LANRemoteAccess.configuredPort()
        let address = LocalNetwork.preferredIPv4Address()
        let token = try LANRemoteAccess.ensureToken()
        let hostName = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
        let info = LANInfo(
            ok: true,
            hostName: hostName,
            hostAddress: address,
            port: port,
            lanStatusURL: LANRemoteAccess.statusURL(address: address, port: port),
            token: token,
            tokenPath: LANRemoteAccess.defaultTokenURL.path,
            setupCommand: LANRemoteAccess.remoteSetupCommand(
                hostName: hostName,
                hostAddress: address,
                port: port,
                token: token
            )
        )

        if isJSON {
            try printJSON(info)
            return
        }

        print("LAN status endpoint")
        print("Host: \(info.hostName)")
        print("URL: \(info.lanStatusURL ?? "-")")
        print("Token path: \(info.tokenPath)")
        print("")
        print("Remote setup command:")
        print(info.setupCommand)
    }

    private static func handleRemoteHostCommand(_ invocation: Invocation) throws {
        let result = try invocation.remoteHostCommandResult()

        if invocation.isJSON {
            try printJSON(result)
            return
        }

        if let message = result.message {
            print(message)
        }

        if result.hosts.isEmpty {
            print("No remote hosts configured.")
            print("Config: \(result.configPath)")
            return
        }

        for host in result.hosts {
            let enabled = host.isEnabled ? "enabled " : "disabled"
            print("\(enabled) \(column(host.displayAddress, width: 24)) \(host.name) \(host.id)")
        }
        print("Config: \(result.configPath)")
    }

    private static func column(_ value: String, width: Int) -> String {
        guard value.count < width else {
            return value
        }

        return value.padding(toLength: width, withPad: " ", startingAt: 0)
    }
}

private struct Invocation {
    var arguments: [String]
    var isJSON: Bool
    var service: String?
    var remote: RemoteEndpoint?
    var token: String?
    var port: Int?

    init(arguments: [String]) throws {
        var remaining = arguments
        self.isJSON = remaining.contains("--json")
        remaining.removeAll { $0 == "--json" }
        self.service = try Self.extractService(from: &remaining)
        self.remote = try Self.extractRemote(from: &remaining)
        self.token = try Self.extractValue(named: ["--token"], from: &remaining)
        self.port = try Self.extractPort(from: &remaining)

        if remaining.isEmpty || remaining.first == "help" || remaining.first == "--help" || remaining.first == "-h" {
            throw CLIError(message: Self.usage)
        }

        self.arguments = remaining
    }

    var isLANInfo: Bool {
        arguments.first == "lan-info"
    }

    var isRemoteHostCommand: Bool {
        switch arguments.first {
        case "remote-list", "remote-add", "remote-remove", "remote-enable", "remote-disable", "remotes":
            return true
        default:
            return false
        }
    }

    func remoteHostCommandResult() throws -> RemoteHostCommandResult {
        guard let command = arguments.first else {
            throw CLIError(message: Self.usage)
        }

        let store = RemoteHostConfigStore()
        var hosts = try store.load()
        let message: String?

        switch command {
        case "remote-list", "remotes":
            message = nil

        case "remote-add":
            guard arguments.count >= 3 else {
                throw CLIError(message: "Usage: jocalhostctl remote-add <name> <host[:port]> --token <token> [--port <port>]")
            }

            let token = try LANRemoteAccess.requestToken(explicitToken: token)
            let host = RemoteHostDefinition(
                name: arguments[1],
                host: arguments[2],
                port: port ?? LANRemoteAccess.defaultPort,
                token: token
            )
            do {
                _ = try LANRemoteAccess.endpointURL(host: host.host, port: host.port)
            } catch {
                throw CLIError(message: error.localizedDescription)
            }

            if let index = hosts.firstIndex(where: { $0.name == host.name }) {
                hosts[index] = RemoteHostDefinition(
                    id: hosts[index].id,
                    name: host.name,
                    host: host.host,
                    port: host.port,
                    token: host.token,
                    isEnabled: hosts[index].isEnabled
                )
            } else {
                hosts.append(host)
            }

            try store.save(hosts)
            notifyRunningAppToReload()
            message = "Saved remote host \(host.name)."

        case "remote-remove":
            let selector = try remoteHostSelector()
            guard let host = resolveRemoteHost(selector, in: hosts) else {
                throw CLIError(message: "Remote host not found: \(selector)")
            }
            hosts.removeAll { $0.id == host.id }
            try store.save(hosts)
            notifyRunningAppToReload()
            message = "Removed remote host \(host.name)."

        case "remote-enable", "remote-disable":
            let selector = try remoteHostSelector()
            guard let index = hosts.firstIndex(where: { host in
                host.id.uuidString == selector ||
                    host.name == selector ||
                    host.name.localizedCaseInsensitiveContains(selector)
            }) else {
                throw CLIError(message: "Remote host not found: \(selector)")
            }

            hosts[index].isEnabled = command == "remote-enable"
            try store.save(hosts)
            notifyRunningAppToReload()
            message = "\(hosts[index].isEnabled ? "Enabled" : "Disabled") remote host \(hosts[index].name)."

        default:
            throw CLIError(message: "Unknown remote host command: \(command)")
        }

        return RemoteHostCommandResult(
            ok: true,
            message: message,
            hosts: hosts.map(RemoteHostView.init(host:)),
            configPath: store.configURL.path
        )
    }

    func send(_ request: ControlRequest) async throws -> ControlResponse {
        guard let remote else {
            return try ControlClient.send(request)
        }

        let allowedRemoteActions: Set<ControlAction> = [.ping, .list, .status, .start, .stop, .restart]
        guard allowedRemoteActions.contains(request.action) else {
            throw CLIError(message: "LAN remote mode supports ping, list, status, start, stop, and restart.")
        }

        do {
            let token = try LANRemoteAccess.requestToken(explicitToken: token)
            if request.action == .ping || request.action == .list || request.action == .status {
                let path = request.action == .ping ? "/v1/ping" : "/v1/status"
                return try await LANStatusClient.fetchStatus(from: try remote.url(path: path), token: token)
            }

            return try await LANStatusClient.sendControl(
                request,
                to: try remote.url(path: "/v1/control"),
                token: token
            )
        } catch let error as CLIError {
            throw error
        } catch {
            throw CLIRuntimeError(message: "LAN remote: \(error.localizedDescription)")
        }
    }

    func request() throws -> ControlRequest {
        guard let command = arguments.first else {
            throw CLIError(message: Self.usage)
        }

        switch command {
        case "ping":
            return ControlRequest(action: .ping)

        case "reload":
            return ControlRequest(action: .reload)

        case "list":
            return ControlRequest(action: .list)

        case "status":
            return ControlRequest(action: .status)

        case "config":
            return ControlRequest(action: .config)

        case "quit":
            return ControlRequest(action: .quit)

        case "lan-info":
            throw CLIError(message: "lan-info does not create a control request")

        case "start":
            return ControlRequest(action: .start, project: try projectSelector(), service: service)

        case "stop":
            return ControlRequest(action: .stop, project: try projectSelector(), service: service)

        case "restart":
            return ControlRequest(action: .restart, project: try projectSelector(), service: service)

        case "open":
            return ControlRequest(action: .open, project: try projectSelector(), service: service)

        default:
            throw CLIError(message: "Unknown command: \(command)\n\n\(Self.usage)")
        }
    }

    private func projectSelector() throws -> String {
        let selector = arguments.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard selector.isEmpty == false else {
            throw CLIError(message: "Project name or id is required.\n\n\(Self.usage)")
        }

        return selector
    }

    private func remoteHostSelector() throws -> String {
        let selector = arguments.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard selector.isEmpty == false else {
            throw CLIError(message: "Remote host name or id is required.\n\n\(Self.usage)")
        }

        return selector
    }

    private static func extractService(from arguments: inout [String]) throws -> String? {
        try extractValue(named: ["--service", "-s"], from: &arguments, missingValueMessage: "Service name is required")
    }

    private static func extractRemote(from arguments: inout [String]) throws -> RemoteEndpoint? {
        guard let value = try extractValue(named: ["--remote"], from: &arguments, missingValueMessage: "Remote host is required") else {
            return nil
        }

        return try RemoteEndpoint(value)
    }

    private static func extractPort(from arguments: inout [String]) throws -> Int? {
        guard let value = try extractValue(named: ["--port"], from: &arguments, missingValueMessage: "Port is required") else {
            return nil
        }

        guard let port = Int(value), (1...65_535).contains(port) else {
            throw CLIError(message: "Port must be between 1 and 65535.")
        }

        return port
    }

    private static func extractValue(
        named names: Set<String>,
        from arguments: inout [String],
        missingValueMessage: String = "Value is required"
    ) throws -> String? {
        guard let index = arguments.firstIndex(where: { names.contains($0) }) else {
            return nil
        }

        let valueIndex = arguments.index(after: index)
        guard valueIndex < arguments.endIndex else {
            throw CLIError(message: "\(missingValueMessage) after \(arguments[index]).\n\n\(usage)")
        }

        let value = arguments[valueIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.isEmpty == false else {
            throw CLIError(message: "\(missingValueMessage) cannot be empty.\n\n\(usage)")
        }

        arguments.remove(at: valueIndex)
        arguments.remove(at: index)
        return value
    }

    private static let usage = """
    Usage:
      jocalhostctl ping [--json]
      jocalhostctl reload [--json]
      jocalhostctl list [--json]
      jocalhostctl status [--json]
      jocalhostctl start <project> [--service <service>] [--json]
      jocalhostctl stop <project> [--service <service>] [--json]
      jocalhostctl restart <project> [--service <service>] [--json]
      jocalhostctl open <project> [--service <service>] [--json]
      jocalhostctl config [--json]
      jocalhostctl quit [--json]
      jocalhostctl lan-info [--json]
      jocalhostctl --remote <host[:port]> --token <token> ping|list|status|start|stop|restart [--json]
      jocalhostctl remote-list [--json]
      jocalhostctl remote-add <name> <host[:port]> --token <token> [--port <port>] [--json]
      jocalhostctl remote-remove <name-or-id> [--json]
      jocalhostctl remote-enable <name-or-id> [--json]
      jocalhostctl remote-disable <name-or-id> [--json]
    """
}

private func notifyRunningAppToReload() {
    _ = try? ControlClient.send(ControlRequest(action: .reload))
}

private func resolveRemoteHost(_ selector: String, in hosts: [RemoteHostDefinition]) -> RemoteHostDefinition? {
    if let id = UUID(uuidString: selector),
       let host = hosts.first(where: { $0.id == id }) {
        return host
    }

    if let exact = hosts.first(where: { $0.name == selector }) {
        return exact
    }

    return hosts.first {
        $0.name.localizedCaseInsensitiveContains(selector)
    }
}

private struct RemoteEndpoint {
    var rawValue: String

    init(_ rawValue: String) throws {
        self.rawValue = rawValue
        do {
            _ = try url(path: "/v1/status")
        } catch {
            throw CLIError(message: error.localizedDescription)
        }
    }

    func url(path: String) throws -> URL {
        try LANRemoteAccess.endpointURL(host: rawValue, port: LANRemoteAccess.defaultPort, path: path)
    }
}

private struct LANInfo: Encodable {
    var ok: Bool
    var hostName: String
    var hostAddress: String?
    var port: Int
    var lanStatusURL: String?
    var token: String
    var tokenPath: String
    var setupCommand: String
}

private struct RemoteHostCommandResult: Encodable {
    var ok: Bool
    var message: String?
    var hosts: [RemoteHostView]
    var configPath: String
}

private struct RemoteHostView: Encodable {
    var id: UUID
    var name: String
    var host: String
    var port: Int
    var displayAddress: String
    var isEnabled: Bool

    init(host: RemoteHostDefinition) {
        self.id = host.id
        self.name = host.name
        self.host = host.host
        self.port = host.port
        self.displayAddress = host.displayAddress
        self.isEnabled = host.isEnabled
    }
}

private struct CLIError: Error {
    var message: String
}

private struct CLIRuntimeError: Error {
    var message: String
}
