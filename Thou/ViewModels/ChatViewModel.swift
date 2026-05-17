/**
 Thou 主聊天页的状态编排层。

 这个文件现在主要承担 App Shell 层的协调职责：
 管理页面模式切换、共享壳层状态，并组合 Alice / OpenClaw 两个模块 ViewModel。
 */

import Foundation
import SwiftUI
import Combine

@MainActor
class ChatViewModel: ObservableObject {
    @Published var isUserInteracting: Bool = false
    @Published var currentMode: AgentMode = .claw
    @Published var currentPage: PageType = .chat
    
    private var cancellables = Set<AnyCancellable>()
    let aliceModule: AliceChatViewModel
    let clawModule: OpenClawChatViewModel
    
    init(
        aliceModule: AliceChatViewModel,
        clawModule: OpenClawChatViewModel
    ) {
        self.aliceModule = aliceModule
        self.clawModule = clawModule
        bindModuleState()
    }

    convenience init() {
        self.init(
            aliceModule: AliceChatViewModel(),
            clawModule: OpenClawChatViewModel()
        )
    }

    var currentRounds: [Round] {
        switch currentMode {
        case .alice:
            return aliceModule.rounds
        case .claw:
            return clawModule.rounds
        }
    }

    var currentDraft: String {
        get {
            switch currentMode {
            case .alice:
                return aliceModule.draft
            case .claw:
                return clawModule.draft
            }
        }
        set {
            switch currentMode {
            case .alice:
                aliceModule.draft = newValue
            case .claw:
                clawModule.draft = newValue
            }
        }
    }

    var aliceRounds: [Round] {
        aliceModule.rounds
    }

    var clawRounds: [Round] {
        clawModule.rounds
    }

    var isSending: Bool {
        switch currentMode {
        case .alice:
            return aliceModule.isSending
        case .claw:
            return clawModule.isSending
        }
    }

    var aliceApiKey: String {
        get { aliceModule.apiKey }
        set { aliceModule.apiKey = newValue }
    }

    var aliceModel: String {
        get { aliceModule.model }
        set { aliceModule.model = newValue }
    }

    var aliceAPIKeySourceDescription: String {
        aliceModule.configStore.apiKeySourceDescription
    }

    var aliceAPIKeyDebugSummary: String {
        aliceModule.configStore.apiKeyDebugSummary
    }

    var aliceRequestStatus: String {
        aliceModule.requestStatus
    }

    var aliceLastErrorMessage: String? {
        aliceModule.lastErrorMessage
    }

    var aliceLastRetrievedTopicTitles: [String] {
        aliceModule.lastRetrievedTopicTitles
    }

    var aliceDidReceiveReasoning: Bool {
        aliceModule.didReceiveReasoning
    }

    var aliceDidReceiveContent: Bool {
        aliceModule.didReceiveContent
    }

    var aliceLastModelResponseSummary: String {
        aliceModule.lastModelResponseSummary
    }

    var aliceConversationHistoryRoundCount: Int {
        aliceModule.conversationHistoryRoundCount
    }

    var aliceActiveWindowRoundCount: Int {
        aliceModule.activeWindowRoundCount
    }

    var aliceLastArchiveSummary: String {
        aliceModule.lastArchiveSummary
    }

    var aliceLastArchiveArchivedRoundCount: Int {
        aliceModule.lastArchiveArchivedRoundCount
    }

    var aliceDidTrimActiveRounds: Bool {
        aliceModule.didTrimActiveRounds
    }

    var aliceMemoryStatusText: String {
        aliceModule.memoryStatusText
    }

    var aliceIsRecallingMemory: Bool {
        aliceModule.isRecallingMemory
    }

    var pairingCode: String {
        get { clawModule.pairingCode }
        set { clawModule.pairingCode = newValue }
    }

    var clawConnectionMode: OpenClawConnectionMode {
        get { clawModule.connectionMode }
        set { clawModule.connectionMode = newValue }
    }

    var clawManualHost: String {
        get { clawModule.manualHost }
        set { clawModule.manualHost = newValue }
    }

    var clawManualPort: String {
        get { clawModule.manualPort }
        set { clawModule.manualPort = newValue }
    }

    var clawManualToken: String {
        get { clawModule.manualToken }
        set { clawModule.manualToken = newValue }
    }

    var clawManager: ClawConnectionManager {
        clawModule.clawManager
    }

    var clawRememberedTargets: [OpenClawConnectionTarget] {
        clawModule.rememberedTargets
    }

    var clawHasStoredManualToken: Bool {
        clawModule.hasStoredManualToken
    }

    var clawCanReconnectAutomatically: Bool {
        clawModule.canReconnectAutomatically
    }

    var clawNeedsSettingsAttention: Bool {
        currentMode == .claw && !clawManager.isConnected && clawCanReconnectAutomatically
    }

    private func bindModuleState() {
        aliceModule.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        clawModule.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
    
    func switchMode() {
        if currentMode == .alice {
            currentMode = .claw
        } else {
            currentMode = .alice
        }
    }
    
    func toggleSettings() {
        if currentPage == .settings {
            currentPage = .chat
        } else {
            currentPage = .settings
        }
    }
    
    func connectClaw() {
        clawModule.connect()
    }

    func loadRememberedClawTarget(_ target: OpenClawConnectionTarget) {
        clawModule.loadRememberedTarget(target)
    }

    func importClawConnectionInfo(_ rawText: String) {
        clawModule.importConnectionInfo(from: rawText)
    }
    
    func sendMessage(_ text: String) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        if currentMode == .alice {
            await aliceModule.sendMessage(text)
        } else {
            await clawModule.sendMessage(text)
        }
    }

    func resetAliceEnvironment() async {
        await aliceModule.resetEnvironment()
    }
}
