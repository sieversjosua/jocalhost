import AppKit
import Foundation
import LocalhostCore

@MainActor
final class ProjectStore: ObservableObject {
    @Published private(set) var projects: [ProjectDefinition] = []
    @Published private(set) var runtimes: [UUID: ProjectRuntime] = [:]
    @Published private(set) var portListeners: [Int: PortListener] = [:]
    @Published private(set) var remoteHosts: [RemoteHostDefinition] = []
    @Published private(set) var remoteHostRuntimes: [UUID: RemoteHostRuntime] = [:]
    @Published private(set) var lanStatusURL: String?
    @Published var errorMessage: String?

    private let configStore = ProjectConfigStore()
    private let remoteHostConfigStore = RemoteHostConfigStore()
    private let supervisor = ProcessSupervisor()
    private var controlServer: ControlServer?
    private var lanStatusServer: LANStatusServer?
    private var remoteRefreshTask: Task<Void, Never>?
    private var requestedStops = Set<UUID>()
    private var startTokens: [UUID: UUID] = [:]
    private var restartTokens: [UUID: UUID] = [:]
    private let startupTimeout: TimeInterval = 30
    private let restartTimeout: TimeInterval = 10

    var anyRunning: Bool {
        runtimes.values.contains { $0.isRunning } || anyRemoteRunning
    }

    var anyRemoteRunning: Bool {
        let enabledRemoteIDs = Set(remoteHosts.filter(\.isEnabled).map(\.id))
        return remoteHostRuntimes.contains { id, runtime in
            enabledRemoteIDs.contains(id) &&
            runtime.response?.projects.contains { project in
                project.status == .running || project.status == .starting || project.status == .stopping
            } == true
        }
    }

    var configPath: String {
        configStore.configURL.path
    }

    var remoteConfigPath: String {
        remoteHostConfigStore.configURL.path
    }

    init() {
        reload()
        controlServer = ControlServer(store: self)
        controlServer?.start()
        startLANStatusServer()
        startRemoteHostPolling()
    }

    func reload() {
        var errors: [String] = []

        do {
            projects = try configStore.load()
            for project in projects {
                for service in project.effectiveServices where runtimes[service.id] == nil {
                    runtimes[service.id] = ProjectRuntime()
                }
            }
            let serviceIDs = Set(projects.flatMap { $0.effectiveServices.map(\.id) })
            runtimes = runtimes.filter { projectID, runtime in
                runtime.isRunning || serviceIDs.contains(projectID)
            }
            refreshPorts()
        } catch {
            errors.append("Config could not be loaded: \(error.localizedDescription)")
        }

        do {
            remoteHosts = try remoteHostConfigStore.load()
            for host in remoteHosts where remoteHostRuntimes[host.id] == nil {
                remoteHostRuntimes[host.id] = RemoteHostRuntime()
            }
            let remoteIDs = Set(remoteHosts.map(\.id))
            remoteHostRuntimes = remoteHostRuntimes.filter { remoteIDs.contains($0.key) }
        } catch {
            errors.append("Remote hosts could not be loaded: \(error.localizedDescription)")
        }

        errorMessage = errors.isEmpty ? nil : errors.joined(separator: " ")
        refreshRemoteHosts()
    }

    func runtime(for project: ProjectDefinition) -> ProjectRuntime {
        let services = project.effectiveServices
        let serviceRuntimes = services.map { runtime(for: $0) }
        guard services.count != 1 else {
            return serviceRuntimes.first ?? ProjectRuntime()
        }

        var aggregate = ProjectRuntime()
        aggregate.status = aggregateStatus(serviceRuntimes.map(\.status))
        let pids = serviceRuntimes.compactMap(\.pid)
        aggregate.pid = pids.count == 1 ? pids.first : nil
        aggregate.detectedPort = services.lazy.compactMap { service in
            service.port ?? self.runtimes[service.id]?.detectedPort
        }.first
        aggregate.startedAt = serviceRuntimes.compactMap(\.startedAt).min()
        aggregate.lastExitCode = serviceRuntimes.compactMap(\.lastExitCode).first
        aggregate.log = services.map { service in
            let log = self.runtimes[service.id]?.log ?? ""
            return log.isEmpty ? "" : "[\(service.name)]\n\(log)"
        }
        .filter { $0.isEmpty == false }
        .joined(separator: "\n")
        return aggregate
    }

