import Darwin
@preconcurrency import Foundation
import LocalhostCore

@MainActor
final class ProcessSupervisor {
    private var processes: [UUID: Process] = [:]
    private var outputPipes: [UUID: Pipe] = [:]

    func start(
        project: ProjectDefinition,
        service: ProjectServiceDefinition,
        onOutput: @escaping @MainActor @Sendable (String) -> Void,
        onExit: @escaping @MainActor @Sendable (Int32) -> Void
    ) throws -> ProcessLaunchResult {
        if let existing = processes[service.id], existing.isRunning {
            return ProcessLaunchResult(
                pid: existing.processIdentifier,
                command: service.command,
                environmentOverrides: [:]
            )
        }

        let process = Process()
        let pipe = Pipe()
        let launchPlan = DevServerLaunchAdapter.launchPlan(
            command: service.command,
            workingDirectory: project.workingDirectory,
            exposeOnLocalNetwork: service.exposeOnLocalNetwork
        )

        if let words = simpleCommandWords(launchPlan.command) {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = words
        } else {
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", launchPlan.command]
        }
        process.currentDirectoryURL = URL(fileURLWithPath: project.workingDirectory)
        process.environment = launchEnvironment(overrides: launchPlan.environment)
        process.standardOutput = pipe
        process.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else {
                return
            }

            Task { @MainActor in
                onOutput(text)
            }
        }

        process.terminationHandler = { [weak self] process in
            Task { @MainActor in
                pipe.fileHandleForReading.readabilityHandler = nil
                self?.processes[service.id] = nil
                self?.outputPipes[service.id] = nil
                onExit(process.terminationStatus)
            }
        }

        try process.run()
        processes[service.id] = process
        outputPipes[service.id] = pipe

        return ProcessLaunchResult(
            pid: process.processIdentifier,
            command: launchPlan.command,
            environmentOverrides: launchPlan.environment
        )
    }

    func stop(serviceID: UUID) {
        guard let process = processes[serviceID], process.isRunning else {
            processes[serviceID] = nil
            outputPipes[serviceID] = nil
            return
        }

        sendSignal(SIGTERM, toTreeRootedAt: process.processIdentifier)

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if process.isRunning {
                sendSignal(SIGKILL, toTreeRootedAt: process.processIdentifier)
            }
        }
    }

    func stopAll() {
        let runningProcesses = processes.values.filter(\.isRunning)
        guard runningProcesses.isEmpty == false else {
            processes.removeAll()
            outputPipes.removeAll()
            return
        }

        for process in runningProcesses {
            sendSignal(SIGTERM, toTreeRootedAt: process.processIdentifier)
        }

        // ponytail: synchronous only during app shutdown; per-process graceful waits if quit ever needs progress UI.
        Thread.sleep(forTimeInterval: 1)

        for process in runningProcesses where process.isRunning {
            sendSignal(SIGKILL, toTreeRootedAt: process.processIdentifier)
        }

        processes.removeAll()
        outputPipes.removeAll()
    }

    func isRunning(serviceID: UUID) -> Bool {
        processes[serviceID]?.isRunning == true
    }

    func managedPIDs(for serviceID: UUID) -> Set<Int32> {
        guard let process = processes[serviceID], process.isRunning else {
            return []
        }

        return Set(descendantPIDs(of: process.processIdentifier) + [process.processIdentifier])
    }

    private func sendSignal(_ signal: Int32, toTreeRootedAt rootPID: Int32) {
        let pids = descendantPIDs(of: rootPID) + [rootPID]
        for pid in pids.reversed() {
            kill(pid, signal)
        }
    }

    private func descendantPIDs(of pid: Int32) -> [Int32] {
        childPIDs(of: pid).flatMap { childPID in
            descendantPIDs(of: childPID) + [childPID]
        }
    }

    private func childPIDs(of pid: Int32) -> [Int32] {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-P", String(pid)]
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        return output
            .split(whereSeparator: \.isNewline)
            .compactMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    private func launchEnvironment(overrides: [String: String]) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let preferredPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

        if let existingPath = environment["PATH"], existingPath.isEmpty == false {
            environment["PATH"] = "\(preferredPath):\(existingPath)"
        } else {
            environment["PATH"] = preferredPath
        }

        for (key, value) in overrides {
            environment[key] = value
        }

        return environment
    }

    private func simpleCommandWords(_ command: String) -> [String]? {
        let blockedFragments = ["&&", "||", ";", "|", ">", "<", "\n", "\"", "'"]
        guard blockedFragments.contains(where: command.contains) == false else {
            return nil
        }

        let words = command.split(whereSeparator: \.isWhitespace).map(String.init)
        return words.isEmpty ? nil : words
    }
}

struct ProcessLaunchResult {
    var pid: Int32
    var command: String
    var environmentOverrides: [String: String]
}
