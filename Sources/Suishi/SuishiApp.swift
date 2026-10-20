import SwiftUI
import AppKit

@main struct SuishiApp: App {
    @NSApplicationDelegateAdaptor(SuishiDelegate.self) private var delegate
    @StateObject private var app = AppCoordinator()
    var body: some Scene {
        Window("随视 · 选片", id: "browser") {
            BrowseView(app: app, browser: app.content.browser)
                .onAppear { delegate.app = app }
        }.defaultSize(width: 1180, height: 820).windowStyle(.hiddenTitleBar)
            .commands {
                CommandGroup(replacing: .newItem) {}
                CommandGroup(replacing: .appSettings) {
                    Button("随视设置…") { app.showingSettings = true }.keyboardShortcut(",")
                }
                CommandMenu("观看") {
                    Button("返回选片") { app.showBrowser() }.keyboardShortcut("l")
                    Button("继续上次观看") { app.resume() }.disabled(app.recent == nil)
                    Button("重新加载当前视频") { app.content.player.reload() }.keyboardShortcut("r", modifiers: [.command, .shift]).disabled(!app.watching)
                    Divider()
                    Button(app.following ? "暂停头部跟随" : "开启头部跟随") { app.toggleFollowing() }.disabled(!app.watching)
                    Button("校准水平") { app.calibrate() }.keyboardShortcut("r").disabled(!app.canCalibrate)
                    Button("井字引导线") { app.toggleGuides() }.keyboardShortcut("g", modifiers: [.command])
                    Button("画面居中") { app.center() }.keyboardShortcut("0", modifiers: [.command, .shift])
                    Button("全屏观看") { app.viewingWindow.toggleFullScreen() }.keyboardShortcut("f", modifiers: [.command, .control]).disabled(!app.watching)
                }
            }
    }
}

@MainActor final class SuishiDelegate: NSObject, NSApplicationDelegate {
    weak var app: AppCoordinator?
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { app?.showBrowser() }; return true
    }
    func applicationWillResignActive(_ notification: Notification) { app?.persistProgress() }
    func applicationWillTerminate(_ notification: Notification) { app?.shutdown() }
}
