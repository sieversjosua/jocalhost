import AppKit
import LocalhostCore
import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject private var store: ProjectStore
    @State private var editedRemoteHost: RemoteHostDefinition?
    @State private var isShowingRemoteHostEditor = false
    @StateObject private var configWindowPresenter = ProjectConfigWindowPresenter()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if let errorMessage = store.errorMessage {
                errorBanner(errorMessage)
            }

            popoverDivider

            VStack(alignment: .leading, spacing: 12) {
                if store.projects.isEmpty && store.remoteHosts.isEmpty {
                    emptyState
                } else {
                    serverList
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            popoverDivider

            footer
        }
        .frame(width: 480)
        .background(JocalhostColors.popoverBackground)
        .sheet(isPresented: $isShowingRemoteHostEditor) {
            RemoteHostEditorView(host: editedRemoteHost)
                .environmentObject(store)
        }
        .environment(\.colorScheme, .light)
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(JocalhostColors.subtleBlue)
                    .frame(width: 34, height: 34)

                Image(systemName: store.anyRunning ? "play.fill" : "terminal")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(JocalhostColors.brandBlue)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("jocalhost")
                    .font(.headline)
                    .foregroundStyle(JocalhostColors.text)

                Text(headerSubtitle)
                    .font(.caption)
                    .foregroundStyle(JocalhostColors.mutedText)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                showVisualConfig(startsAddingProject: true)
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(JocalhostColors.mutedText)
            .controlSize(.small)
            .help("Add project")

            Button {
                editedRemoteHost = nil
                isShowingRemoteHostEditor = true
            } label: {
                Image(systemName: "link")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(JocalhostColors.mutedText)
            .controlSize(.small)
            .help("Add remote host")

            Button {
                store.reload()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(JocalhostColors.mutedText)
            .controlSize(.small)
            .help("Reload projects")
        }
        .padding(14)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "tray")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(JocalhostColors.brandBlue)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 4) {
                    Text("No projects configured")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(JocalhostColors.text)

                    Text("Add a local project or connect a remote jocalhost host.")
                        .font(.caption)
                        .foregroundStyle(JocalhostColors.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Config")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(JocalhostColors.mutedText)

                Text(store.configPath)
                    .font(.caption2.monospaced())
                    .foregroundStyle(JocalhostColors.mutedText)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

            HStack {
                Button {
                    showVisualConfig(startsAddingProject: true)
                } label: {
                    Label("Add Local Project", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(JocalhostColors.brandBlue)

                Button {
                    showVisualConfig()
                } label: {
                    Label("Projects", systemImage: "slider.horizontal.3")
                }

                Button {
                    editedRemoteHost = nil
                    isShowingRemoteHostEditor = true
                } label: {
                    Label("Add Remote", systemImage: "link")
                }
            }
            .controlSize(.small)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(JocalhostColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var serverList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if store.projects.isEmpty == false {
                    SectionHeader(title: "Local", systemImage: "desktopcomputer")

                    LazyVStack(spacing: 10) {
                        ForEach(store.projects) { project in
                            ProjectRowView(project: project) {
                                showVisualConfig(selectedProjectID: project.id)
                            }
                        }
                    }
                }

                if store.remoteHosts.isEmpty == false {
                    SectionHeader(title: "Remote", systemImage: "network")

                    LazyVStack(spacing: 10) {
                        ForEach(store.remoteHosts) { host in
                            RemoteHostRowView(host: host) {
                                editedRemoteHost = host
                                isShowingRemoteHostEditor = true
                            }
                        }
                    }
                }
            }
        }
        .frame(maxHeight: 430)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    showVisualConfig()
                } label: {
                    Label("Projects", systemImage: "slider.horizontal.3")
                }
                .foregroundStyle(JocalhostColors.text)

                Spacer()

                Button {
                    store.quit()
                } label: {
                    Label("Quit", systemImage: "xmark.circle")
                }
                .foregroundStyle(JocalhostColors.mutedText)
                .help("Quit jocalhost")
            }

            if let lanStatusURL = store.lanStatusURL {
                HStack(spacing: 6) {
                    Image(systemName: "network")
                        .font(.caption2.weight(.semibold))
                    Text(lanStatusURL)
                        .font(.caption2.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                    Button {
                        store.copyRemoteSetupCommand()
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .help("Copy remote setup command")
                }
                .foregroundStyle(JocalhostColors.mutedText)
                .help("LAN status/control endpoint")
            }
        }
        .controlSize(.small)
        .padding(14)
    }

    private var runningCount: Int {
        store.projects.filter { store.runtime(for: $0).status == .running }.count +
            store.remoteHostRuntimes.values.reduce(0) { count, runtime in
                count + (runtime.response?.projects.filter { $0.status == .running }.count ?? 0)
            }
    }

    private var headerSubtitle: String {
        if store.projects.isEmpty && store.remoteHosts.isEmpty {
            return "No projects configured"
        }

        let remoteProjectCount = store.remoteHostRuntimes.values.reduce(0) { count, runtime in
            count + (runtime.response?.projects.count ?? 0)
        }
        let total = store.projects.count + remoteProjectCount
        let noun = total == 1 ? "project" : "projects"
        let hostCount = (store.projects.isEmpty ? 0 : 1) + store.remoteHosts.count
        let remoteSuffix = store.remoteHosts.isEmpty ? "" : " across \(hostCount) hosts"
        return "\(runningCount) running / \(total) \(noun)\(remoteSuffix)"
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(JocalhostColors.danger)

            Text(message)
                .font(.caption)
                .foregroundStyle(JocalhostColors.danger)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
        .padding(.top, 2)
        .background(JocalhostColors.danger.opacity(0.18))
    }

    private var popoverDivider: some View {
        Rectangle()
            .fill(JocalhostColors.separator)
            .frame(height: 1)
    }

    private func showVisualConfig(selectedProjectID: UUID? = nil, startsAddingProject: Bool = false) {
        store.reload()
        configWindowPresenter.show(
            store: store,
            selectedProjectID: selectedProjectID,
            startsAddingProject: startsAddingProject
        )
    }
}

