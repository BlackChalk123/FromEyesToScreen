import Foundation
import CoreGraphics

/// Fixed media size while rotating. Geometry constrains the engine, never applies another angle transform.
public struct ViewingLayout {
    public let size: CGSize
    public let center: CGPoint
    public let travel: CGSize
    public let safeAngle: Double

    public init(viewport: CGSize, aspect: Double = 16.0 / 9, scale: Double,
                position: CGPoint = .zero, crop: Bool = false) {
        let width = viewport.width.isFinite ? max(0, viewport.width) : 0
        let height = viewport.height.isFinite ? max(0, viewport.height) : 0
        let ratio = aspect.isFinite && aspect > 0 ? aspect : 16.0 / 9
        let factor = scale.isFinite ? min(1, max(0.35, scale)) : 0.6
        // Complete = aspect fit. Crop = aspect fill, so 100% covers the display
        // even when the source and monitor have different aspect ratios.
        let h = (crop ? max(height, width / ratio) : min(height, width / ratio)) * factor
        size = CGSize(width: h * ratio, height: h)
        travel = CGSize(width: max(0, (width - size.width) / 2), height: max(0, (height - size.height) / 2))
        center = CGPoint(x: width / 2 + Self.unit(position.x) * travel.width,
                         y: height / 2 + Self.unit(position.y) * travel.height)
        let available = CGSize(width: 2 * max(0, min(center.x, width - center.x)),
                               height: 2 * max(0, min(center.y, height - center.y)))
        if crop { safeAngle = 75; return }
        let media = size
        func fits(_ angle: Double) -> Bool {
            let box = Self.envelope(media, angle: angle)
            return box.width <= available.width + 1e-7 && box.height <= available.height + 1e-7
        }
        if fits(75) { safeAngle = 75 }
        else {
            var low = 0.0, high = 75.0
            for _ in 0..<40 {
                let mid = (low + high) / 2
                if fits(mid) { low = mid } else { high = mid }
            }
            safeAngle = low < 0.001 ? 0 : low
        }
    }

    public func moved(from position: CGPoint, translation: CGSize) -> CGPoint {
        CGPoint(x: travel.width > 0.5 ? Self.unit(position.x + translation.width / travel.width) : 0,
                y: travel.height > 0.5 ? Self.unit(position.y + translation.height / travel.height) : 0)
    }

    public static func envelope(_ size: CGSize, angle: Double) -> CGSize {
        let limit = min(90, abs(angle)) * .pi / 180
        let x = min(limit, atan2(size.height, size.width)), y = min(limit, atan2(size.width, size.height))
        return CGSize(width: size.width * cos(x) + size.height * sin(x),
                      height: size.width * sin(y) + size.height * cos(y))
    }
    private static func unit(_ value: CGFloat) -> CGFloat { value.isFinite ? min(1, max(-1, value)) : 0 }
}
