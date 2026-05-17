/**
 Thou 主聊天页的 SwiftUI 视图实现。

 这个文件负责把 ChatViewModel 提供的状态渲染成 Alice / OpenClaw 双模式页面，
 同时承接设置页、聊天列表和输入区的具体布局。
 */

import SwiftUI
import UIKit

struct ChatView: View {
    @StateObject var viewModel: ChatViewModel
    @FocusState private var inputFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if viewModel.currentPage == .chat {
                    chatPager
                } else if viewModel.currentPage == .settings {
                    settingsView
                } else if viewModel.currentPage == .readme {
                    readmeView
                } else if viewModel.currentPage == .fun {
                    funView
                }
            }
            
            if viewModel.currentPage == .chat {
                inputBar
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                titleMenu
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                if viewModel.currentPage == .chat {
                    Button(action: { viewModel.toggleSettings() }) {
                        Image(systemName: viewModel.clawNeedsSettingsAttention ? "ellipsis.circle.fill" : "ellipsis.circle")
                            .foregroundColor(viewModel.clawNeedsSettingsAttention ? .orange : .black)
                    }
                } else {
                    Button("完成") { viewModel.currentPage = .chat }
                        .foregroundColor(.black)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Subviews

    private var chatPager: some View {
        TabView(selection: $viewModel.currentMode) {
            chatList(for: .alice)
                .tag(AgentMode.alice)

            chatList(for: .claw)
                .tag(AgentMode.claw)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .animation(.easeInOut(duration: 0.2), value: viewModel.currentMode)
    }

    private func chatList(for mode: AgentMode) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if mode == .alice {
                        aliceDebugCard
                    }

                    ForEach(rounds(for: mode)) { round in
                        RoundView(round: round, mode: mode)
                            .id(round.id)
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .contentShape(Rectangle())
            .onTapGesture {
                inputFocused = false
            }
            .onChange(of: rounds(for: mode).map { $0.id }) { _, _ in
                if !viewModel.isUserInteracting {
                    withAnimation {
                        proxy.scrollTo(rounds(for: mode).last?.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func rounds(for mode: AgentMode) -> [Round] {
        switch mode {
        case .alice:
            return viewModel.aliceRounds
        case .claw:
            return viewModel.clawRounds
        }
    }

    private var aliceDebugCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Alice 联调状态")
                .font(.subheadline.weight(.semibold))

            Text(viewModel.aliceRequestStatus)
                .font(.caption)
                .foregroundColor(.secondary)

            Text("Key 来源: \(viewModel.aliceAPIKeySourceDescription)")
                .font(.caption)
                .foregroundColor(.secondary)

            Text("Key 摘要: \(viewModel.aliceAPIKeyDebugSummary)")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                debugPill(title: "正在回忆", isActive: viewModel.aliceIsRecallingMemory)
                debugPill(title: "已归档", isActive: viewModel.aliceMemoryStatusText == "已归档")
                debugPill(title: "Retrieve", isActive: !viewModel.aliceLastRetrievedTopicTitles.isEmpty)
                debugPill(title: "Reasoning", isActive: viewModel.aliceDidReceiveReasoning)
                debugPill(title: "正文", isActive: viewModel.aliceDidReceiveContent)
                debugPill(title: "Archive", isActive: viewModel.aliceLastArchiveArchivedRoundCount > 0)
                debugPill(title: "截断", isActive: viewModel.aliceDidTrimActiveRounds)
            }

            Text("记忆状态: \(viewModel.aliceMemoryStatusText)")
                .font(.caption)
                .foregroundColor(.secondary)

            if !viewModel.aliceLastRetrievedTopicTitles.isEmpty {
                Text("命中 Topics: " + viewModel.aliceLastRetrievedTopicTitles.joined(separator: "、"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text("当前显示 \(viewModel.aliceActiveWindowRoundCount) 轮，完整会话已记录 \(viewModel.aliceConversationHistoryRoundCount) 轮")
                .font(.caption)
                .foregroundColor(.secondary)

            Text(viewModel.aliceLastArchiveSummary)
                .font(.caption)
                .foregroundColor(.secondary)

            Text(viewModel.aliceLastModelResponseSummary)
                .font(.caption)
                .foregroundColor(.secondary)

            if let errorMessage = viewModel.aliceLastErrorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 249/255, green: 246/255, blue: 239/255))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
    }

    private func debugPill(title: String, isActive: Bool) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isActive ? Color.black : Color.black.opacity(0.08))
            .foregroundColor(isActive ? .white : .black.opacity(0.6))
            .clipShape(Capsule())
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 12) {
            HStack(alignment: .bottom, spacing: 8) {
                TextField(
                    "It's all about you...",
                    text: currentDraftBinding,
                    axis: .vertical
                )
                .focused($inputFocused)
                .textFieldStyle(.plain)
                .textInputAutocapitalization(.sentences)
                .autocorrectionDisabled(false)
                .lineLimit(1...4)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                if viewModel.currentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button(action: pasteDraft) {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.black.opacity(0.6))
                            .frame(width: 32, height: 32)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(viewModel.currentMode == .alice ? Color(red: 240/255, green: 238/255, blue: 231/255) : Color(red: 239/255, green: 228/255, blue: 230/255))
            )
            .frame(minHeight: 56)

            Button(action: {
                let text = viewModel.currentDraft
                Task { await viewModel.sendMessage(text) }
                inputFocused = true
            }) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 48, height: 48)
                    .background(Color.black)
                    .foregroundColor(.white)
                    .clipShape(Circle())
            }
            .disabled(viewModel.currentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isSending)
            .opacity(viewModel.currentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isSending ? 0.4 : 1)
        }
        .padding()
        .background(Color.white)
    }

    private var currentDraftBinding: Binding<String> {
        Binding(
            get: { viewModel.currentDraft },
            set: { viewModel.currentDraft = $0 }
        )
    }

    private func pasteDraft() {
        let pasted = UIPasteboard.general.string?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !pasted.isEmpty else { return }
        viewModel.currentDraft = pasted
        inputFocused = true
    }

    private var settingsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(viewModel.currentMode == .alice ? "Alice 配置" : "OpenClaw 配置")
                    .font(.title2).bold()

                if viewModel.currentMode == .alice {
                    AliceSettingsView(
                        apiKey: Binding(
                            get: { viewModel.aliceApiKey },
                            set: { viewModel.aliceApiKey = $0 }
                        ),
                        model: Binding(
                            get: { viewModel.aliceModel },
                            set: { viewModel.aliceModel = $0 }
                        ),
                        memoryStatusText: viewModel.aliceMemoryStatusText,
                        onResetEnvironment: {
                            Task { await viewModel.resetAliceEnvironment() }
                        }
                    )
                } else {
                    OpenClawSettingsView(
                        connectionMode: Binding(
                            get: { viewModel.clawConnectionMode },
                            set: { viewModel.clawConnectionMode = $0 }
                        ),
                        pairingCode: $viewModel.pairingCode,
                        manualHost: Binding(
                            get: { viewModel.clawManualHost },
                            set: { viewModel.clawManualHost = $0 }
                        ),
                        manualPort: Binding(
                            get: { viewModel.clawManualPort },
                            set: { viewModel.clawManualPort = $0 }
                        ),
                        manualToken: Binding(
                            get: { viewModel.clawManualToken },
                            set: { viewModel.clawManualToken = $0 }
                        ),
                        rememberedTargets: viewModel.clawRememberedTargets,
                        hasStoredManualToken: viewModel.clawHasStoredManualToken,
                        isConnected: viewModel.clawManager.isConnected,
                        connectionStatus: viewModel.clawManager.connectionStatus,
                        onLoadRememberedTarget: { target in
                            viewModel.loadRememberedClawTarget(target)
                        },
                        onImportConnectionText: { rawText in
                            viewModel.importClawConnectionInfo(rawText)
                        },
                        onConnect: {
                            print("Connect Button Tapped")
                            viewModel.connectClaw()
                        }
                    )
                }
                Spacer()
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .contentShape(Rectangle())
        .onTapGesture {
            inputFocused = false
        }
    }

    private var funView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Fun").font(.title).bold()
                Text("这个页面先保留为占位，后续再补具体内容。")
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .contentShape(Rectangle())
        .onTapGesture {
            inputFocused = false
        }
    }

    private var readmeView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("关于 Thou").font(.title).bold()
                Text("Thou 是一款极简的 AI 社交陪伴与远程控制工具。")
                Text("Alice 模式：基于云端大模型的智能陪伴。")
                Text("OpenClaw 模式：直连本地 Mac 的 AI 代理。")
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .contentShape(Rectangle())
        .onTapGesture {
            inputFocused = false
        }
    }

    private var titleMenu: some View {
        Menu {
            Button("Readme") { viewModel.currentPage = .readme }
            Button("Fun (Coming Soon)") { viewModel.currentPage = .fun }
            if viewModel.currentPage != .chat {
                Divider()
                Button("返回聊天") { viewModel.currentPage = .chat }
            }
        } label: {
            HStack {
                Text(viewModel.currentPage == .chat ? viewModel.currentMode.rawValue : (viewModel.currentPage == .settings ? "设置" : "说明"))
                    .font(.headline)
                    .foregroundColor(.black)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
        }
    }
}

struct RoundView: View {
    let round: Round
    let mode: AgentMode
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 用户消息
            HStack {
                Spacer()
                Text(round.userPrompt.content)
                    .padding(12)
                    .background(mode == .alice ? Color(red: 240/255, green: 238/255, blue: 231/255) : Color(red: 242/255, green: 222/255, blue: 221/255))
                    .cornerRadius(16)
                    .foregroundColor(.black)
            }
            
            // AI 思考过程 (如果有)
            if !round.streamingReasoning.isEmpty || (round.aiResponse?.reasoning != nil) {
                DisclosureGroup("Thinking...") {
                    Text(round.aiResponse?.reasoning ?? round.streamingReasoning)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
                .font(.caption)
                .accentColor(.secondary)
            }
            
            // AI 正文
            if !round.streamingContent.isEmpty || (round.aiResponse != nil) {
                Text(round.aiResponse?.content ?? round.streamingContent)
                    .padding(12)
                    .background(Color(.systemGray6))
                    .cornerRadius(16)
                    .foregroundColor(.black)
            }
        }
    }
}