    func runtime(for service: ProjectServiceDefinition) -> ProjectRuntime {
        runtimes[service.id] ?? ProjectRuntime()
    }

    func portListener(for project: ProjectDefinition) -> PortListener? {
        for service in project.effectiveServices {
            guard let port = service.port,
                  let listener = portListeners[port] else {
                continue
            }

            return listener
        }

        return nil
    }

    func portListener(for service: ProjectServiceDefinition) -> PortListener? {
        guard let port = service.port else {
            return nil
        }

        return portListeners[port]
    }

    @discardableResult
    func start(_ project: ProjectDefinition, service serviceSelector: String? = nil) -> ProjectActionResult {
        let services: [ProjectServiceDefinition]
        if let serviceSelector {
            guard let service = resolveService(serviceSelector, in: project) else {
                return ProjectActionResult(ok: false, message: "service not found: \(serviceSelector)")
            }
            services = [service]
        } else {
            services = project.effectiveServices
        }

        let results = services.map { startService($0, in: project) }
        if results.count == 1, let result = results.first {
            return result
        }

        let ok = results.allSatisfy(\.ok)
        let message = results.map(\.message).joined(separator: "; ")
        return ProjectActionResult(ok: ok, message: message)
    }

    private func startService(_ service: ProjectServiceDefinition, in project: ProjectDefinition) -> ProjectActionResult {
        if runtime(for: service).status == .stopping {
            return ProjectActionResult(ok: false, message: "\(project.name)/\(service.name) is still stopping")
        }

        if supervisor.isRunning(serviceID: service.id) {
            return ProjectActionResult(ok: true, message: "\(project.name)/\(service.name) is already running")
        }

        if let port = service.port,
           let listener = PortInspector.listener(on: port),
           listener.isOccupied,
           runtime(for: service).isRunning == false {
            portListeners[port] = listener
            updateRuntime(for: service.id) { runtime in
                runtime.status = .failed
                runtime.pid = nil
            }

            let message = "Port \(port) is already in use by pid(s): \(listener.pids.map(String.init).joined(separator: ", "))"
            append("\(message)\n", to: service.id)
            return ProjectActionResult(ok: false, message: message)
        }

        let token = UUID()
        startTokens[service.id] = token
        requestedStops.remove(service.id)
        updateRuntime(for: service.id) { runtime in
            runtime.status = .starting
            runtime.pid = nil
            runtime.detectedPort = nil
            runtime.lastExitCode = nil
        }

        do {
            let launch = try supervisor.start(
                project: project,
                service: service,
                onOutput: { [weak self] output in
                    self?.append(output, to: service.id)
                },
                onExit: { [weak self] exitCode in
                    self?.markExited(serviceID: service.id, exitCode: exitCode)
                }
            )

            updateRuntime(for: service.id) { runtime in
                runtime.pid = launch.pid
                runtime.startedAt = Date()
                runtime.status = service.port == nil ? .running : .starting
            }
            append("$ \(launch.command)\n", to: service.id)
            if service.exposeOnLocalNetwork,
               let port = service.port,
               let networkURL = LocalNetwork.networkURL(port: port) {
                append("Local network URL: \(networkURL)\n", to: service.id)
            }
            refreshPorts()

            if let port = service.port {
                monitorStartup(project: project, service: service, port: port, token: token)
                return ProjectActionResult(ok: true, message: "starting \(project.name)/\(service.name)")
            }

            startTokens[service.id] = nil
            detectManagedPort(for: service.id)
            return ProjectActionResult(ok: true, message: "started \(project.name)/\(service.name)")
        } catch {
            startTokens[service.id] = nil
            updateRuntime(for: service.id) { runtime in
                runtime.status = .failed
            }

            let message = "Failed to start \(project.name)/\(service.name): \(error.localizedDescription)"
            append("\(message)\n", to: service.id)
            return ProjectActionResult(ok: false, message: message)
        }
    }

