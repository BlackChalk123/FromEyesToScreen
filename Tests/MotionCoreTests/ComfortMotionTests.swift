import Foundation

@main
struct ComfortMotionTests {
    static let dt = 1.0 / 120
    static func main() {
        var c = AngleCompensation()
        c.enabled = true
        precondition(c.correct(60) == 56 && c.correct(-60) == -56)
        precondition(c.correct(10) == 10 && c.correct(0) == 0)
        c.left = 3; c.right = 6; c.blendWidth = 1
        precondition(c.correct(-60) == -57 && c.correct(60) == 54)
        var previous = -100.0
        for angle in stride(from: -90.0, through: 90, by: 0.01) {
            let corrected = c.correct(angle)
            precondition(corrected >= previous - 1e-9 && abs(corrected) <= abs(angle) + 1e-9)
            previous = corrected
        }

        var filter = HeadMotionFilter()
        filter.lockingEnabled = true; filter.unlockTolerance = 20; filter.unlockDuration = 0.45
        for _ in 0..<600 { filter.update(rawAngle: 30, deltaTime: dt) }
        precondition(filter.isLocked)
        let frozen = filter.angle
        for _ in 0..<300 { filter.update(rawAngle: 45, deltaTime: dt) }
        precondition(filter.isLocked && filter.angle == frozen, "Ordinary movements must not unlock the pose")
        filter.update(rawAngle: -85, deltaTime: dt)
        for _ in 0..<120 { filter.update(rawAngle: 30, deltaTime: dt) }
        precondition(filter.isLocked)
        for _ in 0..<120 { filter.update(rawAngle: 80, deltaTime: dt, confidence: 0.3) }
        precondition(filter.isLocked, "Uncertain face estimates must not release the lock")
        for _ in 0..<200 { filter.update(rawAngle: 60, deltaTime: dt) }
        precondition(!filter.isLocked && filter.angle > frozen)
        filter.lock(rawAngle: 60)
        filter.manualUnlockOnly = true
        for _ in 0..<600 { filter.update(rawAngle: -60, deltaTime: dt) }
        precondition(filter.isLocked, "Manual-only mode must ignore any automatic release gesture")
        filter.update(rawAngle: nil, deltaTime: 5)
        precondition(filter.isLocked)
        filter.unlock()
        precondition(!filter.isLocked)
        filter.update(rawAngle: 0, deltaTime: dt)
        filter.lock(rawAngle: 0)
        filter.hold(angle: 7, preservingLock: true)
        precondition(filter.isLocked && filter.angle == 7)

        var config = CurtainConfiguration()
        config.enabled = true; config.minimumVisible = 0.5
        var rotation = RotationTransition()
        var sawCovered = false, completed = false
        var before = 0.0
        for _ in 0..<200 {
            rotation.step(target: 3, relocation: 56, fresh: true, deltaTime: dt, configuration: config)
            if rotation.phase == .covered { sawCovered = true }
            if abs(rotation.angle - before) > 10 { precondition(rotation.opacity == 1, "Hidden turn must occur only behind an opaque curtain") }
            before = rotation.angle
            if sawCovered && rotation.phase == .visible { completed = true; break }
        }
        precondition(sawCovered && completed && rotation.opacity == 0 && rotation.angle == 56)
        // No immediate blackout on a second relocation; a minimum visible interval is required.
        for _ in 0..<30 {
            rotation.step(target: 56, relocation: -40, fresh: true, deltaTime: dt, configuration: config)
            precondition(rotation.opacity == 0)
        }
        for _ in 0..<120 {
            rotation.step(target: 56, relocation: -40, fresh: true, deltaTime: dt, configuration: config)
            if rotation.phase == .fadingOut { break }
        }
        precondition(rotation.phase == .fadingOut)
        for _ in 0..<100 { rotation.step(target: rotation.angle, relocation: 0, fresh: false, deltaTime: dt, configuration: config) }
        precondition(rotation.phase == .visible && rotation.opacity == 0, "Face loss must recover from the curtain")
        rotation = RotationTransition()
        for _ in 0..<36 { rotation.step(target: 0, relocation: 40, fresh: true, deltaTime: dt, configuration: config) }
        precondition(rotation.opacity > 0)
        config.enabled = false
        for _ in 0..<100 { rotation.step(target: rotation.angle, relocation: 40, fresh: true, deltaTime: dt, configuration: config) }
        precondition(rotation.opacity == 0)
        config.enabled = true
        rotation = RotationTransition()
        for i in 0..<150 {
            rotation.step(target: 0, relocation: i % 2 == 0 ? 40 : -40, fresh: true, deltaTime: dt, configuration: config)
            precondition(rotation.opacity == 0, "Unconfirmed movements must not flash a curtain")
        }
        for _ in 0..<36 { rotation.step(target: 0, relocation: 40, fresh: true, deltaTime: dt, configuration: config) }
        rotation.step(target: 0, relocation: 0, fresh: false, deltaTime: 8, configuration: config)
        for _ in 0..<100 { rotation.step(target: 0, relocation: 0, fresh: false, deltaTime: dt, configuration: config) }
        precondition(rotation.opacity == 0)

        var cues = EdgeMotionFilter()
        cues.reset(angle: 0)
        for i in 1...120 { cues.step(angle: Double(i) * 0.1, deltaTime: dt, strength: 1, maximumSpeed: 6, visible: true) }
        precondition(cues.velocity < 0 && abs(cues.velocity) <= 6 && cues.phase < 0)
        for _ in 0..<500 { cues.step(angle: 12, deltaTime: dt, strength: 1, maximumSpeed: 6, visible: true) }
        precondition(cues.velocity == 0, "At a geometry boundary the dots must stop, even if the head keeps moving")
        let phase = cues.phase
        cues.step(angle: -60, deltaTime: dt, strength: 1, maximumSpeed: 6, visible: false)
        precondition(cues.phase == phase && cues.velocity == 0, "Concealed jumps must not generate artificial cue motion")
        cues.reset(angle: 0)
        for i in 1...120 { cues.step(angle: -Double(i) * 0.1, deltaTime: dt, strength: 1, maximumSpeed: 30, visible: true) }
        precondition(cues.velocity > 0 && cues.phase > 0)
        var grid = MotionReferenceVisibility()
        for _ in 0..<60 { grid.step(angle: 0, deltaTime: dt, enabled: true); precondition(grid.opacity == 1) }
        for i in 1...120 { grid.step(angle: Double(i) * 0.1, deltaTime: dt, enabled: true) }
        precondition(grid.opacity == 0, "Grid must disappear while visible rotation continues without a curtain")
        for _ in 0..<120 { grid.step(angle: 12, deltaTime: dt, enabled: true) }
        precondition(grid.opacity == 1)
        grid.step(angle: 20, deltaTime: dt, enabled: false)
        precondition(grid.opacity == 1)
        print("PASS: Compensation continuity, durable/manual locks, confidence filtering, curtain timing/recovery/cooldown and reverse motion cues.")
    }
}
