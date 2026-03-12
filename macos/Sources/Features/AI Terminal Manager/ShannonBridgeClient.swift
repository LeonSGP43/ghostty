import Foundation

private struct ShannonBridgeHealthResponse: Decodable {
    var status: String
    var version: String?
}

private struct ShannonBridgeStatusResponse: Decodable {
    var isConnected: Bool
    var activeAgent: String?
    var uptime: Int
    var version: String?
}

private struct ShannonBridgeTextDelta: Decodable {
    var text: String
}

struct ShannonBridgeToolPayload: Decodable, Equatable, Sendable {
    var tool: String
    var status: String
    var elapsed: Double?
}

private struct ShannonBridgeApprovalPayload: Decodable {
    var id: String
    var tool: String
    var args: String
}

private struct ShannonBridgeApprovalResultPayload: Decodable {
    var id: String
    var approved: Bool
}

private struct ShannonBridgeErrorPayload: Decodable {
    var error: String
}

struct ShannonBridgeRunResult: Decodable, Equatable, Sendable {
    var reply: String
    var sessionID: String
    var agent: String

    enum CodingKeys: String, CodingKey {
        case reply
        case sessionID = "session_id"
        case agent
    }
}

struct ShannonActionRequest: Equatable, Identifiable, Sendable {
    let id: String
    var action: ShannonProposedAction
    var summary: String
}

struct ShannonActionExecutionResult: Equatable, Sendable {
    var success: Bool
    var output: String
    var sessionID: UUID?
    var sessionTitle: String?

    init(
        success: Bool,
        output: String,
        sessionID: UUID? = nil,
        sessionTitle: String? = nil
    ) {
        self.success = success
        self.output = output
        self.sessionID = sessionID
        self.sessionTitle = sessionTitle
    }
}

enum ShannonBridgeEvent: Equatable, Sendable {
    case delta(String)
    case tool(ShannonBridgeToolPayload)
    case approvalNeeded(ShannonPendingApproval)
    case approvalResult(id: String, approved: Bool)
    case actionRequested(ShannonActionRequest)
    case done(ShannonBridgeRunResult)
    case failed(String)
}

private struct ShannonBridgeRunRequest: Encodable {
    var text: String
    var approvalMode: String

    enum CodingKeys: String, CodingKey {
        case text
        case approvalMode = "approval_mode"
    }
}

private struct ShannonBridgeApprovalDecision: Encodable {
    var approved: Bool
}

private enum ShannonBridgeClientError: LocalizedError {
    case invalidBaseURL
    case invalidResponse
    case unexpectedStatus(Int)
    case unsupportedActionResults

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            "Invalid Shannon runtime URL."
        case .invalidResponse:
            "Invalid Shannon runtime response."
        case .unexpectedStatus(let status):
            "Shannon runtime returned HTTP \(status)."
        case .unsupportedActionResults:
            "This Shannon runtime does not accept Ghostty-native action results."
        }
    }
}

struct ShannonBridgeClient {
    private let embeddedRuntime = EmbeddedShannonRuntime.shared

    func fetchRuntimeStatus(
        configuration: ShannonSupervisorConfiguration
    ) async -> ShannonRuntimeStatus {
        if configuration.isEmbeddedRuntime {
            return await embeddedRuntime.fetchRuntimeStatus()
        }

        guard let baseURL = configuration.resolvedControlURL else {
            return .unavailable
        }

        do {
            let health: ShannonBridgeHealthResponse = try await request(
                baseURL: baseURL,
                path: "health",
                configuration: configuration
            )

            var runtime = ShannonRuntimeStatus(
                baseURL: baseURL.absoluteString,
                health: health.status == "ok" ? .healthy : .unreachable(message: health.status),
                version: health.version,
                gatewayConnected: nil,
                activeAgent: nil,
                uptimeSeconds: nil
            )

            if let status: ShannonBridgeStatusResponse = try? await request(
                baseURL: baseURL,
                path: "status",
                configuration: configuration
            ) {
                runtime.version = status.version ?? runtime.version
                runtime.gatewayConnected = status.isConnected
                runtime.activeAgent = status.activeAgent
                runtime.uptimeSeconds = status.uptime
            }

            return runtime
        } catch {
            return ShannonRuntimeStatus(
                baseURL: baseURL.absoluteString,
                health: .unreachable(message: error.localizedDescription),
                version: nil,
                gatewayConnected: nil,
                activeAgent: nil,
                uptimeSeconds: nil
            )
        }
    }

    func streamMessage(
        configuration: ShannonSupervisorConfiguration,
        request: ShannonRuntimeRequest
    ) -> AsyncThrowingStream<ShannonBridgeEvent, Error> {
        if configuration.isEmbeddedRuntime {
            return embeddedRuntime.streamMessage(request)
        }

        return streamExternalMessage(
            configuration: configuration,
            text: request.externalPromptText
        )
    }

