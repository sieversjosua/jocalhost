import Foundation

public struct ProjectServiceDetection: Equatable, Sendable {
    public var name: String
    public var command: String
    public var port: Int?
}

public struct ProjectDetection: Equatable, Sendable {
    public var name: String?
    public var command: String?
    public var port: Int?
    public var summary: String
    public var convexCommand: String?
    public var services: [ProjectServiceDetection]

    public static func detect(in directory: String) -> ProjectDetection? {
        let directoryURL = URL(fileURLWithPath: directory)
        let packageObject = loadPackageObject(from: directoryURL)
        let scripts = (packageObject?["scripts"] as? [String: Any])?
            .compactMapValues { $0 as? String } ?? [:]
        let packageName = packageObject?["name"] as? String
        let manager = packageManager(in: directoryURL)
        let convexCommand = detectConvex(in: directoryURL, packageObject: packageObject, scripts: scripts) ? "npx convex dev" : nil

        guard packageObject != nil || convexCommand != nil else {
            return nil
        }

        let scriptName = ["dev", "start", "serve", "preview"].first { scripts[$0] != nil }
        let scriptCommand = scriptName.flatMap { scripts[$0] }
        let port = scriptCommand.flatMap(detectPort(in:)) ?? scriptCommand.flatMap(defaultPort(for:))
        let scriptLaunchCommand = scriptName.map { commandForScript($0, manager: manager) }
        var services: [ProjectServiceDetection] = []

        if let scriptName,
           let scriptLaunchCommand {
            services.append(
                ProjectServiceDetection(
                    name: serviceName(for: scriptName, command: scriptCommand),
                    command: scriptLaunchCommand,
                    port: port
                )
            )
        }

        if let convexCommand,
           scriptCommand?.localizedCaseInsensitiveContains("convex dev") != true {
            services.append(
                ProjectServiceDetection(
                    name: "convex",
                    command: convexCommand,
                    port: nil
                )
            )
        }

        let command = services.first?.command ?? convexCommand

        var parts = packageObject == nil ? ["Convex"] : [manager.uppercased()]
        if convexCommand != nil, packageObject != nil {
            parts.append("Convex")
        }
        if let scriptName {
            parts.append("\(scriptName) script")
        } else if convexCommand != nil {
            parts.append("Convex dev")
        } else {
            parts.append("no dev/start script")
        }
        if let port {
            parts.append("port \(port)")
        }

        return ProjectDetection(
            name: packageName ?? (convexCommand == nil ? nil : directoryURL.lastPathComponent),
            command: command,
            port: port,
            summary: parts.joined(separator: " - "),
            convexCommand: convexCommand,
            services: services
        )
    }

    private static func loadPackageObject(from directoryURL: URL) -> [String: Any]? {
        let packageURL = directoryURL.appendingPathComponent("package.json")
        guard let data = try? Data(contentsOf: packageURL) else {
            return nil
        }

        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func detectConvex(in directoryURL: URL, packageObject: [String: Any]?, scripts: [String: String]) -> Bool {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: directoryURL.appendingPathComponent("convex").path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            return true
        }

        if fileManager.fileExists(atPath: directoryURL.appendingPathComponent("convex.json").path) {
            return true
        }

        if packageHasDependency("convex", in: packageObject) {
            return true
        }

        if scripts.values.contains(where: { $0.localizedCaseInsensitiveContains("convex dev") }) {
            return true
        }

        let envURL = directoryURL.appendingPathComponent(".env.local")
        guard let envData = try? Data(contentsOf: envURL),
              let envText = String(data: envData, encoding: .utf8) else {
            return false
        }

        return envText.contains("CONVEX_DEPLOYMENT")
    }

    private static func packageHasDependency(_ dependency: String, in packageObject: [String: Any]?) -> Bool {
        let groups = ["dependencies", "devDependencies", "optionalDependencies", "peerDependencies"]
        return groups.contains { group in
            guard let dependencies = packageObject?[group] as? [String: Any] else {
                return false
            }
            return dependencies[dependency] != nil
        }
    }

    private static func packageManager(in directoryURL: URL) -> String {
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: directoryURL.appendingPathComponent("bun.lockb").path) ||
            fileManager.fileExists(atPath: directoryURL.appendingPathComponent("bun.lock").path) {
            return "bun"
        }

        if fileManager.fileExists(atPath: directoryURL.appendingPathComponent("pnpm-lock.yaml").path) {
            return "pnpm"
        }

        if fileManager.fileExists(atPath: directoryURL.appendingPathComponent("yarn.lock").path) {
            return "yarn"
        }

        return "npm"
    }

    private static func commandForScript(_ script: String, manager: String) -> String {
        switch manager {
        case "bun":
            "bun run \(script)"
        case "pnpm":
            script == "start" ? "pnpm start" : "pnpm \(script)"
        case "yarn":
            script == "start" ? "yarn start" : "yarn \(script)"
        default:
            script == "start" ? "npm start" : "npm run \(script)"
        }
    }

    private static func serviceName(for script: String, command: String?) -> String {
        guard let command else {
            return script
        }

        let lowercased = command.lowercased()
        if lowercased.contains("convex dev") {
            return "convex"
        }
        if lowercased.contains("vite") ||
            lowercased.contains("next") ||
            lowercased.contains("nuxt") ||
            lowercased.contains("astro") ||
            lowercased.contains("remix") ||
            lowercased.contains("svelte-kit") {
            return "web"
        }

        return script
    }

    private static func detectPort(in command: String) -> Int? {
        let patterns = [
            #"(?:--port|-p)\s+([0-9]{2,5})"#,
            #"(?:PORT|port)=([0-9]{2,5})"#,
            #"localhost:([0-9]{2,5})"#,
            #":([0-9]{4,5})"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                continue
            }

            let range = NSRange(command.startIndex..<command.endIndex, in: command)
            guard let match = regex.firstMatch(in: command, range: range),
                  match.numberOfRanges > 1,
                  let portRange = Range(match.range(at: 1), in: command),
                  let port = Int(command[portRange]),
                  (1...65_535).contains(port) else {
                continue
            }

            return port
        }

        return nil
    }

    private static func defaultPort(for command: String) -> Int? {
        let lowercased = command.lowercased()

        if lowercased.contains("vite") || lowercased.contains("svelte-kit") {
            return 5173
        }

        if lowercased.contains("astro") {
            return 4321
        }

        if lowercased.contains("next") || lowercased.contains("nuxt") || lowercased.contains("remix") {
            return 3000
        }

        return nil
    }
}