struct ProjectRowView: View {
    @EnvironmentObject private var store: ProjectStore
    let project: ProjectDefinition
    let onEdit: () -> Void

    var body: some View {
        let runtime = store.runtime(for: project)
        let portListener = store.portListener(for: project)
        let services = project.effectiveServices
        let urlService = services.first { service in
            service.port != nil || store.runtime(for: service).detectedPort != nil
        }
        let effectivePort = urlService.flatMap { service in
            store.runtime(for: service).effectivePort(preferredPort: service.port)
        }

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                StatusIndicator(status: runtime.status)
                    .padding(.top, 3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(JocalhostColors.text)
                        .lineLimit(1)

                    Text(statusText(runtime: runtime))
                        .font(.caption)
                        .foregroundStyle(JocalhostColors.mutedText)
                        .lineLimit(1)
                }

                Spacer()

                rowActions(runtime: runtime)
            }

            if let port = effectivePort {
                ProjectURLLauncher(
                    url: store.displayURL(
                        port: port,
                        exposeOnLocalNetwork: urlService?.exposeOnLocalNetwork == true
                    ),
                    isRunning: runtime.status == .running
                ) {
                    store.openURL(
                        port: port,
                        exposeOnLocalNetwork: urlService?.exposeOnLocalNetwork == true
                    )
                }
                if let urlService,
                   let preferredPort = urlService.port,
                   let detectedPort = store.runtime(for: urlService).detectedPort,
                   detectedPort != preferredPort {
                    WarningLine(text: "Using port \(detectedPort); preferred \(preferredPort) is unavailable.")
                }
            } else if runtime.isRunning {
                URLDetectionPendingLine()
            }

