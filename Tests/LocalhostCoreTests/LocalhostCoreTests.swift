import Foundation
import LocalhostCore
import Testing

@Suite
struct LocalhostCoreTests {
    @Test
    func projectRegistrationDetectsPackageDevScript() throws {
        try withTemporaryDirectory { directory in
            try """
            {"name":"sample-app","scripts":{"dev":"vite --port 5173"}}
            """.write(to: directory.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
            let store = ProjectConfigStore(
                configURL: directory.appendingPathComponent("projects.plist")
            )

            let first = try store.registerProject(workingDirectory: directory.path)
            let second = try store.registerProject(workingDirectory: directory.path)

            #expect(first.created)
            #expect(!second.created)
            #expect(first.project.name == "sample-app")
            #expect(first.project.command == "npm run dev")
            #expect(first.project.port == 5173)
            #expect(first.project.exposeOnLocalNetwork)
            #expect(try store.load().count == 1)
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
    func runtimeEffectivePortPrefersDetectedPort() {
        var runtime = ProjectRuntime()
        #expect(runtime.effectivePort(preferredPort: 5173) == 5173)

        runtime.detectedPort = 5174
        #expect(runtime.effectivePort(preferredPort: 5173) == 5174)
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
