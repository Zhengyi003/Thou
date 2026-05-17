/**
 Thou 聊天域的基础数据模型。

 这个文件集中定义聊天模式、页面类型、消息结构、回合结构，
 以及 OpenClaw 历史消息等轻量投影模型，供 ViewModel 和 View 共享。
 */

import Foundation

enum AgentMode: String, Codable, CaseIterable {
    case alice = "Alice"
    case claw = "OpenClaw"
}

enum PageType: Equatable {
    case chat
    case settings
    case readme
    case fun
}

enum OpenClawConnectionMode: String, Codable, CaseIterable {
    case pairing = "pairing"
    case manualHost = "manualHost"
}

enum OpenClawConnectionTargetSource: String, Codable, CaseIterable {
    case lanHint = "lanHint"
    case tailnetHint = "tailnetHint"
    case manual = "manual"
}

struct OpenClawConnectionTarget: Codable, Equatable, Identifiable {
    var host: String
    var port: Int
    var source: OpenClawConnectionTargetSource

    var id: String {
        "\(source.rawValue):\(host.lowercased()):\(port)"
    }

    var isValid: Bool {
        !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (1...65535).contains(port)
    }

    func matches(host otherHost: String, port otherPort: Int) -> Bool {
        host.caseInsensitiveCompare(otherHost) == .orderedSame && port == otherPort
    }

    func normalized(source fallbackSource: OpenClawConnectionTargetSource? = nil) -> OpenClawConnectionTarget {
        OpenClawConnectionTarget(
            host: host.trimmingCharacters(in: .whitespacesAndNewlines),
            port: port,
            source: fallbackSource ?? source
        )
    }
}

struct ClawHandshakeConnectionProfile: Equatable {
    let bridgeListenPort: Int
    let bridgeListenPath: String
    let hostHints: [String]
    let pairingTokenPrefix: String

    func pairingCode(forHost host: String) -> String? {
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let octets = normalizedHost.split(separator: ".")
        guard octets.count == 4 else {
            return nil
        }

        let encodedOctets = octets.compactMap { octet -> String? in
            guard let value = Int(octet), (0...255).contains(value) else {
                return nil
            }
            return String(format: "%02X", value)
        }

        let normalizedPrefix = pairingTokenPrefix.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard encodedOctets.count == 4, normalizedPrefix.count == 4 else {
            return nil
        }

        return "\(encodedOctets[0])\(encodedOctets[1])-\(encodedOctets[2])\(encodedOctets[3])-\(normalizedPrefix)"
    }
}

struct OpenClawImportedConnectionCard: Decodable, Equatable {
    static let clipboardPrefix = "THOU_OPENCLAW_V1:"

    let version: Int
    let kind: String
    let label: String
    let preferredHost: String
    let port: Int
    let path: String
    let token: String
    let hosts: [String]

    var normalizedHosts: [String] {
        var ordered: [String] = []
        for host in [preferredHost] + hosts {
            let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }
            guard !ordered.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
                continue
            }
            ordered.append(trimmed)
        }
        return ordered
    }

    static func parse(from rawText: String) -> OpenClawImportedConnectionCard? {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let encoded = extractEncodedPayload(from: trimmed),
              let data = decodeBase64URL(encoded),
              let decoded = try? JSONDecoder().decode(OpenClawImportedConnectionCard.self, from: data),
              decoded.version == 1,
              decoded.kind == "openclaw-connection",
              !decoded.preferredHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !decoded.token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              (1...65535).contains(decoded.port) else {
            return nil
        }
        return decoded
    }

    private static func extractEncodedPayload(from rawText: String) -> String? {
        let pattern = NSRegularExpression.escapedPattern(for: clipboardPrefix) + "[A-Za-z0-9_-]+"
        guard let range = rawText.range(of: pattern, options: .regularExpression) else {
            return nil
        }
        let matched = String(rawText[range])
        return String(matched.dropFirst(clipboardPrefix.count))
    }

    private static func decodeBase64URL(_ value: String) -> Data? {
        let normalized = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let paddingCount = (4 - normalized.count % 4) % 4
        let padded = normalized + String(repeating: "=", count: paddingCount)
        return Data(base64Encoded: padded)
    }
}

struct OpenClawConnectionProfile: Codable, Equatable {
    private static let currentSchemaVersion = 1

    var schemaVersion: Int = currentSchemaVersion
    var connectionMode: OpenClawConnectionMode = .pairing
    var pairingCode: String = ""
    var manualTarget: OpenClawConnectionTarget = OpenClawConnectionTarget(host: "", port: 8080, source: .manual)
    var manualToken: String = ""
    var savedTargets: [OpenClawConnectionTarget] = []
    var lastSuccessfulTarget: OpenClawConnectionTarget?
    var updatedAt: Date?

