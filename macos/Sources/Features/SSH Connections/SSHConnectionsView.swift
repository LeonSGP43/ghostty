import AppKit
import Foundation
import SwiftUI

struct SSHConnectionsView: View {
    @EnvironmentObject private var store: AITerminalManagerStore
    @State private var hostName = ""
    @State private var hostAlias = ""
    @State private var hostHostname = ""
    @State private var hostUser = ""
    @State private var hostPort = ""
    @State private var hostDefaultDirectory = ""
    @State private var hostPassword = ""
    @State private var hostAuthMode: AITerminalHostAuthMode = .system
    @State private var editingHostID: String?
    @State private var isPresentingEditor = false
    @State private var selectedHostID: String?
    @State private var hostSearchText = ""

    var body: some View {
        VStack(spacing: 0) {
            header

            if let lastError = store.lastError, !lastError.isEmpty {
                Text(lastError)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
            }

            NavigationSplitView {
                sidebar
            } detail: {
                detailPane
            }
            .navigationSplitViewStyle(.balanced)
        }
        .frame(minWidth: 1180, minHeight: 760)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $isPresentingEditor) {
            hostEditorSheet
        }
        .onAppear(perform: syncSelection)
        .onChange(of: allSSHHosts.map(\.id)) { _ in
            syncSelection()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.SSHConnections.title)
                    .font(.title2.weight(.semibold))
                Text(L10n.SSHConnections.subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Picker(L10n.AITerminalManager.launch, selection: $store.launchTarget) {
                ForEach(AITerminalLaunchTarget.allCases) { target in
                    Text(target.displayName).tag(target)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 220)
        }
        .padding(20)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Button(L10n.SSHConnections.newConnection) {
                    prepareNewConnection()
                }
                Button(L10n.AITerminalManager.reloadSSHConfig) {
                    store.reloadImportedSSHHosts()
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            TextField(L10n.AITerminalManager.searchHosts, text: $hostSearchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 12)

            List(selection: $selectedHostID) {
                if filteredRecentHosts.isEmpty && filteredSavedHosts.isEmpty && filteredImportedHosts.isEmpty {
                    Text(L10n.AITerminalManager.hostsEmpty)
                        .foregroundStyle(.secondary)
                } else {
                    hostSection(title: L10n.AITerminalManager.recentHosts, hosts: filteredRecentHosts)
                    hostSection(title: L10n.AITerminalManager.savedHosts, hosts: filteredSavedHosts)
                    hostSection(title: L10n.AITerminalManager.importedHosts, hosts: filteredImportedHosts)
                }
            }
            .listStyle(.sidebar)
        }
    }

    @ViewBuilder
    private func hostSection(title: String, hosts: [AITerminalHost]) -> some View {
        if !hosts.isEmpty {
            Section(title) {
                ForEach(hosts) { host in
                    hostListRow(host)
                        .tag(host.id)
                }
            }
        }
    }

    private func hostListRow(_ host: AITerminalHost) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(host.name)
                    .font(.headline)
                    .lineLimit(1)

                Spacer(minLength: 8)

