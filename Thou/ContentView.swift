/**
 Thou 应用的主界面入口。

 这个文件负责把根导航容器和主聊天视图接到一起，
 让 OpenClaw companion 聊天壳在应用启动后成为默认首页。
 */

import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel = ChatViewModel()

    var body: some View {
        NavigationView {
            ChatView(viewModel: viewModel)
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else {
                return
            }
            viewModel.handleAppDidBecomeActive()
        }
    }
}
