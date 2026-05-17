/**
 OpenClaw 模块的聊天状态与连接编排层。

 这个文件负责 OpenClaw 专属的连接状态、配对码、会话列表、历史回放、
 draft 和远程发送逻辑，让远程连接链从共享壳层 ChatViewModel 中脱离。
 */

import Foundation
import Combine

@MainActor
final class OpenClawChatViewModel: ObservableObject {
    private enum DefaultsKey {
        static let connectionProfile = "OpenClawConnectionProfile"
        static let legacyConnectionMode = "OpenClawConnectionMode"
        static let legacyPairingCode = "OpenClawPairingCode"
        static let legacyManualHost = "OpenClawManualHost"
        static let legacyManualPort = "OpenClawManualPort"
        static let legacyManualToken = "OpenClawManualToken"
    }

    private enum BootstrapConfig {
        static let hostKey = "OpenClawBootstrapHost"
        static let portKey = "OpenClawBootstrapPort"
        static let tokenKey = "OpenClawBootstrapToken"

        static var manualTarget: OpenClawConnectionTarget? {
            guard let rawHost = Bundle.main.object(forInfoDictionaryKey: hostKey) as? String else {
                return nil
            }

            let host = rawHost.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !host.isEmpty else {
                return nil
            }

            let rawPort = Bundle.main.object(forInfoDictionaryKey: portKey)
            let port = (rawPort as? Int) ?? Int(rawPort as? String ?? "") ?? 8080
            guard (1...65535).contains(port) else {
                return nil
            }

            return OpenClawConnectionTarget(host: host, port: port, source: .manual)
        }

        static var manualToken: String? {
            guard let rawToken = Bundle.main.object(forInfoDictionaryKey: tokenKey) as? String else {
                return nil
            }

            let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty else {
                return nil
            }

            return token
        }
    }