                if hasActiveSession(for: host) {
                    Image(systemName: "wave.3.right.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }

            Text(primarySubtitle(for: host))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack(spacing: 6) {
                badge(hostSourceLabel(for: host))

                if host.authMode == .password {
                    badge(host.authMode.displayName)
                }

                if let recentRecord = store.recentRecord(for: host) {
                    badge(recentStatusTitle(for: recentRecord))
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedHostID = host.id
        }
        .onTapGesture(count: 2) {
            store.open(host: host)
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        if let selectedHost {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    heroCard(for: selectedHost)
                    detailCard(for: selectedHost)
                    sessionsCard(for: selectedHost)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        } else {
            VStack(alignment: .leading, spacing: 14) {
                Text(L10n.SSHConnections.title)
                    .font(.title2.weight(.semibold))
                Text(allSSHHosts.isEmpty ? L10n.AITerminalManager.hostsEmpty : L10n.AITerminalManager.noHostSelected)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Button(L10n.SSHConnections.newConnection) {
                        prepareNewConnection()
                    }
                    Button(L10n.AITerminalManager.reloadSSHConfig) {
                        store.reloadImportedSSHHosts()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(32)
        }
    }

    private func heroCard(for host: AITerminalHost) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(host.name)
                        .font(.title2.weight(.semibold))

                    Text(primarySubtitle(for: host))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)

                    HStack(spacing: 8) {
                        badge(hostSourceLabel(for: host))
                        badge(host.authMode.displayName)
                        if hasActiveSession(for: host) {
                            badge(L10n.SSHConnections.activeSessions)
                        }
                    }
                }

                Spacer(minLength: 12)

                Button(L10n.AITerminalManager.connect) {
                    store.open(host: host)
                }
                .controlSize(.large)
            }

            if let recentRecord = store.recentRecord(for: host) {
                Text(recentSummary(for: recentRecord))
                    .font(.callout)
                    .foregroundStyle(recentRecord.status == .failed ? .red : .secondary)
            }

            if host.authMode == .password {
                Text(store.hasStoredPassword(for: host) ? L10n.SSHConnections.passwordStored : L10n.SSHConnections.passwordNotStored)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button(L10n.AITerminalManager.edit) {
                    beginEditing(host)
                }
                Button(L10n.AITerminalManager.duplicateHost) {
                    beginDuplicating(host)
                }

                if store.isUserManagedHost(host) {
                    Button(L10n.AITerminalManager.remove, role: .destructive) {
                        store.removeHost(host)
                    }
                } else if store.isImportedHostOverridden(host) {
                    Button(L10n.AITerminalManager.resetOverride, role: .destructive) {
                        store.resetImportedHostOverride(host)
                    }
                }
            }
        }
        .padding(20)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 16))
    }

    private func detailCard(for host: AITerminalHost) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.AITerminalManager.hostDetails)
                .font(.headline)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(minimum: 180), spacing: 16, alignment: .topLeading),
                    GridItem(.flexible(minimum: 180), spacing: 16, alignment: .topLeading),
                ],
                alignment: .leading,
                spacing: 14
            ) {
                infoCell(label: L10n.AITerminalManager.displayName, value: host.name)
                infoCell(label: L10n.AITerminalManager.hostTarget, value: host.connectionTarget ?? "—")
                infoCell(label: L10n.AITerminalManager.hostname, value: host.hostname ?? "—")
                infoCell(label: L10n.AITerminalManager.user, value: host.user ?? "—")
                infoCell(label: L10n.AITerminalManager.port, value: host.port.map(String.init) ?? "—")
                infoCell(label: L10n.AITerminalManager.defaultDirectory, value: host.defaultDirectory ?? "—")
                infoCell(label: L10n.SSHConnections.authentication, value: host.authMode.displayName)
                infoCell(label: L10n.AITerminalManager.hostSource, value: hostSourceLabel(for: host))
            }
        }
        .padding(20)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 16))
    }

    private func sessionsCard(for host: AITerminalHost) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.SSHConnections.activeSessions)
                .font(.headline)

            if contextualRemoteSessions(for: host).isEmpty {
                Text(L10n.SSHConnections.activeSessionsEmpty)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(contextualRemoteSessions(for: host)) { session in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 8) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(session.title)
                                    .font(.headline)
                                Text(session.hostTarget)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }

                            Spacer(minLength: 8)

                            if session.isFocused {
                                badge(L10n.AITerminalManager.focused)
                            }
                        }

                        if let workingDirectory = session.workingDirectory, !workingDirectory.isEmpty {
                            Text(workingDirectory)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }

                        Text(session.authState.displayName)
                            .font(.caption)
                            .foregroundStyle(authStateColor(session.authState))

                        HStack(spacing: 10) {
                            Button(L10n.AITerminalManager.focus) {
                                store.focus(sessionID: session.id)
                            }
                            Button(L10n.SSHConnections.reconnect) {
                                reconnect(session: session)
                            }
                        }
                    }
                    .padding(14)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding(20)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 16))
    }

    private var hostEditorSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L10n.AITerminalManager.displayName, text: $hostName)
                    TextField(L10n.AITerminalManager.sshAlias, text: $hostAlias)
                    TextField(L10n.AITerminalManager.hostname, text: $hostHostname)
                    TextField(L10n.AITerminalManager.user, text: $hostUser)
                    TextField(L10n.AITerminalManager.port, text: $hostPort)
                    TextField(L10n.AITerminalManager.defaultDirectory, text: $hostDefaultDirectory)
                }

                Section(L10n.SSHConnections.authentication) {
                    Picker(L10n.SSHConnections.authentication, selection: $hostAuthMode) {
                        ForEach(AITerminalHostAuthMode.allCases) { authMode in
                            Text(authMode.displayName).tag(authMode)
                        }
                    }

                    if hostAuthMode == .password {
                        SecureField(L10n.SSHConnections.password, text: $hostPassword)
                        Text(passwordHelperText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(editingHostID == nil ? L10n.SSHConnections.newConnection : L10n.AITerminalManager.editSSHHost)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.AITerminalManager.cancelEdit) {
                        cancelEditor()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(editingHostID == nil ? L10n.SSHConnections.saveConnection : L10n.SSHConnections.updateConnection) {
                        persistEditor()
                    }
                }
            }
        }
        .frame(minWidth: 540, minHeight: 420)
    }

    private func infoCell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func badge(_ title: String) -> some View {
        Text(title)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.12), in: Capsule())
    }

    private var cardBackground: Color {
        Color(nsColor: .controlBackgroundColor)
    }

    private func authStateColor(_ authState: AITerminalSSHSessionAuthState) -> Color {
        switch authState {
        case .failed: .red
        case .connected: .green
        case .authenticating, .awaitingPassword, .connecting: .secondary
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
        hostAuthMode = host.authMode
        hostPassword = ""
        isPresentingEditor = true
    }

    private func beginDuplicating(_ host: AITerminalHost) {
        selectedHostID = host.id
        editingHostID = nil
        hostName = "\(host.name) \(L10n.AITerminalManager.copySuffix)"
        hostAlias = AITerminalManagerStore.duplicateAlias(
            for: host,
            existingHosts: allSSHHosts
        )
        hostHostname = host.hostname ?? ""
        hostUser = host.user ?? ""
        hostPort = host.port.map(String.init) ?? ""
        hostDefaultDirectory = host.defaultDirectory ?? ""
        hostAuthMode = host.authMode
        hostPassword = ""
        isPresentingEditor = true
    }

    private func prepareNewConnection() {
        editingHostID = nil
        hostName = ""
        hostAlias = ""
        hostHostname = ""
        hostUser = ""
        hostPort = ""
        hostDefaultDirectory = ""
        hostAuthMode = .system
        hostPassword = ""
        isPresentingEditor = true
    }

    private func cancelEditor() {
        isPresentingEditor = false
        hostPassword = ""
        editingHostID = nil
    }

    private func persistEditor() {
        let draftHostID = AITerminalHost.stableID(
            existingID: editingHostID,
            sshAlias: hostAlias,
            hostname: hostHostname,
            user: hostUser
        )

        store.saveHost(
            existingHostID: editingHostID,
            name: hostName,
            sshAlias: hostAlias,
            hostname: hostHostname,
            user: hostUser,
            port: hostPort,
            defaultDirectory: hostDefaultDirectory,
            authMode: hostAuthMode,
            password: hostPassword
        )

        guard store.lastError == nil else { return }
        selectedHostID = draftHostID
        cancelEditor()
    }

    private func reconnect(session: AITerminalRemoteSessionSummary) {
        guard let host = store.availableHosts.first(where: { $0.id == session.hostID }) else { return }
        store.open(host: host)
    }

    private func syncSelection() {
        let ids = Set(allSSHHosts.map(\.id))

        if let selectedHostID, ids.contains(selectedHostID) {
            return
        }

        selectedHostID = allSSHHosts.first?.id
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

    private var allSSHHosts: [AITerminalHost] {
        store.availableHosts.filter { !$0.isLocal }
    }

    private var selectedHost: AITerminalHost? {
        guard let selectedHostID else { return nil }
        return allSSHHosts.first(where: { $0.id == selectedHostID })
    }

    private var passwordHelperText: String {
        if hostAuthMode != .password {
            return ""
        }
        if let editingHost,
           store.hasStoredPassword(for: editingHost) {
            return L10n.SSHConnections.passwordStored
        }
        return L10n.SSHConnections.passwordNotStored
    }

    private var editingHost: AITerminalHost? {
        guard let editingHostID else { return nil }
        return allSSHHosts.first(where: { $0.id == editingHostID })
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

    private func recentSummary(for record: AITerminalRecentHostRecord) -> String {
        let status = recentStatusTitle(for: record)
        let timestamp = record.connectedAt.formatted(date: .abbreviated, time: .shortened)
        if let errorSummary = record.errorSummary, !errorSummary.isEmpty {
            return "\(status) • \(timestamp) • \(errorSummary)"
        }
        return "\(status) • \(timestamp)"
    }

    private func recentStatusTitle(for record: AITerminalRecentHostRecord) -> String {
        switch record.status {
        case .connected: L10n.AITerminalManager.hostStatusConnected
        case .failed: L10n.AITerminalManager.hostStatusFailed
        }
    }

    private func primarySubtitle(for host: AITerminalHost) -> String {
        host.connectionTarget ?? host.displaySubtitle
    }

    private func contextualRemoteSessions(for host: AITerminalHost) -> [AITerminalRemoteSessionSummary] {
        store.remoteSessions.filter { $0.hostID == host.id }
    }

    private func hasActiveSession(for host: AITerminalHost) -> Bool {
        store.remoteSessions.contains { $0.hostID == host.id }
    }
}

#Preview {
    SSHConnectionsView()
        .environmentObject(
            AITerminalManagerStore(
                appDelegateProvider: { nil },
                configurationURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("json")
            )
        )
}
