import Foundation

public struct DevServerLaunchPlan: Equatable, Sendable {
    public var command: String
    public var environment: [String: String]

    public init(command: String, environment: [String: String] = [:]) {
        self.command = command
        self.environment = environment
    }
}

public enum DevServerLaunchAdapter {
    public static func launchPlan(
        command: String,
        workingDirectory: String,
        exposeOnLocalNetwork: Bool
    ) -> DevServerLaunchPlan {
        guard exposeOnLocalNetwork else {
            return DevServerLaunchPlan(command: command)
        }

        var adaptedCommand = command
        if commandAlreadyBindsHost(command) == false,
           let hostFlag = hostFlag(for: command, workingDirectory: workingDirectory),
           canAppendHostFlag(to: command) {
            adaptedCommand = commandWithHostFlag(command, hostFlag: hostFlag)
        }

        return DevServerLaunchPlan(
            command: adaptedCommand,
            environment: [
                "HOST": "0.0.0.0",
                "VITE_HOST": "0.0.0.0",
                "JOCALHOST_EXPOSE_ON_LOCAL_NETWORK": "1"
            ]
        )
    }

    private static func hostFlag(for command: String, workingDirectory: String) -> HostFlag? {
        if let directFlag = hostFlag(forKnownCommandText: command) {
            return directFlag
        }

        guard let scriptName = packageScriptName(from: command),
              let scriptCommand = packageScript(named: scriptName, workingDirectory: workingDirectory) else {
            return nil
        }

        return hostFlag(forKnownCommandText: scriptCommand)
    }

    private static func hostFlag(forKnownCommandText command: String) -> HostFlag? {
        let lowercased = command.lowercased()

        if lowercased.contains("next") {
            return .hostname
        }

        if lowercased.contains("vite") ||
            lowercased.contains("astro") ||
            lowercased.contains("svelte-kit") ||
            lowercased.contains("nuxt") {
            return .host
        }

        return nil
    }

    private static func packageScriptName(from command: String) -> String? {
        let words = shellWords(in: command)
        guard let first = words.first else {
            return nil
        }

        switch first {
        case "npm":
            if words.count >= 3, words[1] == "run" {
                return words[2]
            }
            if words.count >= 2, words[1] == "start" {
                return "start"
            }

        case "pnpm":
            if words.count >= 3, words[1] == "run" {
                return words[2]
            }
            if words.count >= 2 {
                return words[1]
            }

        case "yarn":
            if words.count >= 3, words[1] == "run" {
                return words[2]
            }
            if words.count >= 2 {
                return words[1]
            }

        case "bun":
            if words.count >= 3, words[1] == "run" {
                return words[2]
            }
            if words.count >= 2, isBunScriptShortcut(words[1]) {
                return words[1]
            }

        default:
            break
        }

        return nil
    }

    private static func isBunScriptShortcut(_ word: String) -> Bool {
        let builtinCommands: Set<String> = [
            "add",
            "build",
            "create",
            "install",
            "i",
            "pm",
            "remove",
            "run",
            "test",
            "upgrade",
            "x"
        ]
        return builtinCommands.contains(word) == false
    }

    private static func packageScript(named name: String, workingDirectory: String) -> String? {
        let packageURL = URL(fileURLWithPath: workingDirectory).appendingPathComponent("package.json")
        guard let data = try? Data(contentsOf: packageURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let scripts = object["scripts"] as? [String: Any],
              let script = scripts[name] as? String else {
            return nil
        }

        return script
    }

    private static func commandAlreadyBindsHost(_ command: String) -> Bool {
        let lowercased = command.lowercased()
        return lowercased.contains("--host") ||
            lowercased.contains("--hostname") ||
            lowercased.contains("host=") ||
            lowercased.contains("hostname=") ||
            lowercased.contains("0.0.0.0") ||
            lowercased.contains("::")
    }

    private static func canAppendHostFlag(to command: String) -> Bool {
        let blockedFragments = ["&&", "||", ";", "|", ">", "<", "\n"]
        return blockedFragments.contains { command.contains($0) } == false
    }

    private static func commandWithHostFlag(_ command: String, hostFlag: HostFlag) -> String {
        let words = shellWords(in: command)
        let separator: String

        if words.contains("--") {
            separator = " "
        } else if let first = words.first, first == "yarn" || isDirectFrameworkInvocation(first) {
            separator = " "
        } else {
            separator = " -- "
        }

        return "\(command)\(separator)\(hostFlag.rawValue) 0.0.0.0"
    }

    private static func isDirectFrameworkInvocation(_ word: String) -> Bool {
        ["astro", "next", "nuxt", "svelte-kit", "vite"].contains(word)
    }

    private static func shellWords(in command: String) -> [String] {
        command
            .split(whereSeparator: \.isWhitespace)
            .map { word in
                String(word).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            }
    }
}

private enum HostFlag: String {
    case host = "--host"
    case hostname = "--hostname"
}
