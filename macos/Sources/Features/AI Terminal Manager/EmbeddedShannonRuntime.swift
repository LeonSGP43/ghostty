import Foundation

struct ShannonRuntimeSessionContext: Sendable {
    let id: UUID
    var title: String
    var hostID: String?
    var hostLabel: String
    var workspaceID: String?
    var workingDirectory: String?
    var managedState: AITerminalManagedState
}

struct ShannonRuntimeHostContext: Sendable {
    var id: String
    var name: String
    var transport: AITerminalTransport
    var sshAlias: String?
    var hostname: String?
    var defaultDirectory: String?
}

struct ShannonRuntimeWorkspaceContext: Sendable {
    var id: String
    var name: String
    var hostID: String
    var directory: String
}

struct ShannonRuntimeRequest: Sendable {
    var userPrompt: String
    var session: ShannonRuntimeSessionContext
    var visibleText: String
    var screenText: String
    var availableHosts: [ShannonRuntimeHostContext]
    var availableWorkspaces: [ShannonRuntimeWorkspaceContext]

    var externalPromptText: String {
        let hostsText = availableHosts.isEmpty
            ? "(none)"
            : availableHosts.map { host in
                let connection = [host.sshAlias, host.hostname]
                    .compactMap { $0 }
                    .filter { !$0.isEmpty }
                    .joined(separator: "/")
                let suffix = connection.isEmpty ? "" : " [\(connection)]"
                return "- \(host.name) (\(host.transport.rawValue))\(suffix)"
            }.joined(separator: "\n")

        let workspacesText = availableWorkspaces.isEmpty
            ? "(none)"
            : availableWorkspaces.map { workspace in
                "- \(workspace.name) [\(workspace.hostID)] \(workspace.directory)"
            }.joined(separator: "\n")

        return """
        You are operating as Ghostty's AI control brain.

        The user is asking about a specific Ghostty terminal session. Analyze the terminal context first. If you need to perform any action that would use tools or change state, request approval through the runtime approval mechanism instead of assuming permission.

        Session title: \(session.title)
        Session host ID: \(session.hostID ?? "unknown")
        Host: \(session.hostLabel)
        Session workspace ID: \(session.workspaceID ?? "none")
        Working directory: \(session.workingDirectory ?? "unknown")
        Managed state: \(session.managedState.rawValue)

        Available hosts:
        \(hostsText)

        Available workspaces:
        \(workspacesText)

        Visible buffer:
        \(visibleText.isEmpty ? "(empty)" : visibleText)

        Screen buffer:
        \(screenText.isEmpty ? "(empty)" : screenText)

        User request:
        \(userPrompt)
        """
    }
}

private enum EmbeddedShannonRuntimeError: LocalizedError {
    case approvalNotFound
    case actionNotFound

    var errorDescription: String? {
        switch self {
        case .approvalNotFound:
            "The pending embedded Shannon approval no longer exists."
        case .actionNotFound:
            "The pending embedded Shannon action no longer exists."
        }
    }
}

private struct EmbeddedShannonPlan {
    var lead: String
    var analysisReply: String
    var deniedReply: String
    var toolName: String?
    var actionSummary: String?
    var action: ShannonProposedAction?
    var prefersChinese: Bool
}

