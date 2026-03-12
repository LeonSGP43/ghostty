import SwiftUI

struct AITerminalManagerView: View {
    @EnvironmentObject private var store: AITerminalManagerStore
    @State private var hostName = ""
    @State private var hostAlias = ""
    @State private var hostHostname = ""
    @State private var hostUser = ""
    @State private var hostPort = ""
    @State private var hostDefaultDirectory = ""
    @State private var editingHostID: String?
    @State private var selectedHostID: String?
    @State private var hostSearchText = ""
    @State private var workspaceName = ""
    @State private var workspaceDirectory = ""
    @State private var selectedWorkspaceHostID = AITerminalHost.local.id
    @State private var sessionCommand = ""
    @State private var sessionInput = ""
    @State private var shannonPrompt = ""
    @State private var shannonRuntimeMode: ShannonRuntimeMode = .embedded
    @State private var shannonBinaryPath = ""
    @State private var shannonControlURL = ""
    @State private var shannonEndpoint = ""
    @State private var shannonAPIKey = ""
    @State private var shannonModelTier: ShannonModelTier = .medium
    @State private var shannonModelName = ""
    @State private var shannonAutoStart = false
    @State private var shannonTimeoutSeconds = "2"
    @State private var showsSessionContext = false

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            content
        }
        .frame(minWidth: 1120, minHeight: 760)
        .onAppear(perform: syncShannonSetupFromStore)
        .onChange(of: store.configuration.supervisor) { _ in
            syncShannonSetupFromStore()
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if let lastError = store.lastError, !lastError.isEmpty {
                Text(lastError)
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            globalShannonSection

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 16) {
                    supervisorSection
                    hostsSection
                    workspacesSection
                }
                .frame(maxWidth: 420, alignment: .topLeading)

                VStack(alignment: .leading, spacing: 16) {
                    sessionsSection
                    sessionControlSection
                    tasksSection
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .padding(20)
        .frame(minWidth: 1120, minHeight: 760, alignment: .topLeading)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.AITerminalManager.title)
                    .font(.largeTitle.weight(.semibold))
                Text(L10n.AITerminalManager.subtitle)
                    .foregroundStyle(.secondary)
            }
            Spacer()

            Picker(L10n.AITerminalManager.launch, selection: $store.launchTarget) {
                ForEach(AITerminalLaunchTarget.allCases) { target in
                    Text(target.displayName).tag(target)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 220)
        }
    }

    private var globalShannonSection: some View {
        GroupBox(L10n.AITerminalManager.globalShannon) {
            VStack(alignment: .leading, spacing: 14) {
                Text(L10n.AITerminalManager.globalShannonDescription)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        detailLine(
                            label: L10n.AITerminalManager.shannonPrimaryTarget,
                            value: store.shannonPrimarySessionLabel
                        )
                        detailLine(
                            label: L10n.AITerminalManager.shannonCurrentMode,
                            value: store.shannonModeLabel
                        )
                        detailLine(
                            label: L10n.AITerminalManager.shannonCurrentModel,
                            value: store.shannonModelLabel
                        )
                        detailLine(
                            label: L10n.AITerminalManager.shannonCurrentEndpoint,
                            value: store.shannonEndpointLabel
                        )
                    }

                    Spacer()

                    Text(store.shannonStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.AITerminalManager.shannonSetup)
                        .font(.headline)

                    Picker(L10n.AITerminalManager.shannonRuntimeMode, selection: $shannonRuntimeMode) {
                        ForEach(ShannonRuntimeMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(shannonRuntimeMode.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if shannonRuntimeMode == .externalShan {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField(L10n.AITerminalManager.shannonBinaryPath, text: $shannonBinaryPath)
                                .textFieldStyle(.roundedBorder)
                            Text(L10n.AITerminalManager.shannonBinaryPathHint)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            TextField(L10n.AITerminalManager.runtimeEndpoint, text: $shannonControlURL)
                                .textFieldStyle(.roundedBorder)
                            TextField(L10n.AITerminalManager.shannonGatewayEndpoint, text: $shannonEndpoint)
                                .textFieldStyle(.roundedBorder)
                            SecureField(L10n.AITerminalManager.shannonGatewayAPIKey, text: $shannonAPIKey)
                                .textFieldStyle(.roundedBorder)

                            HStack {
                                Picker(L10n.AITerminalManager.shannonModelTier, selection: $shannonModelTier) {
                                    ForEach(ShannonModelTier.allCases) { tier in
                                        Text(tier.displayName).tag(tier)
                                    }
                                }
                                .frame(maxWidth: 220)

                                TextField(L10n.AITerminalManager.shannonSpecificModel, text: $shannonModelName)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                    }

                    HStack(spacing: 12) {
                        Toggle(L10n.AITerminalManager.shannonAutoStart, isOn: $shannonAutoStart)
                        TextField(L10n.AITerminalManager.shannonRequestTimeout, text: $shannonTimeoutSeconds)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 160)
                    }

                    HStack {
                        Button(L10n.AITerminalManager.shannonSaveSetup) {
                            store.saveShannonSetup(composeShannonSupervisorConfiguration())
                        }
                        Button(L10n.AITerminalManager.startSupervisor) {
                            store.saveShannonSetup(composeShannonSupervisorConfiguration())
                            store.startSupervisor()
                        }
                        Button(L10n.AITerminalManager.stopSupervisor) {
                            store.stopSupervisor()
                        }
                        Spacer()
                        Button(L10n.AITerminalManager.refreshSnapshot) {
                            store.refresh()
                        }
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.AITerminalManager.shannonPrompt)
                        .font(.headline)
                    TextEditor(text: $shannonPrompt)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 92, maxHeight: 140)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                        )

                    HStack {
                        Button(L10n.AITerminalManager.askShannon) {
                            store.askGlobalShannon(shannonPrompt)
                            if store.lastError == nil {
                                shannonPrompt = ""
                            }
                        }
                        .disabled(!store.runtimeStatus.healthIsUsable || store.shannonPrimarySession == nil)

                        Spacer()
                    }

                    if let approval = store.pendingShannonApproval {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L10n.AITerminalManager.shannonApprovalCard)
                                .font(.headline)
                            Text(approval.tool)
                                .font(.callout.weight(.semibold))
                            Text(approval.args)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))

                            HStack {
                                Button(L10n.AITerminalManager.approveAction) {
                                    store.respondToShannonApproval(approved: true)
                                }
                                Button(L10n.AITerminalManager.denyAction) {
                                    store.respondToShannonApproval(approved: false)
                                }
                                Spacer()
                            }
                        }
                        .padding(10)
                        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    }

                    Text(L10n.AITerminalManager.shannonResponse)
                        .font(.headline)
                    ScrollView {
                        Text(store.shannonResponse.isEmpty ? L10n.AITerminalManager.shannonResponseEmpty : store.shannonResponse)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(minHeight: 120, maxHeight: 220)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var supervisorSection: some View {
        GroupBox(L10n.AITerminalManager.supervisor) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(store.supervisorState.displayName)
                        .font(.headline)
                    Spacer()
                    Button(L10n.AITerminalManager.refreshSnapshot) { store.refresh() }
                }

                Text(L10n.AITerminalManager.supervisorHint)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Divider()

                detailLine(
                    label: L10n.AITerminalManager.runtimeEndpoint,
                    value: store.runtimeStatus.baseURL ?? "—"
                )
                detailLine(
                    label: L10n.AITerminalManager.runtimeHealth,
                    value: store.runtimeStatus.health.displayName
                )
                detailLine(
                    label: L10n.AITerminalManager.runtimeVersion,
                    value: store.runtimeStatus.version ?? "—"
                )
                detailLine(
                    label: L10n.AITerminalManager.runtimeGateway,
                    value: store.runtimeStatus.gatewayDisplayName
                )
                detailLine(
                    label: L10n.AITerminalManager.runtimeActiveAgent,
                    value: store.runtimeStatus.activeAgent ?? "—"
                )
                detailLine(
                    label: L10n.AITerminalManager.runtimeUptime,
                    value: store.runtimeStatus.uptimeDisplayName
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var hostsSection: some View {
        GroupBox(L10n.AITerminalManager.hosts) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button(L10n.AITerminalManager.openLocalShell) {
                        store.openLocalShell()
                    }
                    Button(L10n.AITerminalManager.reloadSSHConfig) {
                        store.reloadImportedSSHHosts()
                    }
                    Spacer()
                    if editingHostID != nil {
                        Button(L10n.AITerminalManager.newSSHHost) {
                            resetHostEditor()
                        }
                    }
                }

                Divider()

                TextField(L10n.AITerminalManager.searchHosts, text: $hostSearchText)
                    .textFieldStyle(.roundedBorder)

                VStack(alignment: .leading, spacing: 8) {
                    Text(hostEditorTitle)
                        .font(.headline)

                    if let hostEditorSourceDescription {
                        Text(hostEditorSourceDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    TextField(L10n.AITerminalManager.displayName, text: $hostName)
                    TextField(L10n.AITerminalManager.sshAlias, text: $hostAlias)
                    TextField(L10n.AITerminalManager.hostname, text: $hostHostname)
                    TextField(L10n.AITerminalManager.user, text: $hostUser)
                    TextField(L10n.AITerminalManager.port, text: $hostPort)
                    TextField(L10n.AITerminalManager.defaultDirectory, text: $hostDefaultDirectory)

                    Button(hostEditorSaveTitle) {
                        store.saveHost(
                            existingHostID: editingHostID,
                            name: hostName,
                            sshAlias: hostAlias,
                            hostname: hostHostname,
                            user: hostUser,
                            port: hostPort,
                            defaultDirectory: hostDefaultDirectory
                        )
                        if store.lastError == nil {
                            resetHostEditor()
                        }
                    }

                    if editingHostID != nil {
                        Button(L10n.AITerminalManager.cancelEdit) {
                            resetHostEditor()
                        }
                    }
                }
                .textFieldStyle(.roundedBorder)

                if filteredRecentHosts.isEmpty && filteredSavedHosts.isEmpty && filteredImportedHosts.isEmpty {
                    Text(L10n.AITerminalManager.hostsEmpty)
                        .foregroundStyle(.secondary)
                } else {
                    hostGroup(title: L10n.AITerminalManager.recentHosts, hosts: filteredRecentHosts)
                    hostGroup(title: L10n.AITerminalManager.savedHosts, hosts: filteredSavedHosts)
                    hostGroup(title: L10n.AITerminalManager.importedHosts, hosts: filteredImportedHosts)
                }

                Divider()
                hostDetailsSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func hostGroup(title: String, hosts: [AITerminalHost]) -> some View {
        if !hosts.isEmpty {
            Divider()
            Text(title)
                .font(.headline)
            ForEach(hosts) { host in
                hostRow(host)
            }
        }
    }

    private func hostRow(_ host: AITerminalHost) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(host.name)
                        .font(.headline)
                    Text(hostSourceLabel(for: host))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(L10n.AITerminalManager.connect) {
                    store.open(host: host)
                }
                Button(L10n.AITerminalManager.edit) {
                    beginEditing(host)
                }
                if store.isUserManagedHost(host) {
                    Button(L10n.AITerminalManager.remove) {
                        store.removeHost(host)
                        if editingHostID == host.id {
                            resetHostEditor()
                        }
                    }
                } else if store.isImportedHostOverridden(host) {
                    Button(L10n.AITerminalManager.resetOverride) {
                        store.resetImportedHostOverride(host)
                        if editingHostID == host.id {
                            resetHostEditor()
                        }
                    }
                }
            }
            Text(host.displaySubtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(hostRowBackground(for: host), in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture {
            selectedHostID = host.id
        }
    }

    private var hostDetailsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.AITerminalManager.hostDetails)
                .font(.headline)

            if let selectedHost {
                if let recentRecord = store.recentRecord(for: selectedHost) {
                    Text(recentSummary(for: recentRecord))
                        .font(.caption)
                        .foregroundStyle(recentRecord.status == .failed ? .red : .secondary)
                } else {
                    Text(L10n.AITerminalManager.noRecentHostActivity)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                detailLine(label: L10n.AITerminalManager.hostSource, value: hostSourceLabel(for: selectedHost))
                detailLine(label: L10n.AITerminalManager.hostTarget, value: selectedHost.connectionTarget ?? "—")
                detailLine(label: L10n.AITerminalManager.hostname, value: selectedHost.hostname ?? "—")
                detailLine(label: L10n.AITerminalManager.user, value: selectedHost.user ?? "—")
                detailLine(label: L10n.AITerminalManager.port, value: selectedHost.port.map(String.init) ?? "—")
                detailLine(label: L10n.AITerminalManager.defaultDirectory, value: selectedHost.defaultDirectory ?? "—")

                HStack {
                    Button(L10n.AITerminalManager.connect) {
                        store.open(host: selectedHost)
                    }
                    Button(L10n.AITerminalManager.edit) {
                        beginEditing(selectedHost)
                    }
                    Button(L10n.AITerminalManager.duplicateHost) {
                        beginDuplicating(selectedHost)
                    }
                }
            } else {
                Text(L10n.AITerminalManager.noHostSelected)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func detailLine(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout)
                .textSelection(.enabled)
        }
    }

    private var workspacesSection: some View {
        GroupBox(L10n.AITerminalManager.workspaces) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button(L10n.AITerminalManager.addLocalWorkspace) {
                        store.addWorkspaceFromOpenPanel()
                    }
                    Spacer()
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.AITerminalManager.registerWorkspace)
                        .font(.headline)

                    TextField(L10n.AITerminalManager.workspaceName, text: $workspaceName)

                    Picker(L10n.AITerminalManager.host, selection: $selectedWorkspaceHostID) {
                        ForEach(store.availableHosts) { host in
                            Text(host.name).tag(host.id)
                        }
                    }

                    TextField(L10n.AITerminalManager.directory, text: $workspaceDirectory)

                    Button(L10n.AITerminalManager.saveWorkspace) {
                        store.saveWorkspace(
                            name: workspaceName,
                            hostID: selectedWorkspaceHostID,
                            directory: workspaceDirectory
                        )
                        if store.lastError == nil {
                            workspaceName = ""
                            workspaceDirectory = ""
                            selectedWorkspaceHostID = AITerminalHost.local.id
                        }
                    }
                }
                .textFieldStyle(.roundedBorder)

                if store.workspaces.isEmpty {
                    Text(L10n.AITerminalManager.workspacesEmpty)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.workspaces) { workspace in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(workspace.name)
                                    .font(.headline)
                                Text(workspace.directory)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                            Spacer()
                            Button(L10n.AITerminalManager.open) {
                                store.open(workspace: workspace)
                            }
                            Button(L10n.AITerminalManager.remove) {
                                store.removeWorkspace(workspace)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func beginEditing(_ host: AITerminalHost) {
        selectedHostID = host.id
        editingHostID = host.id
        hostName = host.name
        hostAlias = host.sshAlias ?? ""
        hostHostname = host.hostname ?? ""
        hostUser = host.user ?? ""
        hostPort = host.port.map(String.init) ?? ""
        hostDefaultDirectory = host.defaultDirectory ?? ""
    }

    private func resetHostEditor() {
        editingHostID = nil
        hostName = ""
        hostAlias = ""
        hostHostname = ""
        hostUser = ""
        hostPort = ""
        hostDefaultDirectory = ""
    }

    private func beginDuplicating(_ host: AITerminalHost) {
        selectedHostID = host.id
        editingHostID = nil
        hostName = "\(host.name) \(L10n.AITerminalManager.copySuffix)"
        hostAlias = AITerminalManagerStore.duplicateAlias(
            for: host,
            existingHosts: store.availableHosts.filter { !$0.isLocal }
        )
        hostHostname = host.hostname ?? ""
        hostUser = host.user ?? ""
        hostPort = host.port.map(String.init) ?? ""
        hostDefaultDirectory = host.defaultDirectory ?? ""
    }

    private var hostEditorTitle: String {
        editingHostID == nil ? L10n.AITerminalManager.addSSHHost : L10n.AITerminalManager.editSSHHost
    }

    private var hostEditorSaveTitle: String {
        editingHostID == nil ? L10n.AITerminalManager.saveHost : L10n.AITerminalManager.updateHost
    }

    private var hostEditorSourceDescription: String? {
        guard let editingHostID else { return nil }
        guard let host = store.availableHosts.first(where: { $0.id == editingHostID }) else { return nil }
        return hostSourceLabel(for: host)
    }

    private var filteredRecentHosts: [AITerminalHost] {
        filterHosts(store.recentHosts)
    }

    private var filteredSavedHosts: [AITerminalHost] {
        filterHosts(store.savedHosts)
    }

    private var filteredImportedHosts: [AITerminalHost] {
        filterHosts(store.mergedImportedHosts.filter { imported in
            !store.savedHosts.contains(where: { $0.id == imported.id })
        })
    }

    private var selectedHost: AITerminalHost? {
        if let selectedHostID,
           let selectedHost = store.availableHosts.first(where: { $0.id == selectedHostID }) {
            return selectedHost
        }
        return filteredRecentHosts.first ?? filteredSavedHosts.first ?? filteredImportedHosts.first
    }

    private func filterHosts(_ hosts: [AITerminalHost]) -> [AITerminalHost] {
        let query = hostSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return hosts }
        return hosts.filter { host in
            host.name.localizedCaseInsensitiveContains(query)
                || (host.sshAlias?.localizedCaseInsensitiveContains(query) ?? false)
                || (host.hostname?.localizedCaseInsensitiveContains(query) ?? false)
                || (host.user?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    private func hostSourceLabel(for host: AITerminalHost) -> String {
        if store.savedHosts.contains(where: { $0.id == host.id }) {
            return L10n.AITerminalManager.savedHostSource
        }
        if store.isImportedHost(host) {
            return store.isImportedHostOverridden(host)
                ? L10n.AITerminalManager.importedHostOverriddenSource
                : L10n.AITerminalManager.importedHostSource
        }
        return ""
    }

    private func hostRowBackground(for host: AITerminalHost) -> Color {
        selectedHost?.id == host.id ? .accentColor.opacity(0.12) : .clear
    }

    private func recentSummary(for record: AITerminalRecentHostRecord) -> String {
        let status = switch record.status {
        case .connected: L10n.AITerminalManager.hostStatusConnected
        case .failed: L10n.AITerminalManager.hostStatusFailed
        }
        let timestamp = record.connectedAt.formatted(date: .abbreviated, time: .shortened)
        if let errorSummary = record.errorSummary, !errorSummary.isEmpty {
            return "\(status) • \(timestamp) • \(errorSummary)"
        }
        return "\(status) • \(timestamp)"
    }

    private var sessionsSection: some View {
        GroupBox(L10n.AITerminalManager.sessions) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if store.sessions.isEmpty {
                        Text(L10n.AITerminalManager.sessionsEmpty)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(store.sessions) { session in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(session.title)
                                        .font(.headline)
                                    if store.selectedSessionID == session.id {
                                        Text(L10n.AITerminalManager.selected)
                                            .font(.caption.weight(.medium))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 2)
                                            .background(.green.opacity(0.15), in: Capsule())
                                    }
                                    if session.isFocused {
                                        Text(L10n.AITerminalManager.focused)
                                            .font(.caption.weight(.medium))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 2)
                                            .background(.blue.opacity(0.15), in: Capsule())
                                    }
                                    Spacer()
                                    Text(session.managedState.displayName)
                                        .foregroundStyle(.secondary)
                                }

                                Text(session.hostLabel)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)

                                if let workingDirectory = session.workingDirectory, !workingDirectory.isEmpty {
                                    Text(workingDirectory)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }

                                if let taskTitle = session.taskTitle {
                                    HStack {
                                        Text(taskTitle)
                                            .font(.caption.weight(.medium))
                                        if let taskState = session.taskState {
                                            Text(taskState.displayName)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }

                                HStack {
                                    Button(store.selectedSessionID == session.id ? L10n.AITerminalManager.selected : L10n.AITerminalManager.select) {
                                        store.selectSession(session.id)
                                    }
                                    .disabled(store.selectedSessionID == session.id)
                                    Button(L10n.AITerminalManager.focus) {
                                        store.focus(sessionID: session.id)
                                    }
                                    Button(L10n.AITerminalManager.createTask) {
                                        store.createTask(for: session.id)
                                    }
                                    Button(L10n.AITerminalManager.observe) {
                                        store.setManagedState(.observed, for: session.id)
                                    }
                                    Button(L10n.AITerminalManager.manage) {
                                        store.createTask(for: session.id)
                                    }
                                    Button(L10n.AITerminalManager.returnManual) {
                                        store.setManagedState(.manual, for: session.id)
                                    }
                                    Spacer()
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                            .overlay {
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(
                                        store.selectedSessionID == session.id
                                            ? Color.accentColor
                                            : Color.clear,
                                        lineWidth: 2
                                    )
                            }
                            .contentShape(RoundedRectangle(cornerRadius: 10))
                            .onTapGesture {
                                store.selectSession(session.id)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var sessionControlSection: some View {
        GroupBox(L10n.AITerminalManager.selectedSessionControl) {
            VStack(alignment: .leading, spacing: 12) {
                if let session = store.selectedSession {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.title)
                                .font(.headline)
                            Text(session.hostLabel)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            if let workingDirectory = session.workingDirectory, !workingDirectory.isEmpty {
                                Text(workingDirectory)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                        Spacer()
                        Button(L10n.AITerminalManager.refreshSnapshot) {
                            store.refreshSelectedSessionSnapshot()
                        }
                        Button(L10n.AITerminalManager.focus) {
                            store.focus(sessionID: session.id)
                        }
                        Button(L10n.AITerminalManager.closeTab) {
                            store.closeSession(session.id)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.AITerminalManager.command)
                            .font(.headline)
                        TextField(L10n.AITerminalManager.commandPlaceholder, text: $sessionCommand)
                            .textFieldStyle(.roundedBorder)
                        HStack {
                            Button(L10n.AITerminalManager.sendCommand) {
                                store.sendCommand(sessionCommand, to: session.id)
                                if store.lastError == nil {
                                    sessionCommand = ""
                                }
                            }
                            Spacer()
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.AITerminalManager.rawInput)
                            .font(.headline)
                        TextEditor(text: $sessionInput)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 72, maxHeight: 120)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                            )
                        HStack {
                            Button(L10n.AITerminalManager.sendInput) {
                                store.sendInput(sessionInput, to: session.id)
                                if store.lastError == nil {
                                    sessionInput = ""
                                }
                            }
                            Spacer()
                        }
                    }

                    DisclosureGroup(L10n.AITerminalManager.sessionContext, isExpanded: $showsSessionContext) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L10n.AITerminalManager.visibleBuffer)
                                .font(.headline)
                            ScrollView {
                                Text(store.selectedSessionVisibleText.isEmpty ? L10n.AITerminalManager.visibleBufferEmpty : store.selectedSessionVisibleText)
                                    .font(.system(.caption, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                            .frame(minHeight: 100, maxHeight: 150)
                            .padding(8)
                            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))

                            Text(L10n.AITerminalManager.screenBuffer)
                                .font(.headline)
                            ScrollView {
                                Text(store.selectedSessionScreenText.isEmpty ? L10n.AITerminalManager.screenBufferEmpty : store.selectedSessionScreenText)
                                    .font(.system(.caption, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                            .frame(minHeight: 120, maxHeight: 180)
                            .padding(8)
                            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                        }
                        .padding(.top, 8)
                    }
                } else {
                    Text(L10n.AITerminalManager.selectedSessionEmpty)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var tasksSection: some View {
        GroupBox(L10n.AITerminalManager.taskQueue) {
            if store.tasks.isEmpty {
                Text(L10n.AITerminalManager.taskQueueEmpty)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(store.tasks) { task in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(task.title)
                                        .font(.headline)
                                    Spacer()
                                    Text(task.state.displayName)
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.secondary)
                                }

                                Text(task.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                if let note = task.note, !note.isEmpty {
                                    Text(note)
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                }

                                HStack {
                                    Button(L10n.AITerminalManager.focusSession) {
                                        store.focus(sessionID: task.sessionID)
                                    }
                                    Button(L10n.AITerminalManager.pause) {
                                        store.pauseTask(for: task.sessionID)
                                    }
                                    Button(L10n.AITerminalManager.resume) {
                                        store.resumeTask(for: task.sessionID)
                                    }
                                    Button(L10n.AITerminalManager.needApproval) {
                                        store.requireApproval(for: task.sessionID)
                                    }
                                    Button(L10n.AITerminalManager.complete) {
                                        store.completeTask(for: task.sessionID)
                                    }
                                    Button(L10n.AITerminalManager.fail) {
                                        store.failTask(for: task.sessionID)
                                    }
                                    Spacer()
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 200, maxHeight: 260, alignment: .topLeading)
            }
        }
    }

    private func syncShannonSetupFromStore() {
        let supervisor = store.configuration.supervisor
        shannonRuntimeMode = supervisor.runtimeMode
        shannonBinaryPath = supervisor.binaryPath ?? ""
        shannonControlURL = supervisor.controlURL ?? ""
        shannonEndpoint = supervisor.gateway.endpoint
        shannonAPIKey = supervisor.gateway.apiKey
        shannonModelTier = supervisor.gateway.modelTier
        shannonModelName = supervisor.gateway.modelName
        shannonAutoStart = supervisor.autoStart
        shannonTimeoutSeconds = String(supervisor.requestTimeoutSeconds)
    }

    private func composeShannonSupervisorConfiguration() -> ShannonSupervisorConfiguration {
        ShannonSupervisorConfiguration(
            runtimeMode: shannonRuntimeMode,
            binaryPath: shannonBinaryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : shannonBinaryPath,
            arguments: [],
            autoStart: shannonAutoStart,
            environment: [:],
            controlURL: shannonControlURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : shannonControlURL,
            requestTimeoutSeconds: max(Int(shannonTimeoutSeconds) ?? 2, 1),
            gateway: ShannonGatewayConfiguration(
                endpoint: shannonEndpoint,
                apiKey: shannonAPIKey,
                modelTier: shannonModelTier,
                modelName: shannonModelName
            )
        )
    }
}

#Preview {
    AITerminalManagerView()
        .environmentObject(AITerminalManagerStore(appDelegateProvider: { nil }))
}
