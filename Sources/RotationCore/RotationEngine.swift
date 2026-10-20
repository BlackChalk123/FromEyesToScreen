import Foundation
import CoreGraphics

public struct HeadSample {
    public let angle: Double?
    public let confidence: Double
    public let timestamp: TimeInterval
    public init(angle: Double?, confidence: Double = 1, timestamp: TimeInterval) {
        self.angle = angle; self.confidence = confidence; self.timestamp = timestamp
    }
    public func isReliable(at now: TimeInterval) -> Bool {
        guard let angle else { return false }
        return angle.isFinite && abs(angle) <= 90 && confidence.isFinite && confidence >= 0.7 &&
            timestamp.isFinite && now >= timestamp && now - timestamp <= 0.35
    }
}

public enum FollowResponse: String, Codable, CaseIterable {
    case soft, balanced, fast
    public var seconds: Double {
        switch self { case .soft: return 0.24; case .balanced: return 0.14; case .fast: return 0.07 }
    }
}

/// The sole angle writer. No media, windows, persistence, locks or transitions.
public struct RotationEngine {
    public private(set) var angle = 0.0
    public private(set) var target = 0.0
    public private(set) var baseline = 0.0
    public private(set) var tracking = false
    private var lastTick: TimeInterval?
    public init() {}

    public mutating func calibrate(rawAngle: Double) {
        guard rawAngle.isFinite, abs(rawAngle) <= 90 else { return }
        baseline = rawAngle
        target = 0
    }

    public mutating func hold() { target = angle; tracking = false; lastTick = nil }

    @discardableResult public mutating func step(sample: HeadSample?, now: TimeInterval,
        response: FollowResponse = .balanced, offset: Double = 0, limit: Double = 75) -> Double {
        guard now.isFinite else { return angle }
        let elapsed = lastTick.map { now - $0 } ?? (1.0 / 60)
        lastTick = now
        let bound = limit.isFinite ? min(75, max(0, limit)) : 0
        angle = min(bound, max(-bound, angle))
        guard let sample, sample.isReliable(at: now) else {
            tracking = false; target = angle; return angle
        }
        tracking = true
        let trim = offset.isFinite ? min(5, max(-5, offset)) : 0
        let desired = min(bound, max(-bound, sample.angle! - baseline + trim))
        // A small deadband removes stationary noise without a second smoothing stage.
        if abs(desired - target) >= 0.3 { target = desired }
        target = min(bound, max(-bound, target))
        let dt = elapsed > 0 && elapsed <= 0.35 ? min(elapsed, 0.05) : 1.0 / 60
        angle += (target - angle) * (1 - exp(-dt / response.seconds))
        if abs(angle - target) < 0.015 { angle = target }
        return angle
    }

    /// Coordinates are from an unmirrored camera. Positive output rotates the viewing surface clockwise.
    public static func eyeAngle(first: CGPoint, second: CGPoint, imageSize: CGSize) -> Double {
        let (a, b) = first.x <= second.x ? (first, second) : (second, first)
        return atan2((b.y - a.y) * imageSize.height,
                     (b.x - a.x) * imageSize.width) * 180 / .pi
    }
}
