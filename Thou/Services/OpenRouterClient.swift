/**
 Alice 模式的云端模型访问客户端。

 这个文件负责向 OpenRouter 发起流式聊天请求，
 并把服务端返回的增量内容解码成 Thou 前端可消费的 ChatDelta 流。
 */

import Foundation
import Combine

class OpenRouterClient: ObservableObject {
    private enum DiagnosticsKey {
        static let model = "AliceLastOpenRouterModel"
        static let messageCount = "AliceLastOpenRouterMessageCount"
        static let messageRoles = "AliceLastOpenRouterMessageRoles"
        static let requestSummary = "AliceLastOpenRouterRequestSummary"
        static let reasoningEnabled = "AliceLastOpenRouterReasoningEnabled"
        static let statusCode = "AliceLastOpenRouterStatusCode"
        static let responseBody = "AliceLastOpenRouterResponseBody"
    }

    private enum RetryPolicy {
        static let maxAttempts = 3
        static let retryableStatusCodes: Set<Int> = [500]
        static let delayNanoseconds: UInt64 = 800_000_000
    }

    private let baseURL = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
    private let apiKey: String
    private let authorizationHeader: String
    private let session: URLSession
    
    init(apiKey: String) {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.apiKey = trimmedKey
        self.authorizationHeader = "Bearer \(trimmedKey)"

        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpAdditionalHeaders = [
            "Authorization": authorizationHeader,
            "Content-Type": "application/json",
            "Accept": "text/event-stream",
            "HTTP-Referer": "https://thou-ios.local",
            "X-OpenRouter-Title": "Thou iOS"
        ]
        self.session = URLSession(configuration: configuration)
    }
    
    func streamChat(messages: [Message], model: String = AliceConfigStore.defaultModel) async throws -> AsyncThrowingStream<ChatDelta, Error> {
        var payload: [String: Any] = [
            "model": model,
            "messages": messages.map(payloadMessage),
            "stream": true
        ]

        let reasoningEnabled = Self.supportsReasoningEffort(for: model)
        if reasoningEnabled {
            payload["reasoning"] = [
                "effort": "high",
                "exclude": false
            ]
        }
        
        let requestDebugSummary = Self.requestDebugSummary(apiKey: apiKey, authorizationHeader: authorizationHeader)
        Self.storeDiagnostics(
            model: model,
            messagePayloads: payload["messages"] as? [[String: Any]] ?? [],
            requestDebugSummary: annotatedSummary(requestDebugSummary, attempt: 1),
            reasoningEnabled: reasoningEnabled,
            statusCode: nil,
            responseBody: nil
        )

        var lastRetryableError: OpenRouterRequestError?
        for attempt in 1...RetryPolicy.maxAttempts {
            do {
                return try await streamChatRequest(
                    payload: payload,
                    model: model,
                    requestDebugSummary: annotatedSummary(requestDebugSummary, attempt: attempt),
                    reasoningEnabled: reasoningEnabled
                )
            } catch let requestError as OpenRouterRequestError {
                guard Self.shouldRetry(statusCode: requestError.statusCode), attempt < RetryPolicy.maxAttempts else {
                    lastRetryableError = requestError
                    break
                }

                lastRetryableError = requestError
                try await Task.sleep(nanoseconds: RetryPolicy.delayNanoseconds)
            }
        }

        return try await fallbackNonStreamingChat(
            from: payload,
            model: model,
            requestDebugSummary: annotatedSummary(requestDebugSummary, fallbackFrom: lastRetryableError),
            reasoningEnabled: reasoningEnabled
        )
    }

    private func streamChatRequest(
        payload: [String: Any],
        model: String,
        requestDebugSummary: String,
        reasoningEnabled: Bool
    ) async throws -> AsyncThrowingStream<ChatDelta, Error> {
        var request = makeRequest(accept: "text/event-stream")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (result, response) = try await session.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            var responseBody = ""
            for try await line in result.lines {
                responseBody += line
            }
            Self.storeDiagnostics(
                model: model,
                messagePayloads: payload["messages"] as? [[String: Any]] ?? [],
                requestDebugSummary: requestDebugSummary,
                reasoningEnabled: reasoningEnabled,
                statusCode: httpResponse.statusCode,
                responseBody: responseBody
            )
            throw OpenRouterRequestError(
                statusCode: httpResponse.statusCode,
                responseBody: responseBody,
                requestDebugSummary: requestDebugSummary
            )
        }

