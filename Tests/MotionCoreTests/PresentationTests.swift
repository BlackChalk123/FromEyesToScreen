import Foundation
import CoreGraphics

@main
struct PresentationTests {
    static func main() {
        var count = 0
        for viewport in [CGSize(width: 1512, height: 982), CGSize(width: 1920, height: 1080), CGSize(width: 1024, height: 1366)] {
            for aspect in [9.0 / 16, 1, 16.0 / 9, 2.4] {
                for limit in [15.0, 30, 45] {
                    for scale in [0.25, 0.4, 0.6, 0.8, 1] {
                        for position in [CGPoint.zero, CGPoint(x: -1, y: -1), CGPoint(x: 1, y: 1), CGPoint(x: 0.4, y: -0.3)] {
                            let layout = PresentationLayout(viewport: viewport, aspect: aspect,
                                maximumAngle: limit, scale: scale, position: position, allowsCropping: false)
                            precondition(layout.safeAngle <= limit)
                            for requested in stride(from: -limit, through: limit, by: 1) {
                                let angle = layout.angle(requested)
                                let radians = angle * .pi / 180
                                let width = layout.videoSize.width * abs(cos(radians)) + layout.videoSize.height * abs(sin(radians))
                                let height = layout.videoSize.width * abs(sin(radians)) + layout.videoSize.height * abs(cos(radians))
                                precondition(layout.center.x - width / 2 >= -1e-6)
                                precondition(layout.center.x + width / 2 <= viewport.width + 1e-6)
                                precondition(layout.center.y - height / 2 >= -1e-6)
                                precondition(layout.center.y + height / 2 <= viewport.height + 1e-6)
                                count += 1
                            }
                            let crop = PresentationLayout(viewport: viewport, aspect: aspect,
                                maximumAngle: limit, scale: scale, position: position, allowsCropping: true)
                            precondition(crop.videoSize == layout.videoSize && crop.safeAngle == limit)
                            let moved = layout.moved(from: .zero, translation: CGSize(width: 100000, height: -100000))
                            precondition((0...1).contains(moved.x) && (-1...0).contains(moved.y))
                        }
                    }
                }
            }
        }
        let viewport = CGSize(width: 1920, height: 1080)
        func layout(_ scale: Double, crop: Bool = false) -> PresentationLayout {
            PresentationLayout(viewport: viewport, aspect: 16.0 / 9, maximumAngle: 45,
                               scale: scale, position: .zero, allowsCropping: crop)
        }
        precondition(layout(1).safeAngle == 0)
        precondition(layout(0.8).safeAngle > 0 && layout(0.8).safeAngle < layout(0.4).safeAngle)
        precondition(layout(1, crop: true).safeAngle == 45)
        precondition(layout(1.5, crop: true).videoSize.width == 2880)
        let initial = layout(0.6)
        let moved = initial.moved(from: .zero, translation: CGSize(width: 100, height: 75))
        let result = PresentationLayout(viewport: viewport, aspect: 16.0 / 9, maximumAngle: 45,
                                       scale: 0.6, position: moved, allowsCropping: false)
        precondition(abs(result.center.x - initial.center.x - 100) < 1e-6)
        precondition(abs(result.center.y - initial.center.y - 75) < 1e-6)

        var filter = HeadMotionFilter()
        filter.responseTime = 0.1; filter.maximumSpeed = 10
        var previous = 0.0
        for _ in 0..<120 {
            let angle = filter.update(rawAngle: 45, deltaTime: 1.0 / 24)
            precondition(abs(angle - previous) <= 10.0 / 24 + 1e-9)
            previous = angle
        }
        filter = HeadMotionFilter(); filter.gain = 0.5
        for _ in 0..<240 { filter.update(rawAngle: 20, deltaTime: 1.0 / 24) }
        precondition(abs(filter.angle - 10) < 0.02)
        filter.lockingEnabled = true
        for _ in 0..<150 { filter.update(rawAngle: 20, deltaTime: 1.0 / 24) }
        precondition(filter.isLocked)
        for _ in 0..<48 { filter.update(rawAngle: 27, deltaTime: 1.0 / 24) }
        precondition(!filter.isLocked, "Unlock must use actual head movement, independent of follow gain")
        print("PASS: Fullscreen geometry (\(count) placements), size/angle tradeoff, cropping, drag, speed limit and follow gain.")
    }
}
