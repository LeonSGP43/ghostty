import AppKit
import Foundation
import SwiftUI

@MainActor
final class AITerminalManagerStore: ObservableObject {
    @Published private(set) var configuration: AITerminalManagerConfiguration
    @Published private(set) var importedSSHHosts: [AITerminalHost] = []
    @Published private(set) var sessions: [AITerminalSessionSummary] = []
    @Published private(set) var tasks: [AITerminalTaskRecord] = []
    @Published private(set) var supervisorState: ShannonSupervisorState = .unavailable
    @Published private(set) var selectedSessionID: UUID?
    @Published private(set) var selectedSessionVisibleText = ""
    @Published private(set) var selectedSessionScreenText = ""
    @Published var launchTarget: AITerminalLaunchTarget = .tab
    @Published var lastError: String?

    private let appDelegateProvider: () -> AppDelegate?
    private let configurationURL: URL
    private let supervisor = ShannonSupervisor()
    private var registrations: [UUID: AITerminalLaunchRegistration] = [:]
    private var taskBindings: [UUID: UUID] = [:]
    private var pollingTimer: Timer?

    init(
        appDelegateProvider: @escaping () -> AppDelegate?,
        configurationURL: URL? = nil
    ) {
        self.appDelegateProvider = appDelegateProvider
        self.configurationURL = configurationURL ?? Self.defaultConfigurationURL()
        self.configuration = (try? Self.loadConfiguration(from: self.configurationURL)) ?? .empty
        refresh()
        startPolling()
    }

    deinit {
        pollingTimer?.invalidate()
    }

