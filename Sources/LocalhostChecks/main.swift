import Foundation
import LocalhostCore

@main
enum LocalhostChecks {
    static func main() throws {
        try withTemporaryDirectory { directory in
            try testDefaultConfigURLUsesPropertyList()
            try testEnsureExistsCreatesEmptyConfig(in: directory)
            try testSaveAndLoadRoundTripsProjects(in: directory)
            try testSaveAndLoadRoundTripsProjectServices(in: directory)
            try testSaveAndLoadRoundTripsLocalNetworkExposure(in: directory)
            try testWhitespaceOnlyConfigLoadsAsEmpty(in: directory)
            try testInvalidConfigThrowsAndCreatesBackup(in: directory)
            try testLegacyPropertyListConfigMigratesToJocalhostPath(in: directory)
            try testLegacyJSONConfigMigratesToPropertyList(in: directory)
            try testDevServerLaunchAdapterAddsHostFlags(in: directory)
            try testLANRemoteAccessUsesConfiguredPort()
            try testLANRemoteAccessBuildsStatusURL()
            try testLANRemoteAccessBuildsRemoteSetupCommand()
            try testLANRemoteAccessCreatesStableToken(in: directory)
            try testRemoteHostDefinitionNormalizesHostAndPort()
            try testRemoteHostConfigStoreRoundTripsHosts(in: directory)
            try testProjectDetectionUsesPackageScript(in: directory)
            try testProjectDetectionDetectsConvexDependency(in: directory)
            try testProjectDetectionDetectsConvexDirectoryWithoutPackageJSON(in: directory)
            try testProjectDetectionKeepsFrontendScriptAndSuggestsConvex(in: directory)
        }

        print("jocalhost checks passed")
    }

    private static func testDefaultConfigURLUsesPropertyList() throws {
        try expect(
            ProjectConfigStore.defaultConfigURL.lastPathComponent == "projects.plist",
            "Expected default config to use projects.plist"
        )
        try expect(
            ProjectConfigStore.defaultConfigURL.deletingLastPathComponent().lastPathComponent == "jocalhost",
            "Expected default config directory to use jocalhost"
        )
    }

    private static func testEnsureExistsCreatesEmptyConfig(in directory: URL) throws {
        let configURL = directory.appendingPathComponent("nested/projects.plist")
        let store = ProjectConfigStore(configURL: configURL, legacyJSONURL: nil)

        try store.ensureExists()

        let data = try Data(contentsOf: configURL)
        let object = try PropertyListSerialization.propertyList(from: data, format: nil)
        try expect((object as? [[String: Any]])?.isEmpty == true, "Expected new config to contain an empty plist array")
    }

    private static func testSaveAndLoadRoundTripsProjects(in directory: URL) throws {
        let configURL = directory.appendingPathComponent("roundtrip/projects.plist")
        let store = ProjectConfigStore(configURL: configURL, legacyJSONURL: nil)
        let project = ProjectDefinition(
            id: UUID(uuidString: "2EE55378-F944-4C6C-9C21-A9C1D919D4B3")!,
            name: "Example",
            workingDirectory: "/tmp/example",
            command: "npm run dev",
            port: 3000
        )

        try store.save([project])

        try expect(try store.load() == [project], "Expected saved project to round-trip")
    }

    private static func testSaveAndLoadRoundTripsProjectServices(in directory: URL) throws {
        let configURL = directory.appendingPathComponent("service-roundtrip/projects.plist")
        let store = ProjectConfigStore(configURL: configURL, legacyJSONURL: nil)
        let project = ProjectDefinition(
            id: UUID(uuidString: "68A8A74F-4E8B-4F4D-B70D-40B171295FB9")!,
            name: "Full Stack",
            workingDirectory: "/tmp/full-stack",
            command: "npm run dev",
            port: 3000,
            services: [
                ProjectServiceDefinition(
                    id: UUID(uuidString: "D6F49C17-31B4-4A36-8C09-1C66C3CA114F")!,
                    name: "web",
                    command: "npm run dev",
                    port: 3000
                ),
                ProjectServiceDefinition(
                    id: UUID(uuidString: "FB56A771-088C-4C9D-A57F-7D7B592AF847")!,
                    name: "convex",
                    command: "npx convex dev"
                )
            ]
        )

        try store.save([project])

        try expect(try store.load() == [project], "Expected project services to round-trip")
    }

