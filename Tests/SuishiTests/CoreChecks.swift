import Foundation
import CoreGraphics
import SQLite3
import RotationCore
import MediaCore

@main struct CoreChecks {
    static var checks = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        if !value() { fatalError("FAILED: \(message)") }
    }
    @MainActor static func main() throws {
        for display in [CGSize(width: 1920, height: 1080), CGSize(width: 2560, height: 1600), CGSize(width: 3440, height: 1440), CGSize(width: 1080, height: 1920)] {
            for aspect in [9.0 / 16, 1, 16.0 / 9, 2.4] {
                let fit = ViewingLayout(viewport: display, aspect: aspect, scale: 1)
                let fill = ViewingLayout(viewport: display, aspect: aspect, scale: 1, crop: true)
                check(fit.size.width <= display.width + 0.001 && fit.size.height <= display.height + 0.001, "100 percent complete mode fits the display")
                check(abs(fit.size.width - display.width) < 0.001 || abs(fit.size.height - display.height) < 0.001, "100 percent touches at least one pair of screen edges")
                check(fill.size.width >= display.width - 0.001 && fill.size.height >= display.height - 0.001, "100 percent crop mode covers every display aspect ratio")
                check(abs(fill.size.width / fill.size.height - aspect) < 0.001, "Filling never stretches video proportions")
            }
        }
        let areas = [CGRect(x: -1920, y: 0, width: 1920, height: 1080), CGRect(x: 0, y: 0, width: 1440, height: 900)]
        let ball = CGRect(x: -1500, y: 200, width: 72, height: 72)
        check(WindowPlacement.recovered(ball, in: areas) == ball, "A freely parked ball stays put on another display")
        check(areas.contains { $0.contains(WindowPlacement.recovered(CGRect(x: 9000, y: 9000, width: 72, height: 72), in: areas)) }, "A ball stranded by display removal stays reachable")
        for fps in [12, 24, 60, 120] {
            for response in FollowResponse.allCases {
                var engine = RotationEngine(), time = 10.0
                var previous = 0.0
                for _ in 0..<(fps * 3) {
                    time += 1.0 / Double(fps)
                    let angle = engine.step(sample: HeadSample(angle: 30, timestamp: time), now: time, response: response)
                    check(angle >= previous && angle <= 30, "Step response must be monotonic without overshoot")
                    previous = angle
                }
                check(abs(engine.angle - 30) < 0.1, "All sampling rates must converge")
                let saved = engine.angle
                check(engine.step(sample: nil, now: time + 0.1) == saved, "Missing face holds the actual output")
                check(engine.step(sample: HeadSample(angle: -30, confidence: 0.2, timestamp: time + 0.2), now: time + 0.2) == saved, "Low confidence must hold")
                check(engine.step(sample: HeadSample(angle: -30, timestamp: time - 5), now: time + 0.3) == saved, "Old frames cannot drive motion")
                time += 0.4
                let returned = engine.step(sample: HeadSample(angle: -30, timestamp: time), now: time, response: response)
                check(returned < saved && returned > -30, "Reacquisition must ease from the held angle")
            }
        }
        var engine = RotationEngine()
        for index in 0..<180 {
            let time = Double(index) / 60 + 1
            engine.step(sample: HeadSample(angle: 20 + (index % 2 == 0 ? 0.1 : -0.1), timestamp: time), now: time)
        }
        let before = engine.angle
        engine.calibrate(rawAngle: 20)
        check(engine.angle == before, "Calibration cannot jump the displayed angle")
        for index in 0..<180 {
            let time = Double(index) / 60 + 5
            engine.step(sample: HeadSample(angle: 20, timestamp: time), now: time, offset: 2)
        }
        check(abs(engine.angle - 2) < 0.1, "Calibration and trim feed the same pipeline")
        engine.step(sample: HeadSample(angle: 70, timestamp: 9), now: 9, limit: 3)
        check(abs(engine.angle) <= 3, "Geometry constrains the single output")
        engine.step(sample: HeadSample(angle: .nan, timestamp: 10), now: 10)
        check(engine.angle.isFinite, "Invalid input never propagates NaN")
        // Replay two hours at camera cadence with 60 Hz presentation, including
        // face loss and delayed delivery. Clock age must not degrade the response.
        for response in FollowResponse.allCases {
            var longRun = RotationEngine(), reference = RotationEngine()
            var latest: HeadSample?
            var maximumDifference = 0.0
            for frame in 0..<(60 * 60 * 2 * 60) {
                let phase = frame % 600
                let time = 800_000 + Double(frame) / 60
                if frame % 3 == 0 {
                    latest = HeadSample(angle: phase > 480 ? nil : sin(Double(phase) / 600 * 2 * .pi) * 40, timestamp: time)
                }
                let value = longRun.step(sample: latest, now: time, response: response)
                if frame >= 60 * 60 * 60 {
                    let replayTime = 800_000 + Double(frame - 60 * 60 * 60) / 60
                    let replaySample = latest.map { HeadSample(angle: $0.angle, timestamp: $0.timestamp - 3600) }
                    let replayed = reference.step(sample: replaySample, now: replayTime, response: response)
                    if frame % (60 * 60 * 60) > 600 { maximumDifference = max(maximumDifference, abs(value - replayed)) }
                }
            }
            check(longRun.angle.isFinite && maximumDifference < 0.001, "Two-hour rotation replay has the same response after warmup, without timestamp drift")
        }
        let slope = RotationEngine.eyeAngle(first: CGPoint(x: 0.2, y: 0.2), second: CGPoint(x: 0.4, y: 0.4), imageSize: CGSize(width: 640, height: 480))
        check(abs(slope - atan(0.75) * 180 / .pi) < 0.001, "Camera pixels must respect aspect ratio")

        for viewport in [CGSize(width: 1440, height: 900), CGSize(width: 1920, height: 1080), CGSize(width: 800, height: 600)] {
            for aspect in [9.0 / 16, 1, 16.0 / 9, 2.4] {
                for percent in stride(from: 35, through: 100, by: 5) {
                    for x in [-1.0, -0.5, 0, 0.5, 1] {
                        for y in [-1.0, 0, 1] {
                            let layout = ViewingLayout(viewport: viewport, aspect: aspect, scale: Double(percent) / 100, position: CGPoint(x: x, y: y))
                            let box = ViewingLayout.envelope(layout.size, angle: layout.safeAngle)
                            check(layout.center.x - box.width / 2 >= -0.001 && layout.center.x + box.width / 2 <= viewport.width + 0.001 &&
                                  layout.center.y - box.height / 2 >= -0.001 && layout.center.y + box.height / 2 <= viewport.height + 0.001,
                                  "Every angle in the permitted envelope must fit")
                            let crop = ViewingLayout(viewport: viewport, aspect: aspect, scale: Double(percent) / 100, crop: true)
                            check(crop.safeAngle == 75, "Crop mode preserves supported rotation range")
                        }
                    }
                }
            }
        }
        check(ViewingLayout(viewport: CGSize(width: 1440, height: 900), scale: 1).safeAngle == 0, "Full fit must explain zero rotation space")
        let bad = ViewingLayout(viewport: CGSize(width: .nan, height: -.infinity), aspect: .nan, scale: .nan)
        check(bad.size.width.isFinite && bad.size.height.isFinite, "Invalid geometry remains finite")

        let url = URL(string: "https://www.bilibili.com/video/BV1B7411m7LV/?p=2&t=90&share_source=test")!
        let link = BilibiliRoute.video(at: url)!
        check(link.page == 2 && link.startTime == 90 && !link.pageURL.absoluteString.contains("share_source"), "Route preserves playback identity and removes tracking")
        check(BilibiliRoute.video(at: URL(string: "https://evil.test/video/BV1B7411m7LV/")!) == nil, "External sites cannot select video")
        check(!BilibiliRoute.allowsBrowsing(URL(string: "https://bilibili.com.evil.test/")!), "Host suffix validation")
        check(!BilibiliRoute.allowsBrowsing(URL(string: "https://user@www.bilibili.com/")!), "Credential URLs are rejected")
        check(BilibiliRoute.isUnsupportedPlayback(URL(string: "https://www.bilibili.com/bangumi/play/ep123")!), "Unsupported content has an explicit route")
        check(!BilibiliRoute.isUnsupportedPlayback(URL(string: "https://www.bilibili.com/video/BV1B7411m7LV/")!), "Ordinary submissions remain supported")

        let domain = "local.suishi.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let preferences = Preferences(defaults: defaults)
        preferences.value.scale = 0.77; preferences.value.guides = true; preferences.value.response = .fast
        check(Preferences(defaults: defaults).value == preferences.value, "Preferences survive a new instance")
        preferences.reset()
        check(preferences.value == ViewingPreferences(), "Reset restores only the approved defaults")
        var malformed = ViewingPreferences(); malformed.scale = 100; malformed.offset = -99; malformed.guideOpacity = -1
        defaults.set(try JSONEncoder().encode(malformed), forKey: "viewing.v1")
        let repaired = Preferences(defaults: defaults).value
        check(repaired.scale == 1 && repaired.offset == -5 && repaired.guideOpacity == 0.1, "Persisted values are bounded")

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("suishi-check-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let databaseURL = folder.appendingPathComponent("Library.sqlite")
        let item = RecentContent(url: link.pageURL.absoluteString, title: "测试 ' Unicode 山野", seconds: 151.25)
        do {
            let store = RecentStore(url: databaseURL)
            check(store.issue == nil && store.load() == nil, "Empty versioned database initializes")
            check(store.save(item), "Prepared statements save Unicode and quote characters")
        }
        let reopened = RecentStore(url: databaseURL)
        check(reopened.load() == item, "Database survives closing and reopening")
        let invalid = RecentContent(url: "https://evil.test/", title: "bad", seconds: 9)
        check(!reopened.save(invalid) && reopened.load() == item, "Invalid record cannot overwrite the previous link")
        let unavailable = RecentStore(url: URL(fileURLWithPath: "/dev/null/Library.sqlite"))
        check(unavailable.issue != nil && !unavailable.save(item), "Unavailable storage degrades without a crash")
        var db: OpaquePointer?
        let futureURL = folder.appendingPathComponent("Future.sqlite")
        sqlite3_open(futureURL.path, &db); sqlite3_exec(db, "PRAGMA user_version=99", nil, nil, nil); sqlite3_close(db)
        check(RecentStore(url: futureURL).issue != nil, "A future schema must not be silently overwritten")
        print("Suishi core and persistence: \(checks) checks passed")
    }
}
