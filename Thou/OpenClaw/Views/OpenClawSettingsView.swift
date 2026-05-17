/**
 OpenClaw 模块的设置子视图。

 这个文件负责展示配对码输入、粘贴/清空、连接按钮与连接状态，
 让共享聊天壳只负责容器和模式切换，而不直接承载远程连接表单逻辑。
 */

import SwiftUI
import UIKit

struct OpenClawSettingsView: View {
    @Binding var connectionMode: OpenClawConnectionMode
    @Binding var pairingCode: String
    @Binding var manualHost: String
    @Binding var manualPort: String
    @Binding var manualToken: String
    let rememberedTargets: [OpenClawConnectionTarget]
    let hasStoredManualToken: Bool
    let isConnected: Bool
    let connectionStatus: String
    let onLoadRememberedTarget: (OpenClawConnectionTarget) -> Void
    let onImportConnectionText: (String) -> Void
    let onConnect: () -> Void

    @State private var showAdvancedOptions = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            importSection

            Button(showAdvancedOptions ? "收起高级连接选项" : "显示高级连接选项") {
                showAdvancedOptions.toggle()
            }
            .font(.caption)

            if showAdvancedOptions {
                Picker("连接方式", selection: $connectionMode) {
                    Text("神奇配对码").tag(OpenClawConnectionMode.pairing)
                    Text("手动地址").tag(OpenClawConnectionMode.manualHost)
                }
                .pickerStyle(.segmented)

                if connectionMode == .pairing {
                    pairingSection
                } else {
                    manualHostSection
                }

                if !rememberedTargets.isEmpty {
                    rememberedTargetsSection
                }
            }

            Button(action: onConnect) {
                VStack(spacing: 4) {
                    Text(isConnected ? "已连接" : "立即连接")
                        .bold()
                    Text(connectionStatus)
                        .font(.caption2)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(isConnected ? Color.green : (canConnect ? Color.blue : Color.gray))
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .disabled(isConnected || !canConnect)

            Text(helpText)
                .font(.caption)
                .foregroundColor(.gray)
        }
    }

    private var importSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("连接我的 Mac")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text("先在 Mac 端 OpenClaw 的 Thou 设置卡片里复制连接信息，再回到这里直接粘贴。首次成功后，后续会尽量自动恢复连接。")
                .font(.caption)
                .foregroundColor(.gray)

            Button("粘贴连接信息") {
                let pasted = UIPasteboard.general.string?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !pasted.isEmpty {
                    onImportConnectionText(pasted)
                }
            }
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.black)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(14)
    }

    private var pairingSection: some View {
        Group {
            Text("神奇配对码")
                .font(.subheadline)
                .foregroundColor(.secondary)

            TextField("XXXX-XXXX-XXXX", text: $pairingCode)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled(true)

            HStack(spacing: 12) {
                Button("粘贴配对码") {
                    let pasted = UIPasteboard.general.string?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if !pasted.isEmpty {
                        pairingCode = pasted
                    }
                }
                .font(.caption)

                if !pairingCode.isEmpty {
                    Button("清空") {
                        pairingCode = ""
                    }
                    .font(.caption)
                }
            }
        }
    }

    private var manualHostSection: some View {
        Group {
            Text("远程地址")
                .font(.subheadline)
                .foregroundColor(.secondary)

            TextField("主机或域名，例如 100.x.x.x / example.ts.net", text: $manualHost)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)

            TextField("端口", text: $manualPort)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.numberPad)

            SecureField("完整鉴权口令", text: $manualToken)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)

            HStack(spacing: 12) {
                Button("粘贴口令") {
                    let pasted = UIPasteboard.general.string?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if !pasted.isEmpty {
                        manualToken = pasted
                    }
                }
                .font(.caption)

                if !manualToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button("清空口令") {
                        manualToken = ""
                    }
                    .font(.caption)
                }
            }

            if hasStoredManualToken {
                Text("当前已保存完整鉴权口令，可直接修改地址后重连。")
                    .font(.caption)
                    .foregroundColor(.gray)
            } else {
                Text("完整鉴权口令不会随 App 预装；首次可从 Mac 复制后在这里粘贴，随后会本地保存。")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
    }

    private var rememberedTargetsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("已记住的连接目标")
                .font(.subheadline)
                .foregroundColor(.secondary)

            ForEach(rememberedTargets) { target in
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(target.host):\(target.port)")
                            .font(.callout)
                            .foregroundColor(.primary)

                        Text(targetDescription(for: target))
                            .font(.caption)
                            .foregroundColor(.gray)
                    }

                    Spacer()

                    Button("载入") {
                        onLoadRememberedTarget(target)
                    }
                    .font(.caption)
                }
                .padding(10)
                .background(Color(.systemGray6))
                .cornerRadius(10)
            }

            Text("配对模式连接时，系统会先尝试局域网，再尝试这些已记住的目标；手动模式下可把它们载入后再微调。")
                .font(.caption)
                .foregroundColor(.gray)
        }
    }

    private var canConnect: Bool {
        switch connectionMode {
        case .pairing:
            return !pairingCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .manualHost:
            return !manualHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !manualToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !(manualPort.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var helpText: String {
        "若自动恢复失败，可重新粘贴连接信息；高级连接选项保留给手动排查和局域网配对。"
    }

    private func targetDescription(for target: OpenClawConnectionTarget) -> String {
        switch target.source {
        case .lanHint:
            return "局域网线索"
        case .tailnetHint:
            return "Tailnet 线索"
        case .manual:
            return "手动保存"
        }
    }
}