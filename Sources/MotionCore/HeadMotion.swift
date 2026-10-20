import Foundation
import CoreGraphics

public enum MotionGeometry {
    /// Vision eye coordinates use a bottom-left origin in an unmirrored image.
    /// Its positive slope becomes a clockwise rotation in the mirrored viewer.
    public static func eyeAngle(first: CGPoint, second: CGPoint, imageSize: CGSize) -> Double {
        let a = first.x <= second.x ? first : second
        let b = first.x <= second.x ? second : first
        return atan2((b.y - a.y) * imageSize.height,
                     (b.x - a.x) * imageSize.width) * 180 / .pi
    }

    public static func fittedSize(aspect: Double, angle: Double, container: CGSize) -> CGSize {
        guard aspect.isFinite, aspect > 0, angle.isFinite, container.width > 0, container.height > 0 else { return .zero }
        let radians = angle * .pi / 180
        let c = abs(cos(radians)), s = abs(sin(radians))
        let height = min(container.width / (aspect * c + s),
                         container.height / (aspect * s + c))
        return CGSize(width: height * aspect, height: height)
    }

    /// One size fits every angle in the permitted range, including extrema between its endpoints.
    public static func constantSize(aspect: Double, maximumAngle: Double, container: CGSize) -> CGSize {
        guard aspect.isFinite, aspect > 0, maximumAngle.isFinite,
              container.width > 0, container.height > 0 else { return .zero }
        let limit = min(90, abs(maximumAngle)) * .pi / 180
        let xAngle = min(limit, atan(1 / aspect))
        let yAngle = min(limit, atan(aspect))
        let maximumWidth = aspect * cos(xAngle) + sin(xAngle)
        let maximumHeight = aspect * sin(yAngle) + cos(yAngle)
        let height = min(container.width / maximumWidth, container.height / maximumHeight)
        return CGSize(width: height * aspect, height: height)
    }

    /// Bounding box covering every permitted rotation, so moving the video never
    /// makes its position change when the head angle changes.
    public static func rotationEnvelope(size: CGSize, maximumAngle: Double) -> CGSize {
        guard size.width > 0, size.height > 0, size.width.isFinite, size.height.isFinite,
              maximumAngle.isFinite else { return .zero }
        let limit = min(90, abs(maximumAngle)) * .pi / 180
        let x = min(limit, atan(size.height / size.width))
        let y = min(limit, atan(size.width / size.height))
        return CGSize(width: size.width * cos(x) + size.height * sin(x),
                      height: size.width * sin(y) + size.height * cos(y))
    }
}

/// Video size stays fixed; the available angle depends on size and position.
public struct PresentationLayout {
    public let videoSize: CGSize
    public let center: CGPoint
    public let travel: CGSize
    public let safeAngle: Double

    public init(viewport: CGSize, aspect: Double, maximumAngle: Double,
                scale: Double, position: CGPoint, allowsCropping: Bool) {
        let area = CGSize(width: viewport.width.isFinite ? max(0, viewport.width) : 0,
                          height: viewport.height.isFinite ? max(0, viewport.height) : 0)
        let base = MotionGeometry.fittedSize(aspect: aspect, angle: 0, container: area)
        let factor = scale.isFinite ? min(allowsCropping ? 16 : 1, max(0.25, scale)) : 0.8
        videoSize = CGSize(width: base.width * factor, height: base.height * factor)
        travel = CGSize(width: max(0, (area.width - (allowsCropping ? min(80, videoSize.width) : videoSize.width)) / 2),
                        height: max(0, (area.height - (allowsCropping ? min(80, videoSize.height) : videoSize.height)) / 2))
        center = CGPoint(x: area.width / 2 + Self.unit(position.x) * travel.width,
                         y: area.height / 2 + Self.unit(position.y) * travel.height)
        let limit = maximumAngle.isFinite ? min(90, abs(maximumAngle)) : 0
        if allowsCropping { safeAngle = limit }
        else {
            let available = CGSize(width: 2 * max(0, min(center.x, area.width - center.x)),
                                   height: 2 * max(0, min(center.y, area.height - center.y)))
            let fixedSize = videoSize
            func fits(_ angle: Double) -> Bool {
                let envelope = MotionGeometry.rotationEnvelope(size: fixedSize, maximumAngle: angle)
                return envelope.width <= available.width + 1e-8 && envelope.height <= available.height + 1e-8
            }
            if fits(limit) { safeAngle = limit }
            else {
                var low = 0.0, high = limit
                for _ in 0..<48 {
                    let middle = (low + high) / 2
                    if fits(middle) { low = middle } else { high = middle }
                }
                safeAngle = low < 0.001 ? 0 : low
            }
        }
    }

    public func angle(_ requested: Double) -> Double {
        requested.isFinite ? min(safeAngle, max(-safeAngle, requested)) : 0
    }
    public func moved(from position: CGPoint, translation: CGSize) -> CGPoint {
        CGPoint(x: travel.width > 0.5 ? Self.unit(position.x + translation.width / travel.width) : 0,
                y: travel.height > 0.5 ? Self.unit(position.y + translation.height / travel.height) : 0)
    }
    private static func unit(_ value: CGFloat) -> CGFloat { value.isFinite ? min(1, max(-1, value)) : 0 }
}

