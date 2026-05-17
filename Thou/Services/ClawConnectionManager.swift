/**
 OpenClaw 模式的连接与协议管理器。

 这个文件负责 Thou 到 native-plugin bridge 的 WebSocket 连接、鉴权、心跳、
 会话列表与历史加载，以及聊天消息的发送和流式回包分发。
 */

import Foundation
import Combine

enum ClawBridgeEvent {
    case chatStarted
    case chatChunk(String)
    case chatCompleted(reason: String)
    case chatFailed(message: String)
    case connectionClosed(status: String)
}

class ClawConnectionManager: NSObject, ObservableObject, URLSessionWebSocketDelegate {
    @Published var isConnected = false
    @Published var connectionStatus = "未连接"
    @Published var lastHandshakeConnectionProfile: ClawHandshakeConnectionProfile?
    
    // 用于向外部推送流式消息
    let textStream = PassthroughSubject<String, Never>()
    let bridgeEvents = PassthroughSubject<ClawBridgeEvent, Never>()
    
    private var session: URLSession?
    private var webSocketTask: URLSessionWebSocketTask?
    private var pendingToken: String?
    private var connectionCandidates: [URL] = []
    private var currentConnectionCandidateIndex: Int = 0
    private var currentConnectionURL: URL?
    private var pingTimer: Timer?
    private var pendingRequests: [String: (Result<[String: Any], Error>) -> Void] = [:]
    private let deviceId: String
    private let deviceLabel: String

    override init() {
        let defaults = UserDefaults.standard
        let storedDeviceId = defaults.string(forKey: "OpenClawDeviceId")
        let resolvedDeviceId: String
        if let storedDeviceId, !storedDeviceId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            resolvedDeviceId = storedDeviceId
        } else {
            resolvedDeviceId = "device:\(UUID().uuidString.lowercased())"
            defaults.set(resolvedDeviceId, forKey: "OpenClawDeviceId")
        }

        let displayName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        let bundleName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
        let resolvedDeviceLabel = (displayName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? displayName!
            : (bundleName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? bundleName!
                : resolvedDeviceId))

