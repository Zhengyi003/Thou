/**
 Alice 模块的记忆编排骨架。

 这个文件负责把 Methodology A / B、MemoryStore、MemorySkillService 串起来，
 为后续 retrieve / archive 与 system prompt 注入提供统一入口。
 */

import Foundation

actor AliceMemoryOrchestrator {
    struct PreparedRequest {
        let messages: [Message]
        let retrievedTopics: [RetrievedTopic]
    }

    struct ArchiveUpdate {
        let activeRounds: [Round]
        let archivedRoundIDs: [UUID]
        let keepRecentRounds: Int
        let touchedTopicIDs: [String]
        let impressionsUpdated: Bool
        let didArchive: Bool
        let statusSummary: String
    }

    struct RestoredConversation {
        let rounds: [Round]
        let activeRoundIDs: [UUID]
        let lastRetrievedTopicTitles: [String]
        let lastArchiveSummary: String?
        let lastArchivedRoundIDs: [UUID]
    }

    private let memoryStore: MemoryStore
    private let memorySkillService: MemorySkillService
    private let archiveTriggerRoundCount = 8
    private let keepRecentRoundsCount = 4

    init(
        memoryStore: MemoryStore = MemoryStore(),
        memorySkillService: MemorySkillService = MemorySkillService()
    ) {
        self.memoryStore = memoryStore
        self.memorySkillService = memorySkillService
    }

    func buildSystemPrompt() async -> String {
        let impressions = (try? await memoryStore.loadImpressions()) ?? ImpressionRecord()
        let impressionsBlock: String

        if impressions.entries.isEmpty {
            impressionsBlock = "- 当前还没有稳定 impressions。"
        } else {
            impressionsBlock = impressions.entries.map { "- \($0)" }.joined(separator: "\n")
        }

        return [
            AliceMethodologyA.systemPrompt,
            "Current Impressions:\n\(impressionsBlock)"
        ].joined(separator: "\n\n")
    }

    func prepareRequest(from rounds: [Round]) async -> PreparedRequest {
        var messages: [Message] = [
            Message(role: "system", content: await buildSystemPrompt())
        ]

        let retrievedTopics = await resolveRetrievedTopics(from: rounds)
        if !retrievedTopics.isEmpty {
            messages.append(Message(role: "system", content: formatRetrievedTopics(retrievedTopics)))
        }

        for round in rounds {
            messages.append(round.userPrompt)
            if let response = round.aiResponse {
                messages.append(response)
            }
        }

        return PreparedRequest(messages: messages, retrievedTopics: retrievedTopics)
    }

    func archiveGuide() -> String {
        AliceMethodologyB.archiveGuide
    }

    func archiveAfterResponse(
        sessionID: String,
        rounds: [Round],
        retrievedTopics: [RetrievedTopic]
    ) async -> ArchiveUpdate {
        guard shouldArchiveAfterResponse(from: rounds) else {
            return ArchiveUpdate(
                activeRounds: rounds,
                archivedRoundIDs: [],
                keepRecentRounds: min(rounds.count, keepRecentRoundsCount),
                touchedTopicIDs: [],
                impressionsUpdated: false,
                didArchive: false,
                statusSummary: "本轮未触发 archive"
            )
        }

        let safeKeepCount = min(keepRecentRoundsCount, rounds.count)
        let archivedRounds = Array(rounds.dropLast(safeKeepCount))
        guard !archivedRounds.isEmpty else {
            return ArchiveUpdate(
                activeRounds: rounds,
                archivedRoundIDs: [],
                keepRecentRounds: safeKeepCount,
                touchedTopicIDs: [],
                impressionsUpdated: false,
                didArchive: false,
                statusSummary: "archive 条件命中，但没有可归档的 rounds"
            )
        }

        let archiveRequest = ArchiveRequest(
            sessionID: sessionID,
            rounds: rounds.map(memoryRoundRecord(from:)),
            keepRecentRounds: safeKeepCount,
            topicUpdates: buildTopicUpdates(from: archivedRounds, retrievedTopics: retrievedTopics),
            impressionUpdates: buildImpressionUpdates(from: archivedRounds),
            retrievedTopicIDs: retrievedTopics.map(\.id)
        )

        do {
            let result = try await memorySkillService.archive(archiveRequest)
            return ArchiveUpdate(
                activeRounds: Array(rounds.suffix(result.keepRecentRounds)),
                archivedRoundIDs: result.archivedRoundIDs,
                keepRecentRounds: result.keepRecentRounds,
                touchedTopicIDs: result.touchedTopicIDs,
                impressionsUpdated: result.impressionsUpdated,
                didArchive: true,
                statusSummary: formatArchiveSummary(result)
            )
        } catch {
            return ArchiveUpdate(
                activeRounds: rounds,
                archivedRoundIDs: [],
                keepRecentRounds: safeKeepCount,
                touchedTopicIDs: [],
                impressionsUpdated: false,
                didArchive: false,
                statusSummary: "archive 失败：\(error.localizedDescription)"
            )
        }
    }

    func retrieveTopics(for query: String, limit: Int = 3) async throws -> RetrieveResult {
        try await memorySkillService.retrieve(RetrieveRequest(query: query, limit: limit))
    }

    func shouldAttemptRetrieve(from rounds: [Round]) -> Bool {
        shouldRetrieve(from: rounds)
    }

    func resetAllMemory() async {
        do {
            try await memoryStore.resetAllMemory()
        } catch {
            print("Alice resetAllMemory error: \(error)")
        }
    }

    func saveConversationSession(
        sessionID: String,
        fullRounds: [Round],
        activeRounds: [Round],
        lastRetrievedTopicTitles: [String],
        lastArchiveSummary: String?,
        lastArchivedRoundIDs: [UUID]
    ) async {
        let record = ConversationSessionRecord(
            sessionID: sessionID,
            updatedAt: Date(),
            rounds: fullRounds.map(memoryRoundRecord(from:)),
            activeRoundIDs: activeRounds.map(\.id),
            lastRetrievedTopicTitles: lastRetrievedTopicTitles,
            lastArchiveSummary: lastArchiveSummary,
            lastArchivedRoundIDs: lastArchivedRoundIDs
        )

        do {
            try await memoryStore.saveConversationSession(record)
        } catch {
            print("Alice saveConversationSession error: \(error)")
        }
    }

    func restoreConversationSession(sessionID: String) async -> RestoredConversation? {
        do {
            guard let record = try await memoryStore.loadConversationSession(sessionID: sessionID) else {
                return nil
            }

            let rounds = record.rounds.map(round(from:))
            return RestoredConversation(
                rounds: rounds,
                activeRoundIDs: record.activeRoundIDs,
                lastRetrievedTopicTitles: record.lastRetrievedTopicTitles,
                lastArchiveSummary: record.lastArchiveSummary,
                lastArchivedRoundIDs: record.lastArchivedRoundIDs
            )
        } catch {
            print("Alice restoreConversationSession error: \(error)")
            return nil
        }
    }

    private func resolveRetrievedTopics(from rounds: [Round]) async -> [RetrievedTopic] {
        guard shouldRetrieve(from: rounds), let latestQuery = rounds.last?.userPrompt.content else {
            return []
        }

        do {
            let result = try await memorySkillService.retrieve(RetrieveRequest(query: latestQuery, limit: 3))
            return result.topics
        } catch {
            print("Alice retrieve error: \(error)")
            return []
        }
    }

    private func shouldRetrieve(from rounds: [Round]) -> Bool {
        guard let latestUserText = rounds.last?.userPrompt.content.trimmingCharacters(in: .whitespacesAndNewlines), !latestUserText.isEmpty else {
            return false
        }

        if rounds.count >= 4 {
            return true
        }

        let retrievalHints = ["之前", "上次", "记得", "还记得", "你说过", "我说过", "喜欢", "讨厌", "家人", "朋友", "工作", "过去", "一直"]
        return retrievalHints.contains { latestUserText.contains($0) }
    }

    private func shouldArchiveAfterResponse(from rounds: [Round]) -> Bool {
        guard rounds.count >= archiveTriggerRoundCount else {
            return false
        }

        guard let latestRound = rounds.last else {
            return false
        }

        let assistantContent = latestRound.aiResponse?.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !assistantContent.isEmpty && rounds.count > keepRecentRoundsCount
    }

    private func memoryRoundRecord(from round: Round) -> MemoryRoundRecord {
        MemoryRoundRecord(
            id: round.id,
            userContent: round.userPrompt.content,
            assistantContent: round.aiResponse?.content,
            assistantReasoning: round.aiResponse?.reasoning
        )
    }

    private func round(from record: MemoryRoundRecord) -> Round {
        Round(
            id: record.id,
            userPrompt: Message(role: "user", content: record.userContent),
            aiResponse: record.assistantContent.map {
                Message(role: "assistant", content: $0, reasoning: record.assistantReasoning)
            },
            streamingReasoning: "",
            streamingContent: "",
            isStreaming: false
        )
    }

    private func buildTopicUpdates(from archivedRounds: [Round], retrievedTopics: [RetrievedTopic]) -> [ArchiveTopicUpdate] {
        let summary = archiveSummary(from: archivedRounds)
        let tags = archiveTags(from: archivedRounds, retrievedTopics: retrievedTopics)
        let keyFacts = archiveKeyFacts(from: archivedRounds)
        let openQuestions = archiveOpenQuestions(from: archivedRounds)

        if let topic = retrievedTopics.first {
            return [
                ArchiveTopicUpdate(
                    id: topic.id,
                    title: topic.title,
                    summary: summary.isEmpty ? topic.summary : summary,
                    tags: deduplicated(topic.tags + tags),
                    keyFacts: deduplicated(topic.keyFacts + keyFacts),
                    openQuestions: openQuestions
                )
            ]
        }

        let title = archiveTitle(from: archivedRounds)
        return [
            ArchiveTopicUpdate(
                id: topicID(from: title),
                title: title,
                summary: summary,
                tags: tags,
                keyFacts: keyFacts,
                openQuestions: openQuestions
            )
        ]
    }

    private func buildImpressionUpdates(from archivedRounds: [Round]) -> [String] {
        let preferenceSignals = archivedRounds.compactMap { round -> String? in
            let text = round.userPrompt.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                return nil
            }

            let markers = ["喜欢", "不喜欢", "讨厌", "习惯", "经常", "一直", "最近", "计划", "打算", "希望"]
            guard markers.contains(where: text.contains) else {
                return nil
            }

            return "用户提到：\(String(text.prefix(60)))"
        }

        return Array(deduplicated(preferenceSignals).prefix(3))
    }

    private func archiveTitle(from archivedRounds: [Round]) -> String {
        let latestUserText = archivedRounds.last?.userPrompt.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Alice Archive"
        return latestUserText.isEmpty ? "Alice Archive" : String(latestUserText.prefix(24))
    }

    private func archiveSummary(from archivedRounds: [Round]) -> String {
        let userLines = archivedRounds.map { $0.userPrompt.content.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let assistantLines = archivedRounds.compactMap { $0.aiResponse?.content.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if let latestAssistant = assistantLines.last, !latestAssistant.isEmpty {
            return String(latestAssistant.prefix(120))
        }

        if let latestUser = userLines.last, !latestUser.isEmpty {
            return String(latestUser.prefix(120))
        }

        return ""
    }

    private func archiveTags(from archivedRounds: [Round], retrievedTopics: [RetrievedTopic]) -> [String] {
        var tags = retrievedTopics.flatMap(\.tags)
        let tagHints = ["工作", "家人", "朋友", "健康", "计划", "情绪", "偏好", "关系", "旅行", "饮食"]
        let text = archivedRounds.map { $0.userPrompt.content + " " + ($0.aiResponse?.content ?? "") }.joined(separator: " ")

        for hint in tagHints where text.contains(hint) {
            tags.append(hint)
        }

        return Array(deduplicated(tags).prefix(6))
    }

    private func archiveKeyFacts(from archivedRounds: [Round]) -> [String] {
        let candidates = archivedRounds.map(\.userPrompt.content)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { text in
                let markers = ["喜欢", "不喜欢", "想", "计划", "打算", "因为", "工作", "家人", "朋友", "最近", "一直"]
                return markers.contains(where: text.contains)
            }
            .map { String($0.prefix(80)) }

        if !candidates.isEmpty {
            return Array(deduplicated(candidates).prefix(4))
        }

        let fallback = archivedRounds.map(\.userPrompt.content)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(3)
            .map { String($0.prefix(80)) }
        return Array(fallback)
    }

    private func archiveOpenQuestions(from archivedRounds: [Round]) -> [String] {
        let questions = archivedRounds.map(\.userPrompt.content)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.contains("？") || $0.contains("吗") || $0.contains("呢") }
            .map { String($0.prefix(80)) }

        return Array(deduplicated(questions).prefix(3))
    }

    private func topicID(from title: String) -> String {
        let lowered = title.lowercased()
        let allowed = lowered.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) {
                return Character(scalar)
            }
            return "-"
        }
        let raw = String(allowed)
        let collapsed = raw.replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
        let trimmed = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "alice-topic" : trimmed
    }

    private func formatArchiveSummary(_ result: ArchiveResult) -> String {
        let impressionText = result.impressionsUpdated ? "已更新 impressions" : "本轮未更新 impressions"
        return "archive 已归档 \(result.archivedRoundIDs.count) 轮，前台保留 \(result.keepRecentRounds) 轮，topics 更新 \(result.touchedTopicIDs.count) 个，\(impressionText)"
    }

    private func formatRetrievedTopics(_ topics: [RetrievedTopic]) -> String {
        let topicBlocks = topics.map { topic in
            let facts = topic.keyFacts.isEmpty
                ? "- 暂无关键事实"
                : topic.keyFacts.map { "- \($0)" }.joined(separator: "\n")
            return [
                "[Topic] \(topic.title)",
                topic.summary,
                facts
            ].joined(separator: "\n")
        }

        return [
            "Retrieved Topics:",
            topicBlocks.joined(separator: "\n\n")
        ].joined(separator: "\n")
    }
}

private func deduplicated(_ values: [String]) -> [String] {
    var seen = Set<String>()
    var result: [String] = []

    for value in values {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            continue
        }

        if seen.insert(trimmed).inserted {
            result.append(trimmed)
        }
    }

    return result
}