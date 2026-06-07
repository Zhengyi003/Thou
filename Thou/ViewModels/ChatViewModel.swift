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
    let clawModule: OpenClawChatViewModel
    
    init(clawModule: OpenClawChatViewModel) {
        self.clawModule = clawModule
        bindModuleState()
    }

    convenience init() {
        self.init(clawModule: OpenClawChatViewModel())
    }

    var currentRounds: [Round] {
        clawModule.rounds
    }

    var currentDraft: String {
        get {
            clawModule.draft
        }
        set {
            clawModule.draft = newValue
        }
    }

    var clawRounds: [Round] {
        clawModule.rounds
    }

    var isSending: Bool {
        clawModule.isSending
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

    var clawIsShowingAgentInbox: Bool {
        clawModule.isShowingAgentInbox
    }

    var clawIsShowingSessionPicker: Bool {
        clawModule.isShowingSessionPicker
    }

    var clawAgentSummaries: [OpenClawAgentSummary] {
        clawModule.agentSummaries
    }

    var clawSelectedAgentName: String {
        clawModule.selectedAgentName
    }

    var clawSelectedSessionTitle: String {
        clawModule.selectedSessionTitle
    }

    var clawSelectedSessionKey: String {
        clawModule.selectedSessionKey
    }

    var clawSelectedSessionPreview: String? {
        clawModule.selectedSessionPreview
    }

    var clawSessionPickerItems: [OpenClawSessionPickerItem] {
        clawModule.sessionPickerItems
    }

    var clawCanReconnectAutomatically: Bool {
        clawModule.canReconnectAutomatically
    }

    var clawNeedsSettingsAttention: Bool {
        currentMode == .claw && !clawManager.isConnected && clawCanReconnectAutomatically
    }

    private func bindModuleState() {
        clawModule.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
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

    func disconnectClaw() {
        clawModule.disconnect()
    }

    func handleAppDidBecomeActive() {
        clawModule.handleAppDidBecomeActive()
    }

    func loadRememberedClawTarget(_ target: OpenClawConnectionTarget) {
        clawModule.loadRememberedTarget(target)
    }

    func importClawConnectionInfo(_ rawText: String) {
        clawModule.importConnectionInfo(from: rawText)
    }

    func showClawAgentInbox() {
        clawModule.showAgentInbox()
    }

    func selectClawAgent(_ agentId: String) {
        clawModule.selectAgent(agentId)
    }

    func toggleClawSessionPicker() {
        clawModule.toggleSessionPicker()
    }

    func hideClawSessionPicker() {
        clawModule.hideSessionPicker()
    }

    func selectClawSession(_ sessionKey: String) {
        clawModule.selectSession(sessionKey)
    }
    
    func sendMessage(_ text: String) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        await clawModule.sendMessage(text)
    }
}
