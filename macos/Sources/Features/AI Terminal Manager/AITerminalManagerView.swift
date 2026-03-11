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
    @State private var hostSearchText = ""
    @State private var workspaceName = ""
    @State private var workspaceDirectory = ""
    @State private var selectedWorkspaceHostID = AITerminalHost.local.id
    @State private var sessionCommand = ""
    @State private var sessionInput = ""

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            content
        }
        .frame(minWidth: 1120, minHeight: 760)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if let lastError = store.lastError, !lastError.isEmpty {
                Text(lastError)
                    .foregroundStyle(.red)
                    .font(.callout)
            }

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

    private var supervisorSection: some View {
        GroupBox(L10n.AITerminalManager.supervisor) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(store.supervisorState.displayName)
                        .font(.headline)
                    Spacer()
                    Button(L10n.AITerminalManager.refreshSnapshot) { store.refresh() }
                    Button(L10n.AITerminalManager.startSupervisor) { store.startSupervisor() }
                    Button(L10n.AITerminalManager.stopSupervisor) { store.stopSupervisor() }
                }

                Text(L10n.AITerminalManager.supervisorHint)
                    .font(.callout)
                    .foregroundStyle(.secondary)
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
                    }

                    VStack(alignment: .leading, spacing: 8) {
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
}

#Preview {
    AITerminalManagerView()
        .environmentObject(AITerminalManagerStore(appDelegateProvider: { nil }))
}
