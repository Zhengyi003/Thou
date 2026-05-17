/**
 Alice 模块的设置子视图。

 这个文件负责展示 Alice 专属配置，当前包含 OpenRouter API Key 与默认模型，
 让共享聊天壳不再直接承载 Alice 的设置表单细节。
 */

import SwiftUI

struct AliceSettingsView: View {
    @Binding var apiKey: String
    @Binding var model: String
    let memoryStatusText: String
    let onResetEnvironment: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("OpenRouter API Key")
                .font(.subheadline)
                .foregroundColor(.secondary)

            SecureField("sk-or-...", text: $apiKey)
                .textFieldStyle(.roundedBorder)

            Text("Alice 默认模型")
                .font(.subheadline)
                .foregroundColor(.secondary)

            TextField(AliceConfigStore.defaultModel, text: $model)
                .textFieldStyle(.roundedBorder)

            Text("获取方式：访问 openrouter.ai 生成 API Key。")
                .font(.caption)
                .foregroundColor(.gray)

            Text("如果模拟器复制粘贴不可靠，可直接编辑 Thou/Alice/Config/AliceLocalSecrets.plist 里的 OpenRouterAPIKey，然后重新 build。")
                .font(.caption)
                .foregroundColor(.gray)

            Text("填好后回到 Alice 聊天页直接发送一条消息，上方会显示 retrieve / reasoning / 正文 的联调状态。")
                .font(.caption)
                .foregroundColor(.gray)

            Text("若 iPhone 真机上的 Alice 报 OpenRouter HTTP 500，先临时关闭 Tailscale / VPN 再试；当前已确认它会显著放大失败概率，但并不是唯一条件。")
                .font(.caption)
                .foregroundColor(.gray)

            Divider()
                .padding(.vertical, 8)

            Text("当前记忆状态：\(memoryStatusText)")
                .font(.caption)
                .foregroundColor(.secondary)

            Button(role: .destructive, action: onResetEnvironment) {
                Text("重置 Alice 测试环境")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Text("会清空当前 Alice 的 Sessions、Messages、Topics、Impressions，并重置本地 session 锚点；不会删除 API Key 和模型设置。")
                .font(.caption)
                .foregroundColor(.gray)
        }
    }
}