    @discardableResult
    func stop(_ project: ProjectDefinition, service serviceSelector: String? = nil) -> ProjectActionResult {
        let services: [ProjectServiceDefinition]
        if let serviceSelector {
            guard let service = resolveService(serviceSelector, in: project) else {
                return ProjectActionResult(ok: false, message: "service not found: \(serviceSelector)")
            }
            services = [service]
        } else {
            services = project.effectiveServices
        }

        let results = services.map { stopService($0, in: project) }
        if results.count == 1, let result = results.first {
            return result
        }

        let ok = results.allSatisfy(\.ok)
        let message = results.map(\.message).joined(separator: "; ")
        return ProjectActionResult(ok: ok, message: message)
    }

    private func stopService(_ service: ProjectServiceDefinition, in project: ProjectDefinition) -> ProjectActionResult {
        startTokens[service.id] = nil

        guard supervisor.isRunning(serviceID: service.id) else {
            requestedStops.remove(service.id)
            updateRuntime(for: service.id) { runtime in
                runtime.status = .stopped
                runtime.pid = nil
                runtime.detectedPort = nil
            }
            refreshPorts()
            return ProjectActionResult(ok: true, message: "\(project.name)/\(service.name) is already stopped")
        }

        updateRuntime(for: service.id) { runtime in
            runtime.status = .stopping
        }
        requestedStops.insert(service.id)
        supervisor.stop(serviceID: service.id)
        refreshPorts(after: .seconds(2))
        return ProjectActionResult(ok: true, message: "stopping \(project.name)/\(service.name)")
    }

    @discardableResult
    func restart(_ project: ProjectDefinition, service serviceSelector: String? = nil) -> ProjectActionResult {
        if let serviceSelector {
            guard let service = resolveService(serviceSelector, in: project) else {
                return ProjectActionResult(ok: false, message: "service not found: \(serviceSelector)")
            }

            guard supervisor.isRunning(serviceID: service.id) else {
                return startService(service, in: project)
            }

            let token = UUID()
            restartTokens[service.id] = token
            _ = stopService(service, in: project)
            waitForStopThenStart(project: project, service: service, token: token)
            return ProjectActionResult(ok: true, message: "restarting \(project.name)/\(service.name)")
        }

        guard project.effectiveServices.contains(where: { supervisor.isRunning(serviceID: $0.id) }) else {
            return start(project)
        }

        let token = UUID()
        restartTokens[project.id] = token
        _ = stop(project)
        waitForStopThenStart(project: project, token: token)
        return ProjectActionResult(ok: true, message: "restarting \(project.name)")
    }

    func openURL(for project: ProjectDefinition) {
        guard let service = firstServiceWithPort(in: project),
              let port = service.port ?? runtime(for: service).detectedPort else {
            return
        }

        openURL(port: port, exposeOnLocalNetwork: service.exposeOnLocalNetwork)
    }

    func openURL(for service: ProjectServiceDefinition) {
        guard let port = service.port ?? runtime(for: service).detectedPort else {
            return
        }

        openURL(port: port, exposeOnLocalNetwork: service.exposeOnLocalNetwork)
    }

