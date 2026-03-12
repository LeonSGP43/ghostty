import SwiftUI

struct AITerminalManagerView: View {
    @EnvironmentObject private var store: AITerminalManagerStore
    @EnvironmentObject private var theme: GhosttyChromeTheme

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
    @State private var showsRuntimeSetup = true
    @State private var showsHostLibrary = false
    @State private var showsWorkspaceLibrary = false
    @State private var showsTaskQueue = true

    var body: some View {
        ZStack {
            GhosttyTintedBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header

                if let lastError = store.lastError, !lastError.isEmpty {
                    errorBanner(lastError)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        shannonStatusStrip

                        HStack(alignment: .top, spacing: 20) {
                            sidebarColumn
                                .frame(width: 400)

                            mainColumn
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
        }
        .frame(minWidth: 1240, minHeight: 780)
        .environment(\.colorScheme, theme.colorScheme)
        .onAppear(perform: syncShannonSetupFromStore)
        .onChange(of: store.configuration.supervisor) { _ in
            syncShannonSetupFromStore()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(L10n.AITerminalManager.title)
                    .font(.title2.weight(.semibold))

                Text(L10n.AITerminalManager.subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 8) {
                Text(L10n.AITerminalManager.launch)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker(L10n.AITerminalManager.launch, selection: $store.launchTarget) {
                    ForEach(AITerminalLaunchTarget.allCases) { target in
                        Text(target.displayName).tag(target)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 16)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)

            Text(message)
                .font(.callout)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.red.opacity(0.18), lineWidth: 1)
        )
    }

    private var shannonStatusStrip: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.AITerminalManager.globalShannon)
                        .font(.headline)
                    Text(L10n.AITerminalManager.shannonDesignReference)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(store.shannonStatusText)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(statusTint(for: store.shannonRunState).opacity(0.14), in: Capsule())
                    .foregroundStyle(statusTint(for: store.shannonRunState))
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5),
                alignment: .leading,
                spacing: 12
            ) {
                statusSummaryCard(
                    title: L10n.AITerminalManager.shannonCurrentMode,
                    value: store.shannonModeLabel,
                    detail: store.supervisorState.displayName
                )
                statusSummaryCard(
                    title: L10n.AITerminalManager.shannonCurrentModel,
                    value: store.shannonModelLabel,
                    detail: shannonRuntimeMode == .embedded
                        ? L10n.AITerminalManager.shannonEmbeddedConfigHint
                        : L10n.AITerminalManager.shannonExternalConfigHint
                )
                statusSummaryCard(
                    title: L10n.AITerminalManager.shannonCurrentEndpoint,
                    value: store.shannonEndpointLabel,
                    detail: store.runtimeStatus.gatewayDisplayName
                )
                statusSummaryCard(
                    title: L10n.AITerminalManager.shannonPrimaryTarget,
                    value: store.shannonPrimarySessionLabel,
                    detail: store.shannonPrimarySession?.workingDirectory ?? "—"
                )
                statusSummaryCard(
                    title: L10n.AITerminalManager.shannonRecentActivity,
                    value: store.runtimeStatus.health.displayName,
                    detail: store.shannonStatusText
                )
            }
        }
        .padding(18)
        .panelSurface()
    }

    private func statusSummaryCard(title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.6)

            Text(value)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)

            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .subpanelSurface()
    }

    private var sidebarColumn: some View {
        VStack(alignment: .leading, spacing: 20) {
            globalShannonPanel
            runtimePanel
        }
    }

    private var mainColumn: some View {
        VStack(alignment: .leading, spacing: 20) {
            sessionsPanel

            HStack(alignment: .top, spacing: 20) {
                selectedSessionPanel
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                supportColumn
                    .frame(width: 360)
            }
        }
    }

    private var globalShannonPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.AITerminalManager.globalShannon)
                    .font(.headline)

                Text(L10n.AITerminalManager.globalShannonDescription)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.AITerminalManager.shannonQuickPrompts)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.6)

                HStack(spacing: 8) {
                    quickPromptButton(L10n.AITerminalManager.shannonQuickPromptInspectCurrent) {
                        shannonPrompt = L10n.AITerminalManager.shannonQuickPromptInspectCurrentValue
                    }
                    quickPromptButton(L10n.AITerminalManager.shannonQuickPromptInspectOther) {
                        shannonPrompt = L10n.AITerminalManager.shannonQuickPromptInspectOtherValue
                    }
                }

                HStack(spacing: 8) {
                    quickPromptButton(L10n.AITerminalManager.shannonQuickPromptOpenRemote) {
                        shannonPrompt = L10n.AITerminalManager.shannonQuickPromptOpenRemoteValue
                    }
                    quickPromptButton(L10n.AITerminalManager.shannonQuickPromptSummarize) {
                        shannonPrompt = L10n.AITerminalManager.shannonQuickPromptSummarizeValue
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.AITerminalManager.shannonPrompt)
                    .font(.headline)

                TextEditor(text: $shannonPrompt)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 140, maxHeight: 180)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    )

                HStack(alignment: .center) {
                    detailLine(
                        label: L10n.AITerminalManager.shannonPrimaryTarget,
                        value: store.shannonPrimarySessionLabel
                    )

                    Spacer()

                    Button(L10n.AITerminalManager.askShannon) {
                        store.askGlobalShannon(shannonPrompt)
                        if store.lastError == nil {
                            shannonPrompt = ""
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!store.runtimeStatus.healthIsUsable || store.shannonPrimarySession == nil)
                }
            }

            if let approval = store.pendingShannonApproval {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(L10n.AITerminalManager.shannonApprovalCard)
                            .font(.headline)
                        Spacer()
                        Image(systemName: "hand.raised.fill")
                            .foregroundStyle(.orange)
                    }

                    Text(approval.tool)
                        .font(.callout.weight(.semibold))

                    Text(approval.args)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))

                    HStack(spacing: 10) {
                        Button(L10n.AITerminalManager.approveAction) {
                            store.respondToShannonApproval(approved: true)
                        }
                        .buttonStyle(.borderedProminent)

                        Button(L10n.AITerminalManager.denyAction) {
                            store.respondToShannonApproval(approved: false)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(14)
                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.orange.opacity(0.16), lineWidth: 1)
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.AITerminalManager.shannonResponse)
                    .font(.headline)

                ScrollView {
                    Text(store.shannonResponse.isEmpty ? L10n.AITerminalManager.shannonResponseEmpty : store.shannonResponse)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(minHeight: 180, maxHeight: 280)
                .padding(12)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )
            }
        }
        .padding(18)
        .panelSurface()
    }

    private func quickPromptButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.medium))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    private var runtimePanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.AITerminalManager.shannonRuntimePanel)
                    .font(.headline)

                Text(L10n.AITerminalManager.shannonRuntimePanelDescription)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            runtimeStatusDetails

            DisclosureGroup(L10n.AITerminalManager.shannonSetup, isExpanded: $showsRuntimeSetup) {
                VStack(alignment: .leading, spacing: 12) {
                    Picker(L10n.AITerminalManager.shannonRuntimeMode, selection: $shannonRuntimeMode) {
                        ForEach(ShannonRuntimeMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(shannonRuntimeMode.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if shannonRuntimeMode == .embedded {
                        runtimeHintPanel(
                            title: L10n.AITerminalManager.shannonEmbeddedConfigTitle,
                            message: L10n.AITerminalManager.shannonEmbeddedConfigHint
                        )
                    } else {
                        runtimeHintPanel(
                            title: L10n.AITerminalManager.shannonExternalConfigTitle,
                            message: L10n.AITerminalManager.shannonExternalConfigHint
                        )

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

                            HStack(alignment: .top, spacing: 10) {
                                Picker(L10n.AITerminalManager.shannonModelTier, selection: $shannonModelTier) {
                                    ForEach(ShannonModelTier.allCases) { tier in
                                        Text(tier.displayName).tag(tier)
                                    }
                                }
                                .frame(maxWidth: 190)

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

                    HStack(spacing: 10) {
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
                .padding(.top, 12)
            }
        }
        .padding(18)
        .panelSurface()
    }

    private var runtimeStatusDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
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
        .padding(14)
        .subpanelSurface()
    }

    private func runtimeHintPanel(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .subpanelSurface()
    }

    private var sessionsPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.AITerminalManager.terminalContext)
                        .font(.headline)
                    Text(L10n.AITerminalManager.terminalContextDescription)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(L10n.AITerminalManager.refreshSnapshot) {
                    store.refresh()
                }
            }

            if store.sessions.isEmpty {
                Text(L10n.AITerminalManager.sessionsEmpty)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .subpanelSurface()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(store.sessions) { session in
                            sessionRow(session)
                        }
                    }
                    .padding(.bottom, 4)
                }
                .frame(minHeight: 240, maxHeight: 320)
            }
        }
        .padding(18)
        .panelSurface()
    }

    private func sessionRow(_ session: AITerminalSessionSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
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

                VStack(alignment: .trailing, spacing: 6) {
                    HStack(spacing: 6) {
                        if store.selectedSessionID == session.id {
                            sessionBadge(L10n.AITerminalManager.selected, tint: .green)
                        }
                        if session.isFocused {
                            sessionBadge(L10n.AITerminalManager.focused, tint: .blue)
                        }
                        sessionBadge(session.managedState.displayName, tint: .accentColor)
                    }

                    if let taskState = session.taskState {
                        Text(taskState.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let taskTitle = session.taskTitle {
                Text(taskTitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Button(store.selectedSessionID == session.id ? L10n.AITerminalManager.selected : L10n.AITerminalManager.select) {
                    store.selectSession(session.id)
                }
                .disabled(store.selectedSessionID == session.id)

                Button(L10n.AITerminalManager.focus) {
                    store.focus(sessionID: session.id)
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
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground(isSelected: store.selectedSessionID == session.id), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    store.selectedSessionID == session.id ? Color.accentColor.opacity(0.7) : Color(nsColor: .separatorColor).opacity(0.12),
                    lineWidth: 1
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onTapGesture {
            store.selectSession(session.id)
        }
    }

    private func rowBackground(isSelected: Bool) -> Color {
        isSelected ? Color.accentColor.opacity(0.08) : Color.white.opacity(theme.isLight ? 0.08 : 0.04)
    }

    private func sessionBadge(_ title: String, tint: Color) -> some View {
        Text(title)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.14), in: Capsule())
            .foregroundStyle(tint)
    }

    private var selectedSessionPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.AITerminalManager.sessionConsole)
                        .font(.headline)

                    Text(L10n.AITerminalManager.sessionConsoleDescription)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            if let session = store.selectedSession {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 12) {
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

                        HStack(spacing: 8) {
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
                    }

                    VStack(alignment: .leading, spacing: 10) {
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
                            .buttonStyle(.borderedProminent)
                            Spacer()
                        }
                    }
                    .padding(14)
                    .subpanelSurface()

                    VStack(alignment: .leading, spacing: 10) {
                        Text(L10n.AITerminalManager.rawInput)
                            .font(.headline)

                        TextEditor(text: $sessionInput)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 96, maxHeight: 140)
                            .padding(8)
                            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
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
                    .padding(14)
                    .subpanelSurface()

                    DisclosureGroup(L10n.AITerminalManager.sessionContext, isExpanded: $showsSessionContext) {
                        VStack(alignment: .leading, spacing: 12) {
                            bufferPanel(
                                title: L10n.AITerminalManager.visibleBuffer,
                                content: store.selectedSessionVisibleText,
                                empty: L10n.AITerminalManager.visibleBufferEmpty,
                                minHeight: 120,
                                maxHeight: 160
                            )
                            bufferPanel(
                                title: L10n.AITerminalManager.screenBuffer,
                                content: store.selectedSessionScreenText,
                                empty: L10n.AITerminalManager.screenBufferEmpty,
                                minHeight: 160,
                                maxHeight: 220
                            )
                        }
                        .padding(.top, 12)
                    }
                }
            } else {
                Text(L10n.AITerminalManager.selectedSessionEmpty)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .subpanelSurface()
            }
        }
        .padding(18)
        .panelSurface()
    }

    private func bufferPanel(
        title: String,
        content: String,
        empty: String,
        minHeight: CGFloat,
        maxHeight: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            ScrollView {
                Text(content.isEmpty ? empty : content)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: minHeight, maxHeight: maxHeight)
            .padding(10)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
        }
        .padding(14)
        .subpanelSurface()
    }

    private var supportColumn: some View {
        VStack(alignment: .leading, spacing: 20) {
            tasksPanel
            connectionsPanel
        }
    }

    private var tasksPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            DisclosureGroup(L10n.AITerminalManager.taskActivity, isExpanded: $showsTaskQueue) {
                VStack(alignment: .leading, spacing: 12) {
                    if store.tasks.isEmpty {
                        Text(L10n.AITerminalManager.taskQueueEmpty)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .subpanelSurface()
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 10) {
                                ForEach(store.tasks) { task in
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Text(task.title)
                                                .font(.headline)
                                            Spacer()
                                            sessionBadge(task.state.displayName, tint: statusTint(for: task.state))
                                        }

                                        Text(task.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)

                                        if let note = task.note, !note.isEmpty {
                                            Text(note)
                                                .font(.callout)
                                                .foregroundStyle(.secondary)
                                        }

                                        HStack(spacing: 8) {
                                            Button(L10n.AITerminalManager.focusSession) {
                                                store.focus(sessionID: task.sessionID)
                                            }
                                            Button(L10n.AITerminalManager.pause) {
                                                store.pauseTask(for: task.sessionID)
                                            }
                                            Button(L10n.AITerminalManager.resume) {
                                                store.resumeTask(for: task.sessionID)
                                            }
                                            Spacer()
                                        }
                                    }
                                    .padding(14)
                                    .subpanelSurface()
                                }
                            }
                            .padding(.top, 12)
                        }
                        .frame(minHeight: 160, maxHeight: 240)
                    }
                }
            }
        }
        .padding(18)
        .panelSurface()
    }

    private var connectionsPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.AITerminalManager.connectionsLibrary)
                    .font(.headline)

                Text(L10n.AITerminalManager.connectionsLibraryDescription)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            DisclosureGroup(L10n.AITerminalManager.hosts, isExpanded: $showsHostLibrary) {
                hostsLibrary
                    .padding(.top, 12)
            }

            DisclosureGroup(L10n.AITerminalManager.workspaces, isExpanded: $showsWorkspaceLibrary) {
                workspacesLibrary
                    .padding(.top, 12)
            }
        }
        .padding(18)
        .panelSurface()
    }

    private var hostsLibrary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Button(L10n.AITerminalManager.openLocalShell) {
                    store.openLocalShell()
                }

                Button(L10n.AITerminalManager.reloadSSHConfig) {
                    store.reloadImportedSSHHosts()
                }
            }

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

                HStack(spacing: 8) {
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
            }
            .textFieldStyle(.roundedBorder)
            .padding(14)
            .subpanelSurface()

            if filteredRecentHosts.isEmpty && filteredSavedHosts.isEmpty && filteredImportedHosts.isEmpty {
                Text(L10n.AITerminalManager.hostsEmpty)
                    .foregroundStyle(.secondary)
                    .padding(14)
                    .subpanelSurface()
            } else {
                if !filteredRecentHosts.isEmpty {
                    hostGroup(title: L10n.AITerminalManager.recentHosts, hosts: filteredRecentHosts)
                }
                if !filteredSavedHosts.isEmpty {
                    hostGroup(title: L10n.AITerminalManager.savedHosts, hosts: filteredSavedHosts)
                }
                if !filteredImportedHosts.isEmpty {
                    hostGroup(title: L10n.AITerminalManager.importedHosts, hosts: filteredImportedHosts)
                }
            }

            hostDetailsSection
        }
    }

    @ViewBuilder
    private func hostGroup(title: String, hosts: [AITerminalHost]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.6)

            VStack(spacing: 8) {
                ForEach(hosts) { host in
                    hostRow(host)
                }
            }
        }
    }

    private func hostRow(_ host: AITerminalHost) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(host.name)
                    .font(.headline)
                Text(host.displaySubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(hostSourceLabel(for: host))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
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
        }
        .padding(14)
        .background(hostRowBackground(for: host), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(nsColor: .separatorColor).opacity(0.12), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14))
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

                HStack(spacing: 8) {
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
        .padding(14)
        .subpanelSurface()
    }

    private var workspacesLibrary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(L10n.AITerminalManager.addLocalWorkspace) {
                store.addWorkspaceFromOpenPanel()
            }

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
            .padding(14)
            .subpanelSurface()

            if store.workspaces.isEmpty {
                Text(L10n.AITerminalManager.workspacesEmpty)
                    .foregroundStyle(.secondary)
                    .padding(14)
                    .subpanelSurface()
            } else {
                VStack(spacing: 10) {
                    ForEach(store.workspaces) { workspace in
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(workspace.name)
                                    .font(.headline)
                                Text(workspace.directory)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 8) {
                                Button(L10n.AITerminalManager.open) {
                                    store.open(workspace: workspace)
                                }
                                Button(L10n.AITerminalManager.remove) {
                                    store.removeWorkspace(workspace)
                                }
                            }
                        }
                        .padding(14)
                        .subpanelSurface()
                    }
                }
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

    private func statusTint(for state: ShannonRunState) -> Color {
        switch state {
        case .idle:
            return .secondary
        case .running:
            return .blue
        case .waitingApproval:
            return .orange
        case .completed:
            return .green
        case .failed:
            return .red
        }
    }

    private func statusTint(for state: AITerminalTaskState) -> Color {
        switch state {
        case .queued:
            return .secondary
        case .active:
            return .accentColor
        case .waitingApproval:
            return .orange
        case .paused:
            return .secondary
        case .completed:
            return .green
        case .failed:
            return .red
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
        selectedHost?.id == host.id ? Color.accentColor.opacity(0.1) : Color.white.opacity(theme.isLight ? 0.08 : 0.04)
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
        .environmentObject(GhosttyChromeTheme())
}
