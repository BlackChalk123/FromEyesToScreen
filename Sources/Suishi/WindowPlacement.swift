import Foundation
import CoreGraphics

/// Window coordinates may be negative or vertically stacked on a multi-display desktop.
enum WindowPlacement {
    static func recovered(_ frame: CGRect, in areas: [CGRect]) -> CGRect {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        func distance(to area: CGRect) -> CGFloat {
            let dx = max(0, max(area.minX - center.x, center.x - area.maxX))
            let dy = max(0, max(area.minY - center.y, center.y - area.maxY))
            return dx * dx + dy * dy
        }
        guard let area = areas.min(by: { distance(to: $0) < distance(to: $1) }) else { return frame }
        return clamped(frame, to: area)
    }
    static func clamped(_ frame: CGRect, to area: CGRect) -> CGRect {
        let width = min(frame.width, area.width), height = min(frame.height, area.height)
        return CGRect(x: min(area.maxX - width, max(area.minX, frame.minX)),
                      y: min(area.maxY - height, max(area.minY, frame.minY)), width: width, height: height)
    }
}
