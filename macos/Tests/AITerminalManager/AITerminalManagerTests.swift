import Testing
import Foundation
import AppKit
@testable import Ghostty

final class MockSSHConnectionCredentialStore: SSHConnectionCredentialStore {
    var passwords: [String: String] = [:]

    func password(for hostID: String) throws -> String? {
        passwords[hostID]
    }

    func setPassword(_ password: String, for hostID: String) throws {
        passwords[hostID] = password
    }

    func removePassword(for hostID: String) throws {
        passwords.removeValue(forKey: hostID)
    }
}

struct AITerminalManagerTests {
    @Test @MainActor func sshConnectionsWindowsWithoutTabGroupsAreNotTreatedAsSameGroup() {
        let lhs = NSWindow()
        let rhs = NSWindow()

        #expect(SSHConnectionsController.windowsAreInSameTabGroup(lhs, rhs) == false)
    }

    @Test func decodesLegacyHostConfigurationIntoSavedHosts() throws {
        let data = Data(#"{"hosts":[{"id":"ssh:buildbox","name":"Buildbox","transport":"ssh","sshAlias":"buildbox","hostname":"10.0.0.5","user":"deploy","port":2222,"defaultDirectory":"/srv/app","source":"configuration_file"}],"workspaces":[],"supervisor":{"arguments":[],"autoStart":false,"environment":{}}}"#.utf8)
        let configuration = try JSONDecoder().decode(AITerminalManagerConfiguration.self, from: data)

        #expect(configuration.savedHosts.count == 1)
        #expect(configuration.savedHosts.first?.id == "ssh:buildbox")
        #expect(configuration.savedHosts.first?.authMode == .system)
        #expect(configuration.importedHostOverrides.isEmpty)
    }

    @Test func parsesSSHConfigHosts() {
        let config = #"""
        Host *
          AddKeysToAgent yes

        Host buildbox staging
          HostName 10.0.0.5
          User deploy
          Port 2222

        Host prod-*
          HostName ignored.example.com
        """#

        let hosts = AITerminalSSHConfigParser.parse(config)
        #expect(hosts.map(\.id) == ["ssh:buildbox", "ssh:staging"])
        #expect(hosts.first?.hostname == "10.0.0.5")
        #expect(hosts.first?.user == "deploy")
        #expect(hosts.first?.port == 2222)
    }

    @Test func buildsRemoteCommandWithDirectory() {
        let host = AITerminalHost(
            id: "ssh:buildbox",
            name: "buildbox",
            transport: .ssh,
            sshAlias: "buildbox",
            hostname: "10.0.0.5",
            user: "deploy",
            port: 2222,
            defaultDirectory: "/srv/app",
            source: .sshConfig
        )

        let command = AITerminalLaunchPlan.remoteCommand(host: host)
        #expect(command == "ssh buildbox -t 'cd /srv/app && exec ${SHELL:-/bin/sh} -l'\n")
    }

    @Test func mergesImportedHostOverrides() {
        let imported = [
            AITerminalHost(
                id: "ssh:buildbox",
                name: "buildbox",
                transport: .ssh,
                sshAlias: "buildbox",
                hostname: "10.0.0.5",
                user: "deploy",
                port: 22,
                defaultDirectory: nil,
                source: .sshConfig
            ),
        ]
        let overrides = [
            AITerminalHost(
                id: "ssh:buildbox",
                name: "Buildbox Prod",
                transport: .ssh,
                sshAlias: "buildbox",
                hostname: "10.0.0.5",
                user: "deploy",
                port: 2200,
                defaultDirectory: "/srv/prod",
                source: .configurationFile,
                authMode: .password
            ),
        ]

        let merged = AITerminalManagerStore.mergedImportedHosts(imported: imported, overrides: overrides)
        #expect(merged.count == 1)
        #expect(merged.first?.name == "Buildbox Prod")
        #expect(merged.first?.port == 2200)
        #expect(merged.first?.defaultDirectory == "/srv/prod")
        #expect(merged.first?.authMode == .password)
    }

    @Test func localWorkspacePlanUsesWorkingDirectory() throws {
        let workspace = AITerminalWorkspaceTemplate(
            id: "workspace:test",
            name: "Ghostty",
            hostID: AITerminalHost.local.id,
            directory: "/tmp/ghostty"
        )

        let plan = try #require(AITerminalLaunchPlan.workspace(workspace, host: .local))
        #expect(plan.surfaceConfiguration.workingDirectory == "/tmp/ghostty")
        #expect(plan.registration.workspaceID == "workspace:test")
    }

    @Test @MainActor func storeSavesConfiguredHost() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")

        let store = AITerminalManagerStore(
            appDelegateProvider: { nil },
            configurationURL: tempURL
        )

        store.saveHost(
            name: "Buildbox",
            sshAlias: "buildbox",
            hostname: "",
            user: "deploy",
            port: "2222",
            defaultDirectory: "/srv/app"
        )

        #expect(store.configuration.savedHosts.count == 1)
        #expect(store.configuration.savedHosts.first?.sshAlias == "buildbox")
        #expect(store.configuration.savedHosts.first?.port == 2222)
        #expect(store.configuration.savedHosts.first?.id == "ssh:buildbox")
        #expect(store.configuration.savedHosts.first?.authMode == .system)
    }

    @Test func derivesHostNameFromAliasOrHostname() {
        #expect(
            AITerminalManagerStore.resolvedHostName(
                explicitName: "",
                sshAlias: "buildbox",
                hostname: "10.0.0.5",
                user: "deploy"
            ) == "buildbox"
        )
        #expect(
            AITerminalManagerStore.resolvedHostName(
                explicitName: "",
                sshAlias: "",
                hostname: "10.0.0.5",
                user: "deploy"
            ) == "deploy@10.0.0.5"
        )
    }

    @Test @MainActor func storeSavesHostWithoutExplicitName() {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")

        let store = AITerminalManagerStore(
            appDelegateProvider: { nil },
            configurationURL: tempURL
        )

        store.saveHost(
            name: "",
            sshAlias: "buildbox",
            hostname: "",
            user: "deploy",
            port: "2222",
            defaultDirectory: "/srv/app"
        )

        #expect(store.lastError == nil)
        #expect(store.configuration.savedHosts.first?.name == "buildbox")
    }

    @Test @MainActor func storeUpdatesExistingHostByStableID() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")

        let store = AITerminalManagerStore(
            appDelegateProvider: { nil },
            configurationURL: tempURL
        )

        store.saveHost(
            name: "Buildbox",
            sshAlias: "buildbox",
            hostname: "",
            user: "deploy",
            port: "2222",
            defaultDirectory: "/srv/app"
        )

        store.saveHost(
            existingHostID: "ssh:buildbox",
            name: "Buildbox Prod",
            sshAlias: "buildbox",
            hostname: "",
            user: "deploy",
            port: "2200",
            defaultDirectory: "/srv/prod"
        )

        #expect(store.configuration.savedHosts.count == 1)
        #expect(store.configuration.savedHosts.first?.name == "Buildbox Prod")
        #expect(store.configuration.savedHosts.first?.port == 2200)
        #expect(store.configuration.savedHosts.first?.defaultDirectory == "/srv/prod")
    }

    @Test @MainActor func storeSavesPasswordHostIntoCredentialStore() {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        let credentialStore = MockSSHConnectionCredentialStore()

        let store = AITerminalManagerStore(
            appDelegateProvider: { nil },
            configurationURL: tempURL,
            credentialStore: credentialStore
        )

        store.saveHost(
            name: "Buildbox",
            sshAlias: "buildbox",
            hostname: "",
            user: "deploy",
            port: "22",
            defaultDirectory: "/srv/app",
            authMode: .password,
            password: "secret"
        )

        #expect(store.configuration.savedHosts.first?.authMode == .password)
        #expect(credentialStore.passwords["ssh:buildbox"] == "secret")
    }

    @Test @MainActor func storeSwitchingBackToSystemAuthRemovesSavedPassword() {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        let credentialStore = MockSSHConnectionCredentialStore()

        let store = AITerminalManagerStore(
            appDelegateProvider: { nil },
            configurationURL: tempURL,
            credentialStore: credentialStore
        )

        store.saveHost(
            name: "Buildbox",
            sshAlias: "buildbox",
            hostname: "",
            user: "deploy",
            port: "22",
            defaultDirectory: "",
            authMode: .password,
            password: "secret"
        )
        store.saveHost(
            existingHostID: "ssh:buildbox",
            name: "Buildbox",
            sshAlias: "buildbox",
            hostname: "",
            user: "deploy",
            port: "22",
            defaultDirectory: "",
            authMode: .system
        )

        #expect(store.configuration.savedHosts.first?.authMode == .system)
        #expect(credentialStore.passwords["ssh:buildbox"] == nil)
    }

    @Test @MainActor func storeKeepsExistingPasswordWhenEditingWithoutNewPassword() {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        let credentialStore = MockSSHConnectionCredentialStore()

        let store = AITerminalManagerStore(
            appDelegateProvider: { nil },
            configurationURL: tempURL,
            credentialStore: credentialStore
        )

        store.saveHost(
            name: "Buildbox",
            sshAlias: "buildbox",
            hostname: "",
            user: "deploy",
            port: "22",
            defaultDirectory: "",
            authMode: .password,
            password: "secret"
        )
        store.saveHost(
            existingHostID: "ssh:buildbox",
            name: "Buildbox Prod",
            sshAlias: "buildbox",
            hostname: "",
            user: "deploy",
            port: "22",
            defaultDirectory: "/srv/prod",
            authMode: .password,
            password: ""
        )

        #expect(store.configuration.savedHosts.first?.name == "Buildbox Prod")
        #expect(credentialStore.passwords["ssh:buildbox"] == "secret")
    }

    @Test func taskStateLocalizationSupportsEnglishAndChinese() {
        #expect(
            AppLocalization.localizedString(
                "ai.manager.session.awaiting_approval",
                preferredLanguages: ["en-US"]
            ) == "Awaiting Approval"
        )
        #expect(
            AppLocalization.localizedString(
                "ai.manager.session.awaiting_approval",
                preferredLanguages: ["zh-Hans-CN"]
            ) == "等待审批"
        )
    }

    @Test func commandPayloadAppendsTrailingNewline() {
        #expect(AITerminalManagerStore.commandPayload(for: "ls -la") == "ls -la\n")
        #expect(AITerminalManagerStore.commandPayload(for: "ls -la\n") == "ls -la\n")
        #expect(AITerminalManagerStore.commandPayload(for: "   \n") == nil)
    }

    @Test func textPayloadPreservesRawInput() {
        #expect(AITerminalManagerStore.textPayload(for: "y") == "y")
        #expect(AITerminalManagerStore.textPayload(for: "line1\nline2") == "line1\nline2")
        #expect(AITerminalManagerStore.textPayload(for: "") == nil)
    }

    @Test func detectsCommonSSHAuthenticationPromptsAndFailures() {
        #expect(AITerminalManagerStore.containsSSHPasswordPrompt(in: "deploy@10.0.0.5's password:"))
        #expect(AITerminalManagerStore.containsSSHPasswordPrompt(in: "Password:"))
        #expect(!AITerminalManagerStore.containsSSHPasswordPrompt(in: "deploy@buildbox:~$"))
        #expect(AITerminalManagerStore.containsSSHAuthenticationFailure(in: "Permission denied, please try again."))
        #expect(AITerminalManagerStore.containsSSHAuthenticationFailure(in: "ssh: connect to host 10.0.0.5 port 22: Connection refused"))
    }

    @Test func recentHostRecordsAreUpdatedAndTrimmed() {
        let baseDate = Date(timeIntervalSince1970: 1_000)
        var records: [AITerminalRecentHostRecord] = []

        for offset in 0..<10 {
            records = AITerminalManagerStore.upsertRecentHostRecord(
                records,
                hostID: "ssh:host\(offset)",
                status: .connected,
                now: baseDate.addingTimeInterval(TimeInterval(offset))
            )
        }

        #expect(records.count == 8)
        #expect(records.first?.id == "ssh:host9")

        records = AITerminalManagerStore.upsertRecentHostRecord(
            records,
            hostID: "ssh:host4",
            status: .failed,
            errorSummary: "Permission denied",
            now: baseDate.addingTimeInterval(100)
        )
        #expect(records.first?.id == "ssh:host4")
        #expect(records.first?.status == .failed)
        #expect(records.first?.errorSummary == "Permission denied")
    }

    @Test func reconcilesImportedOverridesAndRecentRecords() {
        let configuration = AITerminalManagerConfiguration(
            savedHosts: [
                AITerminalHost(
                    id: "ssh:saved",
                    name: "Saved",
                    transport: .ssh,
                    sshAlias: "saved",
                    hostname: nil,
                    user: nil,
                    port: nil,
                    defaultDirectory: nil,
                    source: .configurationFile
                ),
            ],
            importedHostOverrides: [
                AITerminalHost(
                    id: "ssh:keep",
                    name: "Keep Override",
                    transport: .ssh,
                    sshAlias: "keep",
                    hostname: nil,
                    user: nil,
                    port: nil,
                    defaultDirectory: nil,
                    source: .configurationFile
                ),
                AITerminalHost(
                    id: "ssh:stale",
                    name: "Stale Override",
                    transport: .ssh,
                    sshAlias: "stale",
                    hostname: nil,
                    user: nil,
                    port: nil,
                    defaultDirectory: nil,
                    source: .configurationFile
                ),
            ],
            recentHosts: [
                .init(id: "ssh:keep", status: .connected),
                .init(id: "ssh:saved", status: .connected),
                .init(id: "ssh:stale", status: .failed),
            ]
        )

        let importedHosts = [
            AITerminalHost(
                id: "ssh:keep",
                name: "Keep",
                transport: .ssh,
                sshAlias: "keep",
                hostname: nil,
                user: nil,
                port: nil,
                defaultDirectory: nil,
                source: .sshConfig
            ),
        ]

        let reconciled = AITerminalManagerStore.reconciledConfiguration(
            configuration,
            importedHosts: importedHosts
        )

        #expect(reconciled.importedHostOverrides.map(\.id) == ["ssh:keep"])
        #expect(reconciled.recentHosts.map(\.id) == ["ssh:keep", "ssh:saved"])
    }

    @Test func duplicateAliasAvoidsCollisions() {
        let host = AITerminalHost(
            id: "configured:deploy@10.0.0.5",
            name: "Buildbox Prod",
            transport: .ssh,
            sshAlias: nil,
            hostname: "10.0.0.5",
            user: "deploy",
            port: 22,
            defaultDirectory: nil,
            source: .configurationFile
        )
        let existingHosts = [
            AITerminalHost(
                id: "ssh:10-0-0-5-copy",
                name: "Buildbox Prod Copy",
                transport: .ssh,
                sshAlias: "10-0-0-5-copy",
                hostname: "10.0.0.5",
                user: "deploy",
                port: 22,
                defaultDirectory: nil,
                source: .configurationFile
            ),
        ]

        let alias = AITerminalManagerStore.duplicateAlias(for: host, existingHosts: existingHosts)
        #expect(alias == "10-0-0-5-copy-2")
    }

    @Test @MainActor func reloadImportedSSHHostsUsesInjectedLoader() {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")

        let store = AITerminalManagerStore(
            appDelegateProvider: { nil },
            configurationURL: tempURL,
            sshConfigHostLoader: {
                [
                    AITerminalHost(
                        id: "ssh:buildbox",
                        name: "Buildbox",
                        transport: .ssh,
                        sshAlias: "buildbox",
                        hostname: "10.0.0.5",
                        user: "deploy",
                        port: 2222,
                        defaultDirectory: nil,
                        source: .sshConfig
                    ),
                ]
            }
        )

        store.reloadImportedSSHHosts()

        #expect(store.importedSSHHosts.map(\.id) == ["ssh:buildbox"])
        #expect(store.mergedImportedHosts.map(\.id) == ["ssh:buildbox"])
    }

    @Test @MainActor func recentRecordReturnsLatestStatusForHost() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")

        let host = AITerminalHost(
            id: "ssh:buildbox",
            name: "Buildbox",
            transport: .ssh,
            sshAlias: "buildbox",
            hostname: "10.0.0.5",
            user: "deploy",
            port: 22,
            defaultDirectory: nil,
            source: .configurationFile
        )
        let configuration = AITerminalManagerConfiguration(
            savedHosts: [host],
            recentHosts: [
                .init(id: host.id, connectedAt: Date(timeIntervalSince1970: 1), status: .connected),
                .init(id: host.id, connectedAt: Date(timeIntervalSince1970: 2), status: .failed, errorSummary: "Permission denied"),
            ]
        )
        let data = try JSONEncoder().encode(configuration)
        try data.write(to: tempURL, options: .atomic)

        let store = AITerminalManagerStore(
            appDelegateProvider: { nil },
            configurationURL: tempURL
        )

        let record = store.recentRecord(for: host)
        #expect(record?.status == .failed)
        #expect(record?.errorSummary == "Permission denied")
    }

    @Test @MainActor func sendCommandRequiresSessionSelection() {
        let store = AITerminalManagerStore(
            appDelegateProvider: { nil },
            configurationURL: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("json")
        )

        store.sendCommand("pwd")

        #expect(store.lastError == L10n.AITerminalManager.selectSessionFirst)
    }
}
