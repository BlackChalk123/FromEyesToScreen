import Foundation

public struct AngleCompensation {
    public var enabled = false
    public var threshold = 15.0
    public var left = 4.0
    public var right = 4.0
    public var blendWidth = 15.0
    public init() {}

    public func correct(_ angle: Double) -> Double {
        guard angle.isFinite else { return 0 }
        guard enabled else { return angle }
        let amount = max(0, min(15, angle < 0 ? left : right))
        // Keep the mapping monotonic, even with an aggressive user configuration.
        let width = max(1, max(blendWidth, amount * 1.5))
        let x = max(0, min(1, (abs(angle) - max(0, threshold)) / width))
        let correction = amount * x * x * (3 - 2 * x)
        return (angle < 0 ? -1 : 1) * max(0, abs(angle) - correction)
    }
}

public struct CurtainConfiguration {
    public var enabled = false
    public var threshold = 8.0
    public var confirmation = 0.18
    public var tolerance = 2.0
    public var fadeOut = 0.1
    public var covered = 0.08
    public var fadeIn = 0.15
    public var minimumVisible = 1.5
    public var maximumSpeed = 30.0
    public init() {}
}

/// No media lifecycle operations: only the visible angle and a display-layer mask.
public struct RotationTransition {
    public enum Phase: Equatable { case visible, fadingOut, covered, fadingIn }
    public private(set) var angle = 0.0
    public private(set) var opacity = 0.0
    public private(set) var phase = Phase.visible
    private var elapsed = 0.0
    private var visibleTime = Double.infinity
    private var candidate: Double?
    private var candidateTime = 0.0
    private var waitingTime = 0.0
    private var destination = 0.0
    private var recoveryOpacity = 1.0
    public init() {}

    public mutating func reset(to angle: Double) {
        self.angle = angle.isFinite ? angle : 0
        destination = self.angle
        cancel()
    }

    public mutating func cancel() {
        candidate = nil; candidateTime = 0; waitingTime = 0; elapsed = 0
        if opacity > 0 { recoveryOpacity = opacity; phase = .fadingIn }
        else { phase = .visible }
        visibleTime = 0
    }

    public mutating func step(target: Double, relocation: Double, fresh: Bool,
                              deltaTime: Double, configuration c: CurtainConfiguration) {
        guard target.isFinite, relocation.isFinite, deltaTime.isFinite, deltaTime > 0 else { return }
        // A suspended UI cannot accumulate confirmation time or remain black on return.
        if deltaTime > 0.25 { cancel(); opacity = 0; phase = .visible; return }
        let dt = min(0.05, deltaTime)
        if (!c.enabled || !fresh) && (phase == .fadingOut || phase == .covered) { cancel() }
        switch phase {
        case .visible:
            visibleTime += dt
            if c.enabled && fresh && visibleTime >= max(0, c.minimumVisible) && abs(relocation - angle) >= max(1, c.threshold) {
                waitingTime += dt
                if let candidate, abs(relocation - candidate) <= max(0.2, c.tolerance) { candidateTime += dt }
                else { candidate = relocation; candidateTime = 0 }
                if candidateTime >= max(0.05, c.confirmation) {
                    destination = relocation; elapsed = 0; phase = .fadingOut
                    candidate = nil; candidateTime = 0; waitingTime = 0
                    return
                }
                if waitingTime < 0.8 { return }
                // Continuous wandering is not a confirmed new pose. Resume tracking
                // rather than indefinitely holding the old angle or flashing a mask.
                visibleTime = 0
            }
            candidate = nil; candidateTime = 0; waitingTime = 0
            let step = max(1, c.maximumSpeed) * dt
            let change = (target - angle) * (1 - exp(-dt / 0.08))
            angle += max(-step, min(step, change))
            if abs(target - angle) < 0.01 && abs(target - angle) <= step { angle = target }
        case .fadingOut:
            destination = relocation
            elapsed += dt
            opacity = Self.smooth(elapsed / max(0.05, c.fadeOut))
            if opacity >= 1 { angle = destination; phase = .covered; elapsed = 0 }
        case .covered:
            angle = relocation
            elapsed += dt
            if elapsed >= max(0.02, c.covered) { phase = .fadingIn; elapsed = 0; recoveryOpacity = 1 }
        case .fadingIn:
            elapsed += dt
            opacity = recoveryOpacity * (1 - Self.smooth(elapsed / max(0.05, c.fadeIn)))
            if opacity <= 0 { phase = .visible; elapsed = 0; visibleTime = 0 }
        }
    }

    private static func smooth(_ x: Double) -> Double {
        let x = min(1, max(0, x)); return x * x * (3 - 2 * x)
    }
}

/// Driven by actual visible rotation, after geometry limits. Phase is degrees,
/// and a positive displayed rotation produces negative cue motion.
public struct EdgeMotionFilter {
    public private(set) var velocity = 0.0
    public private(set) var phase = 0.0
    private var previous: Double?
    public init() {}
    public mutating func reset(angle: Double) { previous = angle.isFinite ? angle : 0; velocity = 0; phase = 0 }

    public mutating func step(angle: Double, deltaTime: Double, strength: Double,
                              maximumSpeed: Double, visible: Bool) {
        guard angle.isFinite, deltaTime.isFinite, deltaTime > 0, deltaTime <= 0.25 else { reset(angle: angle); return }
        defer { previous = angle }
        let raw = visible ? (angle - (previous ?? angle)) / deltaTime : 0
        let desired = max(-maximumSpeed, min(maximumSpeed, -raw * strength))
        velocity += (desired - velocity) * (1 - exp(-deltaTime / 0.15))
        if abs(velocity) < 0.02 && abs(desired) < 0.02 { velocity = 0 }
        if visible { phase = (phase + velocity * deltaTime).truncatingRemainder(dividingBy: 360) }
    }
}

public struct MotionReferenceVisibility {
    public private(set) var opacity = 1.0
    private var previous: Double?
    private var stillTime = 0.0
    private var moving = false
    public init() {}
    public mutating func reset(angle: Double) { previous = angle.isFinite ? angle : 0; opacity = 1; stillTime = 0; moving = false }
    public mutating func step(angle: Double, deltaTime: Double, enabled: Bool) {
        guard angle.isFinite, deltaTime.isFinite, deltaTime > 0, deltaTime <= 0.25 else { reset(angle: angle); return }
        let speed = abs(angle - (previous ?? angle)) / deltaTime
        previous = angle
        if !enabled { opacity = 1; stillTime = 0; moving = false; return }
        if speed > 0.5 { stillTime = 0; moving = true }
        else if moving { stillTime += deltaTime; if stillTime >= 0.25 { moving = false } }
        let target = moving ? 0.0 : 1.0
        if target > opacity { opacity = min(1, opacity + deltaTime / 0.15) }
        else if target < opacity { opacity = max(0, opacity - deltaTime / 0.1) }
    }
}
