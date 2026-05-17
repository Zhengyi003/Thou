/**
 Thou iOS 应用的启动入口。

 这个文件只负责声明 App 生命周期和首个 Scene，
 把应用启动后的根视图固定为 ContentView。
 */

import SwiftUI

@main
struct ThouApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