        self.deviceId = resolvedDeviceId
        self.deviceLabel = resolvedDeviceLabel
        super.init()
    }
    
    // 解析神奇配对码 (例如: C612-0001-4F95)
    func parsePairingCode(_ code: String) -> (ip: String, tokenPrefix: String)? {
        let cleanCode = code.replacingOccurrences(of: "-", with: "").uppercased()
        guard cleanCode.count == 12 else { return nil }
        
        let ipPart = String(cleanCode.prefix(8))
        let tokenPrefix = String(cleanCode.suffix(4))
        
        var ipComponents: [String] = []
        for i in 0..<4 {
            let start = ipPart.index(ipPart.startIndex, offsetBy: i * 2)
            let end = ipPart.index(start, offsetBy: 2)
            let hex = String(ipPart[start..<end])
            if let byte = Int(hex, radix: 16) {
                ipComponents.append("\(byte)")
            }
        }
        
        guard ipComponents.count == 4 else { return nil }
        return (ipComponents.joined(separator: "."), tokenPrefix)
    }
    
    func connect(ip: String, port: Int = 8080, token: String) {
        connect(host: ip, port: port, token: token)
    }

    func connect(targets: [OpenClawConnectionTarget], token: String) {
        let normalizedTargets = targets.compactMap { target in
            normalizeConnectionTarget(from: target.host, fallbackPort: target.port).map { resolved in
                OpenClawConnectionTarget(host: resolved.host, port: resolved.port, source: target.source)
            }
        }

        guard !normalizedTargets.isEmpty else {
            DispatchQueue.main.async {
                self.connectionStatus = "连接失败: 没有可用的目标地址"
            }
            return
        }

        pendingToken = token
        connectionCandidates = buildConnectionCandidates(from: normalizedTargets)
        currentConnectionCandidateIndex = 0

        DispatchQueue.main.async {
            self.isConnected = false
            self.connectionStatus = "正在发起连接..."
        }

        stopHeartbeat()
        session?.invalidateAndCancel()
        session = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)

        startCurrentConnectionAttempt()
    }

    func resolveConnectionTarget(host: String, port: Int = 8080) -> (host: String, port: Int)? {
        normalizeConnectionTarget(from: host, fallbackPort: port)
    }

    var activeConnectionTarget: (host: String, port: Int)? {
        guard let currentConnectionURL,
              let host = currentConnectionURL.host?.trimmingCharacters(in: .whitespacesAndNewlines),
              !host.isEmpty else {
            return nil
        }

        let resolvedPort = currentConnectionURL.port ?? 8080
        guard (1...65535).contains(resolvedPort) else {
            return nil
        }

        return (host, resolvedPort)
    }

    func connect(host: String, port: Int = 8080, token: String) {
        guard let target = normalizeConnectionTarget(from: host, fallbackPort: port) else {
            DispatchQueue.main.async {
                self.connectionStatus = "连接失败: 主机地址格式无效"
            }
            return
        }

        self.pendingToken = token
        self.connectionCandidates = buildConnectionCandidates(from: [
            OpenClawConnectionTarget(host: target.host, port: target.port, source: .manual)
        ])
        self.currentConnectionCandidateIndex = 0

        DispatchQueue.main.async {
            self.isConnected = false
            self.connectionStatus = "正在发起连接..."
        }

        stopHeartbeat()
        session?.invalidateAndCancel()
        session = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)

        startCurrentConnectionAttempt()
    }

    private func buildConnectionCandidates(from targets: [OpenClawConnectionTarget]) -> [URL] {
        let rawCandidates = targets.flatMap { target in
            [
                "ws://\(target.host):\(target.port)/thou",
                "ws://\(target.host):\(target.port)"
            ]
        }
        return Array(NSOrderedSet(array: rawCandidates.compactMap { URL(string: $0) })) as? [URL] ?? []
    }

    private func normalizeConnectionTarget(from rawHost: String, fallbackPort: Int) -> (host: String, port: Int)? {
        let trimmed = rawHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if let urlTarget = normalizeURLLikeTarget(from: trimmed, fallbackPort: fallbackPort) {
            return urlTarget
        }

        let cleaned = trimmed
            .replacingOccurrences(of: "/thou", with: "", options: [.caseInsensitive, .anchored], range: nil)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        guard !cleaned.isEmpty else {
            return nil
        }

        if let hostPortTarget = normalizeHostPortTarget(from: cleaned, fallbackPort: fallbackPort) {
            return hostPortTarget
        }

        return (cleaned, fallbackPort)
    }

    private func normalizeURLLikeTarget(from rawValue: String, fallbackPort: Int) -> (host: String, port: Int)? {
        let candidate = rawValue.contains("://") ? rawValue : "ws://\(rawValue)"
        guard let components = URLComponents(string: candidate),
              let host = components.host?.trimmingCharacters(in: .whitespacesAndNewlines),
              !host.isEmpty else {
            return nil
        }

        if let path = components.path.removingPercentEncoding,
           !path.isEmpty,
           path != "/",
           path.caseInsensitiveCompare("/thou") != .orderedSame {
            return nil
        }

        let resolvedPort = components.port ?? fallbackPort
        guard (1...65535).contains(resolvedPort) else {
            return nil
        }

        return (host, resolvedPort)
    }

    private func normalizeHostPortTarget(from rawValue: String, fallbackPort: Int) -> (host: String, port: Int)? {
        guard !rawValue.contains("/") else {
            return nil
        }

        if rawValue.hasPrefix("[") {
            guard let closingBracketIndex = rawValue.firstIndex(of: "]") else {
                return nil
            }

            let host = String(rawValue[rawValue.index(after: rawValue.startIndex)..<closingBracketIndex])
            let remainder = rawValue[rawValue.index(after: closingBracketIndex)...]
            if remainder.isEmpty {
                return (host, fallbackPort)
            }

            guard remainder.first == ":",
                  let port = Int(remainder.dropFirst()),
                  (1...65535).contains(port) else {
                return nil
            }

            return (host, port)
        }

        let colonCount = rawValue.filter { $0 == ":" }.count
        if colonCount == 1,
           let separatorIndex = rawValue.lastIndex(of: ":"),
           let port = Int(rawValue[rawValue.index(after: separatorIndex)...]),
           (1...65535).contains(port) {
            let host = String(rawValue[..<separatorIndex])
            guard !host.isEmpty else {
                return nil
            }
            return (host, port)
        }

        return nil
    }

    private func startCurrentConnectionAttempt() {
        guard currentConnectionCandidateIndex < connectionCandidates.count else {
            DispatchQueue.main.async {
                self.connectionStatus = "连接失败: 没有可用的 WebSocket 地址"
            }
            return
        }

        let url = connectionCandidates[currentConnectionCandidateIndex]
        currentConnectionURL = url

        print("ClawConnectionManager: Connecting to \(url.absoluteString)")

        DispatchQueue.main.async {
            self.connectionStatus = "正在连接 \(self.describe(url: url))..."
        }

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60 * 60 * 24
        configuration.timeoutIntervalForResource = 60 * 60 * 24

        let delegateQueue = OperationQueue()
        delegateQueue.maxConcurrentOperationCount = 1
        delegateQueue.qualityOfService = .userInitiated

        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: delegateQueue)
        self.session = session
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()
    }

    private func startHeartbeat() {
        stopHeartbeat()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            guard let self = self, self.isConnected else { return }
            self.webSocketTask?.sendPing { error in
                if let error = error {
                    print("WebSocket ping error: \(error.localizedDescription)")
                }
            }
        }
    }

    private func stopHeartbeat() {
        pingTimer?.invalidate()
        pingTimer = nil
    }

    private func markDisconnected(_ status: String) {
        stopHeartbeat()
        failPendingRequests(error: NSError(domain: "ClawConnectionManager", code: -1, userInfo: [NSLocalizedDescriptionKey: status]))
        DispatchQueue.main.async {
            self.isConnected = false
            self.connectionStatus = status
            self.bridgeEvents.send(.connectionClosed(status: status))
        }
    }

    private func failPendingRequests(error: Error) {
        let pending = pendingRequests.values
        pendingRequests.removeAll()
        for resolve in pending {
            resolve(.failure(error))
        }
    }

    private func advanceToNextConnectionCandidate() -> Bool {
        let nextIndex = currentConnectionCandidateIndex + 1
        guard nextIndex < connectionCandidates.count else {
            return false
        }

        currentConnectionCandidateIndex = nextIndex
        startCurrentConnectionAttempt()
        return true
    }

    private func describe(url: URL) -> String {
        let host = url.host?.trimmingCharacters(in: .whitespacesAndNewlines) ?? url.absoluteString
        let port = url.port.map { String($0) } ?? "默认端口"
        let path = url.path.isEmpty ? "/" : url.path
        return "\(host):\(port)\(path)"
    }

    private func describeConnectionError(_ error: Error, attemptedURL: URL?) -> String {
        let nsError = error as NSError
        let target = attemptedURL.map(describe(url:)) ?? "目标地址"

        guard nsError.domain == NSURLErrorDomain else {
            return "连接失败: \(target)，\(error.localizedDescription)"
        }

        let code = URLError.Code(rawValue: nsError.code)

        switch code {
        case .timedOut:
            return "连接失败: \(target)，连接超时"
        case .cannotFindHost, .dnsLookupFailed:
            return "连接失败: \(target)，找不到主机"
        case .cannotConnectToHost:
            return "连接失败: \(target)，目标端口未响应"
        case .networkConnectionLost:
            return "连接失败: \(target)，网络连接中断"
        case .notConnectedToInternet:
            return "连接失败: \(target)，当前网络不可用"
        case .secureConnectionFailed, .serverCertificateHasBadDate, .serverCertificateUntrusted:
            return "连接失败: \(target)，安全连接校验失败"
        default:
            return "连接失败: \(target)，\(error.localizedDescription)"
        }
    }
    
    // MARK: - URLSessionWebSocketDelegate
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        print("WebSocket 握手成功！")
        DispatchQueue.main.async {
            let target = self.currentConnectionURL.map(self.describe(url:)) ?? "目标地址"
            self.connectionStatus = "握手成功，正在鉴权 \(target)..."
        }
        
        // 握手成功后，开启消息接收循环
        receiveMessage()
        
        // 握手成功后，发送鉴权 Token
        if let token = pendingToken {
            print("Sending Auth Token...")
            sendAuth(token: token)
        }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        let reasonText = reason.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        print("WebSocket closed: code=\(closeCode.rawValue) reason=\(reasonText)")
        let target = currentConnectionURL.map(describe(url:)) ?? "目标地址"
        let suffix = reasonText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "，\(reasonText)"
        markDisconnected("连接已关闭: \(target)\(suffix)")
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            if isConnected && (error as NSError).code == -1001 {
                print("忽略已连接状态下的假性超时错误")
                return
            }

            if !isConnected {
                let attemptedTarget = currentConnectionURL.map(describe(url:)) ?? "目标地址"
                print("WebSocket attempt failed on \(attemptedTarget): \(error.localizedDescription)")
                if advanceToNextConnectionCandidate() {
                    return
                }
            }

            print("WebSocket Error: \(error.localizedDescription)")
            markDisconnected(describeConnectionError(error, attemptedURL: currentConnectionURL))
        }
    }
    
    private func sendAuth(token: String) {
        let authMsg: [String: Any] = [
            "type": "auth",
            "token": token,
            "deviceId": deviceId,
            "deviceLabel": deviceLabel
        ]
        sendJSON(authMsg)
    }
    
    private func sendJSON(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let string = String(data: data, encoding: .utf8) else { return }
        
        webSocketTask?.send(.string(string)) { error in
            if let error = error {
                print("WebSocket send error: \(error)")
            }
        }
    }

    private func sendRequest(type: String, payload: [String: Any] = [:]) async throws -> [String: Any] {
        guard isConnected else {
            throw NSError(domain: "ClawConnectionManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "尚未连接到 OpenClaw"])
        }
        guard webSocketTask != nil else {
            throw NSError(domain: "ClawConnectionManager", code: -3, userInfo: [NSLocalizedDescriptionKey: "WebSocket 尚未就绪"])
        }

        let requestId = UUID().uuidString.lowercased()
        var requestPayload = payload
        requestPayload["type"] = type
        requestPayload["requestId"] = requestId

        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests[requestId] = { result in
                continuation.resume(with: result)
            }

            guard let data = try? JSONSerialization.data(withJSONObject: requestPayload),
                  let string = String(data: data, encoding: .utf8) else {
                let error = NSError(domain: "ClawConnectionManager", code: -4, userInfo: [NSLocalizedDescriptionKey: "请求序列化失败"])
                let pending = self.pendingRequests.removeValue(forKey: requestId)
                pending?(.failure(error))
                return
            }

            webSocketTask?.send(.string(string)) { error in
                if let error {
                    DispatchQueue.main.async {
                        let pending = self.pendingRequests.removeValue(forKey: requestId)
                        pending?(.failure(error))
                    }
                }
            }
        }
    }
    
    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self?.handleIncomingText(text)
                default:
                    break
                }
                self?.receiveMessage() // 继续监听
            case .failure(let error):
                print("WebSocket receive error: \(error)")
                self?.markDisconnected(self?.describeConnectionError(error, attemptedURL: self?.currentConnectionURL) ?? "连接断开")
            }
        }
    }
    
    private func handleIncomingText(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        
        let type = json["type"] as? String
        let requestId = json["requestId"] as? String

        if let requestId, let pending = pendingRequests.removeValue(forKey: requestId) {
            if type == "error" {
                let message = json["message"] as? String ?? "未知错误"
                pending(.failure(NSError(domain: "ClawConnectionManager", code: -5, userInfo: [NSLocalizedDescriptionKey: message])))
            } else {
                pending(.success(json))
            }
            return
        }
        
        DispatchQueue.main.async {
            if type == "auth-ok" {
                self.lastHandshakeConnectionProfile = Self.parseHandshakeConnectionProfile(from: json)
                self.isConnected = true
                let target = self.currentConnectionURL.map(self.describe(url:)) ?? "目标地址"
                self.connectionStatus = "已连接到插件: \(target)"
                self.startHeartbeat()
            } else if type == "chat-start" {
                self.connectionStatus = "OpenClaw 正在回复..."
                self.bridgeEvents.send(.chatStarted)
            } else if type == "chat.done" {
                self.connectionStatus = "已连接到 OpenClaw"
                let reason = (json["reason"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                self.bridgeEvents.send(.chatCompleted(reason: reason?.isEmpty == false ? reason! : "completed"))
            } else if type == "error" {
                let message = (json["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let resolvedMessage = message?.isEmpty == false ? message! : "未知错误"
                self.connectionStatus = "错误: \(resolvedMessage)"
                self.bridgeEvents.send(.chatFailed(message: resolvedMessage))
            }
            
            if type == "chat.chunk", let content = json["content"] as? String {
                self.textStream.send(content)
                self.bridgeEvents.send(.chatChunk(content))
            }
        }
    }

    private static func parseHandshakeConnectionProfile(from payload: [String: Any]) -> ClawHandshakeConnectionProfile? {
        guard let rawProfile = payload["connectionProfile"] as? [String: Any],
              let rawBridge = rawProfile["bridge"] as? [String: Any],
              let rawAuth = rawProfile["auth"] as? [String: Any],
              let listenPort = rawBridge["listenPort"] as? Int,
              let listenPath = rawBridge["listenPath"] as? String,
              let pairingTokenPrefix = rawAuth["pairingTokenPrefix"] as? String else {
            return nil
        }

        guard (1...65535).contains(listenPort) else {
            return nil
        }

        let hostHints = (rawBridge["hostHints"] as? [String] ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return ClawHandshakeConnectionProfile(
            bridgeListenPort: listenPort,
            bridgeListenPath: listenPath,
            hostHints: hostHints,
            pairingTokenPrefix: pairingTokenPrefix
        )
    }
    
    func sendMessage(_ text: String, sessionKey: String? = nil) {
        var msg: [String: Any] = [
            "type": "chat",
            "text": text
        ]
        if let sessionKey, !sessionKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            msg["sessionKey"] = sessionKey.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        sendJSON(msg)
    }

    func fetchSessions(limit: Int = 12) async throws -> [ClawSessionSummary] {
        let response = try await sendRequest(type: "sessions.list", payload: ["limit": limit])
        let rawSessions = response["sessions"] as? [[String: Any]] ?? []
        return rawSessions.compactMap { raw in
            guard let key = raw["key"] as? String, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }

            let titleCandidates = [raw["label"], raw["title"], raw["preview"]]
                .compactMap { $0 as? String }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let title = titleCandidates.first ?? key
            let preview = (raw["preview"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let updatedAt = (raw["updatedAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
                ?? (raw["updatedAt"] as? Int).map { Date(timeIntervalSince1970: Double($0) / 1000) }

            return ClawSessionSummary(key: key, title: title, preview: preview?.isEmpty == true ? nil : preview, updatedAt: updatedAt)
        }
    }

    func createSession(label: String? = nil) async throws -> ClawSessionSummary {
        var payload: [String: Any] = [:]
        if let label, !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["label"] = label.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let response = try await sendRequest(type: "sessions.create", payload: payload)
        guard let rawSession = response["session"] as? [String: Any],
              let key = rawSession["key"] as? String,
              !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NSError(domain: "ClawConnectionManager", code: -6, userInfo: [NSLocalizedDescriptionKey: "会话创建结果无效"])
        }

        let title = ((rawSession["label"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "新会话"
        let preview = (rawSession["preview"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let updatedAt = (rawSession["updatedAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
            ?? (rawSession["updatedAt"] as? Int).map { Date(timeIntervalSince1970: Double($0) / 1000) }

        return ClawSessionSummary(key: key, title: title, preview: preview?.isEmpty == true ? nil : preview, updatedAt: updatedAt)
    }

    func fetchHistory(sessionKey: String? = nil, limit: Int = 80) async throws -> [ClawHistoryMessage] {
        var payload: [String: Any] = [
            "limit": max(1, min(limit, 200))
        ]
        if let sessionKey, !sessionKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["sessionKey"] = sessionKey.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let response = try await sendRequest(type: "chat.history", payload: payload)
        let rawMessages = response["messages"] as? [[String: Any]] ?? []
        return rawMessages.compactMap { raw in
            guard let role = raw["role"] as? String,
                  let text = Self.extractHistoryText(from: raw),
                  !text.isEmpty else {
                return nil
            }

            let timestamp = (raw["timestamp"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
                ?? (raw["timestamp"] as? Int).map { Date(timeIntervalSince1970: Double($0) / 1000) }
            return ClawHistoryMessage(role: role, text: text, timestamp: timestamp)
        }
    }

    private static func extractHistoryText(from raw: [String: Any]) -> String? {
        if let text = raw["text"] as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        guard let content = raw["content"] as? [[String: Any]] else {
            return nil
        }

        let text = content
            .compactMap { item -> String? in
                guard let type = item["type"] as? String, type == "text" else {
                    return nil
                }
                return item["text"] as? String
            }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
    
    func disconnect() {
        stopHeartbeat()
        failPendingRequests(error: NSError(domain: "ClawConnectionManager", code: -7, userInfo: [NSLocalizedDescriptionKey: "连接已断开"]))
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        session?.invalidateAndCancel()
        session = nil
        connectionCandidates = []
        currentConnectionCandidateIndex = 0
        currentConnectionURL = nil
        isConnected = false
        connectionStatus = "已断开"
    }
}