    func submitApproval(
        configuration: ShannonSupervisorConfiguration,
        approvalID: String,
        approved: Bool
    ) async throws {
        if configuration.isEmbeddedRuntime {
            try await embeddedRuntime.submitApproval(id: approvalID, approved: approved)
            return
        }

        guard let baseURL = configuration.resolvedControlURL else {
            throw ShannonBridgeClientError.invalidBaseURL
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("approvals/\(approvalID)"))
        request.httpMethod = "POST"
        request.timeoutInterval = TimeInterval(max(configuration.requestTimeoutSeconds, 1))
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            ShannonBridgeApprovalDecision(approved: approved)
        )

        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.timeoutIntervalForRequest = TimeInterval(
            max(configuration.requestTimeoutSeconds, 1)
        )
        let session = URLSession(configuration: sessionConfiguration)
        defer { session.invalidateAndCancel() }

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ShannonBridgeClientError.invalidResponse
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            throw ShannonBridgeClientError.unexpectedStatus(httpResponse.statusCode)
        }
    }

    func submitActionResult(
        configuration: ShannonSupervisorConfiguration,
        actionID: String,
        result: ShannonActionExecutionResult
    ) async throws {
        guard configuration.isEmbeddedRuntime else {
            throw ShannonBridgeClientError.unsupportedActionResults
        }

        try await embeddedRuntime.submitActionResult(id: actionID, result: result)
    }

    private func streamExternalMessage(
        configuration: ShannonSupervisorConfiguration,
        text: String
    ) -> AsyncThrowingStream<ShannonBridgeEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard let baseURL = configuration.resolvedControlURL else {
                        throw ShannonBridgeClientError.invalidBaseURL
                    }

                    var request = URLRequest(url: baseURL.appendingPathComponent("message"))
                    request.httpMethod = "POST"
                    request.timeoutInterval = TimeInterval(max(configuration.requestTimeoutSeconds, 1))
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.httpBody = try JSONEncoder().encode(
                        ShannonBridgeRunRequest(text: text, approvalMode: "manual")
                    )

                    let sessionConfiguration = URLSessionConfiguration.ephemeral
                    sessionConfiguration.timeoutIntervalForRequest = TimeInterval(
                        max(configuration.requestTimeoutSeconds, 1)
                    )
                    let session = URLSession(configuration: sessionConfiguration)
                    defer { session.invalidateAndCancel() }

                    let (bytes, response) = try await session.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw ShannonBridgeClientError.invalidResponse
                    }
                    guard 200..<300 ~= httpResponse.statusCode else {
                        throw ShannonBridgeClientError.unexpectedStatus(httpResponse.statusCode)
                    }

                    var currentEvent = "message"
                    var dataLines: [String] = []

                    for try await rawLine in bytes.lines {
                        let line = String(rawLine)
                        if line.isEmpty {
                            try emitSSEEvent(
                                named: currentEvent,
                                dataLines: dataLines,
                                continuation: continuation
                            )
                            currentEvent = "message"
                            dataLines.removeAll(keepingCapacity: true)
                            continue
                        }

                        if line.hasPrefix("event:") {
                            currentEvent = String(line.dropFirst("event:".count))
                                .trimmingCharacters(in: .whitespaces)
                            continue
                        }

                        if line.hasPrefix("data:") {
                            dataLines.append(
                                String(line.dropFirst("data:".count))
                                    .trimmingCharacters(in: .whitespaces)
                            )
                        }
                    }

                    if !dataLines.isEmpty {
                        try emitSSEEvent(
                            named: currentEvent,
                            dataLines: dataLines,
                            continuation: continuation
                        )
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func request<Response: Decodable>(
        baseURL: URL,
        path: String,
        configuration: ShannonSupervisorConfiguration
    ) async throws -> Response {
        let url = baseURL.appendingPathComponent(path)

        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.timeoutIntervalForRequest = TimeInterval(
            max(configuration.requestTimeoutSeconds, 1)
        )
        let session = URLSession(configuration: sessionConfiguration)
        defer { session.invalidateAndCancel() }

        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ShannonBridgeClientError.invalidResponse
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            throw ShannonBridgeClientError.unexpectedStatus(httpResponse.statusCode)
        }

        return try JSONDecoder().decode(Response.self, from: data)
    }

    private func emitSSEEvent(
        named event: String,
        dataLines: [String],
        continuation: AsyncThrowingStream<ShannonBridgeEvent, Error>.Continuation
    ) throws {
        let data = dataLines.joined(separator: "\n")
        guard !data.isEmpty else { return }
        let encoded = Data(data.utf8)

        switch event {
        case "delta":
            let payload = try JSONDecoder().decode(ShannonBridgeTextDelta.self, from: encoded)
            continuation.yield(.delta(payload.text))
        case "tool":
            let payload = try JSONDecoder().decode(ShannonBridgeToolPayload.self, from: encoded)
            continuation.yield(.tool(payload))
        case "approval_needed":
            let payload = try JSONDecoder().decode(ShannonBridgeApprovalPayload.self, from: encoded)
            continuation.yield(
                .approvalNeeded(
                    ShannonPendingApproval(id: payload.id, tool: payload.tool, args: payload.args)
                )
            )
        case "approval_result":
            let payload = try JSONDecoder().decode(ShannonBridgeApprovalResultPayload.self, from: encoded)
            continuation.yield(.approvalResult(id: payload.id, approved: payload.approved))
        case "done":
            let payload = try JSONDecoder().decode(ShannonBridgeRunResult.self, from: encoded)
            continuation.yield(.done(payload))
        case "error":
            let payload = try JSONDecoder().decode(ShannonBridgeErrorPayload.self, from: encoded)
            continuation.yield(.failed(payload.error))
        default:
            break
        }
    }
}
