import SwiftUI
import AppKit

/// Media canvases have explicit SwiftUI frames and manually positioned native children.
/// They must never ask AppKit's constraint solver to infer an intrinsic size.
class NativeCanvasView: NSView {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
    override var fittingSize: NSSize { .zero }
}

enum NativeSurfaceLayout {
    static func size(for proposal: ProposedViewSize, fallback: CGSize = .zero) -> CGSize {
        func dimension(_ value: CGFloat?, fallback: CGFloat) -> CGFloat {
            guard let value, value.isFinite else { return fallback }
            return max(0, value)
        }
        return CGSize(width: dimension(proposal.width, fallback: fallback.width),
                      height: dimension(proposal.height, fallback: fallback.height))
    }
}
