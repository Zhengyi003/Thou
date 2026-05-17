/**
 Alice 模块的聊天状态与发送编排层。

 这个文件负责 Alice 专属的 rounds、draft、发送状态和云端请求链，
 让 Alice 的对话逻辑不再直接堆叠在共享壳层 ChatViewModel 中。
 */

import Foundation
import Combine

@MainActor
final class AliceChatViewModel: ObservableObject {
    @Published var rounds: [Round] = []
    @Published var draft: String = ""
    @Published var isSending: Bool = false
    @Published var requestStatus: String = "尚未发送"
    @Published var lastErrorMessage: String?
    @Published var lastRetrievedTopicTitles: [String] = []
    @Published var didReceiveReasoning: Bool = false
    @Published var didReceiveContent: Bool = false
    @Published var lastModelResponseSummary: String = "等待首次请求"
    @Published var conversationHistoryRoundCount: Int = 0
    @Published var activeWindowRoundCount: Int = 0
    @Published var lastArchiveSummary: String = "尚未发生 archive"
    @Published var lastArchiveArchivedRoundCount: Int = 0
    @Published var didTrimActiveRounds: Bool = false
    @Published var memoryStatusText: String = "记忆空闲"
    @Published var isRecallingMemory: Bool = false

    let configStore: AliceConfigStore
    private var sessionID: String
    private let conversationService: AliceConversationService
    private let memoryOrchestrator: AliceMemoryOrchestrator
    private let sessionDefaultsKey = "AliceCurrentSessionID"
    private var conversationHistoryRounds: [Round] = []
    private var lastArchiveRoundIDs: [UUID] = []

    init(
        configStore: AliceConfigStore,
        conversationService: AliceConversationService,
        memoryOrchestrator: AliceMemoryOrchestrator
    ) {
        self.configStore = configStore
        let defaults = UserDefaults.standard
        let storedSessionID = defaults.string(forKey: sessionDefaultsKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolvedSessionID = storedSessionID.isEmpty ? UUID().uuidString : storedSessionID
        defaults.set(resolvedSessionID, forKey: sessionDefaultsKey)
        self.sessionID = resolvedSessionID
        self.conversationService = conversationService
        self.memoryOrchestrator = memoryOrchestrator

        Task {
            await restoreConversationIfAvailable()
        }
    }

    convenience init() {
        self.init(
            configStore: AliceConfigStore(),
            conversationService: AliceConversationService(),
            memoryOrchestrator: AliceMemoryOrchestrator()
        )
    }

    var apiKey: String {
        get { configStore.apiKey }
        set { configStore.apiKey = newValue }
    }

    var model: String {
        get { configStore.selectedModel }
        set { configStore.selectedModel = newValue }
    }

    func sendMessage(_ text: String) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        draft = ""
        lastErrorMessage = nil
        didReceiveReasoning = false
        didReceiveContent = false
        lastRetrievedTopicTitles = []
        requestStatus = "正在准备 Alice 请求..."
        lastModelResponseSummary = "正在等待 OpenRouter 首个流式分片"

        let userMsg = Message(role: "user", content: text)
        let candidateRounds = rounds + [Round(userPrompt: userMsg)]
        let willAttemptRetrieve = await memoryOrchestrator.shouldAttemptRetrieve(from: candidateRounds)
        if willAttemptRetrieve {
            isRecallingMemory = true
            memoryStatusText = "正在回忆"
        } else {
            isRecallingMemory = false
            memoryStatusText = "记忆空闲"
        }

        var newRound = Round(userPrompt: userMsg, isStreaming: true)
        rounds.append(newRound)
        conversationHistoryRounds.append(newRound)
        updateConversationDebugState()
        isSending = true

        do {
            let preparedRequest = await memoryOrchestrator.prepareRequest(from: rounds)
            isRecallingMemory = false
            lastRetrievedTopicTitles = preparedRequest.retrievedTopics.map(\.title)
            requestStatus = preparedRequest.retrievedTopics.isEmpty
                ? "请求已发出，本轮未命中 retrieve"
                : "请求已发出，本轮 retrieve 命中 \(preparedRequest.retrievedTopics.count) 个 topics"
            memoryStatusText = preparedRequest.retrievedTopics.isEmpty ? "记忆空闲" : "正在回忆"

            let stream = try await conversationService.streamChat(
                messages: preparedRequest.messages,
                apiKey: apiKey,
                model: model
            )

            var collectedReasoningDetails: [MessageReasoningDetail] = []

            for try await delta in stream {
                if let reasoning = delta.reasoning {
                    newRound.streamingReasoning += reasoning
                    didReceiveReasoning = true
                } else if let details = delta.reasoningDetails {
                    collectedReasoningDetails.append(contentsOf: details)
                    let reasoningText = Self.reasoningText(from: details)
                    if !reasoningText.isEmpty {
                        newRound.streamingReasoning += reasoningText
                        didReceiveReasoning = true
                    }
                }
                if let content = delta.content {
                    newRound.streamingContent += content
                    if !content.isEmpty {
                        didReceiveContent = true
                    }
                }
                if let index = rounds.firstIndex(where: { $0.id == newRound.id }) {
                    rounds[index] = newRound
                }
                if let historyIndex = conversationHistoryRounds.firstIndex(where: { $0.id == newRound.id }) {
                    conversationHistoryRounds[historyIndex] = newRound
                }
            }

            newRound.aiResponse = Message(
                role: "assistant",
                content: newRound.streamingContent,
                reasoning: newRound.streamingReasoning,
                reasoningDetails: collectedReasoningDetails.isEmpty ? nil : collectedReasoningDetails
            )
            newRound.isStreaming = false
            if let index = rounds.firstIndex(where: { $0.id == newRound.id }) {
                rounds[index] = newRound
            }
            if let historyIndex = conversationHistoryRounds.firstIndex(where: { $0.id == newRound.id }) {
                conversationHistoryRounds[historyIndex] = newRound
            }

            if didReceiveReasoning && didReceiveContent {
                lastModelResponseSummary = "已收到 reasoning 与正式正文"
            } else if didReceiveReasoning {
                lastModelResponseSummary = "已收到 reasoning，但正文为空"
            } else if didReceiveContent {
                lastModelResponseSummary = "已收到正文，未看到 reasoning tokens"
            } else {
                lastModelResponseSummary = "请求完成，但未收到可展示内容"
            }

            let archiveUpdate = await memoryOrchestrator.archiveAfterResponse(
                sessionID: sessionID,
                rounds: rounds,
                retrievedTopics: preparedRequest.retrievedTopics
            )
            rounds = archiveUpdate.activeRounds
            if archiveUpdate.didArchive || archiveUpdate.statusSummary.contains("archive 失败") {
                lastArchiveSummary = archiveUpdate.statusSummary
                lastArchiveArchivedRoundCount = archiveUpdate.archivedRoundIDs.count
                lastArchiveRoundIDs = archiveUpdate.archivedRoundIDs
            } else if lastArchiveRoundIDs.isEmpty {
                lastArchiveSummary = archiveUpdate.statusSummary
                lastArchiveArchivedRoundCount = archiveUpdate.archivedRoundIDs.count
            }
            didTrimActiveRounds = conversationHistoryRounds.count > rounds.count
            if archiveUpdate.didArchive {
                memoryStatusText = "已归档"
            } else if !preparedRequest.retrievedTopics.isEmpty {
                memoryStatusText = "回忆完成"
            } else {
                memoryStatusText = "记忆空闲"
            }
            updateConversationDebugState()
            await persistConversationSession()
            requestStatus = archiveUpdate.didArchive
                ? "Alice 请求完成，\(archiveUpdate.statusSummary)"
                : "Alice 请求完成，\(archiveUpdate.statusSummary)"
        } catch {
            isRecallingMemory = false
            memoryStatusText = "记忆异常"
            if let index = rounds.firstIndex(where: { $0.id == newRound.id }) {
                rounds[index].aiResponse = Message(role: "assistant", content: "Alice 请求失败：\(error.localizedDescription)")
                rounds[index].isStreaming = false
            }
            if let historyIndex = conversationHistoryRounds.firstIndex(where: { $0.id == newRound.id }) {
                conversationHistoryRounds[historyIndex].aiResponse = Message(role: "assistant", content: "Alice 请求失败：\(error.localizedDescription)")
                conversationHistoryRounds[historyIndex].isStreaming = false
            }
            lastErrorMessage = error.localizedDescription
            lastModelResponseSummary = "请求失败"
            requestStatus = "Alice 请求失败"
            updateConversationDebugState()
            await persistConversationSession()
            print("Alice Error: \(error)")
        }

        isSending = false
    }

