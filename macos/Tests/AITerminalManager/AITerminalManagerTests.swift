import Testing
import Foundation
@testable import Ghostty

struct AITerminalManagerTests {
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

        #expect(store.configuration.hosts.count == 1)
        #expect(store.configuration.hosts.first?.sshAlias == "buildbox")
        #expect(store.configuration.hosts.first?.port == 2222)
        #expect(store.configuration.hosts.first?.id == "ssh:buildbox")
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

        #expect(store.configuration.hosts.count == 1)
        #expect(store.configuration.hosts.first?.name == "Buildbox Prod")
        #expect(store.configuration.hosts.first?.port == 2200)
        #expect(store.configuration.hosts.first?.defaultDirectory == "/srv/prod")
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
