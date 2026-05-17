/**
 Alice 端内记忆系统的数据模型。

 这个文件定义历史归档、主题、印象、检索与归档请求结果等结构，
 为后续 MemoryStore 和 MemorySkillService 提供统一的数据边界。
 */

import Foundation

struct MemoryRoundRecord: Codable, Identifiable, Equatable {
    let id: UUID
    var userContent: String
    var assistantContent: String?
    var assistantReasoning: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        userContent: String,
        assistantContent: String? = nil,
        assistantReasoning: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.userContent = userContent
        self.assistantContent = assistantContent
        self.assistantReasoning = assistantReasoning
        self.createdAt = createdAt
    }
}

struct HistoricalChatArchive: Codable, Identifiable, Equatable {
    let id: UUID
    var sessionID: String
    var archivedAt: Date
    var keepRecentRounds: Int
    var rounds: [MemoryRoundRecord]

    init(
        id: UUID = UUID(),
        sessionID: String,
        archivedAt: Date = Date(),
        keepRecentRounds: Int,
        rounds: [MemoryRoundRecord]
    ) {
        self.id = id
        self.sessionID = sessionID
        self.archivedAt = archivedAt
        self.keepRecentRounds = keepRecentRounds
        self.rounds = rounds
    }
}

struct ConversationSessionRecord: Codable, Equatable {
    var sessionID: String
    var updatedAt: Date
    var rounds: [MemoryRoundRecord]
    var activeRoundIDs: [UUID]
    var lastRetrievedTopicTitles: [String]
    var lastArchiveSummary: String?
    var lastArchivedRoundIDs: [UUID]

    init(
        sessionID: String,
        updatedAt: Date = Date(),
        rounds: [MemoryRoundRecord] = [],
        activeRoundIDs: [UUID] = [],
        lastRetrievedTopicTitles: [String] = [],
        lastArchiveSummary: String? = nil,
        lastArchivedRoundIDs: [UUID] = []
    ) {
        self.sessionID = sessionID
        self.updatedAt = updatedAt
        self.rounds = rounds
        self.activeRoundIDs = activeRoundIDs
        self.lastRetrievedTopicTitles = lastRetrievedTopicTitles
        self.lastArchiveSummary = lastArchiveSummary
        self.lastArchivedRoundIDs = lastArchivedRoundIDs
    }
}

struct TopicRecord: Codable, Identifiable, Equatable {
    let id: String
    var title: String
    var summary: String
    var tags: [String]
    var keyFacts: [String]
    var openQuestions: [String]
    var sourceArchiveIDs: [UUID]
    var sourceRoundIDs: [UUID]
    var lastUpdatedAt: Date
    var salience: Double

    init(
        id: String,
        title: String,
        summary: String,
        tags: [String] = [],
        keyFacts: [String] = [],
        openQuestions: [String] = [],
        sourceArchiveIDs: [UUID] = [],
        sourceRoundIDs: [UUID] = [],
        lastUpdatedAt: Date = Date(),
        salience: Double = 0
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.tags = tags
        self.keyFacts = keyFacts
        self.openQuestions = openQuestions
        self.sourceArchiveIDs = sourceArchiveIDs
        self.sourceRoundIDs = sourceRoundIDs
        self.lastUpdatedAt = lastUpdatedAt
        self.salience = salience
    }
}

struct ImpressionRecord: Codable, Equatable {
    var entries: [String]
    var sourceTopicIDs: [String]
    var sourceArchiveIDs: [UUID]
    var updatedAt: Date

    init(
        entries: [String] = [],
        sourceTopicIDs: [String] = [],
        sourceArchiveIDs: [UUID] = [],
        updatedAt: Date = Date()
    ) {
        self.entries = entries
        self.sourceTopicIDs = sourceTopicIDs
        self.sourceArchiveIDs = sourceArchiveIDs
        self.updatedAt = updatedAt
    }
}

struct ArchiveTopicUpdate: Equatable {
    var id: String
    var title: String
    var summary: String
    var tags: [String]
    var keyFacts: [String]
    var openQuestions: [String]

    init(
        id: String,
        title: String,
        summary: String,
        tags: [String] = [],
        keyFacts: [String] = [],
        openQuestions: [String] = []
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.tags = tags
        self.keyFacts = keyFacts
        self.openQuestions = openQuestions
    }
}

struct ArchiveRequest: Equatable {
    var sessionID: String
    var rounds: [MemoryRoundRecord]
    var keepRecentRounds: Int
    var topicUpdates: [ArchiveTopicUpdate]
    var impressionUpdates: [String]
    var retrievedTopicIDs: [String]

    init(
        sessionID: String,
        rounds: [MemoryRoundRecord],
        keepRecentRounds: Int,
        topicUpdates: [ArchiveTopicUpdate],
        impressionUpdates: [String] = [],
        retrievedTopicIDs: [String] = []
    ) {
        self.sessionID = sessionID
        self.rounds = rounds
        self.keepRecentRounds = keepRecentRounds
        self.topicUpdates = topicUpdates
        self.impressionUpdates = impressionUpdates
        self.retrievedTopicIDs = retrievedTopicIDs
    }
}

struct ArchiveResult: Equatable {
    var archiveID: UUID
    var archivedAt: Date
    var archivedRoundIDs: [UUID]
    var keepRecentRounds: Int
    var touchedTopicIDs: [String]
    var impressionsUpdated: Bool
}

struct RetrieveRequest: Equatable {
    var query: String
    var tags: [String]
    var limit: Int

    init(query: String, tags: [String] = [], limit: Int = 3) {
        self.query = query
        self.tags = tags
        self.limit = limit
    }
}

struct RetrievedTopic: Equatable, Identifiable {
    let id: String
    var title: String
    var summary: String
    var tags: [String]
    var keyFacts: [String]
    var lastUpdatedAt: Date
    var score: Double
}

struct RetrieveResult: Equatable {
    var topics: [RetrievedTopic]
    var totalCandidates: Int
}