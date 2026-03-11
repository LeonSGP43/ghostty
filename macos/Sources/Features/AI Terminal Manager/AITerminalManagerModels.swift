import Foundation
import GhosttyKit

enum AITerminalManagedState: String, Codable, CaseIterable, Sendable {
    case manual
    case observed
    case managedActive = "managed_active"
    case managedWaitingApproval = "managed_waiting_approval"
    case managedPaused = "managed_paused"
    case managedCompleted = "managed_completed"
    case managedFailed = "managed_failed"

    var displayName: String {
        switch self {
        case .manual: L10n.AITerminalManager.manual
        case .observed: L10n.AITerminalManager.observed
        case .managedActive: L10n.AITerminalManager.managed
        case .managedWaitingApproval: L10n.AITerminalManager.awaitingApproval
        case .managedPaused: L10n.AITerminalManager.paused
        case .managedCompleted: L10n.AITerminalManager.completed
        case .managedFailed: L10n.AITerminalManager.failed
        }
    }
}

enum AITerminalLaunchTarget: String, CaseIterable, Identifiable {
    case tab
    case window

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tab: L10n.AITerminalManager.newTab
        case .window: L10n.AITerminalManager.newWindow
        }
    }
}

enum AITerminalHostSource: String, Codable, Sendable {
    case builtIn = "built_in"
    case configurationFile = "configuration_file"
    case sshConfig = "ssh_config"
}

enum AITerminalTransport: String, Codable, Sendable {
    case local
    case ssh
}

struct AITerminalHost: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var name: String
    var transport: AITerminalTransport
    var sshAlias: String?
    var hostname: String?
    var user: String?
    var port: Int?
    var defaultDirectory: String?
    var source: AITerminalHostSource

    static let local = AITerminalHost(
        id: "local",
        name: L10n.AITerminalManager.thisMac,
        transport: .local,
        sshAlias: nil,
        hostname: nil,
        user: nil,
        port: nil,
        defaultDirectory: nil,
        source: .builtIn
    )

    var isLocal: Bool { transport == .local }

    var displaySubtitle: String {
        switch transport {
        case .local:
            return defaultDirectory ?? L10n.AITerminalManager.localShell
        case .ssh:
            var parts: [String] = []
            if let sshAlias, !sshAlias.isEmpty {
                parts.append(sshAlias)
            }
            if let hostname, !hostname.isEmpty, hostname != sshAlias {
                parts.append(hostname)
            }
            if let user, !user.isEmpty {
                parts.append(user)
            }
            if let port = port {
                parts.append(":\(port)")
            }
            if let defaultDirectory, !defaultDirectory.isEmpty {
                parts.append(defaultDirectory)
            }
            return parts.joined(separator: " • ")
        }
    }

    var connectionTarget: String? {
        if let sshAlias, !sshAlias.isEmpty {
            return sshAlias
        }
        guard let hostname, !hostname.isEmpty else { return nil }
        if let user, !user.isEmpty {
            return "\(user)@\(hostname)"
        }
        return hostname
    }
}

struct AITerminalWorkspaceTemplate: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var name: String
    var hostID: String
    var directory: String
}

struct ShannonSupervisorConfiguration: Codable, Hashable, Sendable {
    var binaryPath: String?
    var arguments: [String]
    var autoStart: Bool
    var environment: [String: String]

    init(
        binaryPath: String? = ProcessInfo.processInfo.environment["GHOSTTY_SHANNON_PATH"],
        arguments: [String] = [],
        autoStart: Bool = false,
        environment: [String: String] = [:]
    ) {
        self.binaryPath = binaryPath
        self.arguments = arguments
        self.autoStart = autoStart
        self.environment = environment
    }
}

struct AITerminalManagerConfiguration: Codable, Sendable {
    var hosts: [AITerminalHost]
    var workspaces: [AITerminalWorkspaceTemplate]
    var supervisor: ShannonSupervisorConfiguration

    init(
        hosts: [AITerminalHost] = [],
        workspaces: [AITerminalWorkspaceTemplate] = [],
        supervisor: ShannonSupervisorConfiguration = .init()
    ) {
        self.hosts = hosts
        self.workspaces = workspaces
        self.supervisor = supervisor
    }
}

struct AITerminalLaunchRegistration: Hashable, Sendable {
    var hostID: String?
    var workspaceID: String?
    var managedState: AITerminalManagedState
    var sourceLabel: String
}

struct AITerminalSessionSummary: Identifiable, Hashable {
    let id: UUID
    var title: String
    var workingDirectory: String?
    var isFocused: Bool
    var hostLabel: String
    var managedState: AITerminalManagedState
    var taskID: UUID?
    var taskTitle: String?
    var taskState: AITerminalTaskState?
}

enum AITerminalTaskState: String, Codable, CaseIterable, Sendable {
    case queued
    case active
    case waitingApproval = "waiting_approval"
    case paused
    case completed
    case failed

    var displayName: String {
        switch self {
        case .queued: L10n.AITerminalManager.queued
        case .active: L10n.AITerminalManager.active
        case .waitingApproval: L10n.AITerminalManager.awaitingApproval
        case .paused: L10n.AITerminalManager.paused
        case .completed: L10n.AITerminalManager.completed
        case .failed: L10n.AITerminalManager.failed
        }
    }
}

