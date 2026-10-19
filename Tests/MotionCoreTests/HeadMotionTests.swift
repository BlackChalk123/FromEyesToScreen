import Foundation
import CoreGraphics

func check(_ condition: Bool, _ message: String = "Check failed", file: StaticString = #file, line: UInt = #line) {
    guard condition else { fatalError(message, file: file, line: line) }
}
func expectEqual(_ a: Double, _ b: Double, accuracy: Double = 0, file: StaticString = #file, line: UInt = #line) {
    check(abs(a - b) <= accuracy, "Expected \(a) == \(b) ± \(accuracy)", file: file, line: line)
}
func expectEqual(_ a: CGSize, _ b: CGSize) { check(a == b) }
func expectAtMost(_ a: Double, _ b: Double) { check(a <= b) }
func expectAtLeast(_ a: Double, _ b: Double) { check(a >= b) }
func expectLess(_ a: Double, _ b: Double) { check(a < b) }
func expectGreater(_ a: Double, _ b: Double, _ message: String) { check(a > b, message) }

@main
struct HeadMotionTests {
    static func main() {
        let tests = HeadMotionTests()
        tests.testEyeAngleAccountsForImageAspectAndEyeOrder()
        tests.testAllRotatedCornersFitForWideAndPortraitVideos()
        tests.testSmoothingConvergesWithoutOvershootAndClamps()
        tests.testMissingFaceHoldsAngleThenResumesSmoothly()
        tests.testCalibrationAndReverse()
        tests.testSmallJitterAndInvalidInputsAreIgnored()
        tests.testManualModeTransitionPreservesDisplayedAngle()
        print("PASS: 7 motion checks, including 724 rotated video layouts.")
    }

    func testEyeAngleAccountsForImageAspectAndEyeOrder() {
        let first = CGPoint(x: 0.2, y: 0.3), second = CGPoint(x: 0.7, y: 0.8)
        let expected = atan2(480.0, 640.0) * 180 / .pi
        expectEqual(MotionGeometry.eyeAngle(first: first, second: second,
            imageSize: CGSize(width: 640, height: 480)), expected, accuracy: 0.0001)
        expectEqual(MotionGeometry.eyeAngle(first: second, second: first,
            imageSize: CGSize(width: 640, height: 480)), expected, accuracy: 0.0001)
    }

    func testAllRotatedCornersFitForWideAndPortraitVideos() {
        let container = CGSize(width: 730, height: 420)
        for aspect in [16.0 / 9, 9.0 / 16, 1, 2.4] {
            for angle in stride(from: -45.0, through: 45.0, by: 0.5) {
                let size = MotionGeometry.fittedSize(aspect: aspect, angle: angle, container: container)
                let r = angle * .pi / 180, c = abs(cos(r)), s = abs(sin(r))
                expectAtMost(size.width * c + size.height * s, container.width + 0.0001)
                expectAtMost(size.width * s + size.height * c, container.height + 0.0001)
                expectEqual(size.width / size.height, aspect, accuracy: 0.0001)
            }
        }
    }

    func testSmoothingConvergesWithoutOvershootAndClamps() {
        var filter = HeadMotionFilter()
        var previous = 0.0
        for _ in 0..<200 {
            let current = filter.update(rawAngle: 85, deltaTime: 1.0 / 24)
            expectAtLeast(current, previous)
            expectAtMost(current, 45)
            previous = current
        }
        expectEqual(filter.angle, 45, accuracy: 0.02)
    }

    func testMissingFaceHoldsAngleThenResumesSmoothly() {
        var filter = HeadMotionFilter()
        for _ in 0..<40 { filter.update(rawAngle: 30, deltaTime: 1.0 / 24) }
        let held = filter.angle
        for _ in 0..<120 { expectEqual(filter.update(rawAngle: nil, deltaTime: 1.0 / 24), held) }
        let resumed = filter.update(rawAngle: -30, deltaTime: 8)
        expectLess(resumed, held)
        expectGreater(resumed, 0, "A long gap must not jump straight to the new angle")
    }

    func testCalibrationAndReverse() {
        var filter = HeadMotionFilter()
        filter.calibrate(rawAngle: 17)
        for _ in 0..<100 { filter.update(rawAngle: 17, deltaTime: 1.0 / 24) }
        expectEqual(filter.angle, 0)
        filter.reversed = true
        for _ in 0..<100 { filter.update(rawAngle: 27, deltaTime: 1.0 / 24) }
        expectEqual(filter.angle, -10, accuracy: 0.02)
        filter.reset()
        expectEqual(filter.angle, 0)
        expectEqual(filter.baseline, 0)
    }

    func testManualModeTransitionPreservesDisplayedAngle() {
        var filter = HeadMotionFilter()
        filter.hold(angle: 30)
        expectEqual(filter.update(rawAngle: nil, deltaTime: 1), 30)
        let resumed = filter.update(rawAngle: 0, deltaTime: 1.0 / 24)
        expectGreater(resumed, 20, "Resuming after manual mode must remain smooth")
        expectLess(resumed, 30)
    }

    func testSmallJitterAndInvalidInputsAreIgnored() {
        var filter = HeadMotionFilter()
        for i in 0..<100 { filter.update(rawAngle: i % 2 == 0 ? 0.2 : -0.2, deltaTime: 1.0 / 24) }
        expectEqual(filter.angle, 0)
        expectEqual(filter.update(rawAngle: .nan, deltaTime: 1), 0)
        expectEqual(MotionGeometry.fittedSize(aspect: 0, angle: 0, container: CGSize(width: 100, height: 100)), .zero)
    }
}
