import SwiftUI

/// A viewing surface has metadata and a lifecycle, not necessarily playback controls.
/// Future PDF/web/local-video adapters supply their own surface without changing rotation.
@MainActor protocol ViewingContent: ObservableObject {
    associatedtype Surface: View
    var title: String { get }
    var sourceName: String { get }
    var sourceMark: String { get }
    var statusText: String { get }
    var aspect: Double { get }
    var loading: Bool { get }
    var failure: String? { get }
    func surface(size: CGSize) -> Surface
    func reload()
}

extension BilibiliPage: ViewingContent {
    var sourceName: String { "哔哩哔哩" }
    var sourceMark: String { "b" }
    var statusText: String { paused ? "已暂停" : "播放中" }
    func surface(size: CGSize) -> some View {
        // The fixed website viewport belongs to this adapter, not to the rotating container.
        WebSurface(webView: webView).frame(width: 960, height: 960 / aspect)
            .scaleEffect(size.width / 960).frame(width: size.width, height: size.height).clipped()
    }
}
