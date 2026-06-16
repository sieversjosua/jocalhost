import Foundation
import LocalhostCore
import Testing

@Suite
struct LocalhostCoreTests {
    @Test
    func projectConfigRoundTripsServices() throws {
        try withTemporaryDirectory { directory in
            let store = ProjectConfigStore(
                configURL: directory.appendingPathComponent("projects.plist"),
                legacyJSONURL: nil,
                legacyPropertyListURL: nil
            )
            let project = ProjectDefinition(
                id: UUID(uuidString: "68A8A74F-4E8B-4F4D-B70D-40B171295FB9")!,
                name: "Full Stack",
                workingDirectory: "/tmp/full-stack",
                command: "npm run dev",
                port: 3000,
                exposeOnLocalNetwork: true,
                services: [
                    ProjectServiceDefinition(name: "web", command: "npm run dev", port: 3000, exposeOnLocalNetwork: true),
                    ProjectServiceDefinition(name: "convex", command: "npx convex dev")
                ]
            )

            try store.save([project])

            #expect(try store.load() == [project])
        }
    }

    @Test
    func lanTokenIsStableAndPrivate() throws {
        try withTemporaryDirectory { directory in
            let tokenURL = directory.appendingPathComponent("lan-token")

            let token = try LANRemoteAccess.ensureToken(at: tokenURL)

            #expect(try LANRemoteAccess.ensureToken(at: tokenURL) == token)
            #expect(token.count >= 32)
            #expect(try permissions(at: tokenURL) == 0o600)
        }
    }

    @Test
    func remoteHostConfigIsPrivate() throws {
        try withTemporaryDirectory { directory in
            let configURL = directory.appendingPathComponent("remote-hosts.plist")
            let store = RemoteHostConfigStore(configURL: configURL)

            try store.save([
                RemoteHostDefinition(name: "Mac Mini", host: "http://192.168.1.23:48232/v1/status", token: "secret")
            ])

            #expect(try store.load().first?.displayAddress == "192.168.1.23:48232")
            #expect(try permissions(at: configURL) == 0o600)
        }
    }

    @Test
    func devServerLaunchAdapterAddsLANHostFlag() throws {
        try withTemporaryDirectory { directory in
            try """
            {"scripts":{"dev":"vite --port 5173"}}
            """.write(to: directory.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)

            let plan = DevServerLaunchAdapter.launchPlan(
                command: "npm run dev",
                workingDirectory: directory.path,
                exposeOnLocalNetwork: true
            )

            #expect(plan.command == "npm run dev -- --host 0.0.0.0")
            #expect(plan.environment["HOST"] == "0.0.0.0")
        }
    }

    private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalhostCoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }

    private func permissions(at url: URL) throws -> Int {
        let value = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        return value?.intValue ?? 0
    }
}