actor EmbeddedShannonRuntime {
    static let shared = EmbeddedShannonRuntime()

    private let bootDate = Date()
    private var pendingApprovals: [String: CheckedContinuation<Bool, Never>] = [:]
    private var bufferedApprovals: [String: Bool] = [:]
    private var pendingActions: [String: CheckedContinuation<ShannonActionExecutionResult, Never>] = [:]
    private var bufferedActionResults: [String: ShannonActionExecutionResult] = [:]

    func fetchRuntimeStatus() -> ShannonRuntimeStatus {
        ShannonRuntimeStatus(
            baseURL: "embedded://ghostty-shannon",
            health: .healthy,
            version: "embedded",
            gatewayConnected: nil,
            activeAgent: "embedded-shannon",
            uptimeSeconds: Int(Date.now.timeIntervalSince(bootDate))
        )
    }

    nonisolated func streamMessage(
        _ request: ShannonRuntimeRequest
    ) -> AsyncThrowingStream<ShannonBridgeEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                await self.run(request, continuation: continuation)
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func submitApproval(id: String, approved: Bool) throws {
        if let continuation = pendingApprovals.removeValue(forKey: id) {
            continuation.resume(returning: approved)
            return
        }

        bufferedApprovals[id] = approved
    }

    func submitActionResult(id: String, result: ShannonActionExecutionResult) throws {
        if let continuation = pendingActions.removeValue(forKey: id) {
            continuation.resume(returning: result)
            return
        }

        bufferedActionResults[id] = result
    }

    private func run(
        _ request: ShannonRuntimeRequest,
        continuation: AsyncThrowingStream<ShannonBridgeEvent, Error>.Continuation
    ) async {
        defer {
            continuation.finish()
        }

        let plan = makePlan(for: request)
        continuation.yield(.delta(plan.lead))

        guard let action = plan.action,
              let toolName = plan.toolName,
              let actionSummary = plan.actionSummary else {
            continuation.yield(.done(
                ShannonBridgeRunResult(
                    reply: plan.analysisReply,
                    sessionID: request.session.id.uuidString,
                    agent: "embedded-shannon"
                )
            ))
            return
        }

        continuation.yield(.tool(.init(tool: toolName, status: "planned", elapsed: nil)))

        if action.requiresApproval {
            let approvalID = UUID().uuidString
            continuation.yield(.approvalNeeded(
                ShannonPendingApproval(
                    id: approvalID,
                    tool: toolName,
                    args: actionSummary,
                    action: action
                )
            ))

            let approved = await waitForApproval(id: approvalID)
            guard !Task.isCancelled else { return }

            continuation.yield(.approvalResult(id: approvalID, approved: approved))

            guard approved else {
                continuation.yield(.failed(plan.deniedReply))
                return
            }

            continuation.yield(.tool(.init(tool: toolName, status: "approved", elapsed: nil)))
        }

        let actionID = UUID().uuidString
        continuation.yield(.actionRequested(.init(
            id: actionID,
            action: action,
            summary: actionSummary
        )))

        let actionResult = await waitForActionResult(id: actionID)
        guard !Task.isCancelled else { return }

        guard actionResult.success else {
            continuation.yield(.failed(actionResult.output))
            return
        }

        continuation.yield(.tool(.init(tool: toolName, status: "completed", elapsed: nil)))
        continuation.yield(.done(
            ShannonBridgeRunResult(
                reply: Self.completionReply(
                    for: action,
                    output: actionResult.output,
                    prefersChinese: plan.prefersChinese
                ),
                sessionID: request.session.id.uuidString,
                agent: "embedded-shannon"
            )
        ))
    }

    private func waitForApproval(id: String) async -> Bool {
        if let buffered = bufferedApprovals.removeValue(forKey: id) {
            return buffered
        }

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                pendingApprovals[id] = continuation
            }
        } onCancel: {
            Task {
                await self.cancelPendingApproval(id: id, approved: false)
            }
        }
    }

    private func cancelPendingApproval(id: String, approved: Bool) {
        guard let continuation = pendingApprovals.removeValue(forKey: id) else { return }
        continuation.resume(returning: approved)
    }

    private func waitForActionResult(id: String) async -> ShannonActionExecutionResult {
        if let buffered = bufferedActionResults.removeValue(forKey: id) {
            return buffered
        }

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                pendingActions[id] = continuation
            }
        } onCancel: {
            Task {
                await self.cancelPendingAction(id: id)
            }
        }
    }

    private func cancelPendingAction(id: String) {
        guard let continuation = pendingActions.removeValue(forKey: id) else { return }
        continuation.resume(
            returning: ShannonActionExecutionResult(
                success: false,
                output: "The embedded Shannon action was cancelled."
            )
        )
    }

    private func makePlan(for request: ShannonRuntimeRequest) -> EmbeddedShannonPlan {
        let prefersChinese = request.userPrompt.range(
            of: #"\p{Han}"#,
            options: .regularExpression
        ) != nil
        let latestLine = Self.latestLine(from: request.screenText, fallback: request.visibleText)
        let workingDirectory = request.session.workingDirectory ?? (prefersChinese ? "未知" : "unknown")
        let bufferAssessment = Self.bufferAssessment(
            screenText: request.screenText,
            latestLine: latestLine,
            prefersChinese: prefersChinese
        )

        if let action = Self.proposedAction(request) {
            let lead = if prefersChinese {
                """
                我已经分析了当前 tab，并整理了可用的 Ghostty 原生上下文。
                工作目录：\(workingDirectory)
                最新输出：\(latestLine)
                当前判断：\(bufferAssessment)
                """
            } else {
                """
                I analyzed the current tab and resolved the available Ghostty-native context.
                Working directory: \(workingDirectory)
                Latest terminal line: \(latestLine)
                Current assessment: \(bufferAssessment)
                """
            }

            let deniedReply = if prefersChinese {
                "该动作未获批准，Ghostty 不会修改当前终端。"
            } else {
                "The action was not approved, so Ghostty will not change the current terminal."
            }

            return EmbeddedShannonPlan(
                lead: lead,
                analysisReply: prefersChinese ? "请求已结束。" : "The request finished.",
                deniedReply: deniedReply,
                toolName: action.kind.rawValue,
                actionSummary: Self.actionDescription(
                    action,
                    request: request,
                    prefersChinese: prefersChinese
                ),
                action: action,
                prefersChinese: prefersChinese
            )
        }

        let reply = if prefersChinese {
            """
            当前会话：\(request.session.title)
            主机：\(request.session.hostLabel)
            工作目录：\(workingDirectory)
            最近终端输出：\(latestLine)
            状态判断：\(bufferAssessment)

            我目前只做了分析，没有规划任何会改变 tab 状态的动作。
            """
        } else {
            """
            Session: \(request.session.title)
            Host: \(request.session.hostLabel)
            Working directory: \(workingDirectory)
            Latest terminal line: \(latestLine)
            Assessment: \(bufferAssessment)

            I only analyzed the tab state and did not plan any state-changing action.
            """
        }

        return EmbeddedShannonPlan(
            lead: prefersChinese ? "正在分析当前 Ghostty tab 上下文。" : "Analyzing the current Ghostty tab context.",
            analysisReply: reply,
            deniedReply: prefersChinese ? "请求已结束。" : "The request finished.",
            prefersChinese: prefersChinese
        )
    }

    private static func proposedAction(_ request: ShannonRuntimeRequest) -> ShannonProposedAction? {
        let userPrompt = request.userPrompt

        if let command = extractQuotedCommand(from: userPrompt) {
            return ShannonProposedAction(
                targetSessionID: request.session.id,
                kind: prefersRawInput(prompt: userPrompt) ? .sendInput : .sendCommand,
                payload: command
            )
        }

        if let command = extractCommandPayload(from: userPrompt) {
            return ShannonProposedAction(
                targetSessionID: request.session.id,
                kind: prefersRawInput(prompt: userPrompt) ? .sendInput : .sendCommand,
                payload: command
            )
        }

        let normalized = userPrompt.lowercased()
        let matchedWorkspace = resolveWorkspace(in: request)
        let matchedHost = resolveHost(in: request)
        let currentDirectory = mentionsSameDirectory(userPrompt) ? request.session.workingDirectory : nil

        if normalized.contains("read tab")
            || normalized.contains("read the tab")
            || normalized.contains("inspect tab")
            || normalized.contains("capture tab")
            || userPrompt.contains("读取")
            || userPrompt.contains("重新读")
            || userPrompt.contains("扫描") {
            return ShannonProposedAction(
                targetSessionID: request.session.id,
                kind: .readTab,
                payload: nil
            )
        }

        if isCreateLocalTabRequest(userPrompt) {
            return ShannonProposedAction(
                targetSessionID: request.session.id,
                kind: .createLocalTab,
                payload: nil,
                hostID: AITerminalHost.local.id,
                workspaceID: matchedWorkspace?.hostID == AITerminalHost.local.id ? matchedWorkspace?.id : nil,
                directoryOverride: currentDirectory
            )
        }

        if isCreateTabRequest(userPrompt) {
            if let matchedWorkspace {
                let host = request.availableHosts.first(where: { $0.id == matchedWorkspace.hostID })
                return ShannonProposedAction(
                    targetSessionID: request.session.id,
                    kind: host?.transport == .local ? .createLocalTab : .createRemoteTab,
                    payload: nil,
                    hostID: matchedWorkspace.hostID,
                    workspaceID: matchedWorkspace.id
                )
            }

            if let matchedHost, matchedHost.transport == .ssh {
                return ShannonProposedAction(
                    targetSessionID: request.session.id,
                    kind: .createRemoteTab,
                    payload: nil,
                    hostID: matchedHost.id,
                    directoryOverride: currentDirectory
                )
            }

            if request.session.hostID == AITerminalHost.local.id {
                return ShannonProposedAction(
                    targetSessionID: request.session.id,
                    kind: .createLocalTab,
                    payload: nil,
                    hostID: AITerminalHost.local.id,
                    workspaceID: request.session.workspaceID,
                    directoryOverride: currentDirectory
                )
            }

            if let currentRemoteHostID = request.session.hostID,
               request.availableHosts.contains(where: { $0.id == currentRemoteHostID && $0.transport == .ssh }) {
                return ShannonProposedAction(
                    targetSessionID: request.session.id,
                    kind: .createRemoteTab,
                    payload: nil,
                    hostID: currentRemoteHostID,
                    workspaceID: request.session.workspaceID,
                    directoryOverride: currentDirectory
                )
            }
        }

        if normalized.contains("close tab")
            || normalized.contains("close session")
            || userPrompt.contains("关闭")
            || userPrompt.contains("关掉") {
            return ShannonProposedAction(
                targetSessionID: request.session.id,
                kind: .closeTab,
                payload: nil
            )
        }

        if normalized.contains("focus")
            || userPrompt.contains("聚焦")
            || userPrompt.contains("切到") {
            return ShannonProposedAction(
                targetSessionID: request.session.id,
                kind: .focusSession,
                payload: nil
            )
        }

        return nil
    }

    private static func extractQuotedCommand(from prompt: String) -> String? {
        guard let start = prompt.firstIndex(of: "`"),
              let end = prompt[prompt.index(after: start)...].firstIndex(of: "`")
        else {
            return nil
        }

        let command = String(prompt[prompt.index(after: start)..<end])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return command.isEmpty ? nil : command
    }

    private static func extractCommandPayload(from prompt: String) -> String? {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()

        let englishPrefixes = [
            "run ",
            "run:",
            "execute ",
            "execute:",
            "send command ",
            "send command:",
            "send input ",
            "send input:",
            "type ",
            "type:",
        ]

        for prefix in englishPrefixes where lowercased.hasPrefix(prefix) {
            let index = trimmed.index(trimmed.startIndex, offsetBy: prefix.count)
            let payload = String(trimmed[index...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !payload.isEmpty {
                return payload
            }
        }

        let chinesePrefixes = [
            "运行 ",
            "运行：",
            "运行:",
            "执行 ",
            "执行：",
            "执行:",
            "发送命令 ",
            "发送命令：",
            "发送命令:",
            "输入 ",
            "输入：",
            "输入:",
        ]

        for prefix in chinesePrefixes where trimmed.hasPrefix(prefix) {
            let index = trimmed.index(trimmed.startIndex, offsetBy: prefix.count)
            let payload = String(trimmed[index...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !payload.isEmpty {
                return payload
            }
        }

        return nil
    }

    private static func prefersRawInput(prompt: String) -> Bool {
        let normalized = prompt.lowercased()
        return normalized.contains("send input")
            || normalized.contains("type ")
            || prompt.contains("输入")
    }

    private static func isCreateTabRequest(_ prompt: String) -> Bool {
        let normalized = prompt.lowercased()
        return normalized.contains("new tab")
            || normalized.contains("open tab")
            || normalized.contains("create tab")
            || normalized.contains("ssh ")
            || normalized.contains("remote tab")
            || prompt.contains("新建")
            || prompt.contains("开个")
            || prompt.contains("打开")
            || prompt.contains("远程")
            || prompt.contains("标签页")
    }

    private static func isCreateLocalTabRequest(_ prompt: String) -> Bool {
        let normalized = prompt.lowercased()
        return normalized.contains("local tab")
            || normalized.contains("local shell")
            || prompt.contains("本地")
            || prompt.contains("本机")
            || prompt.contains("当前机器")
    }

    private static func mentionsSameDirectory(_ prompt: String) -> Bool {
        let normalized = prompt.lowercased()
        return normalized.contains("same dir")
            || normalized.contains("same directory")
            || normalized.contains("current directory")
            || prompt.contains("同目录")
            || prompt.contains("当前目录")
    }

    private static func resolveWorkspace(in request: ShannonRuntimeRequest) -> ShannonRuntimeWorkspaceContext? {
        let normalized = request.userPrompt.lowercased()

        if let currentWorkspaceID = request.session.workspaceID,
           request.availableWorkspaces.contains(where: { $0.id == currentWorkspaceID }),
           mentionsSameDirectory(request.userPrompt) {
            return request.availableWorkspaces.first(where: { $0.id == currentWorkspaceID })
        }

        return request.availableWorkspaces.first { workspace in
            normalized.contains(workspace.name.lowercased())
                || normalized.contains(workspace.id.lowercased())
        }
    }

    private static func resolveHost(in request: ShannonRuntimeRequest) -> ShannonRuntimeHostContext? {
        let normalized = request.userPrompt.lowercased()
        return request.availableHosts.first { host in
            let candidates = [
                host.id,
                host.name,
                host.sshAlias,
                host.hostname,
            ]
            .compactMap { $0?.lowercased() }
            return candidates.contains { candidate in
                !candidate.isEmpty && normalized.contains(candidate)
            }
        }
    }

    private static func latestLine(from screenText: String, fallback visibleText: String) -> String {
        lastMeaningfulLine(in: screenText)
            ?? lastMeaningfulLine(in: visibleText)
            ?? "(empty)"
    }

    private static func lastMeaningfulLine(in text: String) -> String? {
        text.split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .last(where: { !$0.isEmpty })
    }

    private static func bufferAssessment(
        screenText: String,
        latestLine: String,
        prefersChinese: Bool
    ) -> String {
        let normalized = screenText.lowercased()
        if normalized.contains("permission denied") || normalized.contains("error") || normalized.contains("failed") {
            return prefersChinese ? "检测到错误或失败输出" : "error or failure output detected"
        }

        if latestLine.hasSuffix("$")
            || latestLine.hasSuffix("#")
            || latestLine.hasSuffix(">")
            || latestLine.hasSuffix("%") {
            return prefersChinese ? "看起来在等待下一条命令" : "the shell looks idle and ready for the next command"
        }

        return prefersChinese ? "终端仍在运行或输出中" : "the terminal still looks active"
    }

    private static func actionDescription(
        _ action: ShannonProposedAction,
        request: ShannonRuntimeRequest,
        prefersChinese: Bool
    ) -> String {
        switch action.kind {
        case .sendCommand:
            return prefersChinese
                ? "发送命令 `\(action.payload ?? "")`"
                : "send command `\(action.payload ?? "")`"
        case .sendInput:
            return prefersChinese
                ? "发送原始输入 `\(action.payload ?? "")`"
                : "send raw input `\(action.payload ?? "")`"
        case .focusSession:
            return prefersChinese ? "聚焦当前 tab" : "focus the current tab"
        case .closeSession:
            return prefersChinese ? "关闭当前 tab" : "close the current tab"
        case .createLocalTab:
            if let workspace = request.availableWorkspaces.first(where: { $0.id == action.workspaceID }) {
                return prefersChinese
                    ? "创建本地 tab 并打开工作区 \(workspace.name)"
                    : "create a local tab for workspace \(workspace.name)"
            }

            if let directoryOverride = action.directoryOverride, !directoryOverride.isEmpty {
                return prefersChinese
                    ? "创建本地 tab，并切到目录 \(directoryOverride)"
                    : "create a local tab in \(directoryOverride)"
            }

            return prefersChinese ? "创建新的本地 tab" : "create a new local tab"
        case .createRemoteTab:
            if let workspace = request.availableWorkspaces.first(where: { $0.id == action.workspaceID }) {
                return prefersChinese
                    ? "创建远程 tab 并打开工作区 \(workspace.name)"
                    : "create a remote tab for workspace \(workspace.name)"
            }

            let hostName = request.availableHosts.first(where: { $0.id == action.hostID })?.name ?? action.hostID ?? "remote"
            return prefersChinese
                ? "创建连接到 \(hostName) 的远程 tab"
                : "create a remote tab connected to \(hostName)"
        case .readTab:
            return prefersChinese ? "读取当前 tab 快照" : "read the current tab snapshot"
        case .closeTab:
            return prefersChinese ? "关闭当前 tab" : "close the current tab"
        }
    }

    private static func completionReply(
        for action: ShannonProposedAction,
        output: String,
        prefersChinese: Bool
    ) -> String {
        switch action.kind {
        case .readTab:
            return output
        case .sendCommand, .sendInput, .focusSession, .closeSession, .createLocalTab, .createRemoteTab, .closeTab:
            if prefersChinese {
                return "Ghostty 已执行该动作：\(output)"
            }
            return "Ghostty executed the requested action: \(output)"
        }
    }
}