    func openURL(port: Int, exposeOnLocalNetwork: Bool = false) {
        guard let url = URL(string: displayURL(port: port, exposeOnLocalNetwork: exposeOnLocalNetwork)) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func openRemoteURL(_ urlString: String) {
        guard let url = URL(string: urlString) else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    func displayURL(port: Int, exposeOnLocalNetwork: Bool) -> String {
        if exposeOnLocalNetwork, let networkURL = LocalNetwork.networkURL(port: port) {
            return networkURL
        }

        return LocalNetwork.localURL(port: port)
    }

    func openWorkingDirectory(_ project: ProjectDefinition) {
        NSWorkspace.shared.open(URL(fileURLWithPath: project.workingDirectory))
    }

    func openConfig() {
        do {
            try configStore.ensureExists()
            NSWorkspace.shared.open(configStore.configURL)
        } catch {
            errorMessage = "Config could not be opened: \(error.localizedDescription)"
        }
    }

    func upsert(_ project: ProjectDefinition) {
        do {
            if let index = projects.firstIndex(where: { $0.id == project.id }) {
                projects[index] = project
            } else {
                projects.append(project)
            }

            for service in project.effectiveServices where runtimes[service.id] == nil {
                runtimes[service.id] = ProjectRuntime()
            }

            try configStore.save(projects)
            refreshPorts()
            errorMessage = nil
        } catch {
            errorMessage = "Project could not be saved: \(error.localizedDescription)"
        }
    }

    func delete(_ project: ProjectDefinition) {
        if runtime(for: project).isRunning {
            stop(project)
        }

        do {
            projects.removeAll { $0.id == project.id }
            for service in project.effectiveServices {
                runtimes[service.id] = nil
            }
            try configStore.save(projects)
            refreshPorts()
            errorMessage = nil
        } catch {
            errorMessage = "Project could not be deleted: \(error.localizedDescription)"
        }
    }

    func remoteRuntime(for host: RemoteHostDefinition) -> RemoteHostRuntime {
        remoteHostRuntimes[host.id] ?? RemoteHostRuntime()
    }

    func upsert(_ host: RemoteHostDefinition) {
        do {
            if let index = remoteHosts.firstIndex(where: { $0.id == host.id }) {
                remoteHosts[index] = host
            } else {
                remoteHosts.append(host)
            }

            if remoteHostRuntimes[host.id] == nil {
                remoteHostRuntimes[host.id] = RemoteHostRuntime()
            }

            try remoteHostConfigStore.save(remoteHosts)
            errorMessage = nil
            refreshRemoteHosts()
        } catch {
            errorMessage = "Remote host could not be saved: \(error.localizedDescription)"
        }
    }

    func delete(_ host: RemoteHostDefinition) {
        do {
            remoteHosts.removeAll { $0.id == host.id }
            remoteHostRuntimes[host.id] = nil
            try remoteHostConfigStore.save(remoteHosts)
            errorMessage = nil
        } catch {
            errorMessage = "Remote host could not be deleted: \(error.localizedDescription)"
        }
    }

    func refreshRemoteHosts() {
        for host in remoteHosts where remoteHostRuntimes[host.id] == nil {
            remoteHostRuntimes[host.id] = RemoteHostRuntime()
        }

        let remoteIDs = Set(remoteHosts.map(\.id))
        remoteHostRuntimes = remoteHostRuntimes.filter { remoteIDs.contains($0.key) }

        for host in remoteHosts where host.isEnabled {
            refreshRemoteHost(host)
        }
    }

    func controlRemoteHost(_ host: RemoteHostDefinition, action: ControlAction, project: ControlProjectSnapshot) {
        guard let url = host.controlURL else {
            var runtime = remoteHostRuntimes[host.id] ?? RemoteHostRuntime()
            runtime.status = .failed
            runtime.errorMessage = "Invalid remote control URL"
            remoteHostRuntimes[host.id] = runtime
            return
        }

        var runtime = remoteHostRuntimes[host.id] ?? RemoteHostRuntime()
        runtime.status = .refreshing
        runtime.errorMessage = nil
        remoteHostRuntimes[host.id] = runtime

        Task { [weak self] in
            do {
                _ = try await LANStatusClient.sendControl(
                    ControlRequest(action: action, project: project.id.uuidString),
                    to: url,
                    token: host.token
                )
                try? await Task.sleep(for: .milliseconds(700))
                guard let statusURL = host.statusURL else {
                    throw LANRemoteAccessError.invalidHost(host.displayAddress)
                }
                let response = try await LANStatusClient.fetchStatus(from: statusURL, token: host.token)
                await MainActor.run {
                    self?.recordRemoteResponse(response, for: host)
                }
            } catch {
                await MainActor.run {
                    self?.recordRemoteError(error, for: host)
                }
            }
        }
    }

    func quit() {
        shutdown()
        NSApplication.shared.terminate(nil)
    }

    func shutdown() {
        remoteRefreshTask?.cancel()
        remoteRefreshTask = nil
        controlServer?.stop()
        controlServer = nil
        lanStatusServer?.stop()
        lanStatusServer = nil
        supervisor.stopAll()
    }

    func handleControl(_ request: ControlRequest) -> ControlResponse {
        switch request.action {
        case .ping:
            return ControlResponse(ok: true, message: "pong")

        case .reload:
            reload()
            return ControlResponse(ok: true, message: "reloaded", projects: snapshots())

        case .list, .status:
            return lanStatusResponse()

        case .config:
            return ControlResponse(ok: true, configPath: configPath)

        case .start:
            guard let project = resolveProject(request.project) else {
                return missingProjectResponse(for: request.project)
            }

            let result = start(project, service: request.service)
            return ControlResponse(ok: result.ok, message: result.message, projects: snapshots())

        case .stop:
            guard let project = resolveProject(request.project) else {
                return missingProjectResponse(for: request.project)
            }

            let result = stop(project, service: request.service)
            return ControlResponse(ok: result.ok, message: result.message, projects: snapshots())

        case .restart:
            guard let project = resolveProject(request.project) else {
                return missingProjectResponse(for: request.project)
            }

            let result = restart(project, service: request.service)
            return ControlResponse(ok: result.ok, message: result.message, projects: snapshots())

        case .open:
            guard let project = resolveProject(request.project) else {
                return missingProjectResponse(for: request.project)
            }

            if let serviceSelector = request.service {
                guard let service = resolveService(serviceSelector, in: project) else {
                    return ControlResponse(ok: false, message: "service not found: \(serviceSelector)", projects: snapshots())
                }
                openURL(for: service)
                return ControlResponse(ok: true, message: "opened \(project.name)/\(service.name)", projects: snapshots())
            }

            openURL(for: project)
            return ControlResponse(ok: true, message: "opened \(project.name)", projects: snapshots())

        case .quit:
            Task { @MainActor in
                self.quit()
            }
            return ControlResponse(ok: true, message: "quitting")
        }
    }

    func lanStatusResponse() -> ControlResponse {
        refreshPorts()
        refreshDetectedPorts()

        let address = LocalNetwork.preferredIPv4Address()
        let port = lanStatusServer?.port ?? LANRemoteAccess.configuredPort()
        let url = LANRemoteAccess.statusURL(address: address, port: port)
        lanStatusURL = url

        return ControlResponse(
            ok: true,
            projects: snapshots(),
            hostName: hostName(),
            hostAddress: address,
            lanStatusURL: url
        )
    }

    private func refreshRemoteHost(_ host: RemoteHostDefinition) {
        guard let url = host.statusURL else {
            remoteHostRuntimes[host.id] = RemoteHostRuntime(
                status: .failed,
                errorMessage: "Invalid remote host URL"
            )
            return
        }

        var runtime = remoteHostRuntimes[host.id] ?? RemoteHostRuntime()
        runtime.status = runtime.response == nil ? .refreshing : .online
        runtime.errorMessage = nil
        remoteHostRuntimes[host.id] = runtime

        Task { [weak self] in
            do {
                let response = try await LANStatusClient.fetchStatus(from: url, token: host.token)
                await MainActor.run {
                    self?.recordRemoteResponse(response, for: host)
                }
            } catch {
                await MainActor.run {
                    self?.recordRemoteError(error, for: host)
                }
            }
        }
    }

    private func recordRemoteResponse(_ response: ControlResponse, for host: RemoteHostDefinition) {
        guard remoteHosts.contains(where: { $0.id == host.id }) else {
            return
        }

        remoteHostRuntimes[host.id] = RemoteHostRuntime(
            status: .online,
            response: response,
            lastUpdated: Date(),
            errorMessage: response.ok ? nil : response.message
        )
    }

    private func recordRemoteError(_ error: Error, for host: RemoteHostDefinition) {
        guard remoteHosts.contains(where: { $0.id == host.id }) else {
            return
        }

        var runtime = remoteHostRuntimes[host.id] ?? RemoteHostRuntime()
        runtime.status = .failed
        runtime.errorMessage = error.localizedDescription
        remoteHostRuntimes[host.id] = runtime
    }

    private func startRemoteHostPolling() {
        remoteRefreshTask?.cancel()
        remoteRefreshTask = Task { [weak self] in
            while Task.isCancelled == false {
                await MainActor.run {
                    self?.refreshRemoteHosts()
                }
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func append(_ output: String, to serviceID: UUID) {
        var runtime = runtimes[serviceID] ?? ProjectRuntime()
        runtime.log += output

        if runtime.log.count > 12_000 {
            runtime.log = String(runtime.log.suffix(12_000))
        }

        runtimes[serviceID] = runtime
    }

    private func markExited(serviceID: UUID, exitCode: Int32) {
        startTokens[serviceID] = nil
        let serviceIDs = Set(projects.flatMap { $0.effectiveServices.map(\.id) })
        guard runtimes[serviceID] != nil || serviceIDs.contains(serviceID) else {
            requestedStops.remove(serviceID)
            return
        }

        var runtime = runtimes[serviceID] ?? ProjectRuntime()
        let wasRequestedStop = requestedStops.remove(serviceID) != nil
        runtime.status = exitCode == 0 || wasRequestedStop ? .stopped : .failed
        runtime.pid = nil
        runtime.detectedPort = nil
        runtime.lastExitCode = wasRequestedStop ? nil : exitCode
        runtimes[serviceID] = runtime
        refreshPorts(after: .milliseconds(250))
    }

    private func resolveProject(_ selector: String?) -> ProjectDefinition? {
        guard let selector = selector?.trimmingCharacters(in: .whitespacesAndNewlines),
              selector.isEmpty == false else {
            return nil
        }

        if let id = UUID(uuidString: selector),
           let project = projects.first(where: { $0.id == id }) {
            return project
        }

        if let exact = projects.first(where: { $0.name == selector }) {
            return exact
        }

        return projects.first {
            $0.name.localizedCaseInsensitiveContains(selector)
        }
    }

    private func resolveService(_ selector: String, in project: ProjectDefinition) -> ProjectServiceDefinition? {
        let selector = selector.trimmingCharacters(in: .whitespacesAndNewlines)
        guard selector.isEmpty == false else {
            return nil
        }

        if let id = UUID(uuidString: selector),
           let service = project.effectiveServices.first(where: { $0.id == id }) {
            return service
        }

        if let exact = project.effectiveServices.first(where: { $0.name == selector }) {
            return exact
        }

        return project.effectiveServices.first {
            $0.name.localizedCaseInsensitiveContains(selector)
        }
    }

    private func missingProjectResponse(for selector: String?) -> ControlResponse {
        let message: String
        if let selector, selector.isEmpty == false {
            message = "project not found: \(selector)"
        } else {
            message = "project is required"
        }

        return ControlResponse(ok: false, message: message, projects: snapshots())
    }

    private func startLANStatusServer() {
        do {
            let token = try LANRemoteAccess.ensureToken()
            let server = LANStatusServer(
                store: self,
                token: token,
                port: LANRemoteAccess.configuredPort()
            )
            try server.start()
            lanStatusServer = server
            lanStatusURL = server.statusURL
        } catch {
            errorMessage = "LAN status server could not start: \(error.localizedDescription)"
        }
    }

    private func hostName() -> String {
        Host.current().localizedName ?? ProcessInfo.processInfo.hostName
    }

    private func snapshots() -> [ControlProjectSnapshot] {
        let networkAddress = LocalNetwork.preferredIPv4Address()

        return projects.map { project in
            let projectRuntime = runtime(for: project)
            let firstService = project.effectiveServices.first
            let legacyCommand = firstService?.command ?? project.command
            let legacyPort = firstService?.port ?? project.port
            let effectivePort = legacyPort ?? projectRuntime.detectedPort
            let portPids = effectivePort.flatMap { portListeners[$0]?.pids } ?? []
            let projectExposesLocalNetwork = firstService?.exposeOnLocalNetwork ?? project.exposeOnLocalNetwork
            let projectLocalURL = effectivePort.map(LocalNetwork.localURL(port:))
            let projectNetworkURL = effectivePort.flatMap { port in
                projectExposesLocalNetwork ? localNetworkURL(port: port, address: networkAddress) : nil
            }
            let serviceSnapshots = project.effectiveServices.map { service in
                let serviceRuntime = runtime(for: service)
                let servicePort = service.port ?? serviceRuntime.detectedPort
                let servicePortPids = servicePort.flatMap { portListeners[$0]?.pids } ?? []
                let localURL = servicePort.map(LocalNetwork.localURL(port:))
                let networkURL = servicePort.flatMap { port in
                    service.exposeOnLocalNetwork ? localNetworkURL(port: port, address: networkAddress) : nil
                }

                return ControlServiceSnapshot(
                    id: service.id,
                    name: service.name,
                    command: service.command,
                    port: service.port,
                    detectedPort: serviceRuntime.detectedPort,
                    exposeOnLocalNetwork: service.exposeOnLocalNetwork,
                    localURL: localURL,
                    networkURL: networkURL,
                    status: serviceRuntime.status,
                    pid: serviceRuntime.pid,
                    startedAt: serviceRuntime.startedAt,
                    lastExitCode: serviceRuntime.lastExitCode,
                    recentLog: recentLog(from: serviceRuntime.log),
                    portPids: servicePortPids
                )
            }

            return ControlProjectSnapshot(
                id: project.id,
                name: project.name,
                workingDirectory: project.workingDirectory,
                command: legacyCommand,
                port: legacyPort,
                detectedPort: projectRuntime.detectedPort,
                exposeOnLocalNetwork: projectExposesLocalNetwork,
                localURL: projectLocalURL,
                networkURL: projectNetworkURL,
                status: projectRuntime.status,
                pid: projectRuntime.pid,
                startedAt: projectRuntime.startedAt,
                lastExitCode: projectRuntime.lastExitCode,
                recentLog: recentLog(from: projectRuntime.log),
                portPids: portPids,
                services: serviceSnapshots
            )
        }
    }

    private func recentLog(from log: String) -> String? {
        let trimmed = log.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return nil
        }

        let lines = trimmed
            .split(separator: "\n", omittingEmptySubsequences: false)
            .suffix(4)

        return lines.joined(separator: "\n")
    }

    private func firstServiceWithPort(in project: ProjectDefinition) -> ProjectServiceDefinition? {
        project.effectiveServices.first { service in
            service.port != nil || runtime(for: service).detectedPort != nil
        }
    }

    private func localNetworkURL(port: Int, address: String?) -> String? {
        address.map { "http://\($0):\(port)" }
    }

    private func refreshPorts(after delay: Duration = .zero) {
        let ports = Set(projects.flatMap { $0.effectiveServices.compactMap(\.port) })
        guard !ports.isEmpty else {
            portListeners = [:]
            return
        }

        if delay == .zero {
            portListeners = inspectPorts(ports)
            return
        }

        Task {
            try? await Task.sleep(for: delay)

            portListeners = inspectPorts(ports)
        }
    }

    private func monitorStartup(project: ProjectDefinition, service: ProjectServiceDefinition, port: Int, token: UUID) {
        Task { @MainActor in
            let deadline = Date().addingTimeInterval(startupTimeout)

            while Date() < deadline {
                guard startTokens[service.id] == token else {
                    return
                }

                guard supervisor.isRunning(serviceID: service.id) else {
                    return
                }

                if let listener = PortInspector.listener(on: port), listener.isOccupied {
                    portListeners[port] = listener

                    let managedPIDs = supervisor.managedPIDs(for: service.id)
                    if listener.pids.contains(where: managedPIDs.contains) {
                        updateRuntime(for: service.id) { runtime in
                            runtime.status = .running
                            runtime.detectedPort = port
                        }
                        startTokens[service.id] = nil
                        return
                    }

                    updateRuntime(for: service.id) { runtime in
                        runtime.status = .failed
                    }
                    append("Port \(port) was taken by unrelated pid(s): \(listener.pids.map(String.init).joined(separator: ", "))\n", to: service.id)
                    supervisor.stop(serviceID: service.id)
                    return
                }

                try? await Task.sleep(for: .milliseconds(250))
            }

            guard startTokens[service.id] == token else {
                return
            }

            startTokens[service.id] = nil
            updateRuntime(for: service.id) { runtime in
                runtime.status = .failed
            }
            append("Timed out waiting for localhost:\(port) to listen.\n", to: service.id)
            supervisor.stop(serviceID: service.id)
        }
    }

    private func waitForStopThenStart(project: ProjectDefinition, token: UUID) {
        Task { @MainActor in
            let deadline = Date().addingTimeInterval(restartTimeout)

            while project.effectiveServices.contains(where: { supervisor.isRunning(serviceID: $0.id) }), Date() < deadline {
                try? await Task.sleep(for: .milliseconds(250))
            }

            guard restartTokens[project.id] == token else {
                return
            }

            restartTokens[project.id] = nil

            guard project.effectiveServices.contains(where: { supervisor.isRunning(serviceID: $0.id) }) == false else {
                for service in project.effectiveServices {
                    updateRuntime(for: service.id) { runtime in
                        runtime.status = .failed
                    }
                }
                for service in project.effectiveServices {
                    append("Timed out waiting for process to stop before restart.\n", to: service.id)
                }
                return
            }

            _ = start(project)
        }
    }

    private func waitForStopThenStart(project: ProjectDefinition, service: ProjectServiceDefinition, token: UUID) {
        Task { @MainActor in
            let deadline = Date().addingTimeInterval(restartTimeout)

            while supervisor.isRunning(serviceID: service.id), Date() < deadline {
                try? await Task.sleep(for: .milliseconds(250))
            }

            guard restartTokens[service.id] == token else {
                return
            }

            restartTokens[service.id] = nil

            guard supervisor.isRunning(serviceID: service.id) == false else {
                updateRuntime(for: service.id) { runtime in
                    runtime.status = .failed
                }
                append("Timed out waiting for process to stop before restart.\n", to: service.id)
                return
            }

            _ = startService(service, in: project)
        }
    }

    private func detectManagedPort(for serviceID: UUID, attempts: Int = 40) {
        Task { @MainActor in
            for _ in 0..<attempts {
                guard supervisor.isRunning(serviceID: serviceID) else {
                    return
                }

                if updateDetectedPort(for: serviceID) {
                    return
                }

                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    private func refreshDetectedPorts() {
        for service in projects.flatMap(\.effectiveServices) where supervisor.isRunning(serviceID: service.id) {
            _ = updateDetectedPort(for: service.id)
        }
    }

    private func updateDetectedPort(for serviceID: UUID) -> Bool {
        let listeners = PortInspector.listeners(forPIDs: supervisor.managedPIDs(for: serviceID))
        guard let listener = listeners.first else {
            return false
        }

        updateRuntime(for: serviceID) { runtime in
            runtime.detectedPort = listener.port
        }
        portListeners[listener.port] = listener
        return true
    }

    private func inspectPorts(_ ports: Set<Int>) -> [Int: PortListener] {
        var listeners: [Int: PortListener] = [:]
        for port in ports {
            if let listener = PortInspector.listener(on: port), listener.isOccupied {
                listeners[port] = listener
            }
        }

        return listeners
    }

    private func aggregateStatus(_ statuses: [ProjectStatus]) -> ProjectStatus {
        if statuses.contains(.failed) {
            return .failed
        }
        if statuses.contains(.stopping) {
            return .stopping
        }
        if statuses.contains(.starting) {
            return .starting
        }
        if statuses.contains(.running) {
            return .running
        }

        return .stopped
    }

    private func updateRuntime(for serviceID: UUID, _ update: (inout ProjectRuntime) -> Void) {
        var runtime = runtimes[serviceID] ?? ProjectRuntime()
        update(&runtime)
        runtimes[serviceID] = runtime
    }
}

enum RemoteHostConnectionStatus: Sendable {
    case idle
    case refreshing
    case online
    case failed
}

struct RemoteHostRuntime: Sendable {
    var status: RemoteHostConnectionStatus = .idle
    var response: ControlResponse?
    var lastUpdated: Date?
    var errorMessage: String?
}

struct ProjectActionResult {
    var ok: Bool
    var message: String
}
