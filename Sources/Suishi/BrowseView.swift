import SwiftUI
import MediaCore

struct BrowseView: View {
    @ObservedObject var app: AppCoordinator
    @ObservedObject var browser: BilibiliPage
    @State private var address = ""
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "viewfinder").font(.system(size: 20)).foregroundStyle(UI.secondary)
                Text("随视.").font(.system(size: 20, weight: .semibold))
                Spacer()
                HStack(spacing: 4) {
                    Label("选片", systemImage: "magnifyingglass").padding(.horizontal, 16).frame(height: 32).background(UI.raised, in: RoundedRectangle(cornerRadius: 8))
                    Button { app.resume() } label: { Label("观看", systemImage: "display").padding(.horizontal, 16).frame(height: 32) }
                        .buttonStyle(.plain).disabled(app.recent == nil)
                }.font(.system(size: 12, weight: .semibold)).padding(4).background(UI.sunken, in: RoundedRectangle(cornerRadius: 12))
                Spacer()
                ToolButton(title: "随视设置 · ⌘,", symbol: "slider.horizontal.3") { app.showingSettings = true }
            }.padding(.horizontal, 24).padding(.vertical, 8)
            Divider().overlay(UI.border)
            HStack(spacing: 8) {
                ToolButton(title: "后退", symbol: "chevron.left") { browser.webView.goBack() }
                ToolButton(title: "刷新", symbol: "arrow.clockwise") { browser.reload() }
                HStack(spacing: 12) {
                    Image(systemName: "link").foregroundStyle(UI.muted)
                    TextField("B 站网址或 BV 号，也可粘贴分享文案", text: $address)
                        .textFieldStyle(.plain).font(.system(size: 14)).onSubmit(openAddress)
                        .accessibilityIdentifier("videoAddress")
                    if app.resolving { ProgressView().controlSize(.small) }
                    else { ToolButton(title: "打开视频", symbol: "arrow.right", action: openAddress).accessibilityIdentifier("openVideo") }
                }.padding(.leading, 16).padding(.trailing, 4).background(UI.raised, in: RoundedRectangle(cornerRadius: 8))
                ToolButton(title: "B 站首页", symbol: "house") { browser.browse() }
            }.padding(.horizontal, 16).padding(.vertical, 8).background(UI.sunken)
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("选好视频，就用舒服的姿势看。").font(.system(size: 24, weight: .semibold))
                        Text("在 B 站浏览与登录。点开视频，自动进入随视观看。").font(.system(size: 14)).foregroundStyle(UI.secondary)
                    }
                    Spacer()
                    Label("哔哩哔哩官网", systemImage: "lock").font(.system(size: 12)).foregroundStyle(UI.muted)
                }
                if let recent = app.recent {
                    HStack(spacing: 16) {
                        Image(systemName: "play.rectangle").font(.system(size: 24)).foregroundStyle(UI.secondary)
                            .frame(width: 64, height: 48).background(UI.sunken, in: RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("上次看到这里").font(.system(size: 12)).foregroundStyle(UI.muted)
                            Text(recent.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                            Text("已看 \(playbackTime(recent.seconds))").font(.system(size: 12)).foregroundStyle(UI.secondary)
                        }
                        Spacer(minLength: 16)
                        Button { app.resume() } label: { Label("继续观看", systemImage: "arrow.right") }
                            .buttonStyle(ActionStyle(primary: true)).accessibilityIdentifier("resumeVideo")
                    }.padding(16).background(UI.raised, in: RoundedRectangle(cornerRadius: 12))
                }
            }.padding(24)
            ZStack {
                WebSurface(webView: browser.webView)
                if browser.loading {
                    VStack { ProgressView().progressViewStyle(.linear).tint(UI.ink); Spacer() }.allowsHitTesting(false)
                }
                if let failure = browser.failure {
                    UI.surface.opacity(0.95)
                    MessageCard(title: "页面加载失败", message: failure, actionTitle: "重新加载") { browser.reload() }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).background(.white)
            HStack(spacing: 8) {
                Image(systemName: "lock")
                Text(app.notice ?? app.library.issue ?? "登录和清晰度由 B 站提供；摄像头仅在你主动开启后使用。")
                Spacer(minLength: 0)
            }.font(.system(size: 12)).foregroundStyle(UI.secondary).padding(.horizontal, 24).padding(.vertical, 12)
        }.foregroundStyle(UI.ink).background(UI.surface).preferredColorScheme(.light)
            .frame(minWidth: 800, minHeight: 640)
            .background(BrowserWindowReader { window in
                app.browserWindow = window
                window.title = "随视 · 选片"
                window.isReleasedWhenClosed = false
            }.frame(width: 0, height: 0))
            .onAppear { browser.startBrowsingIfNeeded() }
            .sheet(isPresented: Binding(get: { app.showingSettings && !app.watching }, set: { app.showingSettings = $0 })) {
                SettingsPanel(app: app, preferences: app.preferences).frame(width: 360, height: 680)
            }
    }
    private func openAddress() {
        let text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        // Recognize browser addresses only when they are official and not video selection.
        let candidate = text.contains("://") ? text : "https://" + text
        if let url = URL(string: candidate), BilibiliWebPolicy.isOfficialPage(url),
           BilibiliRoute.video(at: url) == nil, !url.path.hasPrefix("/video/") {
            browser.browse(url)
        } else { app.openInput(text) }
    }
}