struct AITerminalTaskRecord: Identifiable, Hashable, Sendable {
    let id: UUID
    var title: String
    var sessionID: UUID
    var state: AITerminalTaskState
    var createdAt: Date
    var updatedAt: Date
    var note: String?

    init(
        id: UUID = UUID(),
        title: String,
        sessionID: UUID,
        state: AITerminalTaskState = .queued,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        note: String? = nil
    ) {
        self.id = id
        self.title = title
        self.sessionID = sessionID
        self.state = state
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.note = note
    }
}

struct AITerminalLaunchPlan {
    var surfaceConfiguration: Ghostty.SurfaceConfiguration
    var registration: AITerminalLaunchRegistration

    static func localShell() -> AITerminalLaunchPlan {
        var config = Ghostty.SurfaceConfiguration()
        config.environmentVariables["GHOSTTY_AI_MANAGER"] = "1"
        config.environmentVariables["GHOSTTY_AI_SESSION_KIND"] = "local"
        return .init(
            surfaceConfiguration: config,
            registration: .init(
                hostID: AITerminalHost.local.id,
                workspaceID: nil,
                managedState: .manual,
                sourceLabel: AITerminalHost.local.name
            )
        )
    }

    static func workspace(
        _ workspace: AITerminalWorkspaceTemplate,
        host: AITerminalHost
    ) -> AITerminalLaunchPlan? {
        switch host.transport {
        case .local:
            var config = Ghostty.SurfaceConfiguration()
            config.workingDirectory = workspace.directory
            config.environmentVariables["GHOSTTY_AI_MANAGER"] = "1"
            config.environmentVariables["GHOSTTY_AI_SESSION_KIND"] = "local_workspace"
            config.environmentVariables["GHOSTTY_AI_WORKSPACE_ID"] = workspace.id
            return .init(
                surfaceConfiguration: config,
                registration: .init(
                    hostID: host.id,
                    workspaceID: workspace.id,
                    managedState: .manual,
                    sourceLabel: workspace.name
                )
            )

        case .ssh:
            return remote(host: host, directoryOverride: workspace.directory, workspaceID: workspace.id, sourceLabel: workspace.name)
        }
    }

    static func remote(
        host: AITerminalHost,
        directoryOverride: String? = nil,
        workspaceID: String? = nil,
        sourceLabel: String? = nil
    ) -> AITerminalLaunchPlan? {
        guard let initialInput = remoteCommand(host: host, directoryOverride: directoryOverride) else {
            return nil
        }

        var config = Ghostty.SurfaceConfiguration()
        config.initialInput = initialInput
        config.environmentVariables["GHOSTTY_AI_MANAGER"] = "1"
        config.environmentVariables["GHOSTTY_AI_SESSION_KIND"] = "remote_ssh"
        config.environmentVariables["GHOSTTY_AI_HOST_ID"] = host.id
        if let workspaceID = workspaceID {
            config.environmentVariables["GHOSTTY_AI_WORKSPACE_ID"] = workspaceID
        }

        return .init(
            surfaceConfiguration: config,
            registration: .init(
                hostID: host.id,
                workspaceID: workspaceID,
                managedState: .manual,
                sourceLabel: sourceLabel ?? host.name
            )
        )
    }

    static func remoteCommand(
        host: AITerminalHost,
        directoryOverride: String? = nil
    ) -> String? {
        guard let target = host.connectionTarget else { return nil }

        var command = "ssh"
        if host.sshAlias == nil, let port = host.port {
            command += " -p \(port)"
        }
        command += " \(Ghostty.Shell.quote(target))"

        let directory = directoryOverride ?? host.defaultDirectory
        if let directory, !directory.isEmpty {
            let remoteShell = "cd \(Ghostty.Shell.quote(directory)) && exec ${SHELL:-/bin/sh} -l"
            command += " -t \(Ghostty.Shell.quote(remoteShell))"
        }

        return "\(command)\n"
    }
}

enum AITerminalSSHConfigParser {
    private struct Accumulator {
        var aliases: [String] = []
        var hostname: String?
        var user: String?
        var port: Int?
    }

    static func parse(_ text: String) -> [AITerminalHost] {
        var result: [AITerminalHost] = []
        var current = Accumulator()

        func flush() {
            guard !current.aliases.isEmpty else { return }
            for alias in current.aliases {
                result.append(
                    AITerminalHost(
                        id: "ssh:\(alias)",
                        name: alias,
                        transport: .ssh,
                        sshAlias: alias,
                        hostname: current.hostname,
                        user: current.user,
                        port: current.port,
                        defaultDirectory: nil,
                        source: .sshConfig
                    )
                )
            }
            current = Accumulator()
        }

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let trimmed = rawLine.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
                .first.map(String.init) ?? ""
            let line = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }

            let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard let key = parts.first?.lowercased(), parts.count >= 2 else { continue }

            switch key {
            case "host":
                flush()
                current.aliases = parts.dropFirst().filter {
                    !$0.contains("*") && !$0.contains("?") && !$0.contains("!")
                }

            case "hostname":
                current.hostname = parts.dropFirst().joined(separator: " ")

            case "user":
                current.user = parts.dropFirst().joined(separator: " ")

            case "port":
                current.port = Int(parts.dropFirst().joined(separator: " "))

            default:
                continue
            }
        }

        flush()

        var seen: Set<String> = []
        return result.filter { seen.insert($0.id).inserted }
    }
}

extension AITerminalManagerConfiguration {
    static let empty = AITerminalManagerConfiguration()
}