    var availableHosts: [AITerminalHost] {
        var result: [AITerminalHost] = [AITerminalHost.local]
        var seen: Set<String> = [AITerminalHost.local.id]

        for host in configuration.savedHosts where seen.insert(host.id).inserted {
            result.append(host)
        }
        for host in mergedImportedHosts where seen.insert(host.id).inserted {
            result.append(host)
        }

        return result.sorted { lhs, rhs in
            if lhs.id == AITerminalHost.local.id { return true }
            if rhs.id == AITerminalHost.local.id { return false }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    var savedHosts: [AITerminalHost] {
        configuration.savedHosts.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    var mergedImportedHosts: [AITerminalHost] {
        Self.mergedImportedHosts(imported: importedSSHHosts, overrides: configuration.importedHostOverrides)
    }

    nonisolated static func mergedImportedHosts(
        imported: [AITerminalHost],
        overrides: [AITerminalHost]
    ) -> [AITerminalHost] {
        let overrideLookup = Dictionary(uniqueKeysWithValues: overrides.map { ($0.id, $0) })
        return imported.map { host in
            guard let override = overrideLookup[host.id] else { return host }
            var merged = host
            merged.name = override.name
            merged.sshAlias = override.sshAlias
            merged.hostname = override.hostname
            merged.user = override.user
            merged.port = override.port
            merged.defaultDirectory = override.defaultDirectory
            return merged
        }
        .sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    var recentHosts: [AITerminalHost] {
        let lookup = Dictionary(uniqueKeysWithValues: availableHosts.map { ($0.id, $0) })
        return configuration.recentHosts
            .sorted { $0.connectedAt > $1.connectedAt }
            .compactMap { lookup[$0.id] }
    }

    var workspaces: [AITerminalWorkspaceTemplate] {
        configuration.workspaces.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    var selectedSession: AITerminalSessionSummary? {
        guard let selectedSessionID else { return nil }
        return sessions.first(where: { $0.id == selectedSessionID })
    }

    func isUserManagedHost(_ host: AITerminalHost) -> Bool {
        configuration.savedHosts.contains(where: { $0.id == host.id })
    }

    func isImportedHost(_ host: AITerminalHost) -> Bool {
        importedSSHHosts.contains(where: { $0.id == host.id })
    }

    func isImportedHostOverridden(_ host: AITerminalHost) -> Bool {
        configuration.importedHostOverrides.contains(where: { $0.id == host.id })
    }

    func refresh() {
        if let loaded = try? Self.loadConfiguration(from: configurationURL) {
            configuration = loaded
        }

        importedSSHHosts = loadSSHConfigHosts()
        supervisor.updateAvailability(for: configuration.supervisor)
        supervisorState = supervisor.state

        if configuration.supervisor.autoStart, case .stopped = supervisor.state {
            supervisor.start(configuration: configuration.supervisor)
            supervisorState = supervisor.state
        }

        rebuildSessions()
    }

    func openLocalShell() {
        launch(.localShell())
    }

    func open(host: AITerminalHost) {
        open(host: host, directoryOverride: nil)
    }

    func open(host: AITerminalHost, directoryOverride: String?) {
        if host.isLocal {
            openLocalShell()
            return
        }

        guard let plan = AITerminalLaunchPlan.remote(host: host, directoryOverride: directoryOverride) else {
            lastError = L10n.AITerminalManager.hostMissingSSHDetails
            recordRecentHost(host.id, status: .failed, errorSummary: lastError)
            return
        }

        launch(plan)
        recordRecentHost(host.id, status: .connected)
    }

    func open(workspace: AITerminalWorkspaceTemplate) {
        guard let host = availableHosts.first(where: { $0.id == workspace.hostID }) else {
            lastError = L10n.AITerminalManager.workspaceUnknownHost(workspace.name)
            return
        }
        guard let plan = AITerminalLaunchPlan.workspace(workspace, host: host) else {
            lastError = L10n.AITerminalManager.workspaceInvalidPlan(workspace.name)
            return
        }

        launch(plan)
        if !host.isLocal {
            recordRecentHost(host.id, status: .connected)
        }
    }

    func addWorkspaceFromOpenPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = L10n.AITerminalManager.addWorkspacePrompt

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let path = url.path(percentEncoded: false)
        var workspaces = configuration.workspaces
        let name = url.lastPathComponent.isEmpty ? path : url.lastPathComponent
        workspaces.append(.init(
            id: "workspace:\(UUID().uuidString)",
            name: name,
            hostID: AITerminalHost.local.id,
            directory: path
        ))
        configuration.workspaces = workspaces
        persistConfiguration()
        rebuildSessions()
    }

    func saveHost(
        existingHostID: String? = nil,
        name: String,
        sshAlias: String,
        hostname: String,
        user: String,
        port: String,
        defaultDirectory: String
    ) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAlias = sshAlias.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedHostname = hostname.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUser = user.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDirectory = defaultDirectory.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            lastError = L10n.AITerminalManager.hostNameEmpty
            return
        }
        guard !trimmedAlias.isEmpty || !trimmedHostname.isEmpty else {
            lastError = L10n.AITerminalManager.hostMissingAliasOrHostname
            return
        }

        let parsedPort: Int?
        if port.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parsedPort = nil
        } else if let v = Int(port.trimmingCharacters(in: .whitespacesAndNewlines)) {
            parsedPort = v
        } else {
            lastError = L10n.AITerminalManager.hostInvalidPort
            return
        }

        let hostID = AITerminalHost.stableID(
            existingID: existingHostID,
            sshAlias: trimmedAlias,
            hostname: trimmedHostname,
            user: trimmedUser
        )
        let host = AITerminalHost(
            id: hostID,
            name: trimmedName,
            transport: .ssh,
            sshAlias: trimmedAlias.isEmpty ? nil : trimmedAlias,
            hostname: trimmedHostname.isEmpty ? nil : trimmedHostname,
            user: trimmedUser.isEmpty ? nil : trimmedUser,
            port: parsedPort,
            defaultDirectory: trimmedDirectory.isEmpty ? nil : trimmedDirectory,
            source: .configurationFile
        )

        if importedSSHHosts.contains(where: { $0.id == host.id }) {
            configuration.importedHostOverrides.removeAll { $0.id == host.id }
            configuration.importedHostOverrides.append(host)
            configuration.importedHostOverrides.sort {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        } else {
            configuration.savedHosts.removeAll { $0.id == host.id }
            configuration.savedHosts.append(host)
            configuration.savedHosts.sort {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
        lastError = nil
        persistConfiguration()
        rebuildSessions()
    }

    func removeHost(_ host: AITerminalHost) {
        configuration.savedHosts.removeAll { $0.id == host.id }
        configuration.importedHostOverrides.removeAll { $0.id == host.id }
        configuration.recentHosts.removeAll { $0.id == host.id }
        if !importedSSHHosts.contains(where: { $0.id == host.id }) {
            configuration.workspaces.removeAll { $0.hostID == host.id }
        }
        lastError = nil
        persistConfiguration()
        rebuildSessions()
    }

    func resetImportedHostOverride(_ host: AITerminalHost) {
        configuration.importedHostOverrides.removeAll { $0.id == host.id }
        configuration.recentHosts.removeAll { $0.id == host.id }
        lastError = nil
        persistConfiguration()
        rebuildSessions()
    }

    func saveWorkspace(
        name: String,
        hostID: String,
        directory: String
    ) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDirectory = directory.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            lastError = L10n.AITerminalManager.workspaceNameEmpty
            return
        }
        guard !trimmedDirectory.isEmpty else {
            lastError = L10n.AITerminalManager.workspaceDirectoryEmpty
            return
        }

        configuration.workspaces.append(.init(
            id: "workspace:\(UUID().uuidString)",
            name: trimmedName,
            hostID: hostID,
            directory: trimmedDirectory
        ))
        configuration.workspaces.sort {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        lastError = nil
        persistConfiguration()
        rebuildSessions()
    }

    func removeWorkspace(_ workspace: AITerminalWorkspaceTemplate) {
        configuration.workspaces.removeAll { $0.id == workspace.id }
        lastError = nil
        persistConfiguration()
        rebuildSessions()
    }

    func setManagedState(_ state: AITerminalManagedState, for sessionID: UUID) {
        var registration = registrations[sessionID] ?? .init(
            hostID: AITerminalHost.local.id,
            workspaceID: nil,
            managedState: .manual,
            sourceLabel: L10n.AITerminalManager.manualSession
        )
        registration.managedState = state
        registrations[sessionID] = registration
        rebuildSessions()
    }

    func task(for sessionID: UUID) -> AITerminalTaskRecord? {
        guard let taskID = taskBindings[sessionID] else { return nil }
        return tasks.first(where: { $0.id == taskID })
    }

    func createTask(for sessionID: UUID, title: String? = nil) {
        guard sessions.contains(where: { $0.id == sessionID }) else {
            lastError = L10n.AITerminalManager.sessionUnavailable
            return
        }

        if let existing = task(for: sessionID) {
            updateTask(existing.id, state: .active, note: existing.note)
            setManagedState(.managedActive, for: sessionID)
            return
        }

        let task = AITerminalTaskRecord(
            title: title ?? defaultTaskTitle(for: sessionID),
            sessionID: sessionID,
            state: .active
        )
        taskBindings[sessionID] = task.id
        tasks.insert(task, at: 0)
        setManagedState(.managedActive, for: sessionID)
        lastError = nil
        rebuildSessions()
    }

    func pauseTask(for sessionID: UUID) {
        guard let task = task(for: sessionID) else { return }
        updateTask(task.id, state: .paused, note: task.note)
        setManagedState(.managedPaused, for: sessionID)
    }

    func resumeTask(for sessionID: UUID) {
        guard let task = task(for: sessionID) else {
            createTask(for: sessionID)
            return
        }
        updateTask(task.id, state: .active, note: task.note)
        setManagedState(.managedActive, for: sessionID)
    }

    func requireApproval(for sessionID: UUID) {
        guard let task = task(for: sessionID) else {
            createTask(for: sessionID)
            requireApproval(for: sessionID)
            return
        }
        updateTask(task.id, state: .waitingApproval, note: L10n.AITerminalManager.waitingForOperator)
        setManagedState(.managedWaitingApproval, for: sessionID)
    }

    func completeTask(for sessionID: UUID) {
        guard let task = task(for: sessionID) else { return }
        updateTask(task.id, state: .completed, note: L10n.AITerminalManager.markedComplete)
        setManagedState(.managedCompleted, for: sessionID)
    }

    func failTask(for sessionID: UUID) {
        guard let task = task(for: sessionID) else { return }
        updateTask(task.id, state: .failed, note: L10n.AITerminalManager.markedFailed)
        setManagedState(.managedFailed, for: sessionID)
    }

    func focus(sessionID: UUID) {
        guard let appDelegate = appDelegateProvider(),
              let surface = appDelegate.findSurface(forUUID: sessionID) else {
            lastError = L10n.AITerminalManager.sessionUnavailable
            return
        }

        NotificationCenter.default.post(
            name: Ghostty.Notification.ghosttyPresentTerminal,
            object: surface
        )
        lastError = nil
    }

    func selectSession(_ sessionID: UUID?) {
        guard let sessionID else {
            selectedSessionID = nil
            selectedSessionVisibleText = ""
            selectedSessionScreenText = ""
            lastError = nil
            return
        }

        guard sessions.contains(where: { $0.id == sessionID }) else {
            selectedSessionID = nil
            selectedSessionVisibleText = ""
            selectedSessionScreenText = ""
            lastError = L10n.AITerminalManager.sessionUnavailable
            return
        }

        selectedSessionID = sessionID
        refreshSelectedSessionSnapshot()
    }

    func refreshSelectedSessionSnapshot() {
        guard let currentSelectedSessionID = selectedSessionID else {
            selectedSessionVisibleText = ""
            selectedSessionScreenText = ""
            lastError = nil
            return
        }

        guard let appDelegate = appDelegateProvider(),
              let surface = appDelegate.findSurface(forUUID: currentSelectedSessionID) else {
            self.selectedSessionID = nil
            selectedSessionVisibleText = ""
            selectedSessionScreenText = ""
            lastError = L10n.AITerminalManager.sessionUnavailable
            return
        }

        selectedSessionVisibleText = surface.aiManagerVisibleText()
        selectedSessionScreenText = surface.aiManagerScreenText()
        lastError = nil
    }

    func sendInput(_ input: String, to sessionID: UUID? = nil) {
        guard let payload = Self.textPayload(for: input) else {
            lastError = L10n.AITerminalManager.inputEmpty
            return
        }

        let targetSessionID = sessionID ?? selectedSessionID
        guard let targetSessionID else {
            lastError = L10n.AITerminalManager.selectSessionFirst
            return
        }

        guard let appDelegate = appDelegateProvider(),
              let surface = appDelegate.findSurface(forUUID: targetSessionID) else {
            lastError = L10n.AITerminalManager.sessionUnavailable
            return
        }

        surface.aiManagerSendText(payload)
        if selectedSessionID == targetSessionID {
            refreshSelectedSessionSnapshot()
        } else {
            lastError = nil
        }
    }

    func sendCommand(_ command: String, to sessionID: UUID? = nil) {
        guard let payload = Self.commandPayload(for: command) else {
            lastError = L10n.AITerminalManager.commandEmpty
            return
        }

        let targetSessionID = sessionID ?? selectedSessionID
        guard let targetSessionID else {
            lastError = L10n.AITerminalManager.selectSessionFirst
            return
        }

        guard let appDelegate = appDelegateProvider(),
              let surface = appDelegate.findSurface(forUUID: targetSessionID) else {
            lastError = L10n.AITerminalManager.sessionUnavailable
            return
        }

        surface.aiManagerSendText(payload)
        if selectedSessionID == targetSessionID {
            refreshSelectedSessionSnapshot()
        } else {
            lastError = nil
        }
    }

    func closeSession(_ sessionID: UUID? = nil) {
        let targetSessionID = sessionID ?? selectedSessionID
        guard let targetSessionID else {
            lastError = L10n.AITerminalManager.selectSessionFirst
            return
        }

        guard let appDelegate = appDelegateProvider(),
              let surface = appDelegate.findSurface(forUUID: targetSessionID),
              let nativeSurface = surface.surface else {
            lastError = L10n.AITerminalManager.sessionUnavailable
            return
        }

        appDelegate.ghostty.requestClose(surface: nativeSurface)
        if selectedSessionID == targetSessionID {
            selectedSessionID = nil
            selectedSessionVisibleText = ""
            selectedSessionScreenText = ""
        }
        lastError = nil
        rebuildSessions()
    }

    func startSupervisor() {
        supervisor.start(configuration: configuration.supervisor)
        supervisorState = supervisor.state
    }

    func stopSupervisor() {
        supervisor.stop()
        supervisorState = supervisor.state
    }

    private func launch(_ plan: AITerminalLaunchPlan) {
        guard let appDelegate = appDelegateProvider() else {
            lastError = L10n.AITerminalManager.appDelegateUnavailable
            return
        }

        let createdSurface: Ghostty.SurfaceView?
        switch launchTarget {
        case .tab:
            if let controller = TerminalController.newTab(
                appDelegate.ghostty,
                from: TerminalController.preferredParent?.window,
                withBaseConfig: plan.surfaceConfiguration
            ) {
                createdSurface = controller.surfaceTree.root?.leftmostLeaf()
            } else {
                let controller = TerminalController.newWindow(
                    appDelegate.ghostty,
                    withBaseConfig: plan.surfaceConfiguration
                )
                createdSurface = controller.surfaceTree.root?.leftmostLeaf()
            }

        case .window:
            let controller = TerminalController.newWindow(
                appDelegate.ghostty,
                withBaseConfig: plan.surfaceConfiguration
            )
            createdSurface = controller.surfaceTree.root?.leftmostLeaf()
        }

        guard let createdSurface else {
            lastError = L10n.AITerminalManager.createSessionFailed
            return
        }

        registrations[createdSurface.id] = plan.registration
        rebuildSessions()
    }

    private func rebuildSessions() {
        let hostLookup = Dictionary(uniqueKeysWithValues: availableHosts.map { ($0.id, $0) })
        let activeSessionIDs = Set(
            TerminalController.all.flatMap { controller in
                controller.surfaceTree.map(\.id)
            }
        )

        pruneClosedSessions(activeSessionIDs: activeSessionIDs)

        sessions = TerminalController.all
            .flatMap { controller in
                controller.surfaceTree.map { surface in
                    let registration = registrations[surface.id]
                        let task = task(for: surface.id)
                    let hostLabel = registration
                        .flatMap { $0.hostID }
                        .flatMap { hostLookup[$0]?.name }
                        ?? L10n.AITerminalManager.manualSession
                    let title: String
                    if let override = controller.titleOverride, !override.isEmpty {
                        title = override
                    } else if !surface.title.isEmpty {
                        title = surface.title
                    } else {
                        title = L10n.Common.untitled
                    }

                    return AITerminalSessionSummary(
                        id: surface.id,
                        title: title,
                        workingDirectory: surface.pwd,
                        isFocused: surface.focused,
                        hostLabel: hostLabel,
                        managedState: registration?.managedState ?? .manual,
                        taskID: task?.id,
                        taskTitle: task?.title,
                        taskState: task?.state
                    )
                }
            }
            .sorted {
                if $0.isFocused != $1.isFocused {
                    return $0.isFocused && !$1.isFocused
                }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }

        if let selectedSessionID, sessions.contains(where: { $0.id == selectedSessionID }) {
            refreshSelectedSessionSnapshot()
        } else if self.selectedSessionID != nil {
            self.selectedSessionID = nil
            selectedSessionVisibleText = ""
            selectedSessionScreenText = ""
        }

        supervisorState = supervisor.state
    }

    private func startPolling() {
        pollingTimer?.invalidate()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.rebuildSessions()
            }
        }
        if let pollingTimer {
            RunLoop.main.add(pollingTimer, forMode: .common)
        }
    }

    private func pruneClosedSessions(activeSessionIDs: Set<UUID>) {
        let closedSessionIDs = Set(taskBindings.keys).subtracting(activeSessionIDs)
        guard !closedSessionIDs.isEmpty else { return }

        for sessionID in closedSessionIDs {
            registrations.removeValue(forKey: sessionID)
            if let taskID = taskBindings.removeValue(forKey: sessionID),
               let index = tasks.firstIndex(where: { $0.id == taskID && $0.state == .active }) {
                tasks[index].state = .failed
                tasks[index].updatedAt = .now
                tasks[index].note = L10n.AITerminalManager.sessionClosed
            }
        }
    }

    private func updateTask(_ taskID: UUID, state: AITerminalTaskState, note: String?) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[index].state = state
        tasks[index].updatedAt = .now
        tasks[index].note = note
        lastError = nil
        rebuildSessions()
    }