    func resetEnvironment() async {
        rounds = []
        conversationHistoryRounds = []
        draft = ""
        isSending = false
        requestStatus = "环境已重置"
        lastErrorMessage = nil
        lastRetrievedTopicTitles = []
        didReceiveReasoning = false
        didReceiveContent = false
        lastModelResponseSummary = "等待首次请求"
        lastArchiveSummary = "尚未发生 archive"
        lastArchiveArchivedRoundCount = 0
        didTrimActiveRounds = false
        lastArchiveRoundIDs = []
        memoryStatusText = "记忆已清空"
        isRecallingMemory = false

        UserDefaults.standard.removeObject(forKey: sessionDefaultsKey)
        await memoryOrchestrator.resetAllMemory()

        sessionID = UUID().uuidString
        UserDefaults.standard.set(sessionID, forKey: sessionDefaultsKey)
        updateConversationDebugState()
    }

    private func restoreConversationIfAvailable() async {
        guard let restored = await memoryOrchestrator.restoreConversationSession(sessionID: sessionID) else {
            updateConversationDebugState()
            return
        }

        conversationHistoryRounds = restored.rounds
        if restored.activeRoundIDs.isEmpty {
            rounds = restored.rounds
        } else {
            let activeIDs = Set(restored.activeRoundIDs)
            rounds = restored.rounds.filter { activeIDs.contains($0.id) }
        }

        lastRetrievedTopicTitles = restored.lastRetrievedTopicTitles
        if let summary = restored.lastArchiveSummary, !summary.isEmpty {
            lastArchiveSummary = summary
        }
        lastArchiveRoundIDs = restored.lastArchivedRoundIDs
        lastArchiveArchivedRoundCount = restored.lastArchivedRoundIDs.count
        didTrimActiveRounds = conversationHistoryRounds.count > rounds.count
        updateConversationDebugState()
    }

    private func persistConversationSession() async {
        await memoryOrchestrator.saveConversationSession(
            sessionID: sessionID,
            fullRounds: conversationHistoryRounds,
            activeRounds: rounds,
            lastRetrievedTopicTitles: lastRetrievedTopicTitles,
            lastArchiveSummary: lastArchiveSummary,
            lastArchivedRoundIDs: lastArchiveRoundIDs
        )
    }

    private func updateConversationDebugState() {
        conversationHistoryRoundCount = conversationHistoryRounds.count
        activeWindowRoundCount = rounds.count
    }

    private static func reasoningText(from details: [MessageReasoningDetail]) -> String {
        details
            .filter { $0.type == "reasoning.text" || $0.type == "text" }
            .compactMap(\.text)
            .joined()
    }
}