public struct HeadMotionFilter {
    public private(set) var angle = 0.0
    public private(set) var baseline = 0.0
    private var target = 0.0
    public var responseTime = 0.24
    public var deadband = 0.65
    public var gain = 1.0
    public var maximumSpeed = Double.infinity
    public var reversed = false
    public var limit = 45.0
    public var lockingEnabled = false
    public var lockDuration = 4.0
    public var stabilityTolerance = 1.5
    public var unlockTolerance = 4.0
    public var unlockDuration = 0.25
    public var manualUnlockOnly = false
    public var compensation = AngleCompensation()
    public private(set) var didUnlock = false
    public private(set) var isLocked = false
    public var stabilityProgress: Double { min(1, stableTime / max(0.1, lockDuration)) }
    private var sensorAngle: Double?
    private var candidateAngle: Double?
    private var lockedHeadAngle = 0.0
    private var stableTime = 0.0
    private var unlockTime = 0.0

    public init() {}

    public mutating func calibrate(rawAngle: Double) {
        guard rawAngle.isFinite else { return }
        baseline = rawAngle
        target = 0
        cancelLock()
    }

    /// A missing face holds both the current angle and filter target.
    @discardableResult
    public mutating func update(rawAngle: Double?, deltaTime: Double, confidence: Double = 1) -> Double {
        didUnlock = false
        guard let rawAngle, rawAngle.isFinite, confidence.isFinite, confidence >= 0.7 else {
            candidateAngle = nil
            stableTime = 0
            unlockTime = 0
            sensorAngle = nil
            return angle
        }
        let measured = (rawAngle - baseline) * (reversed ? -1 : 1)
        let validTime = deltaTime.isFinite && deltaTime >= 0
        let dt = validTime ? min(0.1, deltaTime) : 0
        // Never count dropped-camera time toward a lock or release decision.
        let decisionTime = validTime && deltaTime <= 0.25 ? deltaTime : 0
        if decisionTime == 0 { candidateAngle = nil; stableTime = 0; unlockTime = 0 }
        let alpha = 1 - exp(-dt / max(0.01, responseTime))
        sensorAngle = sensorAngle.map { $0 + alpha * (measured - $0) } ?? measured
        let sensed = sensorAngle!
        if !lockingEnabled { cancelLock() }
        if isLocked {
            guard !manualUnlockOnly else { return angle }
            let releaseThreshold = max(stabilityTolerance + 0.5, unlockTolerance)
            if abs(sensed - lockedHeadAngle) > releaseThreshold && abs(measured - lockedHeadAngle) > releaseThreshold {
                unlockTime += decisionTime
            } else { unlockTime = 0 }
            guard unlockTime >= max(0.05, unlockDuration) else { return angle }
            isLocked = false
            didUnlock = true
            unlockTime = 0
            stableTime = 0
            candidateAngle = sensed
        }
        let bounded = desiredAngle(rawAngle: rawAngle)
        if abs(bounded - target) >= deadband { target = bounded }
        let step = maximumSpeed.isFinite ? max(0, maximumSpeed) * dt : Double.infinity
        angle += max(-step, min(step, alpha * (target - angle)))
        if abs(angle - target) < 0.02 && abs(angle - target) <= step { angle = target }
        angle = max(-limit, min(limit, angle))
        if lockingEnabled {
            if let candidateAngle, abs(sensed - candidateAngle) <= max(0.1, stabilityTolerance) {
                stableTime += decisionTime
            } else {
                candidateAngle = sensed
                stableTime = 0
            }
            if stableTime >= max(0.1, lockDuration) && abs(angle - bounded) <= 0.2 {
                isLocked = true
                lockedHeadAngle = sensed
                target = angle
            }
        }
        return angle
    }

    public mutating func reset() {
        angle = 0
        target = 0
        baseline = 0
        cancelLock()
    }

    public mutating func hold(angle: Double, preservingLock: Bool = false) {
        guard angle.isFinite else { return }
        self.angle = max(-limit, min(limit, angle))
        target = self.angle
        if !preservingLock { cancelLock() }
    }

    public mutating func cancelLock() {
        isLocked = false
        candidateAngle = nil
        stableTime = 0
        unlockTime = 0
        sensorAngle = nil
    }

    public func desiredAngle(rawAngle: Double) -> Double {
        let measured = (rawAngle - baseline) * (reversed ? -1 : 1) * gain
        return max(-limit, min(limit, compensation.correct(measured)))
    }

    public mutating func unlock() { cancelLock() }

    public mutating func lock(rawAngle: Double) {
        guard rawAngle.isFinite else { return }
        cancelLock()
        lockedHeadAngle = (rawAngle - baseline) * (reversed ? -1 : 1)
        isLocked = true
        target = angle
    }
}