    @Published var rounds: [Round] = []
    @Published var draft: String = ""
    @Published var isSending: Bool = false
    @Published var isLoadingHistory: Bool = false
    @Published private var connectionProfile = OpenClawConnectionProfile()
    @Published var connectionMode: OpenClawConnectionMode = .pairing {
        didSet {
            guard connectionMode != oldValue else { return }
            updateConnectionProfile {
                $0.connectionMode = connectionMode
            }
        }
    }
    @Published var pairingCode: String = "" {
        didSet {
            guard pairingCode != oldValue else { return }
            updateConnectionProfile {
                $0.pairingCode = pairingCode
            }
        }
    }
    @Published var manualHost: String = "" {
        didSet {
            guard manualHost != oldValue else { return }
            updateConnectionProfile {
                let currentPort = Int(manualPort.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 8080
                $0.setManualTarget(host: manualHost, port: currentPort)
            }
        }
    }
    @Published var manualPort: String = "8080" {
        didSet {
            guard manualPort != oldValue else { return }
            updateConnectionProfile {
                let currentPort = Int(manualPort.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 8080
                $0.setManualTarget(host: manualHost, port: currentPort)
            }
        }
    }
    @Published var manualToken: String = "" {
        didSet {
            guard manualToken != oldValue else { return }
            updateConnectionProfile {
                $0.setManualToken(manualToken)
            }
        }
    }
    @Published var clawManager = ClawConnectionManager()

    var canReconnectAutomatically: Bool {
        switch connectionMode {
        case .pairing:
            return !pairingCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .manualHost:
            let host = manualHost.trimmingCharacters(in: .whitespacesAndNewlines)
            let token = manualToken.trimmingCharacters(in: .whitespacesAndNewlines)
            let port = Int(manualPort.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            return !host.isEmpty && !token.isEmpty && (1...65535).contains(port)
        }
    }

    var rememberedTargets: [OpenClawConnectionTarget] {
        connectionProfile.orderedTargets.filter(\.isValid)
    }

    var hasStoredManualToken: Bool {
        !connectionProfile.manualToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var cancellables = Set<AnyCancellable>()
    private var pendingStreamingContent = ""
    private var chunkFlushTask: Task<Void, Never>?
    private var didAttemptAutoReconnect = false
    private let chunkFlushDelayNanoseconds: UInt64 = 80_000_000

    init() {
        loadConnectionSettings()
        setupClawStream()
        bindClawManagerState()
        attemptAutoReconnectIfPossible()
    }

    func connect() {
        switch connectionMode {
        case .pairing:
            guard !pairingCode.isEmpty else {
                clawManager.connectionStatus = "请输入配对码"
                return
            }

            guard let result = clawManager.parsePairingCode(pairingCode) else {
                clawManager.connectionStatus = "配对码格式错误"
                return
            }

            let pairingTargets = buildPairingTargets(from: result)
            clawManager.connect(targets: pairingTargets, token: result.tokenPrefix)

        case .manualHost:
            let host = manualHost.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !host.isEmpty else {
                clawManager.connectionStatus = "请输入主机地址"
                return
            }

            let portValue = Int(manualPort.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 8080
            guard (1...65535).contains(portValue) else {
                clawManager.connectionStatus = "端口格式错误"
                return
            }

            let token = manualToken.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty else {
                clawManager.connectionStatus = "请输入完整鉴权口令"
                return
            }

            guard let normalizedTarget = clawManager.resolveConnectionTarget(host: host, port: portValue) else {
                clawManager.connectionStatus = "主机地址格式错误"
                return
            }

            updateConnectionProfile {
                $0.setManualTarget(host: normalizedTarget.host, port: normalizedTarget.port)
                $0.setManualToken(token)
            }

            clawManager.connect(host: normalizedTarget.host, port: normalizedTarget.port, token: token)
        }
    }

    func reloadSelectedHistory() async {
        guard clawManager.isConnected else {
            rounds = []
            return
        }

        clawManager.connectionStatus = "正在同步当前对话..."
        isLoadingHistory = true
        defer {
            isLoadingHistory = false
            restoreIdleStatusIfNeeded()
        }

        do {
            let history = try await clawManager.fetchHistory(limit: 80)
            rounds = Self.buildRounds(from: history)
        } catch {
            clawManager.connectionStatus = "当前对话同步失败"
            print("Claw history load error: \(error)")
        }
    }

    func sendMessage(_ text: String) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        draft = ""
        let userMsg = Message(role: "user", content: text)
        let newRound = Round(userPrompt: userMsg, isStreaming: true)
        rounds.append(newRound)
        isSending = true

        if clawManager.isConnected {
            print("Sending to Claw: \(text)")
            clawManager.sendMessage(text)
        } else if let index = rounds.firstIndex(where: { $0.id == newRound.id }) {
            rounds[index].aiResponse = Message(role: "assistant", content: "未连接到 OpenClaw，请检查配对码设置。")
            rounds[index].isStreaming = false
            isSending = false
        }
    }

    func loadRememberedTarget(_ target: OpenClawConnectionTarget) {
        updateConnectionProfile {
            $0.connectionMode = .manualHost
            $0.setManualTarget(host: target.host, port: target.port)
        }
    }

    func importConnectionInfo(from rawText: String) {
        guard let card = OpenClawImportedConnectionCard.parse(from: rawText) else {
            clawManager.connectionStatus = "粘贴内容里没有可识别的连接信息"
            return
        }

        updateConnectionProfile {
            $0.importConnectionCard(card)
        }

        clawManager.connectionStatus = "已导入连接信息，正在连接 \(card.label)..."
        connect()
    }

    private func setupClawStream() {
        clawManager.bridgeEvents
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                guard let self else { return }
                switch event {
                case .chatStarted:
                    self.markLatestRoundStreaming()
                case .chatChunk(let content):
                    self.appendChunkToLatestRound(content)
                case .chatCompleted:
                    self.finalizeLatestRound()
                case .chatFailed(let message):
                    self.failLatestRound(message: message)
                case .connectionClosed(let status):
                    self.failLatestRound(message: status)
                }
            }
            .store(in: &cancellables)
    }

    private func bindClawManagerState() {
        clawManager.$isConnected
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] connected in
                guard let self else { return }
                if connected {
                    self.recordSuccessfulConnectionIfNeeded()
                    Task {
                        if self.rounds.isEmpty {
                            await self.reloadSelectedHistory()
                        }
                    }
                }
            }
            .store(in: &cancellables)

        clawManager.$lastHandshakeConnectionProfile
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] profile in
                self?.syncHandshakeConnectionProfile(profile)
            }
            .store(in: &cancellables)
    }

    private func restoreIdleStatusIfNeeded() {
        guard clawManager.isConnected, !isSending else {
            return
        }
        clawManager.connectionStatus = "已连接到 OpenClaw"
    }

    private func markLatestRoundStreaming() {
        guard let lastIndex = rounds.indices.last else {
            return
        }
        rounds[lastIndex].isStreaming = true
    }

    private func appendChunkToLatestRound(_ content: String) {
        guard !content.isEmpty else {
            return
        }

        pendingStreamingContent += content
        scheduleChunkFlushIfNeeded()
    }

    private func scheduleChunkFlushIfNeeded() {
        guard chunkFlushTask == nil else {
            return
        }

        chunkFlushTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.chunkFlushTask = nil }
            try? await Task.sleep(nanoseconds: self.chunkFlushDelayNanoseconds)
            self.flushPendingChunkBuffer()
        }
    }

    private func flushPendingChunkBuffer() {
        guard !pendingStreamingContent.isEmpty else {
            return
        }

        guard let lastIndex = rounds.indices.last else {
            pendingStreamingContent = ""
            return
        }

        rounds[lastIndex].streamingContent += pendingStreamingContent
        rounds[lastIndex].isStreaming = true
        rounds[lastIndex] = rounds[lastIndex]
        pendingStreamingContent = ""
    }

    private func finalizeLatestRound() {
        flushPendingChunkBuffer()
        guard let lastIndex = rounds.indices.last, rounds[lastIndex].isStreaming else {
            isSending = false
            return
        }

        let finalContent = rounds[lastIndex].streamingContent.trimmingCharacters(in: .whitespacesAndNewlines)
        rounds[lastIndex].aiResponse = Message(role: "assistant", content: finalContent)
        rounds[lastIndex].isStreaming = false
        rounds[lastIndex] = rounds[lastIndex]
        isSending = false
    }

    private func failLatestRound(message: String) {
        flushPendingChunkBuffer()
        guard let lastIndex = rounds.indices.last, rounds[lastIndex].isStreaming else {
            isSending = false
            return
        }

        let partialContent = rounds[lastIndex].streamingContent.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalContent = partialContent.isEmpty ? message : partialContent
        rounds[lastIndex].aiResponse = Message(role: "assistant", content: finalContent)
        rounds[lastIndex].isStreaming = false
        rounds[lastIndex] = rounds[lastIndex]
        isSending = false
    }

    private func loadConnectionSettings() {
        let defaults = UserDefaults.standard

        let loadedProfile: OpenClawConnectionProfile
        if let data = defaults.data(forKey: DefaultsKey.connectionProfile),
           let decoded = try? JSONDecoder().decode(OpenClawConnectionProfile.self, from: data) {
            loadedProfile = decoded
        } else {
            loadedProfile = migrateLegacyConnectionProfile(defaults: defaults)
        }

        let bootstrapProfile = applyingBootstrapDefaults(to: loadedProfile)
        print("[OpenClawSettings] loaded profile: \(debugSummary(for: bootstrapProfile))")

        applyConnectionProfile(bootstrapProfile, persist: false)
        saveConnectionSettings()
    }

    private func attemptAutoReconnectIfPossible() {
        guard !didAttemptAutoReconnect else {
            return
        }

        didAttemptAutoReconnect = true
        guard canReconnectAutomatically else {
            return
        }

        clawManager.connectionStatus = "正在恢复与 OpenClaw 的连接..."
        connect()
    }

    private func applyingBootstrapDefaults(to profile: OpenClawConnectionProfile) -> OpenClawConnectionProfile {
        var updatedProfile = profile

        if !updatedProfile.manualTarget.isValid, let bootstrapTarget = BootstrapConfig.manualTarget {
            updatedProfile.setManualTarget(host: bootstrapTarget.host, port: bootstrapTarget.port)
        }

        if updatedProfile.manualToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let bootstrapToken = BootstrapConfig.manualToken {
            updatedProfile.setManualToken(bootstrapToken)
        }

        return updatedProfile
    }

    private func debugSummary(for profile: OpenClawConnectionProfile) -> String {
        let manualHost = profile.manualTarget.host.trimmingCharacters(in: .whitespacesAndNewlines)
        let manualTokenState = profile.manualToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "empty" : "present"
        let lastSuccessful = profile.lastSuccessfulTarget.map { "\($0.host):\($0.port) [\($0.source.rawValue)]" } ?? "nil"
        let remembered = profile.savedTargets.map { "\($0.host):\($0.port) [\($0.source.rawValue)]" }.joined(separator: ", ")
        return "mode=\(profile.connectionMode.rawValue), manual=\(manualHost):\(profile.manualTarget.port), token=\(manualTokenState), lastSuccessful=\(lastSuccessful), savedTargets=[\(remembered)]"
    }

    private func saveConnectionSettings() {
        let defaults = UserDefaults.standard
        guard let encoded = try? JSONEncoder().encode(connectionProfile) else {
            return
        }
        defaults.set(encoded, forKey: DefaultsKey.connectionProfile)
    }

    private func updateConnectionProfile(_ mutate: (inout OpenClawConnectionProfile) -> Void) {
        var updatedProfile = connectionProfile
        mutate(&updatedProfile)
        applyConnectionProfile(updatedProfile, persist: true)
    }

    private func applyConnectionProfile(_ profile: OpenClawConnectionProfile, persist: Bool) {
        connectionProfile = profile

        if connectionMode != profile.connectionMode {
            connectionMode = profile.connectionMode
        }
        if pairingCode != profile.pairingCode {
            pairingCode = profile.pairingCode
        }

        let preferredManualTarget = preferredManualDisplayTarget(from: profile)
        let profileHost = preferredManualTarget.host
        let profilePort = String(preferredManualTarget.port)
        if manualHost != profileHost {
            manualHost = profileHost
        }
        if manualPort != profilePort {
            manualPort = profilePort
        }
        if manualToken != profile.manualToken {
            manualToken = profile.manualToken
        }

        if persist {
            saveConnectionSettings()
        }
    }

    private func preferredManualDisplayTarget(from profile: OpenClawConnectionProfile) -> OpenClawConnectionTarget {
        if profile.manualTarget.isValid {
            return profile.manualTarget
        }

        if let lastSuccessfulTarget = profile.lastSuccessfulTarget, lastSuccessfulTarget.isValid {
            return lastSuccessfulTarget
        }

        if let rememberedTarget = profile.orderedTargets.first(where: \.isValid) {
            return rememberedTarget
        }

        if let bootstrapTarget = BootstrapConfig.manualTarget {
            return bootstrapTarget
        }

        return profile.manualTarget
    }

    private func migrateLegacyConnectionProfile(defaults: UserDefaults) -> OpenClawConnectionProfile {
        var profile = OpenClawConnectionProfile()

        if let rawMode = defaults.string(forKey: DefaultsKey.legacyConnectionMode),
           let mode = OpenClawConnectionMode(rawValue: rawMode) {
            profile.connectionMode = mode
        }

        profile.pairingCode = defaults.string(forKey: DefaultsKey.legacyPairingCode) ?? ""
        let legacyHost = defaults.string(forKey: DefaultsKey.legacyManualHost) ?? ""
        let legacyPort = Int(defaults.string(forKey: DefaultsKey.legacyManualPort) ?? "") ?? 8080
        profile.setManualTarget(host: legacyHost, port: legacyPort)
        profile.setManualToken(defaults.string(forKey: DefaultsKey.legacyManualToken) ?? "")

        return profile
    }

    private func recordSuccessfulConnectionIfNeeded() {
        guard let activeTarget = clawManager.activeConnectionTarget else {
            return
        }

        updateConnectionProfile {
            $0.recordSuccessfulTarget(host: activeTarget.host, port: activeTarget.port)
        }
    }

    private func syncHandshakeConnectionProfile(_ handshakeProfile: ClawHandshakeConnectionProfile) {
        guard let activeTarget = clawManager.activeConnectionTarget else {
            return
        }

        updateConnectionProfile {
            if let pairingCode = handshakeProfile.pairingCode(forHost: activeTarget.host) {
                $0.setPairingCode(pairingCode)
            }

            for hostHint in handshakeProfile.hostHints {
                $0.mergeDiscoveredTarget(host: hostHint, port: handshakeProfile.bridgeListenPort)
            }
        }
    }

    private func buildPairingTargets(from result: (ip: String, tokenPrefix: String)) -> [OpenClawConnectionTarget] {
        var targets: [OpenClawConnectionTarget] = [
            OpenClawConnectionTarget(host: result.ip, port: 8080, source: .lanHint)
        ]

        for target in connectionProfile.orderedTargets {
            guard !targets.contains(where: { $0.matches(host: target.host, port: target.port) }) else {
                continue
            }
            targets.append(target)
        }

        return targets
    }

    private static func buildRounds(from history: [ClawHistoryMessage]) -> [Round] {
        var rounds: [Round] = []
        var pendingUser: ClawHistoryMessage?

        for item in history {
            switch item.role {
            case "user":
                if let pendingUser {
                    rounds.append(Round(
                        userPrompt: Message(role: "user", content: pendingUser.text),
                        aiResponse: nil,
                        streamingReasoning: "",
                        streamingContent: "",
                        isStreaming: false
                    ))
                }
                pendingUser = item
            case "assistant":
                guard let currentPendingUser = pendingUser else {
                    continue
                }
                rounds.append(Round(
                    userPrompt: Message(role: "user", content: currentPendingUser.text),
                    aiResponse: Message(role: "assistant", content: item.text),
                    streamingReasoning: "",
                    streamingContent: "",
                    isStreaming: false
                ))
                pendingUser = nil
            default:
                continue
            }
        }

        if let pendingUser {
            rounds.append(Round(
                userPrompt: Message(role: "user", content: pendingUser.text),
                aiResponse: nil,
                streamingReasoning: "",
                streamingContent: "",
                isStreaming: false
            ))
        }

        return rounds
    }
}