    private func defaultTaskTitle(for sessionID: UUID) -> String {
        if let session = sessions.first(where: { $0.id == sessionID }) {
            return L10n.AITerminalManager.manageSession(session.title)
        }
        return L10n.AITerminalManager.defaultTaskTitle
    }

    private func loadSSHConfigHosts() -> [AITerminalHost] {
        let sshConfig = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ssh")
            .appendingPathComponent("config")
        guard let contents = try? String(contentsOf: sshConfig, encoding: .utf8) else { return [] }
        return AITerminalSSHConfigParser.parse(contents)
    }

    private func recordRecentHost(
        _ hostID: String,
        status: AITerminalRecentHostRecord.Status,
        errorSummary: String? = nil
    ) {
        guard hostID != AITerminalHost.local.id else { return }
        configuration.recentHosts = Self.upsertRecentHostRecord(
            configuration.recentHosts,
            hostID: hostID,
            status: status,
            errorSummary: errorSummary
        )
        persistConfiguration()
    }

    nonisolated static func upsertRecentHostRecord(
        _ records: [AITerminalRecentHostRecord],
        hostID: String,
        status: AITerminalRecentHostRecord.Status,
        errorSummary: String? = nil,
        now: Date = .now
    ) -> [AITerminalRecentHostRecord] {
        var next = records
        next.removeAll { $0.id == hostID }
        next.insert(
            .init(id: hostID, connectedAt: now, status: status, errorSummary: errorSummary),
            at: 0
        )
        return Array(next.prefix(8))
    }

    private func persistConfiguration() {
        do {
            try Self.saveConfiguration(configuration, to: configurationURL)
        } catch {
            lastError = L10n.AITerminalManager.saveConfigurationFailed(error.localizedDescription)
        }
    }

    private static func defaultConfigurationURL() -> URL {
        let fileManager = FileManager.default
        let appSupport = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.homeDirectoryForCurrentUser

        let bundleID = Bundle.main.bundleIdentifier ?? "com.mitchellh.ghostty"
        let directory = appSupport.appendingPathComponent(bundleID, isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("ai-terminal-manager.json", isDirectory: false)
    }

    private static func loadConfiguration(from url: URL) throws -> AITerminalManagerConfiguration {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(AITerminalManagerConfiguration.self, from: data)
    }

    private static func saveConfiguration(_ configuration: AITerminalManagerConfiguration, to url: URL) throws {
        let data = try JSONEncoder().encode(configuration)
        try data.write(to: url, options: .atomic)
    }

    nonisolated static func commandPayload(for input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return input.hasSuffix("\n") ? input : "\(input)\n"
    }

    nonisolated static func textPayload(for input: String) -> String? {
        guard !input.isEmpty else { return nil }
        return input
    }
}
