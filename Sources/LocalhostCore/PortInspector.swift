import Foundation

public enum PortInspector {
    public static func listener(on port: Int) -> PortListener? {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = [
            "-nP",
            "-iTCP:\(port)",
            "-sTCP:LISTEN",
            "-t"
        ]
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        let pids = output
            .split(whereSeparator: \.isNewline)
            .compactMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }

        return PortListener(port: port, pids: Array(Set(pids)).sorted())
    }

    public static func listeners(forPIDs pids: Set<Int32>) -> [PortListener] {
        guard pids.isEmpty == false else {
            return []
        }

        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = [
            "-nP",
            "-a",
            "-iTCP",
            "-sTCP:LISTEN",
            "-p",
            pids.map(String.init).sorted().joined(separator: ","),
            "-FnP"
        ]
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
        var currentPID: Int32?
        var portPIDs: [Int: Set<Int32>] = [:]

        for line in output.split(whereSeparator: \.isNewline).map(String.init) {
            if line.hasPrefix("p") {
                currentPID = Int32(line.dropFirst())
                continue
            }

            guard line.hasPrefix("n"),
                  let currentPID,
                  let port = port(fromLsofName: String(line.dropFirst())) else {
                continue
            }

            portPIDs[port, default: []].insert(currentPID)
        }

        return portPIDs
            .map { port, pids in
                PortListener(port: port, pids: pids.sorted())
            }
            .sorted { $0.port < $1.port }
    }

    private static func port(fromLsofName name: String) -> Int? {
        let endpoint = name.split(separator: "->", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? name
        guard let colonIndex = endpoint.lastIndex(of: ":") else {
            return nil
        }

        let portText = endpoint[endpoint.index(after: colonIndex)...]
        return Int(portText)
    }
}
