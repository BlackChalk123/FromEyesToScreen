import AppKit
import SwiftUI
import WebKit

/// Explicit sizing avoids the AppKit fitting-size assertion encountered in the demo.
final class WebCanvas: NSView {
    private weak var webView: WKWebView?
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric) }
    override var fittingSize: NSSize { .zero }
    func attach(_ webView: WKWebView) {
        self.webView = webView
        if webView.superview !== self {
            webView.removeFromSuperview()
            webView.translatesAutoresizingMaskIntoConstraints = true
            webView.autoresizingMask = [.width, .height]
            addSubview(webView)
        }
        if webView.frame != bounds { webView.frame = bounds }
    }
    override func layout() {
        super.layout()
        if let webView, webView.superview === self, webView.frame != bounds { webView.frame = bounds }
    }
}

struct WebSurface: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WebCanvas { let view = WebCanvas(); view.attach(webView); return view }
    func updateNSView(_ nsView: WebCanvas, context: Context) { nsView.attach(webView) }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: WebCanvas, context: Context) -> CGSize? {
        CGSize(width: proposal.width.map { $0.isFinite ? max(0, $0) : 960 } ?? 960,
               height: proposal.height.map { $0.isFinite ? max(0, $0) : 540 } ?? 540)
    }
}

struct BrowserWindowReader: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void
    final class Reader: NSView {
        var onWindow: ((NSWindow) -> Void)?
        override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric) }
        override var fittingSize: NSSize { .zero }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); if let window { onWindow?(window) } }
    }
    func makeNSView(context: Context) -> Reader { let view = Reader(); view.onWindow = onWindow; return view }
    func updateNSView(_ nsView: Reader, context: Context) {}
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: Reader, context: Context) -> CGSize? { .zero }
}
