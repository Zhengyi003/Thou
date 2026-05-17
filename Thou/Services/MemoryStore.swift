/**
 Alice 端内记忆系统的本地存储层。

 这个文件负责在应用沙盒内维护 Messages、Topics、Impressions 的文件布局，
 并提供归档、主题和印象数据的读写能力。
 */

import Foundation

actor MemoryStore {
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let baseURL: URL

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder.dateDecodingStrategy = .iso8601

        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.baseURL = applicationSupport.appendingPathComponent("ThouMemory", isDirectory: true)
    }

    func ensureStorageStructure() throws {
        try createDirectoryIfNeeded(messagesDirectory)
        try createDirectoryIfNeeded(sessionsDirectory)
        try createDirectoryIfNeeded(topicsDirectory)
        try createDirectoryIfNeeded(baseURL)

        if !fileManager.fileExists(atPath: impressionsURL.path) {
            try saveImpressions(ImpressionRecord())
        }
    }

    func saveArchive(_ archive: HistoricalChatArchive) throws {
        try ensureStorageStructure()
        let url = archiveURL(for: archive.id)
        let data = try encoder.encode(archive)
        try data.write(to: url, options: .atomic)
    }

    func saveConversationSession(_ session: ConversationSessionRecord) throws {
        try ensureStorageStructure()
        let data = try encoder.encode(session)
        try data.write(to: conversationSessionURL(for: session.sessionID), options: .atomic)
    }

    func loadConversationSession(sessionID: String) throws -> ConversationSessionRecord? {
        try ensureStorageStructure()
        let url = conversationSessionURL(for: sessionID)
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        let data = try Data(contentsOf: url)
        return try decoder.decode(ConversationSessionRecord.self, from: data)
    }

    func loadTopic(id: String) throws -> TopicRecord? {
        try ensureStorageStructure()
        let url = topicURL(for: id)
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        let data = try Data(contentsOf: url)
        return try decoder.decode(TopicRecord.self, from: data)
    }

    func loadAllTopics() throws -> [TopicRecord] {
        try ensureStorageStructure()
        let urls = try fileManager.contentsOfDirectory(
            at: topicsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        return try urls
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { url in
                let data = try Data(contentsOf: url)
                return try decoder.decode(TopicRecord.self, from: data)
            }
    }

    func saveTopic(_ topic: TopicRecord) throws {
        try ensureStorageStructure()
        let data = try encoder.encode(topic)
        try data.write(to: topicURL(for: topic.id), options: .atomic)
    }

    func loadImpressions() throws -> ImpressionRecord {
        try ensureStorageStructure()
        let data = try Data(contentsOf: impressionsURL)
        return try decoder.decode(ImpressionRecord.self, from: data)
    }

    func saveImpressions(_ impressions: ImpressionRecord) throws {
        try createDirectoryIfNeeded(baseURL)
        let data = try encoder.encode(impressions)
        try data.write(to: impressionsURL, options: .atomic)
    }

    func resetAllMemory() throws {
        if fileManager.fileExists(atPath: baseURL.path) {
            try fileManager.removeItem(at: baseURL)
        }
        try ensureStorageStructure()
    }

    private var messagesDirectory: URL {
        baseURL.appendingPathComponent("Messages", isDirectory: true)
    }

    private var topicsDirectory: URL {
        baseURL.appendingPathComponent("Topics", isDirectory: true)
    }

    private var sessionsDirectory: URL {
        baseURL.appendingPathComponent("Sessions", isDirectory: true)
    }

    private var impressionsURL: URL {
        baseURL.appendingPathComponent("Impressions.json")
    }

    private func archiveURL(for id: UUID) -> URL {
        messagesDirectory.appendingPathComponent("\(id.uuidString).json")
    }

    private func conversationSessionURL(for sessionID: String) -> URL {
        sessionsDirectory.appendingPathComponent("\(sanitizedFileName(sessionID)).json")
    }

    private func topicURL(for id: String) -> URL {
        topicsDirectory.appendingPathComponent("\(sanitizedFileName(id)).json")
    }

    private func sanitizedFileName(_ value: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        return value.components(separatedBy: invalidCharacters).joined(separator: "-")
    }

    private func createDirectoryIfNeeded(_ url: URL) throws {
        guard !fileManager.fileExists(atPath: url.path) else {
            return
        }

        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }
}