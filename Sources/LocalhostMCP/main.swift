import Foundation
import LocalhostCore

@main
struct LocalhostMCP {
    static func main() {
        signal(SIGPIPE, SIG_IGN)
        let server = MCPServer()
        server.run()
    }
}

private final class MCPServer {
    private let encoder = JSONEncoder()
    private let projectConfigStore = ProjectConfigStore()
    private let remoteHostStore = RemoteHostConfigStore()
    private let protocolVersion = "2025-06-18"
    private let serverName = "jocalhost"
    private let serverVersion = "0.1.0"

    init() {
        encoder.outputFormatting = [.sortedKeys]
    }

    func run() {
        while let line = readLine(strippingNewline: true) {
            guard line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                continue
            }

            do {
                let data = Data(line.utf8)
                let object = try JSONSerialization.jsonObject(with: data)

                if let message = object as? [String: Any] {
                    if let response = handle(message) {
                        write(response)
                    }
                } else {
                    write(errorResponse(id: nil, code: -32600, message: "Invalid Request"))
                }
            } catch {
                write(errorResponse(id: nil, code: -32700, message: "Parse error"))
            }
        }
    }

    private func handle(_ message: [String: Any]) -> [String: Any]? {
        let id = message["id"]
        guard let method = message["method"] as? String else {
            if id == nil {
                return nil
            }
            return errorResponse(id: id, code: -32600, message: "Invalid Request")
        }

        do {
            switch method {
            case "initialize":
                return response(id: id, result: initializeResult(from: message))

            case "notifications/initialized", "notifications/cancelled":
                return nil

            case "ping":
                return response(id: id, result: [:])

            case "tools/list":
                return response(id: id, result: ["tools": tools()])

            case "tools/call":
                return response(id: id, result: try callTool(from: message))

            default:
                if id == nil {
                    return nil
                }
                return errorResponse(id: id, code: -32601, message: "Method not found: \(method)")
            }
        } catch let error as MCPError {
            return errorResponse(id: id, code: error.code, message: error.message)
        } catch {
            return response(
                id: id,
                result: toolResult(
                    text: error.localizedDescription,
                    structuredContent: ["ok": false, "message": error.localizedDescription],
                    isError: true
                )
            )
        }
    }

    private func initializeResult(from message: [String: Any]) -> [String: Any] {
        let params = message["params"] as? [String: Any]
        let requestedProtocol = params?["protocolVersion"] as? String

        return [
            "protocolVersion": requestedProtocol ?? protocolVersion,
            "capabilities": [
                "tools": [
                    "listChanged": false
                ]
            ],
            "serverInfo": [
                "name": serverName,
                "title": "jocalhost",
                "version": serverVersion
            ],
            "instructions": "Use these tools to inspect and control projects registered in the jocalhost menu bar app or saved remote hosts. Prefer start_project/restart_project over running npm run dev, bun dev, pnpm dev, yarn dev, or framework dev servers directly. Present networkURL to users; do not present localhost URLs to remote-device users. The menu bar app must be running on the host Mac."
        ]
    }

    private func tools() -> [[String: Any]] {
        [
            tool(
                name: "get_status",
                title: "Get Status",
                description: "Get runtime status and URLs for all projects, or one project when a selector is provided.",
                properties: [
                    "project": [
                        "type": "string",
                        "description": "Optional project name, partial name, or UUID."
                    ]
                ],
                required: [],
                annotations: ["readOnlyHint": true]
            ),
            tool(
                name: "reload_projects",
                title: "Reload Projects",
                description: "Ask the running jocalhost app to reload its project config from disk.",
                properties: [:],
                required: [],
                annotations: ["readOnlyHint": false]
            ),
            tool(
                name: "add_project",
                title: "Add Project",
                description: "Register a local workspace as a jocalhost project. Detects name, dev command, and port from package.json when omitted.",
                properties: [
                    "workingDirectory": [
                        "type": "string",
                        "description": "Absolute path to the project directory."
                    ],
                    "name": [
                        "type": "string",
                        "description": "Optional project name. Defaults to package.json name or folder name."
                    ],
                    "command": [
                        "type": "string",
                        "description": "Optional dev command. Defaults to detected dev/start/serve/preview script."
                    ],
                    "port": [
                        "type": "integer",
                        "description": "Optional dev server port."
                    ],
                    "exposeOnLocalNetwork": [
                        "type": "boolean",
                        "description": "Whether jocalhost should expose networkURL. Defaults to true."
                    ]
                ],
                required: ["workingDirectory"],
                annotations: ["readOnlyHint": false, "destructiveHint": false]
            ),
            tool(
                name: "start_project",
                title: "Start Project",
                description: "Start a registered project through the jocalhost app.",
                properties: projectSelectorProperties(),
                required: ["project"],
                annotations: ["readOnlyHint": false, "destructiveHint": false]
            ),
            tool(
                name: "stop_project",
                title: "Stop Project",
                description: "Stop a running project through the jocalhost app.",
                properties: projectSelectorProperties(),
                required: ["project"],
                annotations: ["readOnlyHint": false, "destructiveHint": true]
            ),
            tool(
                name: "restart_project",
                title: "Restart Project",
                description: "Restart a registered project through the jocalhost app.",
                properties: projectSelectorProperties(),
                required: ["project"],
                annotations: ["readOnlyHint": false, "destructiveHint": true]
            ),
            tool(
                name: "open_project",
                title: "Open Project URL",
                description: "Open the configured project URL on the Codex host.",
                properties: projectSelectorProperties(),
                required: ["project"],
                annotations: ["readOnlyHint": false, "openWorldHint": true]
            ),
            tool(
                name: "get_config_path",
                title: "Get Config Path",
                description: "Return the jocalhost app project config file path.",
                properties: [:],
                required: [],
                annotations: ["readOnlyHint": true]
            )
        ]
    }

    private func tool(
        name: String,
        title: String,
        description: String,
        properties: [String: Any],
        required: [String],
        annotations: [String: Any]
    ) -> [String: Any] {
        [
            "name": name,
            "title": title,
            "description": description,
            "inputSchema": [
                "type": "object",
                "properties": properties,
                "required": required,
                "additionalProperties": false
            ],
            "annotations": annotations
        ]
    }

    private func projectSelectorProperties() -> [String: Any] {
        [
            "project": [
                "type": "string",
                "description": "Project name, partial name, or UUID."
            ],
            "service": [
                "type": "string",
                "description": "Optional service name, partial name, or UUID within the project."
            ]
        ]
    }

    private func callTool(from message: [String: Any]) throws -> [String: Any] {
        guard let params = message["params"] as? [String: Any],
              let name = params["name"] as? String else {
            throw MCPError(code: -32602, message: "Missing tool name")
        }

        let arguments = params["arguments"] as? [String: Any] ?? [:]
        let project = arguments["project"] as? String
        let service = arguments["service"] as? String

        switch name {
        case "get_status":
            return toolResult(from: filter(try statusResponse(), project: project))

        case "reload_projects":
            return try invoke(.reload)

        case "add_project":
            return try addProject(arguments)

        case "start_project":
            return try controlProject(.start, project: try requiredProject(project), service: service)

        case "stop_project":
            return try controlProject(.stop, project: try requiredProject(project), service: service)

        case "restart_project":
            return try controlProject(.restart, project: try requiredProject(project), service: service)

        case "open_project":
            return try openProject(try requiredProject(project), service: service)

        case "get_config_path":
            return try invoke(.config)

        default:
            throw MCPError(code: -32602, message: "Unknown tool: \(name)")
        }
    }

    private func requiredProject(_ project: String?) throws -> String {
        guard let project = project?.trimmingCharacters(in: .whitespacesAndNewlines),
              project.isEmpty == false else {
            throw MCPError(code: -32602, message: "Missing required argument: project")
        }

        return project
    }

    private func addProject(_ arguments: [String: Any]) throws -> [String: Any] {
        guard let workingDirectory = arguments["workingDirectory"] as? String,
              workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw MCPError(code: -32602, message: "Missing required argument: workingDirectory")
        }

        let result = try projectConfigStore.registerProject(
            workingDirectory: workingDirectory,
            name: arguments["name"] as? String,
            command: arguments["command"] as? String,
            port: arguments["port"] as? Int,
            exposeOnLocalNetwork: (arguments["exposeOnLocalNetwork"] as? Bool) ?? true
        )
        _ = try? ControlClient.send(ControlRequest(action: .reload))

        let project = (try? sanitizedJSON(result.project)) as? [String: Any] ?? [:]
        let message = result.created ? "Added jocalhost project \(result.project.name)." : "Jocalhost project already exists: \(result.project.name)."
        return toolResult(
            text: message,
            structuredContent: [
                "ok": true,
                "created": result.created,
                "message": message,
                "configPath": result.configPath,
                "project": project
            ],
            isError: false
        )
    }

    private func invoke(_ action: ControlAction, project: String? = nil, service: String? = nil) throws -> [String: Any] {
        let response = try ControlClient.send(ControlRequest(action: action, project: project, service: service))
        return toolResult(from: response)
    }

    private func statusResponse() throws -> ControlResponse {
        var projects: [ControlProjectSnapshot] = []
        var failures: [String] = []
        var hostName: String?
        var hostAddress: String?
        var lanStatusURL: String?

        do {
            let response = try ControlClient.send(ControlRequest(action: .status))
            appendUnique(response.projects, to: &projects)
            hostName = response.hostName
            hostAddress = response.hostAddress
            lanStatusURL = response.lanStatusURL
            if response.ok == false, let message = response.message {
                failures.append(message)
            }
        } catch {
            failures.append("local jocalhost unavailable: \(error.localizedDescription)")
        }

        for result in remoteStatuses() {
            if let response = result.response {
                appendUnique(response.projects, to: &projects)
                if hostName == nil {
                    hostName = response.hostName ?? result.host.name
                    hostAddress = response.hostAddress
                    lanStatusURL = response.lanStatusURL
                }
            } else if let errorMessage = result.errorMessage {
                failures.append("\(result.host.name): \(errorMessage)")
            }
        }

        return ControlResponse(
            ok: projects.isEmpty == false || failures.isEmpty,
            message: projects.isEmpty ? failures.joined(separator: "; ") : nil,
            projects: projects,
            hostName: hostName,
            hostAddress: hostAddress,
            lanStatusURL: lanStatusURL
        )
    }

    private func controlProject(_ action: ControlAction, project selector: String, service: String?) throws -> [String: Any] {
        if let localStatus = try? ControlClient.send(ControlRequest(action: .status)),
           containsProject(selector, in: localStatus) {
            return try invoke(action, project: selector, service: service)
        }

        for result in remoteStatuses() {
            guard let status = result.response,
                  containsProject(selector, in: status),
                  let url = result.host.controlURL else {
                continue
            }

            let request = ControlRequest(action: action, project: selector, service: service)
            let response = try waitForAsync {
                try await LANStatusClient.sendControl(request, to: url, token: result.host.token)
            }

            if response.projects.isEmpty,
               let statusURL = result.host.statusURL,
               let updated = try? waitForAsync({
                   try await LANStatusClient.fetchStatus(from: statusURL, token: result.host.token)
               }) {
                return toolResult(from: filter(updated, project: selector))
            }

            return toolResult(from: response)
        }

        return toolResult(from: filter(try statusResponse(), project: selector))
    }

    private func openProject(_ selector: String, service: String?) throws -> [String: Any] {
        if let localStatus = try? ControlClient.send(ControlRequest(action: .status)),
           containsProject(selector, in: localStatus) {
            return try invoke(.open, project: selector, service: service)
        }

        for result in remoteStatuses() {
            guard let status = result.response,
                  let project = matchingProject(selector, in: status.projects),
                  let urlString = networkURL(for: project, service: service),
                  let url = URL(string: urlString) else {
                continue
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = [url.absoluteString]
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                throw MCPError(code: -32000, message: "open failed for \(urlString)")
            }

            return toolResult(from: filter(status, project: selector))
        }

        return toolResult(from: filter(try statusResponse(), project: selector))
    }

    private func remoteStatuses() -> [RemoteStatusResult] {
        let hosts = (try? remoteHostStore.load().filter(\.isEnabled)) ?? []
        guard hosts.isEmpty == false else {
            return []
        }

        return (try? waitForAsync {
            await withTaskGroup(of: RemoteStatusResult.self) { group in
                for host in hosts {
                    group.addTask {
                        guard let url = host.statusURL else {
                            return RemoteStatusResult(host: host, response: nil, errorMessage: "invalid status URL")
                        }

                        do {
                            let response = try await LANStatusClient.fetchStatus(from: url, token: host.token)
                            return RemoteStatusResult(host: host, response: response, errorMessage: nil)
                        } catch {
                            return RemoteStatusResult(host: host, response: nil, errorMessage: error.localizedDescription)
                        }
                    }
                }

                var results: [RemoteStatusResult] = []
                for await result in group {
                    results.append(result)
                }
                return results
            }
        }) ?? []
    }

    private func appendUnique(_ newProjects: [ControlProjectSnapshot], to projects: inout [ControlProjectSnapshot]) {
        for project in newProjects where projects.contains(where: { existing in
            existing.id == project.id && existing.networkURL == project.networkURL
        }) == false {
            projects.append(project)
        }
    }

    private func filter(_ response: ControlResponse, project selector: String?) -> ControlResponse {
        guard let selector = selector?.trimmingCharacters(in: .whitespacesAndNewlines),
              selector.isEmpty == false else {
            return response
        }

        let projects = response.projects.filter { project in
            project.id.uuidString == selector ||
                project.name == selector ||
                project.name.localizedCaseInsensitiveContains(selector)
        }

        if projects.isEmpty {
            return ControlResponse(
                ok: false,
                message: "project not found: \(selector)",
                projects: response.projects,
                configPath: response.configPath
            )
        }

        return ControlResponse(
            ok: response.ok,
            message: response.message,
            projects: projects,
            configPath: response.configPath,
            hostName: response.hostName,
            hostAddress: response.hostAddress,
            lanStatusURL: response.lanStatusURL
        )
    }

    private func toolResult(from controlResponse: ControlResponse) -> [String: Any] {
        let structuredContent = (try? sanitizedJSON(controlResponse)) as? [String: Any] ?? [
            "ok": controlResponse.ok,
            "message": controlResponse.message ?? ""
        ]

        return toolResult(
            text: textSummary(for: controlResponse),
            structuredContent: structuredContent,
            isError: controlResponse.ok == false
        )
    }

    private func toolResult(text: String, structuredContent: [String: Any], isError: Bool) -> [String: Any] {
        [
            "content": [
                [
                    "type": "text",
                    "text": text
                ]
            ],
            "structuredContent": structuredContent,
            "isError": isError
        ]
    }

    private func textSummary(for response: ControlResponse) -> String {
        if response.projects.isEmpty {
            return response.message ?? response.configPath ?? (response.ok ? "ok" : "error")
        }

        let lines = response.projects.map { project in
            let url = project.networkURL ?? project.services.first { $0.networkURL != nil }?.networkURL ?? "no network URL"
            let pid = project.pid.map(String.init) ?? "-"
            let projectLine = "\(project.status.rawValue) \(url) pid=\(pid) \(project.name)"
            guard project.services.count > 1 else {
                return projectLine
            }

            let serviceLines = project.services.map { service in
                let serviceURL = service.networkURL ?? "no network URL"
                let servicePid = service.pid.map(String.init) ?? "-"
                return "  \(service.status.rawValue) \(serviceURL) pid=\(servicePid) \(service.name)"
            }
            return ([projectLine] + serviceLines).joined(separator: "\n")
        }

        if let message = response.message {
            return ([message] + lines).joined(separator: "\n")
        }

        return lines.joined(separator: "\n")
    }

    private func jsonObject<T: Encodable>(_ value: T) throws -> Any {
        let data = try encoder.encode(value)
        return try JSONSerialization.jsonObject(with: data)
    }

    private func sanitizedJSON<T: Encodable>(_ value: T) throws -> Any {
        sanitize(try jsonObject(value))
    }

    private func sanitize(_ value: Any) -> Any {
        if var dictionary = value as? [String: Any] {
            dictionary.removeValue(forKey: "localURL")
            dictionary.removeValue(forKey: "recentLog")
            return dictionary.mapValues(sanitize)
        }

        if let array = value as? [Any] {
            return array.map(sanitize)
        }

        return value
    }

    private func containsProject(_ selector: String, in response: ControlResponse) -> Bool {
        matchingProject(selector, in: response.projects) != nil
    }

    private func matchingProject(_ selector: String, in projects: [ControlProjectSnapshot]) -> ControlProjectSnapshot? {
        projects.first { project in
            project.id.uuidString == selector ||
                project.name == selector ||
                project.name.localizedCaseInsensitiveContains(selector)
        }
    }

    private func networkURL(for project: ControlProjectSnapshot, service selector: String?) -> String? {
        if let selector,
           let service = project.services.first(where: { service in
               service.id.uuidString == selector ||
                   service.name == selector ||
                   service.name.localizedCaseInsensitiveContains(selector)
           }) {
            return service.networkURL
        }

        return project.networkURL ?? project.services.first { $0.networkURL != nil }?.networkURL
    }

    private func waitForAsync<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) throws -> T {
        let semaphore = DispatchSemaphore(value: 0)
        let box = ResultBox<T>()

        Task {
            do {
                box.result = .success(try await operation())
            } catch {
                box.result = .failure(error)
            }
            semaphore.signal()
        }

        semaphore.wait()
        return try box.result!.get()
    }

    private func response(id: Any?, result: Any) -> [String: Any] {
        [
            "jsonrpc": "2.0",
            "id": sanitizeID(id),
            "result": result
        ]
    }

    private func errorResponse(id: Any?, code: Int, message: String) -> [String: Any] {
        [
            "jsonrpc": "2.0",
            "id": sanitizeID(id),
            "error": [
                "code": code,
                "message": message
            ]
        ]
    }

    private func sanitizeID(_ id: Any?) -> Any {
        switch id {
        case let value as String:
            value
        case let value as NSNumber:
            value
        default:
            NSNull()
        }
    }

    private func write(_ object: [String: Any]) {
        do {
            let data = try JSONSerialization.data(withJSONObject: object)
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
        } catch {
            FileHandle.standardError.write(Data("jocalhost-mcp: \(error.localizedDescription)\n".utf8))
        }
    }
}

private struct MCPError: Error {
    var code: Int
    var message: String
}

private final class ResultBox<T>: @unchecked Sendable {
    var result: Result<T, Error>?
}

private struct RemoteStatusResult: Sendable {
    var host: RemoteHostDefinition
    var response: ControlResponse?
    var errorMessage: String?
}
