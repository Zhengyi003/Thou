/**
 Thou 主聊天页的 SwiftUI 视图实现。

 这个文件当前只渲染 OpenClaw companion 首发 UI，
 并承接设置页、agent 列表、聊天列表和输入区布局。
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
            
            if viewModel.currentPage == .chat && !(viewModel.currentMode == .claw && viewModel.clawIsShowingAgentInbox) {
                inputBar
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                leadingToolbarItem
            }

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
        .confirmationDialog(
            "选择 Session",
            isPresented: Binding(
                get: { viewModel.currentMode == .claw && viewModel.currentPage == .chat && viewModel.clawIsShowingSessionPicker },
                set: { isPresented in
                    if !isPresented {
                        viewModel.hideClawSessionPicker()
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            ForEach(viewModel.clawSessionPickerItems) { session in
                Button(sessionTitle(session)) {
                    viewModel.selectClawSession(session.key)
                }
            }

            Button("取消", role: .cancel) {
                viewModel.hideClawSessionPicker()
            }
        }
    }

    // MARK: - Subviews

    private var chatPager: some View {
        chatList
    }

    @ViewBuilder
    private var chatList: some View {
        if viewModel.clawIsShowingAgentInbox {
            clawAgentInboxView
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(viewModel.clawRounds) { round in
                            RoundView(round: round)
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
                .onChange(of: viewModel.clawRounds.map { $0.id }) { _, _ in
                    if !viewModel.isUserInteracting {
                        withAnimation {
                            proxy.scrollTo(viewModel.clawRounds.last?.id, anchor: .bottom)
                        }
                    }
                }
                .simultaneousGesture(backToAgentInboxGesture)
            }
        }
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
                    .fill(Color(red: 239/255, green: 228/255, blue: 230/255))
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
                Text("OpenClaw 配置")
                    .font(.title2).bold()

                OpenClawSettingsView(
                    connectionMode: Binding(
                        get: { viewModel.clawConnectionMode },
                        set: { viewModel.clawConnectionMode = $0 }
                    ),
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
                    },
                    onDisconnect: {
                        viewModel.disconnectClaw()
                    }
                )
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
                Text("Thou 当前首发聚焦 OpenClaw companion。")
                Text("你可以先选一个 agent，再进入它名下的 session 继续工作。")
                Text("当前版本的目标是把 iPhone 变成连接 Mac 上 OpenClaw 的低摩擦 companion。")
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
        Group {
            if viewModel.currentPage == .chat {
                Text(viewModel.clawIsShowingAgentInbox ? "Agents" : viewModel.clawSelectedAgentName)
                    .font(.headline)
                    .foregroundColor(.black)
            } else {
                Menu {
                    Button("Readme") { viewModel.currentPage = .readme }
                    Button("Fun (Coming Soon)") { viewModel.currentPage = .fun }
                    if viewModel.currentPage != .chat {
                        Divider()
                        Button("返回聊天") { viewModel.currentPage = .chat }
                    }
                } label: {
                    HStack {
                        Text(viewModel.currentPage == .settings ? "设置" : "说明")
                            .font(.headline)
                            .foregroundColor(.black)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                }
            }
        }
    }

    private var leadingToolbarItem: some View {
        Group {
            if viewModel.currentPage == .chat {
                if viewModel.clawIsShowingAgentInbox {
                    EmptyView()
                } else {
                    HStack(spacing: 14) {
                        Button(action: {
                            viewModel.showClawAgentInbox()
                        }) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.black)
                        }

                        Button(action: {
                            viewModel.toggleClawSessionPicker()
                        }) {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundColor(.black)
                        }
                    }
                }
            } else {
                EmptyView()
            }
        }
    }

    private var backToAgentInboxGesture: some Gesture {
        DragGesture(minimumDistance: 20, coordinateSpace: .local)
            .onEnded { value in
                guard viewModel.currentPage == .chat,
                      !viewModel.clawIsShowingAgentInbox else {
                    return
                }

                let horizontalTravel = value.translation.width
                let verticalTravel = abs(value.translation.height)

                guard horizontalTravel > 90, verticalTravel < 80 else {
                    return
                }

                viewModel.showClawAgentInbox()
            }
    }

    private var clawAgentInboxView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Agents")
                    .font(.title2.weight(.bold))

                Text("像聊天对象列表一样先选一个 agent，再进入它名下的 session。")
                    .font(.caption)
                    .foregroundColor(.secondary)

                ForEach(viewModel.clawAgentSummaries) { agent in
                    Button(action: {
                        viewModel.selectClawAgent(agent.id)
                    }) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(agent.name)
                                        .font(.headline)
                                        .foregroundColor(.black)

                                    Text(agent.subtitle)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                if agent.unreadCount > 0 {
                                    Text("\(agent.unreadCount)")
                                        .font(.caption2.weight(.bold))
                                        .frame(minWidth: 22, minHeight: 22)
                                        .background(Color.black)
                                        .foregroundColor(.white)
                                        .clipShape(Capsule())
                                }
                            }

                            if let preview = agent.lastPreview, !preview.isEmpty {
                                Text(preview)
                                    .font(.subheadline)
                                    .foregroundColor(.black.opacity(0.75))
                                    .lineLimit(2)
                            }

                            if let updatedAt = agent.updatedAt {
                                Text(relativeDate(updatedAt))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .fill(Color(red: 246/255, green: 241/255, blue: 241/255))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(Color.black.opacity(0.08), lineWidth: 1)
                        )
                    }
                }
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .contentShape(Rectangle())
        .onTapGesture {
            inputFocused = false
            viewModel.hideClawSessionPicker()
        }
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func sessionTitle(_ session: OpenClawSessionPickerItem) -> String {
        if session.key == viewModel.clawSelectedSessionKey {
            return "✓ " + session.title
        }

        return session.title
    }
}

struct RoundView: View {
    let round: Round
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 用户消息
            HStack {
                Spacer()
                Text(round.userPrompt.content)
                    .padding(12)
                    .background(Color(red: 242/255, green: 222/255, blue: 221/255))
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