        Self.storeDiagnostics(
            model: model,
            messagePayloads: payload["messages"] as? [[String: Any]] ?? [],
            requestDebugSummary: requestDebugSummary,
            reasoningEnabled: reasoningEnabled,
            statusCode: httpResponse.statusCode,
            responseBody: "<streaming>"
        )

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await line in result.lines {
                        if line.hasPrefix("data: ") {
                            let dataString = String(line.dropFirst(6))
                            if dataString == "[DONE]" {
                                continuation.finish()
                                return
                            }

                            if let data = dataString.data(using: .utf8),
                               let chunk = try? JSONDecoder().decode(OpenRouterResponse.self, from: data),
                               let delta = chunk.choices.first?.delta {
                                continuation.yield(delta)
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func fallbackNonStreamingChat(
        from streamingPayload: [String: Any],
        model: String,
        requestDebugSummary: String,
        reasoningEnabled: Bool
    ) async throws -> AsyncThrowingStream<ChatDelta, Error> {
        var payload = streamingPayload
        payload["stream"] = false

        var request = makeRequest(accept: "application/json")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        var lastError: OpenRouterRequestError?
        var successfulData: Data?

        for attempt in 1...RetryPolicy.maxAttempts {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }

            let responseBody = String(data: data, encoding: .utf8) ?? ""
            let attemptSummary = requestDebugSummary + "，fallback=non-stream，attempt=\(attempt)/\(RetryPolicy.maxAttempts)"
            Self.storeDiagnostics(
                model: model,
                messagePayloads: payload["messages"] as? [[String: Any]] ?? [],
                requestDebugSummary: attemptSummary,
                reasoningEnabled: reasoningEnabled,
                statusCode: httpResponse.statusCode,
                responseBody: responseBody.isEmpty ? "<empty>" : responseBody
            )

            if (200...299).contains(httpResponse.statusCode) {
                successfulData = data
                break
            }

            let requestError = OpenRouterRequestError(
                statusCode: httpResponse.statusCode,
                responseBody: responseBody,
                requestDebugSummary: attemptSummary
            )
            lastError = requestError

            guard Self.shouldRetry(statusCode: httpResponse.statusCode), attempt < RetryPolicy.maxAttempts else {
                throw requestError
            }

            try await Task.sleep(nanoseconds: RetryPolicy.delayNanoseconds)
        }

        guard let successfulData else {
            throw lastError ?? URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(OpenRouterNonStreamingResponse.self, from: successfulData)
        let message = decoded.choices.first?.message

        return AsyncThrowingStream { continuation in
            if let message {
                continuation.yield(
                    ChatDelta(
                        content: message.content,
                        reasoning: message.reasoning,
                        reasoningDetails: message.reasoningDetails
                    )
                )
            }
            continuation.finish()
        }
    }

    private func makeRequest(accept: String) -> URLRequest {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("https://thou-ios.local", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("Thou iOS", forHTTPHeaderField: "X-OpenRouter-Title")
        request.timeoutInterval = 120
        return request
    }

    private func payloadMessage(from message: Message) -> [String: Any] {
        [
            "role": message.role,
            "content": message.content
        ]
    }

    private func annotatedSummary(_ summary: String, attempt: Int) -> String {
        summary + "，stream-attempt=\(attempt)/\(RetryPolicy.maxAttempts)"
    }

    private func annotatedSummary(_ summary: String, fallbackFrom error: OpenRouterRequestError?) -> String {
        guard let error else {
            return summary + "，fallback=non-stream"
        }
        return summary + "，fallback=non-stream，streamFailedStatus=\(error.statusCode)"
    }

    private static func requestDebugSummary(apiKey: String, authorizationHeader: String) -> String {
        let hasWhitespace = apiKey.rangeOfCharacter(from: .whitespacesAndNewlines) != nil
        let hasControl = apiKey.rangeOfCharacter(from: .controlCharacters) != nil
        let hasNonASCII = apiKey.unicodeScalars.contains { !$0.isASCII }
        let keyPrefix = String(apiKey.prefix(6))
        let keySuffix = String(apiKey.suffix(4))
        return "authHeaderLen=\(authorizationHeader.count)，keyLen=\(apiKey.count)，prefix=\(keyPrefix)，suffix=\(keySuffix)，空白=\(hasWhitespace ? "是" : "否")，控制符=\(hasControl ? "是" : "否")，非 ASCII=\(hasNonASCII ? "是" : "否")"
    }

    private static func supportsReasoningEffort(for model: String) -> Bool {
        let normalizedModel = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !normalizedModel.hasPrefix("x-ai/")
    }

    private static func shouldRetry(statusCode: Int) -> Bool {
        RetryPolicy.retryableStatusCodes.contains(statusCode)
    }

    private static func storeDiagnostics(
        model: String,
        messagePayloads: [[String: Any]],
        requestDebugSummary: String,
        reasoningEnabled: Bool,
        statusCode: Int?,
        responseBody: String?
    ) {
        let defaults = UserDefaults.standard
        defaults.set(model, forKey: DiagnosticsKey.model)
        defaults.set(messagePayloads.count, forKey: DiagnosticsKey.messageCount)
        defaults.set(messagePayloads.compactMap { $0["role"] as? String }.joined(separator: ","), forKey: DiagnosticsKey.messageRoles)
        defaults.set(requestDebugSummary, forKey: DiagnosticsKey.requestSummary)
        defaults.set(reasoningEnabled, forKey: DiagnosticsKey.reasoningEnabled)

        if let statusCode {
            defaults.set(statusCode, forKey: DiagnosticsKey.statusCode)
        } else {
            defaults.removeObject(forKey: DiagnosticsKey.statusCode)
        }

        if let responseBody {
            defaults.set(String(responseBody.prefix(500)), forKey: DiagnosticsKey.responseBody)
        } else {
            defaults.removeObject(forKey: DiagnosticsKey.responseBody)
        }
    }
}

struct OpenRouterRequestError: LocalizedError {
    let statusCode: Int
    let responseBody: String
    let requestDebugSummary: String

    var errorDescription: String? {
        let trimmedBody = responseBody.trimmingCharacters(in: .whitespacesAndNewlines)
        let networkHint = statusCode == 500
            ? " 若在 iPhone 真机上使用 Alice，Tailscale / VPN 已确认会显著放大失败概率；即使关闭后，当前也仍可能偶发 500。应用会先做有限次重试。"
            : ""
        if trimmedBody.isEmpty {
            return "OpenRouter 请求失败，HTTP \(statusCode)。请求诊断：\(requestDebugSummary)。\(networkHint)"
        }
        return "OpenRouter 请求失败，HTTP \(statusCode)：\(trimmedBody)。请求诊断：\(requestDebugSummary)。\(networkHint)"
    }
}

// 响应模型
struct OpenRouterResponse: Codable {
    let choices: [Choice]
}

struct OpenRouterNonStreamingResponse: Codable {
    let choices: [OpenRouterNonStreamingChoice]
}

struct OpenRouterNonStreamingChoice: Codable {
    let message: OpenRouterNonStreamingMessage
}

struct OpenRouterNonStreamingMessage: Codable {
    let content: String?
    let reasoning: String?
    let reasoningDetails: [MessageReasoningDetail]?

    enum CodingKeys: String, CodingKey {
        case content
        case reasoning
        case reasoningDetails = "reasoning_details"
    }
}

struct Choice: Codable {
    let delta: ChatDelta
}

struct ChatDelta: Codable {
    let content: String?
    let reasoning: String?
    let reasoningDetails: [MessageReasoningDetail]?

    enum CodingKeys: String, CodingKey {
        case content
        case reasoning
        case reasoningDetails = "reasoning_details"
    }
}
