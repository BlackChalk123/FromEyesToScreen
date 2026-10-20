import AppKit
import WebKit
import Combine
import MediaCore

private final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var owner: BilibiliPage?
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        owner?.receive(message)
    }
}

/// Each page has one owner and one permanent native container; no WebView reparenting between modes.
@MainActor final class BilibiliPage: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    enum Role { case browse, playback }
    let webView: WKWebView
    let role: Role
    @Published private(set) var loading = false
    @Published private(set) var failure: String?
    @Published private(set) var title = "哔哩哔哩"
    @Published private(set) var seconds = 0.0
    @Published private(set) var paused = true
    @Published private(set) var aspect = 16.0 / 9
    @Published private(set) var ready = false
    private(set) var needsAuthRefresh = false
    private(set) var link: BilibiliVideoLink?
    private(set) var loadCount = 0
    var onSelect: ((BilibiliVideoLink) -> Void)?
    var onBrowse: ((URL) -> Void)?
    var onProgress: (() -> Void)?
    var onAccountInteraction: (() -> Void)?
    var onUnsupported: (() -> Void)?
    /// Optional transport injection for offline integration tests; production uses WebKit directly.
    var requestLoader: ((WKWebView, URLRequest) -> Void)?
    private var active = true
    private var watchdog: Task<Void, Never>?
    private var urlObservation: NSKeyValueObservation?
    private let testing: Bool
    private var acceptsMessages = true

    init(role: Role, store: WKWebsiteDataStore, testing: Bool = false) {
        self.role = role; self.testing = testing
        let config = WKWebViewConfiguration()
        config.websiteDataStore = store
        config.preferences.isElementFullscreenEnabled = false
        config.mediaTypesRequiringUserActionForPlayback = .all
        let os = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        config.applicationNameForUserAgent = "Version/\(max(17, os >= 26 ? os : os + 3)).0 Safari/605.1.15"
        let handler = WeakScriptHandler()
        config.userContentController.add(handler, name: "suishi")
        config.userContentController.addUserScript(WKUserScript(source: role == .browse ? BilibiliScripts.browser : BilibiliScripts.player,
            injectionTime: role == .browse ? .atDocumentStart : .atDocumentEnd, forMainFrameOnly: true))
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 960, height: 540), configuration: config)
        super.init()
        handler.owner = self
        webView.navigationDelegate = self; webView.uiDelegate = self
        webView.underPageBackgroundColor = role == .playback ? .black : .white
        webView.allowsBackForwardNavigationGestures = role == .browse
        urlObservation = webView.observe(\.url, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self, self.role == .browse, let url = self.webView.url,
                      let link = BilibiliRoute.video(at: url) else { return }
                self.webView.pauseAllMediaPlayback(completionHandler: nil)
                self.onSelect?(link)
            }
        }
    }

    func browse(_ url: URL = BilibiliWebPolicy.accountURL) {
        guard role == .browse, BilibiliRoute.allowsBrowsing(url) else { return }
        if let video = BilibiliRoute.video(at: url) { onSelect?(video); return }
        loading = true; failure = nil
        load(URLRequest(url: url, timeoutInterval: 30))
    }
    func startBrowsingIfNeeded() { if role == .browse && webView.url == nil { browse() } }

    func open(_ video: BilibiliVideoLink, at position: Double? = nil) {
        guard role == .playback else { return }
        watchdog?.cancel()
        needsAuthRefresh = false
        link = video; seconds = position ?? video.startTime; title = video.title
        loading = true; failure = nil; ready = false; paused = true; acceptsMessages = false
        var parts = URLComponents(url: video.pageURL, resolvingAgainstBaseURL: false)!
        if let position, position.isFinite, position >= 0 {
            parts.queryItems = (parts.queryItems ?? []).filter { $0.name != "t" } + [URLQueryItem(name: "t", value: String(position))]
        }
        loadCount += 1
        load(URLRequest(url: parts.url!, timeoutInterval: 30))
        startWatchdog()
    }

    private func load(_ request: URLRequest) {
        if let requestLoader { requestLoader(webView, request) }
        else { webView.load(request) }
    }
    func markAuthRefreshNeeded() { needsAuthRefresh = true }

    private func startWatchdog() {
        watchdog?.cancel()
        watchdog = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 30_000_000_000) } catch { return }
            guard let self, !self.ready else { return }
            self.loading = false
            self.failure = "未能找到可用的 B 站播放器。可以重试，或返回官网检查登录与视频状态。"
        }
    }

    func reload() {
        if role == .playback, let link { open(link, at: seconds) }
        else { loading = true; failure = nil; webView.reload() }
    }

    func setActive(_ value: Bool) {
        active = value
        webView.evaluateJavaScript("window.__suishiActive = \(value ? "true" : "false"); void 0", completionHandler: nil)
        if !value { webView.pauseAllMediaPlayback(completionHandler: nil); paused = true }
    }

    func togglePlayback() {
        guard role == .playback, active else { return }
        webView.evaluateJavaScript("(() => { const v = document.querySelector('.bpx-player-container video'); if(v) { if(v.paused) v.play().catch(()=>{}); else v.pause(); } })()", completionHandler: nil)
    }

    func capturePosition() async {
        let identity = link.map(BilibiliRoute.key)
        let value = try? await webView.evaluateJavaScript("document.querySelector('.bpx-player-container video')?.currentTime ?? null")
        if identity == link.map(BilibiliRoute.key), let value = value as? Double, value.isFinite, value >= 0 { seconds = value }
    }

    func receive(_ message: WKScriptMessage) {
        let origin = message.frameInfo.securityOrigin
        let officialOrigin = origin.protocol == "https" && (origin.port == 0 || origin.port == 443) &&
            (origin.host == "bilibili.com" || origin.host.hasSuffix(".bilibili.com"))
        guard message.frameInfo.isMainFrame, testing || officialOrigin,
              let data = message.body as? [String: Any] else { return }
        if role == .browse && data["kind"] as? String == "account" { onAccountInteraction?(); return }
        if role == .playback && data["kind"] as? String == "login" {
            needsAuthRefresh = true; setActive(false); onBrowse?(BilibiliWebPolicy.accountURL); return
        }
        guard let urlString = data["url"] as? String,
              let url = URL(string: urlString),
              let video = BilibiliRoute.video(at: url) ?? (testing && role == .playback ? link : nil) else { return }
        if role == .browse, data["kind"] as? String == "route" {
            webView.pauseAllMediaPlayback(completionHandler: nil)
            onSelect?(video)
        } else if role == .playback, data["kind"] as? String == "state" {
            guard acceptsMessages, testing || webView.url.flatMap(BilibiliRoute.video).map(BilibiliRoute.key) == BilibiliRoute.key(video) else { return }
            link = video
            if let text = data["title"] as? String, !text.isEmpty {
                let value = String(text.replacingOccurrences(of: "_哔哩哔哩_bilibili", with: "").prefix(240))
                if value != title { title = value }
            }
            let wasPaused = paused
            let isPaused = data["paused"] as? Bool ?? true
            if paused != isPaused { paused = isPaused }
            if let value = data["time"] as? Double, value.isFinite, value >= 0, value != seconds { seconds = value }
            if let value = data["aspect"] as? Double, value.isFinite, (0.2...5).contains(value), abs(value - aspect) > 0.001 { aspect = value }
            if data["ready"] as? Bool == true {
                if !ready { ready = true; watchdog?.cancel() }
                if loading { loading = false }
                if failure != nil { failure = nil }
            }
            if !active { webView.pauseAllMediaPlayback(completionHandler: nil) }
            if paused || wasPaused { onProgress?() }
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        if action.targetFrame?.isMainFrame == false { decisionHandler(.allow); return }
        if url.scheme == "about" || (testing && url.isFileURL) { decisionHandler(.allow); return }
        if BilibiliRoute.isUnsupportedPlayback(url) { decisionHandler(.cancel); onUnsupported?(); return }
        if let video = BilibiliRoute.video(at: url) {
            if role == .browse { decisionHandler(.cancel); onSelect?(video) }
            else { decisionHandler(.allow) }
        } else if BilibiliRoute.allowsBrowsing(url) {
            if role == .browse { decisionHandler(.allow) }
            else { decisionHandler(.cancel); setActive(false); onBrowse?(url) }
        } else {
            decisionHandler(.cancel)
            if action.navigationType == .linkActivated, ["https", "http"].contains(url.scheme ?? "") { NSWorkspace.shared.open(url) }
        }
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard let url = action.request.url else { return nil }
        if BilibiliRoute.isUnsupportedPlayback(url) { onUnsupported?(); return nil }
        if let video = BilibiliRoute.video(at: url) { onSelect?(video) }
        else if BilibiliRoute.allowsBrowsing(url) {
            if role == .browse { browse(url) } else { setActive(false); onBrowse?(url) }
        } else if ["http", "https"].contains(url.scheme ?? "") { NSWorkspace.shared.open(url) }
        return nil
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if role == .browse { loading = false }
        if !active { setActive(false) }
    }
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { acceptsMessages = true }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        loading = true; failure = nil
        if role == .playback { ready = false; startWatchdog() }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { fail(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { fail(error) }
    private func fail(_ error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        watchdog?.cancel(); loading = false; failure = "页面加载失败：\(error.localizedDescription)"
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        watchdog?.cancel(); loading = false; ready = false
        failure = "网页暂时停止运行，请重新加载。"
    }
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) { decisionHandler(.deny) }
}

@MainActor final class BilibiliSession {
    let browser: BilibiliPage
    let player: BilibiliPage
    convenience init() { self.init(store: .default()) }
    init(store: WKWebsiteDataStore, testing: Bool = false) {
        browser = BilibiliPage(role: .browse, store: store, testing: testing)
        player = BilibiliPage(role: .playback, store: store, testing: testing)
    }
}
