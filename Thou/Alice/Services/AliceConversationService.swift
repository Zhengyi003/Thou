/**
 Alice 模块的对话服务层。

 这个文件把 OpenRouterClient 作为底层传输封装起来，
 让上层 ViewModel 只关心消息数组、模型和 key，而不直接持有网络客户端实现。
 */

import Foundation

final class AliceConversationService {
    func streamChat(messages: [Message], apiKey: String, model: String) async throws -> AsyncThrowingStream<ChatDelta, Error> {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw NSError(
                domain: "AliceConversationService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Alice 尚未配置 OpenRouter API Key。可在设置页填写，或编辑 Thou/Alice/Config/AliceLocalSecrets.plist。"]
            )
        }

        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedModel = trimmedModel.isEmpty ? AliceConfigStore.defaultModel : trimmedModel
        let client = OpenRouterClient(apiKey: trimmedKey)
        return try await client.streamChat(messages: messages, model: resolvedModel)
    }
}