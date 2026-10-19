import SwiftUI

final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    var onTerminate: (() -> Void)?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { onTerminate?() }
}

@main
struct EyesToScreenApp: App {
    @NSApplicationDelegateAdaptor(ApplicationDelegate.self) var delegate
    @StateObject private var model = AppModel()
    var body: some Scene {
        Window("随视 · From Eyes to Screen", id: "main") {
            Group {
                if model.viewingMode == .workbench { MainView(model: model) }
                else { Color.clear }
            }
                .frame(minWidth: 1020, minHeight: 740)
                .background(MainWindowReader { model.viewingWindows.mainWindow = $0 })
                .sheet(isPresented: $model.showingSettings) { SettingsView(model: model, settings: model.settings) }
                .onAppear { delegate.onTerminate = { model.shutdown() } }
                .onOpenURL { model.openVideo($0) }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1240, height: 850)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("随视设置…", action: model.openSettings).keyboardShortcut(",")
            }
            CommandGroup(replacing: .newItem) {
                Button("导入本地视频…", action: model.importVideo).keyboardShortcut("o")
                Button("打开哔哩哔哩视频…") { model.showingBilibiliSheet = true }.keyboardShortcut("l")
                Button("试播演示", action: model.openExample)
            }
            CommandMenu("播放") {
                Button("登录哔哩哔哩…", action: model.webPlayer.showLogin).disabled(model.viewingMode != .workbench)
                Divider()
                Button(model.isPlaying ? "暂停" : "播放", action: model.togglePlayback).keyboardShortcut(.space, modifiers: []).disabled(model.isBilibili)
                Button("后退 10 秒") { model.seek(to: model.currentTime - 10) }.keyboardShortcut(.leftArrow, modifiers: []).disabled(model.isBilibili)
                Button("前进 10 秒") { model.seek(to: model.currentTime + 10) }.keyboardShortcut(.rightArrow, modifiers: []).disabled(model.isBilibili)
                Divider()
                Button("校准水平", action: model.calibrate).keyboardShortcut("r").disabled(!model.canCalibrate)
            }
            CommandMenu("观看") {
                Button("全屏观看") { model.enterViewing(.fullscreen) }.disabled(!model.hasContent)
                Button("返回观看室", action: model.leaveViewing).disabled(model.viewingMode == .workbench)
                Button(model.following ? "冻结角度" : "恢复跟随") { model.following.toggle() }
                    .keyboardShortcut(.space, modifiers: [.command, .shift]).disabled(model.manualMode)
                Button("画面居中", action: model.centerViewing).keyboardShortcut("0", modifiers: [.command, .shift])
            }
        }
    }
}
