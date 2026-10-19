import SwiftUI
import WebKit
import MediaCore

@MainActor
final class BilibiliAccountWindow: NSObject, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate {
    private let dataStore: WKWebsiteDataStore
    private var window: NSWindow?
    private var webView: WKWebView?
    var onFinish: (() -> Void)?

    init(dataStore: WKWebsiteDataStore) { self.dataStore = dataStore }

    func show(url: URL = BilibiliWebPolicy.accountURL) {
        guard BilibiliWebPolicy.isOfficialPage(url) else { return }
        if let window { window.makeKeyAndOrderFront(nil); return }
        let configuration = BilibiliWebConfiguration.make(dataStore: dataStore)
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        self.webView = webView
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 800),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "随视 · 登录哔哩哔哩"
        window.minSize = NSSize(width: 900, height: 650)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: BilibiliAccountView(webView: webView) { [weak self] in
            self?.close()
            self?.onFinish?()
        })
        self.window = window
        window.center()
        window.makeKeyAndOrderFront(nil)
        webView.load(URLRequest(url: url))
    }

    func close() {
        webView?.stopLoading()
        webView?.pauseAllMediaPlayback(completionHandler: nil)
        webView?.navigationDelegate = nil
        webView?.uiDelegate = nil
        window?.orderOut(nil)
        window?.contentView = nil
        window = nil
        webView = nil
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { close(); return false }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if navigationAction.targetFrame?.isMainFrame == false || url.scheme == "about" || BilibiliWebPolicy.isOfficialPage(url) {
            decisionHandler(.allow)
        } else {
            decisionHandler(.cancel)
            if navigationAction.navigationType == .linkActivated, ["https", "http"].contains(url.scheme ?? "") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, BilibiliWebPolicy.isOfficialPage(url) { webView.load(URLRequest(url: url)) }
        else if navigationAction.navigationType == .linkActivated,
                let url = navigationAction.request.url, ["https", "http"].contains(url.scheme ?? "") { NSWorkspace.shared.open(url) }
        return nil
    }

    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) { decisionHandler(.deny) }
}

private struct AccountWebSurface: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WebPlayerContainer {
        let view = WebPlayerContainer(); view.configure(webView, active: true); return view
    }
    func updateNSView(_ view: WebPlayerContainer, context: Context) { view.configure(webView, active: true) }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: WebPlayerContainer, context: Context) -> CGSize? {
        NativeSurfaceLayout.size(for: proposal)
    }
}

private struct BilibiliAccountView: View {
    let webView: WKWebView
    let finish: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("在下方 B 站官网点击「登录」，自行扫码或输入账号。")
                    Text("官网：www.bilibili.com · 此窗口与随视播放器共享登录状态；Safari / Chrome 的登录不会自动同步。")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }.font(.system(size: 12))
                Spacer()
                Button("完成并刷新播放", action: finish).accessibilityIdentifier("finishBilibiliLogin")
            }.padding(16)
            Divider()
            AccountWebSurface(webView: webView).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
