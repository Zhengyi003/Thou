/**
 Alice 模块的本地配置存储。

 这个文件负责持久化 Alice 专属的 OpenRouter API Key 与默认模型，
 让 App Shell 不需要直接注入 key，后续也便于独立扩展 Alice 的设置页。
 */

import Foundation
import Combine

@MainActor
final class AliceConfigStore: ObservableObject {
    static let defaultModel = "x-ai/grok-4.1-fast"
    static let bundledSecretsFileName = "AliceLocalSecrets"

    private enum Keys {
        static let apiKey = "AliceOpenRouterAPIKey"
        static let selectedModel = "AliceSelectedModel"
    }

    @Published var apiKey: String {
        didSet {
            userDefaults.set(apiKey, forKey: Keys.apiKey)
            apiKeySourceDescription = apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未配置" : "设置页 / UserDefaults"
            apiKeyDebugSummary = Self.describeKey(apiKey)
        }
    }

    @Published var selectedModel: String {
        didSet { userDefaults.set(selectedModel, forKey: Keys.selectedModel) }
    }

    @Published private(set) var apiKeySourceDescription: String
    @Published private(set) var apiKeyDebugSummary: String

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        let bundledSecrets = Self.loadBundledSecrets()

        let storedApiKey = userDefaults.string(forKey: Keys.apiKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let storedKeyIsUsable = Self.isLikelyOpenRouterAPIKey(storedApiKey)
        let bundledKeyIsUsable = Self.isLikelyOpenRouterAPIKey(bundledSecrets.apiKey)
        let resolvedAPIKey: String
        let resolvedAPIKeySource: String
        if storedKeyIsUsable {
            resolvedAPIKey = storedApiKey
            resolvedAPIKeySource = "设置页 / UserDefaults"
        } else if bundledKeyIsUsable {
            resolvedAPIKey = bundledSecrets.apiKey
            resolvedAPIKeySource = storedApiKey.isEmpty ? "AliceLocalSecrets.plist" : "AliceLocalSecrets.plist（已忽略无效的 UserDefaults Key）"
            if !storedApiKey.isEmpty {
                userDefaults.removeObject(forKey: Keys.apiKey)
            }
        } else {
            resolvedAPIKey = storedApiKey
            resolvedAPIKeySource = storedApiKey.isEmpty ? "未配置" : "设置页 / UserDefaults（格式可疑）"
        }

        let storedModel = userDefaults.string(forKey: Keys.selectedModel)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolvedModel: String
        if storedModel.isEmpty {
            resolvedModel = bundledSecrets.model?.isEmpty == false ? bundledSecrets.model! : Self.defaultModel
        } else {
            resolvedModel = storedModel
        }

        self.apiKey = resolvedAPIKey
        self.selectedModel = resolvedModel
        self.apiKeySourceDescription = resolvedAPIKeySource
        self.apiKeyDebugSummary = Self.describeKey(resolvedAPIKey)
    }

    private static func loadBundledSecrets() -> (apiKey: String, model: String?) {
        guard let url = Bundle.main.url(forResource: bundledSecretsFileName, withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return ("", nil)
        }

        let apiKey = (plist["OpenRouterAPIKey"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let model = (plist["OpenRouterModel"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (apiKey, model)
    }

    private static func describeKey(_ rawKey: String) -> String {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            return "未检测到 API Key"
        }

        let hasWhitespace = key.rangeOfCharacter(from: .whitespacesAndNewlines) != nil
        let hasControl = key.rangeOfCharacter(from: .controlCharacters) != nil
        let hasNonASCII = key.unicodeScalars.contains { !$0.isASCII }
        let prefix = String(key.prefix(6))
        let suffix = String(key.suffix(4))

        return "长度 \(key.count)，前缀 \(prefix)，后缀 \(suffix)，空白=\(hasWhitespace ? "是" : "否")，控制符=\(hasControl ? "是" : "否")，非 ASCII=\(hasNonASCII ? "是" : "否")"
    }

    private static func isLikelyOpenRouterAPIKey(_ rawKey: String) -> Bool {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            return false
        }

        return key.hasPrefix("sk-or-") && key.count >= 16
    }
}