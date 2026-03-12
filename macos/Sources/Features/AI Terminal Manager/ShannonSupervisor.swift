import Foundation
import OSLog

enum ShannonSupervisorState: Equatable {
    case unavailable
    case stopped
    case starting
    case runningEmbedded
    case running(pid: Int32)
    case failed(message: String)

    var displayName: String {
        switch self {
        case .unavailable: L10n.AITerminalManager.supervisorUnavailable
        case .stopped: L10n.AITerminalManager.supervisorStopped
        case .starting: L10n.AITerminalManager.supervisorStarting
        case .runningEmbedded: L10n.AITerminalManager.supervisorRunningEmbedded
        case .running(let pid): L10n.AITerminalManager.supervisorRunning(pid: pid)
        case .failed(let message): L10n.AITerminalManager.supervisorFailed(message)
        }
    }
}

@MainActor
final class ShannonSupervisor {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.mitchellh.ghostty",
        category: "ShannonSupervisor"
    )

    private(set) var state: ShannonSupervisorState = .unavailable
    private var process: Process?

    var isRunning: Bool {
        if process != nil {
            return true
        }
        switch state {
        case .running, .runningEmbedded:
            return true
        default:
            return false
        }
    }

    func updateAvailability(for configuration: ShannonSupervisorConfiguration) {
        guard process == nil else { return }
        if configuration.isLaunchable {
            state = .stopped
        } else {
            state = .unavailable
        }
    }

    func start(
        configuration: ShannonSupervisorConfiguration,
        workingDirectoryURL: URL? = nil
    ) {
        guard process == nil else { return }
        guard configuration.isLaunchable else {
            state = .unavailable
            return
        }

        if configuration.isEmbeddedRuntime {
            state = .runningEmbedded
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: configuration.resolvedLaunchExecutable)
        process.arguments = configuration.resolvedLaunchArguments
        process.environment = ProcessInfo.processInfo.environment.merging(configuration.environment, uniquingKeysWith: { _, new in new })
        process.currentDirectoryURL = workingDirectoryURL

        process.terminationHandler = { [weak self] process in
            Task { @MainActor in
                guard let self else { return }
                self.process = nil
                if process.terminationStatus == 0 {
                    self.state = .stopped
                } else {
                    self.state = .failed(
                        message: L10n.AITerminalManager.supervisorExitStatus(process.terminationStatus)
                    )
                }
            }
        }

        do {
            state = .starting
            try process.run()
            self.process = process
            state = .running(pid: process.processIdentifier)
        } catch {
            Self.logger.error("failed to launch Shannon supervisor: \(error.localizedDescription)")
            state = .failed(message: error.localizedDescription)
        }
    }

    func stop() {
        if case .runningEmbedded = state {
            state = .stopped
            return
        }

        guard let process else { return }
        process.terminate()
        self.process = nil
        state = .stopped
    }
}
