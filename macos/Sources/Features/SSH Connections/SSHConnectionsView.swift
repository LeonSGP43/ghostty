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
    @State private var selectedHostID: String?
    @State private var hostSearchText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if let lastError = store.lastError, !lastError.isEmpty {
                Text(lastError)
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            HStack(alignment: .top, spacing: 16) {
                sidebar
                    .frame(width: 340, alignment: .topLeading)
                detailsAndEditor
                    .frame(minWidth: 420, maxWidth: .infinity, alignment: .topLeading)
                activeSessions
                    .frame(width: 340, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(20)
        .frame(minWidth: 1280, minHeight: 760, alignment: .topLeading)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.SSHConnections.title)
                    .font(.largeTitle.weight(.semibold))
                Text(L10n.SSHConnections.subtitle)
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

    private var sidebar: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Button(L10n.SSHConnections.newConnection) {
                        resetEditor()
                    }
                    Button(L10n.AITerminalManager.reloadSSHConfig) {
                        store.reloadImportedSSHHosts()
                    }
                }

                TextField(L10n.AITerminalManager.searchHosts, text: $hostSearchText)
                    .textFieldStyle(.roundedBorder)

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if filteredRecentHosts.isEmpty && filteredSavedHosts.isEmpty && filteredImportedHosts.isEmpty {
                            Text(L10n.AITerminalManager.hostsEmpty)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            hostGroup(title: L10n.AITerminalManager.recentHosts, hosts: filteredRecentHosts)
                            hostGroup(title: L10n.AITerminalManager.savedHosts, hosts: filteredSavedHosts)
                            hostGroup(title: L10n.AITerminalManager.importedHosts, hosts: filteredImportedHosts)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            .frame(maxHeight: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private func hostGroup(title: String, hosts: [AITerminalHost]) -> some View {
        if !hosts.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                ForEach(hosts) { host in
                    hostRow(host)
                }
            }
        }
    }

    private func hostRow(_ host: AITerminalHost) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(host.name)
                        .font(.headline)
                    Text(host.displaySubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        badge(hostSourceLabel(for: host))
                        badge(host.authMode.displayName)
                    }
                }
                Spacer()
                Button(L10n.AITerminalManager.connect) {
                    store.open(host: host)
                }
            }

            if let recentRecord = store.recentRecord(for: host) {
                Text(recentSummary(for: recentRecord))
                    .font(.caption2)
                    .foregroundStyle(recentRecord.status == .failed ? .red : .secondary)
            }
        }
        .padding(10)
        .background(hostRowBackground(for: host), in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onTapGesture {
            selectedHostID = host.id
        }
    }

    private var detailsAndEditor: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox(L10n.AITerminalManager.hostDetails) {
                VStack(alignment: .leading, spacing: 10) {
                    if let selectedHost {
                        detailLine(label: L10n.AITerminalManager.displayName, value: selectedHost.name)
                        detailLine(label: L10n.AITerminalManager.hostSource, value: hostSourceLabel(for: selectedHost))
                        detailLine(label: L10n.AITerminalManager.hostTarget, value: selectedHost.connectionTarget ?? "—")
                        detailLine(label: L10n.AITerminalManager.hostname, value: selectedHost.hostname ?? "—")
                        detailLine(label: L10n.AITerminalManager.user, value: selectedHost.user ?? "—")
                        detailLine(label: L10n.AITerminalManager.port, value: selectedHost.port.map(String.init) ?? "—")
                        detailLine(label: L10n.AITerminalManager.defaultDirectory, value: selectedHost.defaultDirectory ?? "—")
                        detailLine(label: L10n.SSHConnections.authentication, value: selectedHost.authMode.displayName)

                        if selectedHost.authMode == .password {
                            Text(store.hasStoredPassword(for: selectedHost) ? L10n.SSHConnections.passwordStored : L10n.SSHConnections.passwordNotStored)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

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
                            if store.isUserManagedHost(selectedHost) {
                                Button(L10n.AITerminalManager.remove) {
                                    store.removeHost(selectedHost)
                                    if editingHostID == selectedHost.id {
                                        resetEditor()
                                    }
                                }
                            } else if store.isImportedHostOverridden(selectedHost) {
                                Button(L10n.AITerminalManager.resetOverride) {
                                    store.resetImportedHostOverride(selectedHost)
                                    if editingHostID == selectedHost.id {
                                        resetEditor()
                                    }
                                }
                            }
                        }
                    } else {
                        Text(L10n.AITerminalManager.noHostSelected)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox(editingHostID == nil ? L10n.SSHConnections.newConnection : L10n.AITerminalManager.editSSHHost) {
                VStack(alignment: .leading, spacing: 10) {
                    TextField(L10n.AITerminalManager.displayName, text: $hostName)
                    TextField(L10n.AITerminalManager.sshAlias, text: $hostAlias)
                    TextField(L10n.AITerminalManager.hostname, text: $hostHostname)
                    TextField(L10n.AITerminalManager.user, text: $hostUser)
                    TextField(L10n.AITerminalManager.port, text: $hostPort)
                    TextField(L10n.AITerminalManager.defaultDirectory, text: $hostDefaultDirectory)

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

                    HStack {
                        Button(editingHostID == nil ? L10n.SSHConnections.saveConnection : L10n.SSHConnections.updateConnection) {
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
                            if store.lastError == nil {
                                hostPassword = ""
                                resetEditor()
                            }
                        }

                        if editingHostID != nil {
                            Button(L10n.AITerminalManager.cancelEdit) {
                                resetEditor()
                            }
                        }
                    }
                }
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var activeSessions: some View {
        GroupBox(L10n.SSHConnections.activeSessions) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if store.remoteSessions.isEmpty {
                        Text(L10n.SSHConnections.activeSessionsEmpty)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(store.remoteSessions) { session in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(session.title)
                                            .font(.headline)
                                        Text(session.hostName)
                                            .font(.callout)
                                        Text(session.hostTarget)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
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

                                HStack {
                                    Button(L10n.AITerminalManager.focus) {
                                        store.focus(sessionID: session.id)
                                    }
                                    Button(L10n.SSHConnections.reconnect) {
                                        reconnect(session: session)
                                    }
                                }
                            }
                            .padding(10)
                            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
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

    private func badge(_ title: String) -> some View {
        Text(title)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.14), in: Capsule())
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
    }

    private func resetEditor() {
        editingHostID = nil
        hostName = ""
        hostAlias = ""
        hostHostname = ""
        hostUser = ""
        hostPort = ""
        hostDefaultDirectory = ""
        hostAuthMode = .system
        hostPassword = ""
    }

    private func reconnect(session: AITerminalRemoteSessionSummary) {
        guard let host = store.availableHosts.first(where: { $0.id == session.hostID }) else { return }
        store.open(host: host)
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
        if let selectedHostID,
           let selectedHost = allSSHHosts.first(where: { $0.id == selectedHostID }) {
            return selectedHost
        }
        return filteredRecentHosts.first ?? filteredSavedHosts.first ?? filteredImportedHosts.first
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