    private static func testSaveAndLoadRoundTripsLocalNetworkExposure(in directory: URL) throws {
        let configURL = directory.appendingPathComponent("lan-roundtrip/projects.plist")
        let store = ProjectConfigStore(configURL: configURL, legacyJSONURL: nil)
        let project = ProjectDefinition(
            id: UUID(uuidString: "49C4D1AA-A03C-4C17-B3F8-B2912CE7E807")!,
            name: "LAN App",
            workingDirectory: "/tmp/lan-app",
            command: "npm run dev",
            port: 5173,
            exposeOnLocalNetwork: true,
            services: [
                ProjectServiceDefinition(
                    id: UUID(uuidString: "2F67B0E6-EC5F-4105-B9D8-0257C3A056D7")!,
                    name: "web",
                    command: "npm run dev",
                    port: 5173,
                    exposeOnLocalNetwork: true
                )
            ]
        )

        try store.save([project])

        let loadedProjects = try store.load()
        try expect(loadedProjects == [project], "Expected local-network exposure to round-trip")
        try expect(loadedProjects.first?.effectiveServices.first?.exposeOnLocalNetwork == true, "Expected service exposure flag to remain enabled")
    }

    private static func testWhitespaceOnlyConfigLoadsAsEmpty(in directory: URL) throws {
        let configURL = directory.appendingPathComponent("whitespace/projects.plist")
        let store = ProjectConfigStore(configURL: configURL, legacyJSONURL: nil)
        try FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try " \n\t ".write(to: configURL, atomically: true, encoding: .utf8)

        try expect(try store.load().isEmpty, "Expected whitespace-only config to load as empty")
    }

    private static func testInvalidConfigThrowsAndCreatesBackup(in directory: URL) throws {
        let configURL = directory.appendingPathComponent("invalid/projects.plist")
        let store = ProjectConfigStore(configURL: configURL, legacyJSONURL: nil)
        try FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "not a plist".write(to: configURL, atomically: true, encoding: .utf8)

        do {
            _ = try store.load()
            throw CheckFailure("Expected invalid config to throw")
        } catch let error as ProjectConfigStoreError {
            guard case let .invalidConfig(path, backupPath, _) = error else {
                throw CheckFailure("Expected invalidConfig error, got \(error)")
            }

            try expect(path == configURL.path, "Expected invalid config path to match config path")
            try expect(FileManager.default.fileExists(atPath: configURL.path), "Expected invalid config to remain in place")
            guard let backupPath else {
                throw CheckFailure("Expected invalid config backup path")
            }
            try expect(FileManager.default.fileExists(atPath: backupPath), "Expected invalid config backup to exist")
        }
    }

