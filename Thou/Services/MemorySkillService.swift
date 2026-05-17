/**
 Alice 端内记忆技能的编排服务。

 这个文件把归档和检索两类操作封装成统一的 actor 服务，
 负责在 MemoryStore 之上完成主题更新、印象更新和结果排序。
 */

import Foundation

actor MemorySkillService {
    private let store: MemoryStore

    init(store: MemoryStore = MemoryStore()) {
        self.store = store
    }

    func archive(_ request: ArchiveRequest) async throws -> ArchiveResult {
        let safeKeepCount = max(0, min(request.keepRecentRounds, request.rounds.count))
        let archivedRounds = Array(request.rounds.dropLast(safeKeepCount))
        guard !archivedRounds.isEmpty else {
            return ArchiveResult(
                archiveID: UUID(),
                archivedAt: Date(),
                archivedRoundIDs: [],
                keepRecentRounds: safeKeepCount,
                touchedTopicIDs: [],
                impressionsUpdated: false
            )
        }

        let archive = HistoricalChatArchive(
            sessionID: request.sessionID,
            keepRecentRounds: safeKeepCount,
            rounds: archivedRounds
        )
        try await store.saveArchive(archive)

        let topicUpdates = request.topicUpdates.isEmpty
            ? [fallbackTopicUpdate(from: archivedRounds)]
            : request.topicUpdates

        var touchedTopicIDs: [String] = []
        for update in topicUpdates {
            var topic = try await store.loadTopic(id: update.id) ?? TopicRecord(
                id: update.id,
                title: update.title,
                summary: update.summary
            )

            topic.title = update.title.isEmpty ? topic.title : update.title
            topic.summary = update.summary.isEmpty ? topic.summary : update.summary
            topic.tags = mergedUnique(topic.tags, update.tags)
            topic.keyFacts = mergedUnique(topic.keyFacts, update.keyFacts)
            topic.openQuestions = mergedUnique(topic.openQuestions, update.openQuestions)
            topic.sourceArchiveIDs = mergedUnique(topic.sourceArchiveIDs, [archive.id])
            topic.sourceRoundIDs = mergedUnique(topic.sourceRoundIDs, archivedRounds.map(\.id))
            topic.lastUpdatedAt = archive.archivedAt
            topic.salience = max(topic.salience, Double(topic.keyFacts.count + topic.tags.count))
            try await store.saveTopic(topic)
            touchedTopicIDs = mergedUnique(touchedTopicIDs, [topic.id])
        }

        let impressionsUpdated = try await updateImpressions(
            updates: request.impressionUpdates,
            topicIDs: touchedTopicIDs,
            archiveID: archive.id,
            updatedAt: archive.archivedAt
        )

        return ArchiveResult(
            archiveID: archive.id,
            archivedAt: archive.archivedAt,
            archivedRoundIDs: archivedRounds.map(\.id),
            keepRecentRounds: safeKeepCount,
            touchedTopicIDs: touchedTopicIDs,
            impressionsUpdated: impressionsUpdated
        )
    }

    func retrieve(_ request: RetrieveRequest) async throws -> RetrieveResult {
        let topics = try await store.loadAllTopics()
        let scoredTopics = topics.compactMap { topic -> RetrievedTopic? in
            let score = score(topic: topic, request: request)
            guard score > 0 else {
                return nil
            }

            return RetrievedTopic(
                id: topic.id,
                title: topic.title,
                summary: topic.summary,
                tags: topic.tags,
                keyFacts: Array(topic.keyFacts.prefix(4)),
                lastUpdatedAt: topic.lastUpdatedAt,
                score: score
            )
        }
        .sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.lastUpdatedAt > rhs.lastUpdatedAt
            }
            return lhs.score > rhs.score
        }

        let limitedTopics = Array(scoredTopics.prefix(max(1, request.limit)))
        return RetrieveResult(topics: limitedTopics, totalCandidates: scoredTopics.count)
    }

    private func updateImpressions(
        updates: [String],
        topicIDs: [String],
        archiveID: UUID,
        updatedAt: Date
    ) async throws -> Bool {
        guard !updates.isEmpty else {
            return false
        }

        var impressions = try await store.loadImpressions()
        impressions.entries = mergedUnique(impressions.entries, updates)
        impressions.sourceTopicIDs = mergedUnique(impressions.sourceTopicIDs, topicIDs)
        impressions.sourceArchiveIDs = mergedUnique(impressions.sourceArchiveIDs, [archiveID])
        impressions.updatedAt = updatedAt
        try await store.saveImpressions(impressions)
        return true
    }

    private func fallbackTopicUpdate(from archivedRounds: [MemoryRoundRecord]) -> ArchiveTopicUpdate {
        let titleSource = archivedRounds.last?.userContent ?? "Alice Archive"
        let summarySource = archivedRounds.last?.assistantContent ?? archivedRounds.last?.userContent ?? ""
        let trimmedTitle = titleSource.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmedTitle.isEmpty ? "Alice Archive" : String(trimmedTitle.prefix(24))
        let summary = String(summarySource.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))

        return ArchiveTopicUpdate(
            id: slug(from: title),
            title: title,
            summary: summary,
            keyFacts: archivedRounds
                .map(\.userContent)
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .prefix(3)
                .map { String($0.prefix(80)) }
        )
    }

    private func slug(from text: String) -> String {
        let lowered = text.lowercased()
        let allowed = lowered.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) {
                return Character(scalar)
            }
            return "-"
        }
        let raw = String(allowed)
        let collapsed = raw.replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
        let trimmed = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "alice-archive" : trimmed
    }

    private func score(topic: TopicRecord, request: RetrieveRequest) -> Double {
        var score = 0.0
        let queryTerms = request.query
            .lowercased()
            .split(whereSeparator: \ .isWhitespace)
            .map(String.init)

        let searchableSegments = [topic.title, topic.summary] + topic.keyFacts + topic.openQuestions
        let searchableText = searchableSegments.joined(separator: " ").lowercased()

        for term in queryTerms where searchableText.contains(term) {
            score += 2
        }

        let topicTags = Set(topic.tags.map { $0.lowercased() })
        for tag in request.tags where topicTags.contains(tag.lowercased()) {
            score += 3
        }

        score += min(topic.salience, 5) * 0.1
        return score
    }
}

private func mergedUnique<T: Hashable>(_ current: [T], _ incoming: [T]) -> [T] {
    var seen = Set<T>()
    var merged: [T] = []

    for item in current + incoming where seen.insert(item).inserted {
        merged.append(item)
    }

    return merged
}