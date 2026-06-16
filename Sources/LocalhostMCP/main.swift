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
            "instructions": "Use these tools to inspect and control projects registered in the jocalhost menu bar app. Prefer start_project/restart_project over running npm run dev, bun dev, pnpm dev, yarn dev, or framework dev servers directly. When a snapshot includes networkURL, present that URL to users on remote devices; localhost URLs refer to the Codex host only. The menu bar app must be running."
        ]
    }

    private func tools() -> [[String: Any]] {
        [
            tool(
                name: "list_projects",
                title: "List Projects",
                description: "List projects registered in the jocalhost app with runtime status, ports, local URLs, and local-network URLs.",
                properties: [:],
                required: [],
                annotations: ["readOnlyHint": true]
            ),
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
        case "list_projects":
            return try invoke(.list)

        case "get_status":
            let response = try ControlClient.send(ControlRequest(action: .status))
            return toolResult(from: filter(response, project: project))

        case "reload_projects":
            return try invoke(.reload)

        case "start_project":
            return try invoke(.start, project: try requiredProject(project), service: service)

        case "stop_project":
            return try invoke(.stop, project: try requiredProject(project), service: service)

        case "restart_project":
            return try invoke(.restart, project: try requiredProject(project), service: service)

        case "open_project":
            return try invoke(.open, project: try requiredProject(project), service: service)

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

    private func invoke(_ action: ControlAction, project: String? = nil, service: String? = nil) throws -> [String: Any] {
        let response = try ControlClient.send(ControlRequest(action: action, project: project, service: service))
        return toolResult(from: response)
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
            configPath: response.configPath
        )
    }

    private func toolResult(from controlResponse: ControlResponse) -> [String: Any] {
        let structuredContent = (try? jsonObject(controlResponse)) as? [String: Any] ?? [
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
            let url = project.networkURL ?? project.localURL ?? (project.port ?? project.detectedPort).map { ":\($0)" } ?? "-"
            let pid = project.pid.map(String.init) ?? "-"
            let projectLine = "\(project.status.rawValue) \(url) pid=\(pid) \(project.name)"
            guard project.services.count > 1 else {
                return projectLine
            }

            let serviceLines = project.services.map { service in
                let serviceURL = service.networkURL ?? service.localURL ?? (service.port ?? service.detectedPort).map { ":\($0)" } ?? "-"
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