    private static func testLegacyPropertyListConfigMigratesToJocalhostPath(in directory: URL) throws {
        let configURL = directory.appendingPathComponent("jocalhost/projects.plist")
        let legacyURL = directory.appendingPathComponent("localhost-app/projects.plist")
        let store = ProjectConfigStore(configURL: configURL, legacyPropertyListURL: legacyURL)
        let project = ProjectDefinition(
            id: UUID(uuidString: "C7209E4C-7B31-4DDF-80CE-9D1E8A09F720")!,
            name: "Legacy Plist",
            workingDirectory: "/tmp/legacy-plist",
            command: "npm run dev",
            port: 4000
        )

        try FileManager.default.createDirectory(
            at: legacyURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try PropertyListEncoder().encode([project]).write(to: legacyURL, options: .atomic)

        try expect(try store.load() == [project], "Expected legacy localhost-app plist config to migrate")
        try expect(FileManager.default.fileExists(atPath: configURL.path), "Expected migrated jocalhost config to exist")
        try expect(FileManager.default.fileExists(atPath: legacyURL.path) == false, "Expected legacy plist to be archived")
        let archivedFiles = try FileManager.default.contentsOfDirectory(atPath: legacyURL.deletingLastPathComponent().path)
            .filter { $0.hasPrefix("projects.legacy-localhost-app-") && $0.hasSuffix(".backup") }
        try expect(archivedFiles.count == 1, "Expected one archived legacy plist backup")
    }

    private static func testLegacyJSONConfigMigratesToPropertyList(in directory: URL) throws {
        let configURL = directory.appendingPathComponent("migration/projects.plist")
        let legacyURL = directory.appendingPathComponent("migration/projects.json")
        let store = ProjectConfigStore(configURL: configURL, legacyJSONURL: legacyURL)
        let project = ProjectDefinition(
            id: UUID(uuidString: "37BCB1E9-66D2-437D-A881-AF9579ED6797")!,
            name: "Migrated",
            workingDirectory: "/tmp/migrated",
            command: "npm run dev",
            port: 5173
        )

        try FileManager.default.createDirectory(
            at: legacyURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode([project]).write(to: legacyURL, options: .atomic)

        try expect(try store.load() == [project], "Expected legacy JSON config to migrate")
        try expect(FileManager.default.fileExists(atPath: configURL.path), "Expected migrated plist config to exist")
        try expect(FileManager.default.fileExists(atPath: legacyURL.path) == false, "Expected legacy projects.json to be archived")
        let archivedFiles = try FileManager.default.contentsOfDirectory(atPath: legacyURL.deletingLastPathComponent().path)
            .filter { $0.hasPrefix("projects.legacy-json-") && $0.hasSuffix(".backup") }
        try expect(archivedFiles.count == 1, "Expected one archived legacy JSON backup")

        let data = try Data(contentsOf: configURL)
        _ = try PropertyListSerialization.propertyList(from: data, format: nil)
    }

    private static func testDevServerLaunchAdapterAddsHostFlags(in directory: URL) throws {
        let viteURL = directory.appendingPathComponent("vite-launch", isDirectory: true)
        try write(
            """
            {
              "scripts": {
                "dev": "vite --port 5173"
              }
            }
            """,
            to: viteURL.appendingPathComponent("package.json")
        )

        let vitePlan = DevServerLaunchAdapter.launchPlan(
            command: "npm run dev",
            workingDirectory: viteURL.path,
            exposeOnLocalNetwork: true
        )
        try expect(vitePlan.command == "npm run dev -- --host 0.0.0.0", "Expected npm/Vite command to receive --host")
        try expect(vitePlan.environment["HOST"] == "0.0.0.0", "Expected HOST override for LAN exposure")

        let nextURL = directory.appendingPathComponent("next-launch", isDirectory: true)
        try write(
            """
            {
              "scripts": {
                "dev": "next dev --port 3000"
              }
            }
            """,
            to: nextURL.appendingPathComponent("package.json")
        )

        let nextPlan = DevServerLaunchAdapter.launchPlan(
            command: "bun dev",
            workingDirectory: nextURL.path,
            exposeOnLocalNetwork: true
        )
        try expect(nextPlan.command == "bun dev -- --hostname 0.0.0.0", "Expected bun/Next command to receive --hostname")

        let existingHostPlan = DevServerLaunchAdapter.launchPlan(
            command: "npm run dev -- --host 127.0.0.1",
            workingDirectory: viteURL.path,
            exposeOnLocalNetwork: true
        )
        try expect(existingHostPlan.command == "npm run dev -- --host 127.0.0.1", "Expected existing host flag to be preserved")

        let localhostPlan = DevServerLaunchAdapter.launchPlan(
            command: "npm run dev",
            workingDirectory: viteURL.path,
            exposeOnLocalNetwork: false
        )
        try expect(localhostPlan.command == "npm run dev", "Expected command to remain unchanged without LAN exposure")
        try expect(localhostPlan.environment.isEmpty, "Expected no environment overrides without LAN exposure")
    }

    private static func testLANRemoteAccessUsesConfiguredPort() throws {
        try expect(
            LANRemoteAccess.configuredPort(environment: ["JOCALHOST_LAN_PORT": "48232"]) == 48_232,
            "Expected valid LAN port environment override"
        )
        try expect(
            LANRemoteAccess.configuredPort(environment: ["JOCALHOST_LAN_PORT": "invalid"]) == LANRemoteAccess.defaultPort,
            "Expected invalid LAN port override to fall back to default"
        )
        try expect(
            LANRemoteAccess.configuredPort(environment: ["JOCALHOST_LAN_PORT": "70000"]) == LANRemoteAccess.defaultPort,
            "Expected out-of-range LAN port override to fall back to default"
        )
    }

    private static func testLANRemoteAccessBuildsStatusURL() throws {
        try expect(
            LANRemoteAccess.statusURL(address: "192.168.1.23", port: 48_231) == "http://192.168.1.23:48231/v1/status",
            "Expected LAN status URL to include host, port, and status path"
        )
        try expect(
            LANRemoteAccess.statusURL(address: nil, port: 48_231) == nil,
            "Expected LAN status URL to be nil without a network address"
        )
    }

    private static func testLANRemoteAccessBuildsRemoteSetupCommand() throws {
        try expect(
            LANRemoteAccess.remoteSetupCommand(
                hostName: "Josua's Mac Mini",
                hostAddress: "192.168.1.23",
                port: 48_231,
                token: "abc'def"
            ) == "jocalhostctl remote-add 'Josua'\\''s Mac Mini' '192.168.1.23' --token 'abc'\\''def' --port 48231",
            "Expected remote setup command to shell-quote dynamic values"
        )
    }

    private static func testLANRemoteAccessCreatesStableToken(in directory: URL) throws {
        let tokenURL = directory.appendingPathComponent("lan-token")
        let firstToken = try LANRemoteAccess.ensureToken(at: tokenURL)
        let secondToken = try LANRemoteAccess.ensureToken(at: tokenURL)

        try expect(firstToken.count >= 32, "Expected generated LAN token to be long enough")
        try expect(firstToken == secondToken, "Expected LAN token to be reused once created")
        try expect(FileManager.default.fileExists(atPath: tokenURL.path), "Expected LAN token file to exist")
    }

    private static func testRemoteHostDefinitionNormalizesHostAndPort() throws {
        let host = RemoteHostDefinition(
            name: "Mac Mini",
            host: "http://192.168.1.23:48232/v1/status",
            token: "secret"
        )

        try expect(host.host == "192.168.1.23", "Expected remote host to strip scheme and path")
        try expect(host.port == 48_232, "Expected remote host to keep explicit port from URL")
        try expect(
            host.statusURL?.absoluteString == "http://192.168.1.23:48232/v1/status",
            "Expected remote status URL to normalize to status endpoint"
        )
    }

    private static func testRemoteHostConfigStoreRoundTripsHosts(in directory: URL) throws {
        let configURL = directory.appendingPathComponent("remote-hosts/remote-hosts.plist")
        let store = RemoteHostConfigStore(configURL: configURL)
        let host = RemoteHostDefinition(
            id: UUID(uuidString: "15327F99-B828-43CE-AB7B-4E88C8937D65")!,
            name: "Mac Mini",
            host: "192.168.1.23",
            port: 48_231,
            token: "secret",
            isEnabled: true
        )

        try store.save([host])

        try expect(try store.load() == [host], "Expected remote host config to round-trip")
    }

    private static func testProjectDetectionUsesPackageScript(in directory: URL) throws {
        let projectURL = directory.appendingPathComponent("vite-project", isDirectory: true)
        try write(
            """
            {
              "name": "vite-project",
              "scripts": {
                "dev": "vite --port 5174"
              }
            }
            """,
            to: projectURL.appendingPathComponent("package.json")
        )

        let detection = try requireDetection(in: projectURL)
        try expect(detection.name == "vite-project", "Expected package name to be detected")
        try expect(detection.command == "npm run dev", "Expected npm dev command to be detected")
        try expect(detection.port == 5174, "Expected explicit Vite port to be detected")
        try expect(detection.convexCommand == nil, "Expected no Convex command for a plain Vite project")
        try expect(detection.services.count == 1, "Expected one service for a plain Vite project")
        try expect(detection.services.first?.name == "web", "Expected Vite project to create a web service")
        try expect(detection.services.first?.command == "npm run dev", "Expected Vite service command")
        try expect(detection.services.first?.port == 5174, "Expected Vite service port")
    }

    private static func testProjectDetectionDetectsConvexDependency(in directory: URL) throws {
        let projectURL = directory.appendingPathComponent("convex-package", isDirectory: true)
        try write(
            """
            {
              "name": "convex-package",
              "dependencies": {
                "convex": "^1.0.0"
              }
            }
            """,
            to: projectURL.appendingPathComponent("package.json")
        )

        let detection = try requireDetection(in: projectURL)
        try expect(detection.name == "convex-package", "Expected Convex package name to be detected")
        try expect(detection.command == "npx convex dev", "Expected Convex dependency to use npx convex dev")
        try expect(detection.port == nil, "Expected Convex dev command to leave port detection empty")
        try expect(detection.convexCommand == "npx convex dev", "Expected Convex command suggestion")
        try expect(detection.summary.contains("Convex"), "Expected Convex in detection summary")
        try expect(detection.services.count == 1, "Expected one service for a Convex-only package")
        try expect(detection.services.first?.name == "convex", "Expected Convex-only package to create a Convex service")
        try expect(detection.services.first?.command == "npx convex dev", "Expected Convex service command")
        try expect(detection.services.first?.port == nil, "Expected Convex service to have no browser port")
    }

    private static func testProjectDetectionDetectsConvexDirectoryWithoutPackageJSON(in directory: URL) throws {
        let projectURL = directory.appendingPathComponent("convex-only", isDirectory: true)
        try FileManager.default.createDirectory(
            at: projectURL.appendingPathComponent("convex", isDirectory: true),
            withIntermediateDirectories: true
        )

        let detection = try requireDetection(in: projectURL)
        try expect(detection.name == "convex-only", "Expected directory name for Convex project without package.json")
        try expect(detection.command == "npx convex dev", "Expected Convex directory to use npx convex dev")
        try expect(detection.convexCommand == "npx convex dev", "Expected Convex command suggestion")
        try expect(detection.services.count == 1, "Expected one service for a Convex directory")
        try expect(detection.services.first?.name == "convex", "Expected Convex directory to create a Convex service")
    }

    private static func testProjectDetectionKeepsFrontendScriptAndSuggestsConvex(in directory: URL) throws {
        let projectURL = directory.appendingPathComponent("convex-web", isDirectory: true)
        try write(
            """
            {
              "name": "convex-web",
              "scripts": {
                "dev": "next dev --port 3001"
              },
              "devDependencies": {
                "convex": "^1.0.0"
              }
            }
            """,
            to: projectURL.appendingPathComponent("package.json")
        )

        let detection = try requireDetection(in: projectURL)
        try expect(detection.command == "npm run dev", "Expected frontend dev script to remain the default command")
        try expect(detection.port == 3001, "Expected frontend dev port to be detected")
        try expect(detection.convexCommand == "npx convex dev", "Expected Convex command suggestion alongside frontend script")
        try expect(detection.summary.contains("Convex"), "Expected Convex in detection summary")
        try expect(detection.services.map(\.name) == ["web", "convex"], "Expected web and Convex services")
        try expect(detection.services.map(\.command) == ["npm run dev", "npx convex dev"], "Expected service commands")
        try expect(detection.services.map(\.port) == [3001, nil], "Expected only the web service to expose a browser port")
    }

    private static func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalhostChecks-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        try body(directory)
    }

    private static func write(_ contents: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func requireDetection(in directory: URL) throws -> ProjectDetection {
        guard let detection = ProjectDetection.detect(in: directory.path) else {
            throw CheckFailure("Expected project detection for \(directory.path)")
        }

        return detection
    }

    private static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        if try condition() == false {
            throw CheckFailure(message)
        }
    }
}

private struct CheckFailure: Error, CustomStringConvertible {
    var description: String

    init(_ description: String) {
        self.description = description
    }
}
