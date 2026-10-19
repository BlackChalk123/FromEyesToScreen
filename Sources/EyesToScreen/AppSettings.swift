import Foundation
import Combine

enum RotationBoundary: String, CaseIterable { case complete, crop }
enum BackdropKind: String, CaseIterable { case color, image }
enum GuideStyle: String, CaseIterable { case horizontal, cross, thirds, square, rectangle }

/// Only preferences persist. Camera access, playback and manual mode always start explicitly.
final class AppSettings: ObservableObject {
    private let defaults: UserDefaults
    @Published var responseTime: Double { didSet { defaults.set(responseTime, forKey: "tracking.response") } }
    @Published var reversed: Bool { didSet { defaults.set(reversed, forKey: "tracking.reversed") } }
    @Published var autoLock: Bool { didSet { defaults.set(autoLock, forKey: "tracking.autoLock") } }
    @Published var lockDuration: Double { didSet { defaults.set(lockDuration, forKey: "tracking.lockDuration") } }
    @Published var stabilityTolerance: Double {
        didSet {
            defaults.set(stabilityTolerance, forKey: "tracking.stabilityTolerance")
            if unlockTolerance < stabilityTolerance + 0.5 { unlockTolerance = stabilityTolerance + 0.5 }
        }
    }
    @Published var unlockTolerance: Double { didSet { defaults.set(unlockTolerance, forKey: "tracking.unlockTolerance") } }
    @Published var rotationLimit: Double { didSet { defaults.set(rotationLimit, forKey: "view.rotationLimit") } }
    @Published var fixedVideoSize: Bool { didSet { defaults.set(fixedVideoSize, forKey: "view.fixedSize") } }
    @Published var videoScale: Double { didSet { defaults.set(videoScale, forKey: "view.scale") } }
    @Published var fullscreenScale: Double { didSet { defaults.set(fullscreenScale, forKey: "fullscreen.scale") } }
    @Published var boundary: RotationBoundary { didSet { defaults.set(boundary.rawValue, forKey: "fullscreen.boundary"); if boundary == .complete && fullscreenScale > 1 { fullscreenScale = 1 } } }
    @Published var transparentBackground: Bool { didSet { defaults.set(transparentBackground, forKey: "fullscreen.transparent") } }
    @Published var backdrop: BackdropKind { didSet { defaults.set(backdrop.rawValue, forKey: "fullscreen.backdrop") } }
    @Published var backgroundHex: String { didSet { defaults.set(backgroundHex, forKey: "fullscreen.backgroundHex") } }
    @Published var backgroundOpacity: Double { didSet { defaults.set(backgroundOpacity, forKey: "fullscreen.backgroundOpacity") } }
    @Published var backgroundImagePath: String { didSet { defaults.set(backgroundImagePath, forKey: "fullscreen.image") } }
    @Published var backgroundBlur: Double { didSet { defaults.set(backgroundBlur, forKey: "fullscreen.blur") } }
    @Published var backgroundDim: Double { didSet { defaults.set(backgroundDim, forKey: "fullscreen.dim") } }
    @Published var guides: Bool { didSet { defaults.set(guides, forKey: "fullscreen.guides") } }
    @Published var guideStyle: GuideStyle { didSet { defaults.set(guideStyle.rawValue, forKey: "fullscreen.guideStyle") } }
    @Published var guideHex: String { didSet { defaults.set(guideHex, forKey: "fullscreen.guideHex") } }
    @Published var guideOpacity: Double { didSet { defaults.set(guideOpacity, forKey: "fullscreen.guideOpacity") } }
    @Published var guideWidth: Double { didSet { defaults.set(guideWidth, forKey: "fullscreen.guideWidth") } }
    @Published var guideOutsideOnly: Bool { didSet { defaults.set(guideOutsideOnly, forKey: "fullscreen.guideOutsideOnly") } }
    @Published var followGain: Double { didSet { defaults.set(followGain, forKey: "tracking.gain") } }
    @Published var maximumSpeed: Double { didSet { defaults.set(maximumSpeed, forKey: "tracking.maximumSpeed") } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        func number(_ key: String, fallback: Double, range: ClosedRange<Double>) -> Double {
            guard defaults.object(forKey: key) != nil else { return fallback }
            let value = defaults.double(forKey: key)
            return value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
        }
        responseTime = number("tracking.response", fallback: 0.24, range: 0.10...0.55)
        reversed = defaults.bool(forKey: "tracking.reversed")
        autoLock = defaults.object(forKey: "tracking.autoLock") == nil ? true : defaults.bool(forKey: "tracking.autoLock")
        lockDuration = number("tracking.lockDuration", fallback: 4, range: 1...10)
        let stableTolerance = number("tracking.stabilityTolerance", fallback: 1.5, range: 0.5...3)
        stabilityTolerance = stableTolerance
        unlockTolerance = max(stableTolerance + 0.5, number("tracking.unlockTolerance", fallback: 4, range: 1...10))
        rotationLimit = number("view.rotationLimit", fallback: 45, range: 15...45)
        fixedVideoSize = defaults.object(forKey: "view.fixedSize") == nil ? true : defaults.bool(forKey: "view.fixedSize")
        videoScale = number("view.scale", fallback: 1, range: 0.4...1)
        let initialBoundary = RotationBoundary(rawValue: defaults.string(forKey: "fullscreen.boundary") ?? "") ?? .complete
        boundary = initialBoundary
        fullscreenScale = number("fullscreen.scale", fallback: 0.8, range: 0.25...(initialBoundary == .complete ? 1 : 16))
        transparentBackground = defaults.bool(forKey: "fullscreen.transparent")
        backdrop = BackdropKind(rawValue: defaults.string(forKey: "fullscreen.backdrop") ?? "") ?? .color
        backgroundHex = defaults.string(forKey: "fullscreen.backgroundHex") ?? "000000"
        backgroundOpacity = number("fullscreen.backgroundOpacity", fallback: 1, range: 0...1)
        backgroundImagePath = defaults.string(forKey: "fullscreen.image") ?? ""
        backgroundBlur = number("fullscreen.blur", fallback: 0, range: 0...30)
        backgroundDim = number("fullscreen.dim", fallback: 0.3, range: 0...1)
        guides = defaults.bool(forKey: "fullscreen.guides")
        guideStyle = GuideStyle(rawValue: defaults.string(forKey: "fullscreen.guideStyle") ?? "") ?? .horizontal
        guideHex = defaults.string(forKey: "fullscreen.guideHex") ?? "B5D9D1"
        guideOpacity = number("fullscreen.guideOpacity", fallback: 0.2, range: 0...1)
        guideWidth = number("fullscreen.guideWidth", fallback: 1, range: 0.5...4)
        guideOutsideOnly = defaults.object(forKey: "fullscreen.guideOutsideOnly") == nil ? true : defaults.bool(forKey: "fullscreen.guideOutsideOnly")
        followGain = number("tracking.gain", fallback: 1, range: 0.25...1)
        maximumSpeed = number("tracking.maximumSpeed", fallback: 30, range: 5...120)
    }

    func restoreDefaults() {
        responseTime = 0.24; reversed = false; autoLock = true
        lockDuration = 4; stabilityTolerance = 1.5; unlockTolerance = 4
        rotationLimit = 45; fixedVideoSize = true; videoScale = 1
        fullscreenScale = 0.8; boundary = .complete; transparentBackground = false
        backdrop = .color; backgroundHex = "000000"; backgroundOpacity = 1
        backgroundBlur = 0; backgroundDim = 0.3
        guides = false; guideStyle = .horizontal; guideHex = "B5D9D1"
        guideOpacity = 0.2; guideWidth = 1; guideOutsideOnly = true
        followGain = 1; maximumSpeed = 30
    }
}
