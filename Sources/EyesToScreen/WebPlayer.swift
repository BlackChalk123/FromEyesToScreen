import SwiftUI
import WebKit
import MediaCore

@MainActor
final class WebPlayerController: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    let webView: WKWebView
    @Published private(set) var loading = false
    @Published private(set) var failure: String?
    @Published private(set) var playbackMode = BilibiliPlaybackMode.website
    private var currentLink: BilibiliVideoLink?
    private var activeNavigation: WKNavigation?
    private var documentID = UUID()
    private lazy var accountWindow: BilibiliAccountWindow = {
        let controller = BilibiliAccountWindow(dataStore: webView.configuration.websiteDataStore)
        controller.onFinish = { [weak self] in
            guard let self else { return }
            self.navigatePreservingPosition(to: self.playbackMode)
        }
        return controller
    }()

    override convenience init() { self.init(configuration: BilibiliWebConfiguration.make()) }

    init(configuration: WKWebViewConfiguration) {
        configuration.userContentController.addUserScript(WKUserScript(source: BilibiliPageLayout.script,
            injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        // Native app fullscreen preserves our rotated viewing surface.
        configuration.preferences.isElementFullscreenEnabled = false
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.underPageBackgroundColor = .black
        webView.allowsBackForwardNavigationGestures = false
    }

    func load(_ link: BilibiliVideoLink, at time: Double? = nil) {
        documentID = UUID()
        currentLink = link
        loading = true
        failure = nil
        var url = playbackMode.url(for: link)
        if let time, time.isFinite, time >= 0 {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            components.queryItems = (components.queryItems ?? []).filter { $0.name != "t" } +
                [URLQueryItem(name: "t", value: String(time))]
            url = components.url!
        }
        activeNavigation = webView.load(URLRequest(url: url, timeoutInterval: 30))
    }

    func reload() {
        if let currentLink { load(currentLink) }
    }

    func setPlaybackMode(_ mode: BilibiliPlaybackMode) {
        guard mode != playbackMode else { return }
        navigatePreservingPosition(to: mode)
    }

    private func navigatePreservingPosition(to mode: BilibiliPlaybackMode) {
        let id = UUID()
        documentID = id
        Task { @MainActor [weak self] in
            guard let self else { return }
            let time = try? await self.webView.evaluateJavaScript("document.querySelector('video')?.currentTime ?? null") as? Double
            guard self.documentID == id else { return }
            self.playbackMode = mode
            if let link = self.currentLink { self.load(link, at: time) }
        }
    }

    func showLogin() {
        webView.pauseAllMediaPlayback(completionHandler: nil)
        accountWindow.show()
    }

    func stop() {
        documentID = UUID()
        accountWindow.close()
        currentLink = nil
        activeNavigation = nil
        loading = false
        failure = nil
        webView.stopLoading()
        webView.pauseAllMediaPlayback(completionHandler: nil)
        // Replacing the document releases the remote media and stops its audio.
        webView.loadHTMLString("<html><body style='background:#000'></body></html>", baseURL: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard currentLink != nil, navigation === activeNavigation else { return }
        loading = false
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        fail(navigation, error: error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        fail(navigation, error: error)
    }

    private func fail(_ navigation: WKNavigation?, error: Error) {
        guard currentLink != nil, navigation === activeNavigation,
              (error as NSError).code != NSURLErrorCancelled else { return }
        loading = false
        failure = "B 站播放器加载失败：\(error.localizedDescription)"
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard currentLink != nil else { return }
        loading = false
        failure = "网页播放器已停止，请点击重新加载。"
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if navigationAction.targetFrame?.isMainFrame == false { decisionHandler(.allow); return }
        if url.scheme == "about" || (url.scheme == "https" && url.host == "player.bilibili.com") ||
            (playbackMode == .website && BilibiliWebPolicy.isVideoPage(url) && navigationAction.navigationType != .linkActivated) {
            decisionHandler(.allow)
        } else {
            decisionHandler(.cancel)
            if BilibiliWebPolicy.isOfficialPage(url) {
                webView.pauseAllMediaPlayback(completionHandler: nil)
                accountWindow.show(url: url)
            } else if navigationAction.navigationType == .linkActivated, ["https", "http"].contains(url.scheme ?? "") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, BilibiliWebPolicy.isOfficialPage(url) {
            webView.pauseAllMediaPlayback(completionHandler: nil)
            accountWindow.show(url: url)
        } else if navigationAction.navigationType == .linkActivated,
           let url = navigationAction.request.url, ["https", "http"].contains(url.scheme ?? "") {
            NSWorkspace.shared.open(url)
        }
        return nil
    }

    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        // Camera tracking belongs to the native app; remote pages receive no camera or microphone access.
        decisionHandler(.deny)
    }
}

final class WebPlayerContainer: NativeCanvasView {
    private weak var hostedWebView: WKWebView?
    private var active = false
    func configure(_ webView: WKWebView, active: Bool) {
        self.active = active
        hostedWebView = webView
        guard active, window != nil else { return }
        attachIfNeeded()
    }
    private func attachIfNeeded() {
        guard active, window != nil, let webView = hostedWebView else { return }
        if webView.superview !== self {
            webView.removeFromSuperview()
            webView.translatesAutoresizingMaskIntoConstraints = true
            webView.autoresizingMask = [.width, .height]
            addSubview(webView)
        }
        if webView.frame != bounds { webView.frame = bounds }
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { attachIfNeeded() }
        else if let hostedWebView, hostedWebView.superview === self { hostedWebView.removeFromSuperview() }
    }
    override func layout() {
        super.layout()
        if let hostedWebView, hostedWebView.superview === self, hostedWebView.frame != bounds { hostedWebView.frame = bounds }
    }
}

struct BilibiliSurface: NSViewRepresentable {
    let controller: WebPlayerController
    var active = true
    func makeNSView(context: Context) -> WebPlayerContainer {
        let view = WebPlayerContainer()
        view.configure(controller.webView, active: active)
        return view
    }
    func updateNSView(_ view: WebPlayerContainer, context: Context) { view.configure(controller.webView, active: active) }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: WebPlayerContainer, context: Context) -> CGSize? {
        NativeSurfaceLayout.size(for: proposal, fallback: CGSize(width: 960, height: 540))
    }
}

struct WebPlayerStatus: View {
    @ObservedObject var controller: WebPlayerController
    var body: some View {
        if controller.loading {
            ProgressView("正在连接 B 站播放器…").padding(18)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
        } else if let failure = controller.failure {
            VStack(spacing: 13) {
                Image(systemName: "wifi.exclamationmark").font(.title2)
                Text(failure).font(.system(size: 12)).multilineTextAlignment(.center)
                Button("重新加载", action: controller.reload).buttonStyle(.bordered)
            }.padding(24).frame(maxWidth: 350)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

struct BilibiliPlaybackBar: View {
    @ObservedObject var controller: WebPlayerController
    let openOriginal: () -> Void
    let fullscreen: () -> Void
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "play.rectangle.on.rectangle").foregroundStyle(Theme.mint)
            VStack(alignment: .leading, spacing: 5) {
                Text(controller.playbackMode == .website ? "主站播放器 · 登录后在画面内选择清晰度" : "外链播放器 · 高清建议切换主站播放").font(.system(size: 11))
                Text(controller.loading ? "正在加载网页" : controller.failure != nil ? "连接失败，可重新加载" : "可用清晰度取决于视频、账号及平台权限")
                    .font(.system(size: 9)).foregroundStyle(Theme.secondary)
            }
            Spacer()
            Picker("B站播放方式", selection: Binding(get: { controller.playbackMode }, set: controller.setPlaybackMode)) {
                ForEach(BilibiliPlaybackMode.allCases) { mode in Text(mode.title).tag(mode) }
            }.labelsHidden().frame(width: 106).accessibilityIdentifier("bilibiliPlaybackMode")
            Button(action: controller.showLogin) { Label("登录 B 站", systemImage: "person.crop.circle") }
                .accessibilityIdentifier("bilibiliLogin").help("在随视内登录 B 站，与播放器共享登录状态")
            Button(action: controller.reload) { Image(systemName: "arrow.clockwise") }.help("重新加载 B 站播放器").accessibilityLabel("重新加载B站播放器")
            Button(action: openOriginal) { Image(systemName: "safari") }.help("在浏览器打开原视频").accessibilityLabel("在浏览器打开原视频")
            Button(action: fullscreen) { Image(systemName: "arrow.up.left.and.arrow.down.right") }.help("随视全屏，保留旋转效果").accessibilityLabel("全屏")
        }.buttonStyle(.plain).padding(.vertical, 8)
    }
}