            if services.count > 1 {
                serviceList(services)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    DetailLine(icon: "terminal", text: services.first?.command ?? project.command)
                    DetailLine(icon: "folder", text: project.workingDirectory)
                }
            }

            if let portListener, runtime.isRunning == false {
                WarningLine(text: "Port \(portListener.port) is already in use by pid(s): \(portListener.pids.map(String.init).joined(separator: ", "))")
            }

            if !runtime.log.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recent Output")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(JocalhostColors.mutedText)

                    Text(lastLogLines(runtime.log))
                        .font(.caption2.monospaced())
                        .foregroundStyle(JocalhostColors.mutedText)
                        .lineLimit(4)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(8)
                .background(JocalhostColors.codeBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(12)
        .background(JocalhostColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func serviceList(_ services: [ProjectServiceDefinition]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(services) { service in
                let runtime = store.runtime(for: service)
                let effectivePort = runtime.effectivePort(preferredPort: service.port)

                HStack(spacing: 8) {
                    StatusIndicator(status: runtime.status)
                        .scaleEffect(0.72)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(service.name)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(JocalhostColors.text)

                            if let effectivePort {
                                Text(":\(effectivePort)")
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(JocalhostColors.mutedText)
                            }
                        }

                        Text(service.command)
                            .font(.caption2.monospaced())
                            .foregroundStyle(JocalhostColors.mutedText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer()

                    if runtime.isRunning {
                        Button(role: .destructive) {
                            _ = store.stop(project, service: service.name)
                        } label: {
                            Image(systemName: "stop.fill")
                        }
                        .buttonStyle(.borderless)
                        .help("Stop \(service.name)")
                    } else {
                        Button {
                            _ = store.start(project, service: service.name)
                        } label: {
                            Image(systemName: "play.fill")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(JocalhostColors.brandBlue)
                        .help("Start \(service.name)")
                    }
                }
                .padding(8)
                .background(JocalhostColors.codeBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    @ViewBuilder
    private func rowActions(runtime: ProjectRuntime) -> some View {
        HStack(spacing: 6) {
            Button {
                store.openWorkingDirectory(project)
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(JocalhostColors.mutedText)
            .help("Open project folder")

            Button {
                onEdit()
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(JocalhostColors.mutedText)
            .help("Edit project")

            if runtime.isRunning {
                Button(role: .destructive) {
                    _ = store.stop(project)
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .help("Stop project")
            } else {
                Button {
                    _ = store.start(project)
                } label: {
                    Label("Start", systemImage: "play.fill")
                }
                .tint(JocalhostColors.brandBlue)
                .buttonStyle(.borderedProminent)
                .help("Start project")
            }
        }
        .controlSize(.small)
    }

    private func statusText(runtime: ProjectRuntime) -> String {
        var parts = [statusTitle(runtime.status)]

        if let pid = runtime.pid {
            parts.append("pid \(pid)")
        }

        if let port = runtime.effectivePort(preferredPort: project.port) {
            parts.append("port \(port)")
        }

        if let exitCode = runtime.lastExitCode {
            parts.append("exit \(exitCode)")
        }

        return parts.joined(separator: " - ")
    }

    private func lastLogLines(_ log: String) -> String {
        log
            .split(separator: "\n", omittingEmptySubsequences: false)
            .suffix(4)
            .joined(separator: "\n")
    }
}

private struct SectionHeader: View {
    var title: String
    var systemImage: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
            Text(title)
                .font(.caption.weight(.semibold))
            Spacer()
        }
        .foregroundStyle(JocalhostColors.mutedText)
        .padding(.horizontal, 2)
    }
}

struct RemoteHostRowView: View {
    @EnvironmentObject private var store: ProjectStore
    let host: RemoteHostDefinition
    let onEdit: () -> Void

    var body: some View {
        let runtime = store.remoteRuntime(for: host)
        let projects = runtime.response?.projects ?? []

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                ConnectionIndicator(status: runtime.status)
                    .padding(.top, 3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(host.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(JocalhostColors.text)
                        .lineLimit(1)

                    Text(remoteSubtitle(runtime: runtime, projectCount: projects.count))
                        .font(.caption)
                        .foregroundStyle(JocalhostColors.mutedText)
                        .lineLimit(1)
                }

                Spacer()

                HStack(spacing: 6) {
                    Button {
                        store.refreshRemoteHosts()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(JocalhostColors.mutedText)
                    .help("Refresh remote hosts")

                    Button {
                        onEdit()
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(JocalhostColors.mutedText)
                    .help("Edit remote host")
                }
                .controlSize(.small)
            }

            if let errorMessage = runtime.errorMessage,
               runtime.status == .failed {
                WarningLine(text: errorMessage)
            }

            if host.isEnabled == false {
                DetailLine(icon: "pause.circle", text: "Remote host is disabled")
            } else if projects.isEmpty {
                DetailLine(icon: "network", text: emptyRemoteStatusText(runtime.status))
            } else {
                VStack(spacing: 6) {
                    ForEach(projects, id: \.id) { project in
                        RemoteProjectLine(host: host, project: project)
                    }
                }
            }
        }
        .padding(12)
        .background(JocalhostColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func remoteSubtitle(runtime: RemoteHostRuntime, projectCount: Int) -> String {
        if let response = runtime.response {
            let hostLabel = response.hostName ?? response.hostAddress ?? host.displayAddress
            let noun = projectCount == 1 ? "project" : "projects"
            if let lastUpdated = runtime.lastUpdated {
                return "\(hostLabel) - \(projectCount) \(noun) - \(lastUpdated.formatted(date: .omitted, time: .shortened))"
            }
            return "\(hostLabel) - \(projectCount) \(noun)"
        }

        switch runtime.status {
        case .idle:
            return host.displayAddress
        case .refreshing:
            return "Connecting to \(host.displayAddress)"
        case .online:
            return host.displayAddress
        case .failed:
            return "Could not reach \(host.displayAddress)"
        }
    }

}

private struct RemoteProjectLine: View {
    @EnvironmentObject private var store: ProjectStore
    var host: RemoteHostDefinition
    var project: ControlProjectSnapshot

    var body: some View {
        let url = preferredURL(for: project)
        let shouldStop = project.status == .starting || project.status == .running || project.status == .stopping
        let canOpen = project.status == .running && url != nil

        HStack(spacing: 8) {
            StatusIndicator(status: project.status)
                .scaleEffect(0.72)

            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(JocalhostColors.text)
                    .lineLimit(1)

                Text(detailText(url: url, project: project))
                    .font(.caption2.monospaced())
                    .foregroundStyle(JocalhostColors.mutedText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button {
                store.controlRemoteHost(host, action: shouldStop ? .stop : .start, project: project)
            } label: {
                Image(systemName: shouldStop ? "stop.fill" : "play.fill")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(shouldStop ? JocalhostColors.danger : JocalhostColors.brandBlue)
            .help(shouldStop ? "Stop remote project" : "Start remote project")

            Button {
                store.controlRemoteHost(host, action: .restart, project: project)
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(JocalhostColors.mutedText)
            .help("Restart remote project")

            Button {
                if let url {
                    store.openRemoteURL(url)
                }
            } label: {
                Image(systemName: "arrow.up.right")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(canOpen ? JocalhostColors.brandBlue : JocalhostColors.mutedText)
            .disabled(canOpen == false)
            .help(canOpen ? "Open \(url ?? "")" : "Start the remote project before opening the preview")
        }
        .padding(8)
        .background(JocalhostColors.codeBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func preferredURL(for project: ControlProjectSnapshot) -> String? {
        project.networkURL ?? project.services.first { service in
            service.networkURL != nil
        }?.networkURL
    }

    private func detailText(url: String?, project: ControlProjectSnapshot) -> String {
        switch project.status {
        case .failed:
            if let line = lastLogLine(project.recentLog) {
                return "Failed - \(line)"
            }

            if let code = project.lastExitCode {
                return "Failed - exit \(code)"
            }

            return "Failed"

        case .starting where project.workingDirectory.contains("/Documents/"):
            return "Starting - Full Disk Access may be required"

        case .starting:
            if let port = project.detectedPort ?? project.port {
                return "Starting - waiting for port \(port)"
            }

            return "Starting"

        default:
            return url ?? "No LAN URL"
        }
    }

    private func lastLogLine(_ log: String?) -> String? {
        guard let log,
              let line = log.split(whereSeparator: \.isNewline).last else {
            return nil
        }

        let trimmed = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct StatusIndicator: View {
    var status: ProjectStatus

    var body: some View {
        ZStack {
            Circle()
                .fill(statusColor(status).opacity(0.14))
                .frame(width: 18, height: 18)

            Circle()
                .fill(statusColor(status))
                .frame(width: 8, height: 8)
        }
        .help(statusTitle(status))
    }
}

private struct ConnectionIndicator: View {
    var status: RemoteHostConnectionStatus

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.14))
                .frame(width: 18, height: 18)

            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
        }
        .help(title)
    }

    private var color: Color {
        switch status {
        case .idle:
            .secondary
        case .refreshing:
            JocalhostColors.brandBlue.opacity(0.72)
        case .online:
            JocalhostColors.runningGreen
        case .failed:
            JocalhostColors.danger
        }
    }

    private var title: String {
        switch status {
        case .idle:
            "Idle"
        case .refreshing:
            "Refreshing"
        case .online:
            "Online"
        case .failed:
            "Failed"
        }
    }
}

private struct ProjectURLLauncher: View {
    var url: String
    var isRunning: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: isRunning ? "safari.fill" : "safari")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isRunning ? .white : JocalhostColors.brandBlue)
                    .frame(width: 16)

                Text(url)
                    .font(.caption.monospaced().weight(.medium))
                    .foregroundStyle(isRunning ? .white : JocalhostColors.mutedText)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 8)

                Text(isRunning ? "Open" : "Not running")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isRunning ? .white.opacity(0.92) : JocalhostColors.mutedText)

                Image(systemName: "arrow.up.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(isRunning ? .white.opacity(0.92) : JocalhostColors.mutedText)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background)
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(borderColor, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .disabled(isRunning == false)
        .help(isRunning ? "Open \(url)" : "\(url) is available when the project is running")
    }

    private var background: Color {
        isRunning ? JocalhostColors.brandBlue : JocalhostColors.subtleBlue
    }

    private var borderColor: Color {
        isRunning ? JocalhostColors.brandBlue.opacity(0.65) : JocalhostColors.brandBlue.opacity(0.16)
    }
}

private struct URLDetectionPendingLine: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "network")
                .font(.caption.weight(.semibold))
                .foregroundStyle(JocalhostColors.brandBlue)
                .frame(width: 16)

            Text("Detecting localhost URL...")
                .font(.caption.monospaced().weight(.medium))
                .foregroundStyle(JocalhostColors.mutedText)

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(JocalhostColors.subtleBlue)
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(JocalhostColors.brandBlue.opacity(0.16), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

private struct DetailLine: View {
    var icon: String
    var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(JocalhostColors.mutedText)
                .frame(width: 14)

            Text(text)
                .font(.caption2.monospaced())
                .foregroundStyle(JocalhostColors.mutedText)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

private struct WarningLine: View {
    var text: String

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(JocalhostColors.warning)
                .frame(width: 14)

            Text(text)
                .font(.caption2.monospaced())
                .foregroundStyle(JocalhostColors.warning)
                .lineLimit(2)
        }
    }
}

private func emptyRemoteStatusText(_ status: RemoteHostConnectionStatus) -> String {
    switch status {
    case .idle:
        return "Remote status has not been loaded yet"
    case .refreshing:
        return "Loading remote projects"
    case .online:
        return "No projects configured on remote host"
    case .failed:
        return "Remote status unavailable"
    }
}

private func statusColor(_ status: ProjectStatus) -> Color {
    switch status {
    case .stopped:
        .secondary
    case .starting:
        JocalhostColors.brandBlue.opacity(0.72)
    case .running:
        JocalhostColors.runningGreen
    case .stopping:
        JocalhostColors.brandBlue.opacity(0.55)
    case .failed:
        JocalhostColors.danger
    }
}

private enum JocalhostColors {
    static let brandBlue = Color(red: 43 / 255, green: 127 / 255, blue: 255 / 255)
    static let popoverBackground = Color(red: 246 / 255, green: 248 / 255, blue: 251 / 255)
    static let subtleBlue = Color(red: 232 / 255, green: 242 / 255, blue: 255 / 255)
    static let cardBackground = Color.white
    static let codeBackground = Color(red: 242 / 255, green: 244 / 255, blue: 247 / 255)
    static let separator = Color(nsColor: .separatorColor)
    static let configWindowBackground = Color(nsColor: .windowBackgroundColor)
    static let configPanelBackground = Color(nsColor: .controlBackgroundColor)
    static let configSelectedBackground = Color(nsColor: .selectedContentBackgroundColor).opacity(0.18)
    static let configSelectedBorder = Color(nsColor: .selectedContentBackgroundColor).opacity(0.45)
    static let text = Color.primary
    static let mutedText = Color.secondary
    static let runningGreen = Color(red: 22 / 255, green: 163 / 255, blue: 74 / 255)
    static let warning = Color(red: 146 / 255, green: 64 / 255, blue: 14 / 255)
    static let danger = Color(red: 185 / 255, green: 28 / 255, blue: 28 / 255)
}

private func statusTitle(_ status: ProjectStatus) -> String {
    switch status {
    case .stopped:
        "Stopped"
    case .starting:
        "Starting"
    case .running:
        "Running"
    case .stopping:
        "Stopping"
    case .failed:
        "Failed"
    }
}

private struct ProjectDraft {
    var id: UUID
    var name: String
    var workingDirectory: String
    var command: String
    var port: String
    var exposeOnLocalNetwork: Bool
    var services: [ProjectServiceDraft]

    init(project: ProjectDefinition?) {
        self.id = project?.id ?? UUID()
        self.name = project?.name ?? ""
        self.workingDirectory = project?.workingDirectory ?? ""
        self.command = project?.command ?? "npm run dev"
        self.port = project?.port.map(String.init) ?? ""
        self.exposeOnLocalNetwork = project?.exposeOnLocalNetwork ?? false
        self.services = project?.services.map(ProjectServiceDraft.init(service:)) ?? []
    }
}

private struct ProjectServiceDraft: Identifiable {
    var id: UUID
    var name: String
    var command: String
    var port: String
    var exposeOnLocalNetwork: Bool

    init(id: UUID = UUID(), name: String, command: String, port: String = "", exposeOnLocalNetwork: Bool = false) {
        self.id = id
        self.name = name
        self.command = command
        self.port = port
        self.exposeOnLocalNetwork = exposeOnLocalNetwork
    }

    init(service: ProjectServiceDefinition) {
        self.id = service.id
        self.name = service.name
        self.command = service.command
        self.port = service.port.map(String.init) ?? ""
        self.exposeOnLocalNetwork = service.exposeOnLocalNetwork
    }

    init(detection: ProjectServiceDetection) {
        self.id = UUID()
        self.name = detection.name
        self.command = detection.command
        self.port = detection.port.map(String.init) ?? ""
        self.exposeOnLocalNetwork = false
    }

    func makeService() -> ProjectServiceDefinition? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPort = port.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmedName.isEmpty == false, trimmedCommand.isEmpty == false else {
            return nil
        }

        return ProjectServiceDefinition(
            id: id,
            name: trimmedName,
            command: trimmedCommand,
            port: trimmedPort.isEmpty ? nil : Int(trimmedPort),
            exposeOnLocalNetwork: exposeOnLocalNetwork
        )
    }
}

private struct RemoteHostDraft {
    var id: UUID
    var name: String
    var host: String
    var port: String
    var token: String
    var isEnabled: Bool

    init(host: RemoteHostDefinition?) {
        self.id = host?.id ?? UUID()
        self.name = host?.name ?? ""
        self.host = host?.host ?? ""
        self.port = host.map { String($0.port) } ?? String(LANRemoteAccess.defaultPort)
        self.token = host?.token ?? ""
        self.isEnabled = host?.isEnabled ?? true
    }
}

@MainActor
private final class ProjectConfigWindowPresenter: NSObject, ObservableObject, NSWindowDelegate {
    private var window: NSWindow?

    func show(store: ProjectStore, selectedProjectID: UUID? = nil, startsAddingProject: Bool = false) {
        if let window {
            if selectedProjectID == nil && startsAddingProject == false {
                center(window)
                window.makeKeyAndOrderFront(nil)
                NSApplication.shared.activate(ignoringOtherApps: true)
                return
            }

            window.close()
            self.window = nil
        }

        let hostingController = NSHostingController(
            rootView: ProjectConfigView(
                initialProjectID: selectedProjectID,
                startsAddingProject: startsAddingProject
            ) { [weak self] in
                self?.window?.close()
            }
            .environmentObject(store)
        )
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Projects"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.contentMinSize = NSSize(width: 820, height: 600)
        window.isReleasedWhenClosed = false
        window.delegate = self

        self.window = window
        center(window)
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }

    private func center(_ window: NSWindow) {
        guard let screen = NSApplication.shared.keyWindow?.screen ?? NSScreen.main else {
            window.center()
            return
        }

        let visibleFrame = screen.visibleFrame
        let frame = window.frame
        window.setFrameOrigin(
            NSPoint(
                x: visibleFrame.midX - frame.width / 2,
                y: visibleFrame.midY - frame.height / 2
            )
        )
    }
}

struct ProjectConfigView: View {
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.dismiss) private var dismiss

    private let initialProjectID: UUID?
    private let startsAddingProject: Bool
    private let onDone: (() -> Void)?

    @State private var selectedProjectID: UUID?
    @State private var draft = ProjectDraft(project: nil)
    @State private var detectionMessage: String?
    @State private var convexCommandSuggestion: String?
    @State private var pendingDeleteProject: ProjectDefinition?
    @State private var isAddingProject: Bool

    init(
        initialProjectID: UUID? = nil,
        startsAddingProject: Bool = false,
        onDone: (() -> Void)? = nil
    ) {
        self.initialProjectID = initialProjectID
        self.startsAddingProject = startsAddingProject
        self.onDone = onDone
        self._selectedProjectID = State(initialValue: initialProjectID)
        self._isAddingProject = State(initialValue: startsAddingProject)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            HStack(spacing: 0) {
                sidebar

                Divider()

                editor
            }

            Divider()

            footer
        }
        .frame(width: 820, height: 600)
        .background(JocalhostColors.configWindowBackground)
        .onAppear(perform: applyInitialSelection)
        .onChange(of: store.projects) { _, _ in
            ensureSelection()
        }
        .confirmationDialog(
            "Delete Project?",
            isPresented: Binding(
                get: { pendingDeleteProject != nil },
                set: { isPresented in
                    if isPresented == false {
                        pendingDeleteProject = nil
                    }
                }
            ),
            presenting: pendingDeleteProject
        ) { project in
            Button("Delete \(project.name)", role: .destructive) {
                delete(project)
            }
        } message: { project in
            Text("This removes \(project.name) from Local Projects.")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(JocalhostColors.configPanelBackground)
                    .frame(width: 36, height: 36)

                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(JocalhostColors.brandBlue)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Projects")
                    .font(.headline)
                    .foregroundStyle(JocalhostColors.text)

                Text(headerSummary)
                    .font(.caption)
                    .foregroundStyle(JocalhostColors.mutedText)
            }

            Spacer()

            Button {
                addProject()
            } label: {
                Label("Add Local Project", systemImage: "plus")
            }
            .controlSize(.small)
            .buttonStyle(.borderedProminent)
            .tint(JocalhostColors.brandBlue)

            Button {
                store.reload()
                ensureSelection()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .controlSize(.small)
            .help("Reload projects")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(JocalhostColors.configWindowBackground)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Local Projects")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(JocalhostColors.mutedText)

                Spacer()

                Button {
                    addProject()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Add project")
            }

            if store.projects.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(JocalhostColors.brandBlue)

                    Text("No local projects")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(JocalhostColors.text)

                    Text("Remote projects stay configured on their host Mac.")
                        .font(.caption)
                        .foregroundStyle(JocalhostColors.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(JocalhostColors.configPanelBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(JocalhostColors.separator, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(store.projects) { project in
                            ConfigProjectListItem(
                                project: project,
                                runtime: store.runtime(for: project),
                                isSelected: project.id == selectedProjectID
                            ) {
                                select(project)
                            }
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(width: 238, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(JocalhostColors.configWindowBackground)
    }

    private var editor: some View {
        VStack(spacing: 0) {
            if showsEmptyLocalProjectState {
                emptyLocalProjectEditor
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        editorTitle
                        projectDetailsEditor
                        servicesEditor
                        editorMessages
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }

                Divider()

                editorActions
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(JocalhostColors.configWindowBackground)
    }

    private var emptyLocalProjectEditor: some View {
        VStack(spacing: 14) {
            Spacer()

            Image(systemName: "laptopcomputer")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(JocalhostColors.brandBlue)

            VStack(spacing: 5) {
                Text(store.remoteHosts.isEmpty ? "No projects yet" : "Remote projects")
                    .font(.headline)
                    .foregroundStyle(JocalhostColors.text)

                Text(emptyLocalProjectMessage)
                    .font(.callout)
                    .foregroundStyle(JocalhostColors.mutedText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 430)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if store.remoteHosts.isEmpty == false {
                remoteProjectsOverview
            }

            Button {
                addProject()
            } label: {
                Label("Add Local Project", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(JocalhostColors.brandBlue)

            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var remoteProjectsOverview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(remoteHostSummary, systemImage: "network")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(JocalhostColors.mutedText)

                Spacer()

                Button {
                    store.refreshRemoteHosts()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh remote projects")
            }

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(store.remoteHosts) { host in
                        remoteHostProjects(host)
                    }
                }
            }
            .frame(maxHeight: 260)
        }
        .padding(12)
        .frame(maxWidth: 520)
        .background(JocalhostColors.configPanelBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(JocalhostColors.separator, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func remoteHostProjects(_ host: RemoteHostDefinition) -> some View {
        let runtime = store.remoteRuntime(for: host)
        let projects = runtime.response?.projects ?? []
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ConnectionIndicator(status: runtime.status)

                Text(runtime.response?.hostName ?? host.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(JocalhostColors.text)
                    .lineLimit(1)

                Text(host.displayAddress)
                    .font(.caption2.monospaced())
                    .foregroundStyle(JocalhostColors.mutedText)
                    .lineLimit(1)

                Spacer()
            }

            if let errorMessage = runtime.errorMessage,
               runtime.status == .failed {
                WarningLine(text: errorMessage)
            } else if projects.isEmpty {
                DetailLine(icon: "network", text: emptyRemoteStatusText(runtime.status))
            } else {
                ForEach(projects, id: \.id) { project in
                    RemoteProjectLine(host: host, project: project)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var editorTitle: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(currentProject == nil ? "Add Local Project" : "Project Details")
                    .font(.headline)
                    .foregroundStyle(JocalhostColors.text)

                Text(currentProject == nil ? "Create a project hosted by this Mac." : "Update the selected local project.")
                    .font(.caption)
                    .foregroundStyle(JocalhostColors.mutedText)
            }

            Spacer()

            if let currentProject {
                StatusPill(status: store.runtime(for: currentProject).status)
            }
        }
    }

    private var projectDetailsEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            configField("Name", systemImage: "tag", text: $draft.name, prompt: "My App")
            directoryField

            HStack(alignment: .top, spacing: 10) {
                configField("Command", systemImage: "terminal", text: $draft.command, prompt: "npm run dev")
                configField("Port", systemImage: "network", text: $draft.port, prompt: "3000")
                    .frame(width: 112)
            }

            HStack(spacing: 8) {
                Toggle(isOn: $draft.exposeOnLocalNetwork) {
                    Label("Expose on local network", systemImage: "network")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(JocalhostColors.mutedText)
                }
                .toggleStyle(.checkbox)

                Spacer()

                Button {
                    runAutodetection()
                } label: {
                    Label("Detect", systemImage: "wand.and.stars")
                }
                .disabled(trimmedDirectory.isEmpty)

                if let convexCommandSuggestion,
                   hasConvexService == false {
                    Button {
                        addConvexService(convexCommandSuggestion)
                    } label: {
                        Label("Add Convex", systemImage: "bolt.horizontal")
                    }
                }
            }
            .controlSize(.small)
        }
        .padding(12)
        .background(JocalhostColors.configPanelBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(JocalhostColors.separator, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var directoryField: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("Project Folder", systemImage: "folder")
                .font(.caption.weight(.medium))
                .foregroundStyle(JocalhostColors.mutedText)

            HStack(spacing: 8) {
                TextField("Path to project folder", text: $draft.workingDirectory)
                    .textFieldStyle(.roundedBorder)

                Button {
                    chooseDirectory()
                } label: {
                    Image(systemName: "folder")
                }
                .accessibilityLabel("Choose folder")
                .help("Choose folder")
            }
        }
    }

    private var editorMessages: some View {
        VStack(alignment: .leading, spacing: 8) {
            if shouldShowValidationMessage, let validationMessage {
                Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(JocalhostColors.warning)
            }

            if let detectionMessage {
                Label(detectionMessage, systemImage: "sparkles")
                    .font(.caption)
                    .foregroundStyle(JocalhostColors.brandBlue)
            }
        }
    }

    private var editorActions: some View {
        HStack {
            if let currentProject {
                Button(role: .destructive) {
                    pendingDeleteProject = currentProject
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }

            Spacer()

            Button {
                resetDraft()
            } label: {
                Label("Reset", systemImage: "arrow.uturn.backward")
            }

            Button {
                saveDraft()
            } label: {
                Label("Save", systemImage: "checkmark")
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .tint(JocalhostColors.brandBlue)
            .disabled(makeProject() == nil)
        }
        .controlSize(.small)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: "externaldrive")
                .font(.caption)
                .foregroundStyle(JocalhostColors.mutedText)

            Text("Local config")
                .font(.caption2.weight(.medium))
                .foregroundStyle(JocalhostColors.mutedText)

            Text(store.configPath)
                .font(.caption2.monospaced())
                .foregroundStyle(JocalhostColors.mutedText)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Button {
                if let onDone {
                    onDone()
                } else {
                    dismiss()
                }
            } label: {
                Text("Done")
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(JocalhostColors.configWindowBackground)
    }

    private var currentProject: ProjectDefinition? {
        store.projects.first { $0.id == draft.id }
    }

    private var showsEmptyLocalProjectState: Bool {
        store.projects.isEmpty && isAddingProject == false
    }

    private var headerSummary: String {
        let projectCount = store.projects.count
        let projectSummary = "\(projectCount) local \(projectCount == 1 ? "project" : "projects") on this Mac"
        guard store.remoteHosts.isEmpty == false else {
            return projectSummary
        }
        return "\(projectSummary) - \(remoteHostSummary)"
    }

    private var remoteHostSummary: String {
        let hostCount = store.remoteHosts.count
        return "\(hostCount) remote \(hostCount == 1 ? "Mac" : "Macs") saved"
    }

    private var emptyLocalProjectMessage: String {
        if store.remoteHosts.isEmpty {
            return "Add one only if this Mac should run dev servers."
        }
        return "These projects are configured on their host Mac. This Mac can control them without copying their local config."
    }

    private var trimmedDirectory: String {
        draft.workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var validationMessage: String? {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let directory = draft.workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        let command = draft.command.trimmingCharacters(in: .whitespacesAndNewlines)
        let port = draft.port.trimmingCharacters(in: .whitespacesAndNewlines)

        if name.isEmpty {
            return "Name is required."
        }

        if directory.isEmpty {
            return "Working directory is required."
        }

        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory) == false || isDirectory.boolValue == false {
            return "Working directory must exist."
        }

        if command.isEmpty, draft.services.isEmpty {
            return "Command is required."
        }

        if port.isEmpty == false {
            guard let parsedPort = Int(port), (1...65_535).contains(parsedPort) else {
                return "Port must be empty or between 1 and 65535."
            }
        }

        for service in draft.services {
            if service.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "Service name is required."
            }
            if service.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "Service command is required."
            }
            let servicePort = service.port.trimmingCharacters(in: .whitespacesAndNewlines)
            if servicePort.isEmpty == false {
                guard let parsedPort = Int(servicePort), (1...65_535).contains(parsedPort) else {
                    return "Service ports must be empty or between 1 and 65535."
                }
            }
        }

        return nil
    }

    private var shouldShowValidationMessage: Bool {
        currentProject != nil ||
            draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ||
            draft.workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ||
            draft.port.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ||
            draft.command.trimmingCharacters(in: .whitespacesAndNewlines) != "npm run dev" ||
            draft.exposeOnLocalNetwork ||
            draft.services.isEmpty == false
    }

    private var servicesEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Services", systemImage: "square.stack.3d.up")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(JocalhostColors.mutedText)

                Spacer()

                Button {
                    addServiceDraft()
                } label: {
                    Label("Add Service", systemImage: "plus")
                }
                .controlSize(.mini)
            }

            if draft.services.isEmpty {
                Text("Detect can add web and Convex services from the selected folder.")
                    .font(.caption)
                    .foregroundStyle(JocalhostColors.mutedText)
            } else {
                VStack(spacing: 8) {
                    ForEach($draft.services) { $service in
                        HStack(spacing: 8) {
                            TextField("Name", text: $service.name)
                                .frame(width: 92)
                            TextField("Command", text: $service.command)
                            TextField("Port", text: $service.port)
                                .frame(width: 72)
                            Toggle("LAN", isOn: $service.exposeOnLocalNetwork)
                                .toggleStyle(.checkbox)
                                .frame(width: 62)
                            Button(role: .destructive) {
                                draft.services.removeAll { $0.id == service.id }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                .textFieldStyle(.roundedBorder)
            }
        }
        .padding(10)
        .background(JocalhostColors.configPanelBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(JocalhostColors.separator, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func configField(_ title: String, systemImage: String, text: Binding<String>, prompt: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.medium))
                .foregroundStyle(JocalhostColors.mutedText)

            TextField(prompt ?? title, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func ensureSelection() {
        if let selectedProjectID,
           let project = store.projects.first(where: { $0.id == selectedProjectID }) {
            if draft.id != project.id {
                draft = ProjectDraft(project: project)
            }
            return
        }

        if let firstProject = store.projects.first {
            select(firstProject)
            return
        }

        if selectedProjectID != nil || isAddingProject == false {
            showEmptyLocalProjectState()
        }
    }

    private func applyInitialSelection() {
        if startsAddingProject {
            addProject()
            return
        }

        if let initialProjectID,
           let project = store.projects.first(where: { $0.id == initialProjectID }) {
            select(project)
            return
        }

        ensureSelection()
    }

    private func select(_ project: ProjectDefinition) {
        selectedProjectID = project.id
        draft = ProjectDraft(project: project)
        detectionMessage = nil
        convexCommandSuggestion = nil
        isAddingProject = false
    }

    private func addProject() {
        selectedProjectID = nil
        draft = ProjectDraft(project: nil)
        detectionMessage = nil
        convexCommandSuggestion = nil
        isAddingProject = true
    }

    private func showEmptyLocalProjectState() {
        selectedProjectID = nil
        draft = ProjectDraft(project: nil)
        detectionMessage = nil
        convexCommandSuggestion = nil
        isAddingProject = false
    }

    private func resetDraft() {
        if let currentProject {
            select(currentProject)
        } else {
            addProject()
        }
    }

    private func saveDraft() {
        guard let project = makeProject() else {
            return
        }

        store.upsert(project)
        selectedProjectID = project.id
        draft = ProjectDraft(project: project)
        detectionMessage = nil
        convexCommandSuggestion = nil
        isAddingProject = false
    }

    private func delete(_ project: ProjectDefinition) {
        pendingDeleteProject = nil
        store.delete(project)

        if let nextProject = store.projects.first {
            select(nextProject)
        } else {
            showEmptyLocalProjectState()
        }
    }

    private func makeProject() -> ProjectDefinition? {
        guard validationMessage == nil else {
            return nil
        }

        return ProjectDefinition(
            id: draft.id,
            name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
            workingDirectory: draft.workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines),
            command: primaryCommand,
            port: primaryPort,
            exposeOnLocalNetwork: draft.exposeOnLocalNetwork,
            services: draft.services.compactMap { $0.makeService() }
        )
    }

    private var primaryCommand: String {
        if let serviceCommand = draft.services.first?.command.trimmingCharacters(in: .whitespacesAndNewlines),
           serviceCommand.isEmpty == false {
            return serviceCommand
        }

        return draft.command.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var primaryPort: Int? {
        if let servicePort = draft.services.first?.port.trimmingCharacters(in: .whitespacesAndNewlines),
           servicePort.isEmpty == false {
            return Int(servicePort)
        }

        let trimmedPort = draft.port.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedPort.isEmpty ? nil : Int(trimmedPort)
    }

    private func addServiceDraft() {
        draft.services.append(
            ProjectServiceDraft(
                name: "service",
                command: draft.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "npm run dev" : draft.command,
                port: draft.port,
                exposeOnLocalNetwork: draft.exposeOnLocalNetwork
            )
        )
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = draft.workingDirectory.isEmpty ? nil : URL(fileURLWithPath: draft.workingDirectory)

        if panel.runModal() == .OK, let url = panel.url {
            draft.workingDirectory = url.path
            if draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                draft.name = url.lastPathComponent
            }
            applyAutodetection(in: url.path)
        }
    }

    private func runAutodetection() {
        applyAutodetection(in: trimmedDirectory)
    }

    private func applyAutodetection(in directory: String) {
        guard let detection = ProjectDetection.detect(in: directory) else {
            detectionMessage = "No package.json or Convex project detected."
            convexCommandSuggestion = nil
            return
        }

        convexCommandSuggestion = detection.convexCommand

        if draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let name = detection.name,
           name.isEmpty == false {
            draft.name = name
        }

        if let command = detection.command,
           draft.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            draft.command == "npm run dev" {
            draft.command = command
        }

        if draft.port.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let port = detection.port {
            draft.port = String(port)
        }

        let detectedServiceDrafts = detection.services.map { detection in
            var service = ProjectServiceDraft(detection: detection)
            service.exposeOnLocalNetwork = draft.exposeOnLocalNetwork && detection.port != nil
            return service
        }
        if detectedServiceDrafts.contains(where: { $0.name == "convex" }) {
            draft.services = detectedServiceDrafts
        }

        detectionMessage = "Detected \(detection.summary)"
    }

    private var hasConvexService: Bool {
        draft.services.contains { service in
            service.name.trimmingCharacters(in: .whitespacesAndNewlines).localizedCaseInsensitiveCompare("convex") == .orderedSame ||
                service.command.localizedCaseInsensitiveContains("convex dev")
        }
    }

    private func addConvexService(_ command: String) {
        guard hasConvexService == false else {
            return
        }

        if draft.services.isEmpty {
            draft.command = command
            draft.port = ""
            draft.services = [
                ProjectServiceDraft(name: "convex", command: command)
            ]
        } else {
            draft.services.append(ProjectServiceDraft(name: "convex", command: command))
        }
        detectionMessage = "Added Convex dev service."
    }
}

struct RemoteHostEditorView: View {
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.dismiss) private var dismiss

    private let originalHost: RemoteHostDefinition?
    @State private var draft: RemoteHostDraft

    init(host: RemoteHostDefinition?) {
        self.originalHost = host
        self._draft = State(initialValue: RemoteHostDraft(host: host))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(JocalhostColors.subtleBlue)
                        .frame(width: 34, height: 34)

                    Image(systemName: "link")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(JocalhostColors.brandBlue)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(originalHost == nil ? "Add Remote Host" : "Edit Remote Host")
                        .font(.headline)
                        .foregroundStyle(JocalhostColors.text)

                    Text("Connect another jocalhost instance on this network.")
                        .font(.caption)
                        .foregroundStyle(JocalhostColors.mutedText)
                }

                Spacer()
            }

            VStack(alignment: .leading, spacing: 12) {
                remoteField("Name", systemImage: "tag", text: $draft.name)
                remoteField("Host", systemImage: "network", text: $draft.host)
                remoteField("Port", systemImage: "number", text: $draft.port)
                remoteField("Token", systemImage: "key", text: $draft.token)

                Toggle(isOn: $draft.isEnabled) {
                    Label("Enabled", systemImage: "checkmark.circle")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(JocalhostColors.mutedText)
                }
                .toggleStyle(.checkbox)
            }

            if let validationMessage {
                Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(JocalhostColors.warning)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("On the host Mac, run:")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(JocalhostColors.mutedText)

                Text("jocalhostctl lan-info")
                    .font(.caption2.monospaced())
                    .foregroundStyle(JocalhostColors.mutedText)
                    .textSelection(.enabled)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(JocalhostColors.codeBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack {
                if let originalHost {
                    Button(role: .destructive) {
                        store.delete(originalHost)
                        dismiss()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Text("Cancel")
                }

                Button {
                    if let host = makeRemoteHost() {
                        store.upsert(host)
                        dismiss()
                    }
                } label: {
                    Label("Save", systemImage: "checkmark")
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(JocalhostColors.brandBlue)
                .disabled(makeRemoteHost() == nil)
            }
            .controlSize(.small)
        }
        .padding(18)
        .frame(width: 520)
    }

    private func remoteField(_ title: String, systemImage: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.medium))
                .foregroundStyle(JocalhostColors.mutedText)

            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var validationMessage: String? {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let host = draft.host.trimmingCharacters(in: .whitespacesAndNewlines)
        let port = draft.port.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = draft.token.trimmingCharacters(in: .whitespacesAndNewlines)

        if name.isEmpty {
            return "Name is required."
        }
        if host.isEmpty {
            return "Host is required."
        }
        guard let parsedPort = Int(port), (1...65_535).contains(parsedPort) else {
            return "Port must be between 1 and 65535."
        }
        if token.isEmpty {
            return "Token is required."
        }
        if (try? LANRemoteAccess.endpointURL(host: host, port: parsedPort)) == nil {
            return "Host must be an IP address, host name, or HTTP URL."
        }

        return nil
    }

    private func makeRemoteHost() -> RemoteHostDefinition? {
        guard validationMessage == nil,
              let port = Int(draft.port.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }

        return RemoteHostDefinition(
            id: draft.id,
            name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
            host: draft.host.trimmingCharacters(in: .whitespacesAndNewlines),
            port: port,
            token: draft.token.trimmingCharacters(in: .whitespacesAndNewlines),
            isEnabled: draft.isEnabled
        )
    }
}

private struct ConfigProjectListItem: View {
    var project: ProjectDefinition
    var runtime: ProjectRuntime
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        let services = project.effectiveServices
        let firstService = services.first
        let singleServiceSummary = firstService?.port.map { port in
            "\(firstService?.exposeOnLocalNetwork == true ? "LAN" : "localhost"):\(port)"
        } ?? "auto-detect port"

        Button(action: action) {
            HStack(alignment: .top, spacing: 8) {
                StatusIndicator(status: runtime.status)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 3) {
                    Text(project.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(JocalhostColors.text)
                        .lineLimit(1)

                    Text(services.count == 1 ? singleServiceSummary : "\(services.count) services")
                        .font(.caption2.monospaced())
                        .foregroundStyle(JocalhostColors.mutedText)
                        .lineLimit(1)

                    Text(services.map { "\($0.name): \($0.command)" }.joined(separator: "  "))
                        .font(.caption2)
                        .foregroundStyle(JocalhostColors.mutedText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? JocalhostColors.configSelectedBackground : JocalhostColors.configPanelBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? JocalhostColors.configSelectedBorder : JocalhostColors.separator, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

private struct StatusPill: View {
    var status: ProjectStatus

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor(status))
                .frame(width: 7, height: 7)

            Text(statusTitle(status))
                .font(.caption.weight(.semibold))
                .foregroundStyle(JocalhostColors.mutedText)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(JocalhostColors.configPanelBackground)
        .overlay(
            Capsule()
                .stroke(JocalhostColors.separator, lineWidth: 1)
        )
        .clipShape(Capsule())
    }
}