    var orderedTargets: [OpenClawConnectionTarget] {
        var result: [OpenClawConnectionTarget] = []

        for source in OpenClawConnectionTargetSource.allCases where source != .manual {
            for target in savedTargets where target.source == source {
                Self.appendUnique(target.normalized(), to: &result)
            }
        }

        if let lastSuccessfulTarget {
            Self.appendUnique(lastSuccessfulTarget.normalized(), to: &result)
        }

        if manualTarget.isValid {
            Self.appendUnique(manualTarget.normalized(), to: &result)
        }

        return result
    }

    mutating func setManualTarget(host: String, port: Int) {
        manualTarget = OpenClawConnectionTarget(
            host: host.trimmingCharacters(in: .whitespacesAndNewlines),
            port: port,
            source: .manual
        )
        touch()
    }

    mutating func setManualToken(_ token: String) {
        manualToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        touch()
    }

    mutating func setPairingCode(_ code: String) {
        pairingCode = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        touch()
    }

    mutating func recordSuccessfulTarget(host: String, port: Int) {
        let resolvedSource = Self.inferSource(forHost: host)
        let target = OpenClawConnectionTarget(host: host, port: port, source: resolvedSource).normalized()
        lastSuccessfulTarget = target

        if resolvedSource != .manual {
            savedTargets.removeAll { $0.matches(host: target.host, port: target.port) }
            savedTargets.append(target)
            savedTargets.sort { lhs, rhs in
                Self.priority(of: lhs.source) < Self.priority(of: rhs.source)
            }
        }

        touch()
    }

    mutating func mergeDiscoveredTarget(host: String, port: Int) {
        let resolvedSource = Self.inferSource(forHost: host)
        guard resolvedSource != .manual else {
            return
        }

        let target = OpenClawConnectionTarget(host: host, port: port, source: resolvedSource).normalized()
        savedTargets.removeAll { $0.matches(host: target.host, port: target.port) }
        savedTargets.append(target)
        savedTargets.sort { lhs, rhs in
            Self.priority(of: lhs.source) < Self.priority(of: rhs.source)
        }
        touch()
    }

    mutating func importConnectionCard(_ card: OpenClawImportedConnectionCard) {
        connectionMode = .manualHost
        setManualTarget(host: card.preferredHost, port: card.port)
        setManualToken(card.token)
        for host in card.normalizedHosts {
            mergeDiscoveredTarget(host: host, port: card.port)
        }
        touch()
    }

    private mutating func touch() {
        updatedAt = Date()
    }

    private static func appendUnique(_ target: OpenClawConnectionTarget, to result: inout [OpenClawConnectionTarget]) {
        guard target.isValid else {
            return
        }
        guard !result.contains(where: { $0.matches(host: target.host, port: target.port) }) else {
            return
        }
        result.append(target)
    }

    private static func priority(of source: OpenClawConnectionTargetSource) -> Int {
        switch source {
        case .lanHint:
            return 0
        case .tailnetHint:
            return 1
        case .manual:
            return 2
        }
    }

    private static func inferSource(forHost rawHost: String) -> OpenClawConnectionTargetSource {
        let host = rawHost.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !host.isEmpty else {
            return .manual
        }
        if host.hasSuffix(".ts.net") || isTailnetIPv4(host) {
            return .tailnetHint
        }
        if host.hasSuffix(".local") || isPrivateLANIPv4(host) {
            return .lanHint
        }
        return .manual
    }

    private static func isTailnetIPv4(_ host: String) -> Bool {
        let octets = host.split(separator: ".").compactMap { Int($0) }
        guard octets.count == 4 else {
            return false
        }
        return octets[0] == 100 && (64...127).contains(octets[1])
    }

    private static func isPrivateLANIPv4(_ host: String) -> Bool {
        let octets = host.split(separator: ".").compactMap { Int($0) }
        guard octets.count == 4 else {
            return false
        }
        if octets[0] == 10 {
            return true
        }
        if octets[0] == 192 && octets[1] == 168 {
            return true
        }
        if octets[0] == 172 && (16...31).contains(octets[1]) {
            return true
        }
        return false
    }
}

struct Message: Codable, Identifiable {
    var id = UUID()
    let role: String
    var content: String
    var reasoning: String?
    var reasoningDetails: [MessageReasoningDetail]?
    
    enum Role: String {
        case system, user, assistant
    }
}

struct MessageReasoningDetail: Codable, Equatable {
    let type: String
    let text: String?

    enum CodingKeys: String, CodingKey {
        case type
        case text
    }
}

struct Round: Codable, Identifiable {
    var id = UUID()
    let userPrompt: Message
    var aiResponse: Message?
    
    // 临时流式状态
    var streamingReasoning: String = ""
    var streamingContent: String = ""
    var isStreaming: Bool = false
}

struct ClawSessionSummary: Identifiable, Equatable {
    let key: String
    var title: String
    var preview: String?
    var updatedAt: Date?

    var id: String { key }
}

struct ClawHistoryMessage: Equatable {
    let role: String
    let text: String
    let timestamp: Date?
}
