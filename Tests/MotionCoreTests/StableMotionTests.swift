import Foundation
import CoreGraphics

@main
struct StableMotionTests {
    static let dt = 1.0 / 24
    static func lockedFilter(at value: Double = 20) -> HeadMotionFilter {
        var filter = HeadMotionFilter()
        filter.lockingEnabled = true
        for _ in 0..<120 { filter.update(rawAngle: value, deltaTime: dt) }
        precondition(filter.isLocked)
        return filter
    }

    static func main() {
        var filter = lockedFilter()
        let frozen = filter.angle
        for index in 0..<150 {
            filter.update(rawAngle: index % 2 == 0 ? 19.3 : 20.7, deltaTime: dt)
            precondition(filter.isLocked && filter.angle == frozen, "Comfortable posture must remain completely still")
        }
        filter.update(rawAngle: 55, deltaTime: dt)
        for _ in 0..<24 { filter.update(rawAngle: 20, deltaTime: dt) }
        precondition(filter.isLocked && filter.angle == frozen, "One outlier must not unlock")
        filter.update(rawAngle: -90, deltaTime: dt)
        for _ in 0..<48 { filter.update(rawAngle: 20, deltaTime: dt) }
        precondition(filter.isLocked && filter.angle == frozen, "Even a large single-frame outlier must not unlock")
        for _ in 0..<24 { filter.update(rawAngle: 35, deltaTime: dt) }
        precondition(!filter.isLocked && filter.angle > frozen, "An intentional change must resume following")

        filter = HeadMotionFilter()
        filter.lockingEnabled = true
        for _ in 0..<48 { filter.update(rawAngle: 20, deltaTime: dt) }
        precondition(!filter.isLocked && filter.stabilityProgress > 0)
        filter.update(rawAngle: nil, deltaTime: 3)
        precondition(filter.stabilityProgress == 0)
        filter.update(rawAngle: 20, deltaTime: 10)
        for _ in 0..<48 { filter.update(rawAngle: 20, deltaTime: dt) }
        precondition(!filter.isLocked, "Lost-camera time must not count toward four seconds")

        filter = HeadMotionFilter()
        filter.lockingEnabled = true
        for index in 0..<240 {
            filter.update(rawAngle: Double(index) * dt * 0.9, deltaTime: dt)
            precondition(!filter.isLocked, "Gradual motion must not be mistaken for a stable pose")
        }

        filter = lockedFilter(at: 70)
        for _ in 0..<24 { filter.update(rawAngle: 85, deltaTime: dt) }
        precondition(!filter.isLocked, "Release must use head measurements before output clamping")
        precondition(filter.angle <= 45)
        filter = lockedFilter()
        filter.calibrate(rawAngle: 20)
        precondition(!filter.isLocked && filter.stabilityProgress == 0)
        filter = lockedFilter()
        filter.lockingEnabled = false
        filter.update(rawAngle: 20, deltaTime: dt)
        precondition(!filter.isLocked)

        for rate in [24.0, 60.0] {
            filter = HeadMotionFilter()
            filter.lockingEnabled = true
            filter.lockDuration = 2
            for _ in 0..<Int(rate * 1.8) { filter.update(rawAngle: 10, deltaTime: 1 / rate) }
            precondition(!filter.isLocked)
            for _ in 0..<Int(rate * 0.4) { filter.update(rawAngle: 10, deltaTime: 1 / rate) }
            precondition(filter.isLocked)
        }

        var layouts = 0
        for container in [CGSize(width: 730, height: 420), CGSize(width: 200, height: 1000)] {
            for aspect in [16.0 / 9, 9.0 / 16, 1, 2.4] {
                for limit in [15.0, 30, 45, 90] {
                    let size = MotionGeometry.constantSize(aspect: aspect, maximumAngle: limit, container: container)
                    precondition(abs(size.width / size.height - aspect) < 0.00001)
                    for angle in stride(from: -limit, through: limit, by: 0.25) {
                        let r = angle * .pi / 180, c = abs(cos(r)), s = abs(sin(r))
                        precondition(size.width * c + size.height * s <= container.width + 0.00001)
                        precondition(size.width * s + size.height * c <= container.height + 0.00001)
                        layouts += 1
                    }
                }
            }
        }
        print("PASS: stable-pose lock, jitter, release, dropouts, drift, clamping, calibration, configurable timer and \(layouts) constant-size layouts.")
    }
}
