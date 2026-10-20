import Foundation
import Combine

enum RotationBoundary: String, CaseIterable { case complete, crop }
enum BackdropKind: String, CaseIterable { case color, image }
enum ViewingStyle: String, Codable, CaseIterable {
    case pose, continuous
    var title: String { self == .pose ? "定姿观看" : "连续跟随" }
}

/// Only preferences persist. Camera access, playback and manual mode always start explicitly.
final class AppSettings: ObservableObject {
    let defaults: UserDefaults
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
    @Published var gridSpacing: Double { didSet { defaults.set(gridSpacing, forKey: "fullscreen.gridSpacing") } }
    @Published var gridFollowsVideo: Bool { didSet { defaults.set(gridFollowsVideo, forKey: "fullscreen.gridFollowsVideo") } }
    @Published var gridFadeOnMotion: Bool { didSet { defaults.set(gridFadeOnMotion, forKey: "fullscreen.gridFadeOnMotion") } }
    @Published var guideHex: String { didSet { defaults.set(guideHex, forKey: "fullscreen.guideHex") } }
    @Published var guideOpacity: Double { didSet { defaults.set(guideOpacity, forKey: "fullscreen.guideOpacity") } }
    @Published var guideWidth: Double { didSet { defaults.set(guideWidth, forKey: "fullscreen.guideWidth") } }
    @Published var guideOutsideOnly: Bool { didSet { defaults.set(guideOutsideOnly, forKey: "fullscreen.guideOutsideOnly") } }
    @Published var followGain: Double { didSet { defaults.set(followGain, forKey: "tracking.gain") } }
    @Published var maximumSpeed: Double { didSet { defaults.set(maximumSpeed, forKey: "tracking.maximumSpeed") } }

    @Published var viewingStyle: ViewingStyle { didSet { defaults.set(viewingStyle.rawValue, forKey: "comfort.style") } }
    @Published var selectedPresetID: String { didSet { defaults.set(selectedPresetID, forKey: "comfort.selectedPreset") } }
    @Published var savedPresets: [SavedViewingPreset] { didSet { if let data = try? JSONEncoder().encode(savedPresets) { defaults.set(data, forKey: "comfort.savedPresets") } } }
    @Published var unlockDuration: Double { didSet { defaults.set(unlockDuration, forKey: "tracking.unlockDuration") } }
    @Published var compensationThreshold: Double { didSet { defaults.set(compensationThreshold, forKey: "comfort.compensationThreshold") } }
    @Published var compensationLeft: Double { didSet { defaults.set(compensationLeft, forKey: "comfort.compensationLeft") } }
    @Published var compensationRight: Double { didSet { defaults.set(compensationRight, forKey: "comfort.compensationRight") } }
    @Published var compensationBlend: Double { didSet { defaults.set(compensationBlend, forKey: "comfort.compensationBlend") } }
    @Published var curtainThreshold: Double { didSet { defaults.set(curtainThreshold, forKey: "comfort.curtainThreshold") } }
    @Published var curtainConfirmation: Double { didSet { defaults.set(curtainConfirmation, forKey: "comfort.curtainConfirmation") } }
    @Published var curtainFadeOut: Double { didSet { defaults.set(curtainFadeOut, forKey: "comfort.curtainFadeOut") } }
    @Published var curtainCovered: Double { didSet { defaults.set(curtainCovered, forKey: "comfort.curtainCovered") } }
    @Published var curtainFadeIn: Double { didSet { defaults.set(curtainFadeIn, forKey: "comfort.curtainFadeIn") } }
    @Published var curtainInterval: Double { didSet { defaults.set(curtainInterval, forKey: "comfort.curtainInterval") } }
    @Published var cueStrength: Double { didSet { defaults.set(cueStrength, forKey: "comfort.cueStrength") } }
    @Published var cueMaximumSpeed: Double { didSet { defaults.set(cueMaximumSpeed, forKey: "comfort.cueMaximumSpeed") } }
    @Published var cueCount: Double { didSet { defaults.set(cueCount, forKey: "comfort.cueCount") } }
    @Published var cueOpacity: Double { didSet { defaults.set(cueOpacity, forKey: "comfort.cueOpacity") } }
    @Published var cueSize: Double { didSet { defaults.set(cueSize, forKey: "comfort.cueSize") } }
    @Published var manualUnlockOnly: Bool { didSet { defaults.set(manualUnlockOnly, forKey: "tracking.manualUnlockOnly") } }
    @Published var compensationEnabled: Bool { didSet { defaults.set(compensationEnabled, forKey: "comfort.compensationEnabled") } }
    @Published var curtainEnabled: Bool { didSet { defaults.set(curtainEnabled, forKey: "comfort.curtainEnabled") } }
    @Published var cuesEnabled: Bool { didSet { defaults.set(cuesEnabled, forKey: "comfort.cuesEnabled") } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        func number(_ key: String, fallback: Double, range: ClosedRange<Double>) -> Double {
            guard defaults.object(forKey: key) != nil else { return fallback }
            let value = defaults.double(forKey: key)
            return value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
        }
        let initialStyle = ViewingStyle(rawValue: defaults.string(forKey: "comfort.style") ?? "") ?? .pose
        let migrateComfort = defaults.integer(forKey: "comfort.version") < 2
        viewingStyle = initialStyle
        selectedPresetID = defaults.string(forKey: "comfort.selectedPreset") ?? initialStyle.rawValue
        savedPresets = ((defaults.data(forKey: "comfort.savedPresets").flatMap { try? JSONDecoder().decode([SavedViewingPreset].self, from: $0) }) ?? [])
            .filter { $0.id.hasPrefix("saved-") && !$0.name.isEmpty }.prefix(20).map { $0 }
        responseTime = number("tracking.response", fallback: 0.24, range: 0.10...0.55)
        reversed = defaults.bool(forKey: "tracking.reversed")
        autoLock = defaults.object(forKey: "tracking.autoLock") == nil ? true : defaults.bool(forKey: "tracking.autoLock")
        lockDuration = number("tracking.lockDuration", fallback: 4, range: 1...10)
        let stableTolerance = number("tracking.stabilityTolerance", fallback: 1.5, range: 0.5...3)
        stabilityTolerance = stableTolerance
        let storedUnlock = max(stableTolerance + 0.5, number("tracking.unlockTolerance", fallback: 20, range: 1...60))
        unlockTolerance = migrateComfort ? max(20, storedUnlock) : storedUnlock
        rotationLimit = number("view.rotationLimit", fallback: 45, range: 15...90)
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
        gridSpacing = number("fullscreen.gridSpacing", fallback: 64, range: 24...180)
        gridFollowsVideo = defaults.object(forKey: "fullscreen.gridFollowsVideo") == nil ? true : defaults.bool(forKey: "fullscreen.gridFollowsVideo")
        gridFadeOnMotion = defaults.object(forKey: "fullscreen.gridFadeOnMotion") == nil ? true : defaults.bool(forKey: "fullscreen.gridFadeOnMotion")
        guideHex = defaults.string(forKey: "fullscreen.guideHex") ?? "B5D9D1"
        guideOpacity = number("fullscreen.guideOpacity", fallback: 0.2, range: 0...1)
        guideWidth = number("fullscreen.guideWidth", fallback: 1, range: 0.5...4)
        guideOutsideOnly = defaults.object(forKey: "fullscreen.guideOutsideOnly") == nil ? true : defaults.bool(forKey: "fullscreen.guideOutsideOnly")
        followGain = number("tracking.gain", fallback: 1, range: 0.25...1)
        maximumSpeed = number("tracking.maximumSpeed", fallback: 30, range: 5...120)
        unlockDuration = number("tracking.unlockDuration", fallback: 0.45, range: 0.1...2)
        compensationThreshold = number("comfort.compensationThreshold", fallback: 15, range: 0...60)
        compensationLeft = number("comfort.compensationLeft", fallback: 4, range: 0...15)
        compensationRight = number("comfort.compensationRight", fallback: 4, range: 0...15)
        compensationBlend = number("comfort.compensationBlend", fallback: 15, range: 1...40)
        curtainThreshold = number("comfort.curtainThreshold", fallback: 8, range: 2...45)
        curtainConfirmation = number("comfort.curtainConfirmation", fallback: 0.18, range: 0.05...0.6)
        curtainFadeOut = number("comfort.curtainFadeOut", fallback: 0.1, range: 0.05...0.3)
        curtainCovered = number("comfort.curtainCovered", fallback: 0.08, range: 0.02...0.3)
        curtainFadeIn = number("comfort.curtainFadeIn", fallback: 0.15, range: 0.05...0.4)
        curtainInterval = number("comfort.curtainInterval", fallback: 1.5, range: 0.5...5)
        cueStrength = number("comfort.cueStrength", fallback: 0.5, range: 0...2)
        cueMaximumSpeed = number("comfort.cueMaximumSpeed", fallback: 60, range: 5...180)
        cueCount = number("comfort.cueCount", fallback: 20, range: 8...40)
        cueOpacity = number("comfort.cueOpacity", fallback: 0.3, range: 0.05...1)
        cueSize = number("comfort.cueSize", fallback: 3, range: 2...8)
        manualUnlockOnly = defaults.object(forKey: "tracking.manualUnlockOnly") == nil ? false : defaults.bool(forKey: "tracking.manualUnlockOnly")
        compensationEnabled = defaults.object(forKey: "comfort.compensationEnabled") == nil ? true : defaults.bool(forKey: "comfort.compensationEnabled")
        curtainEnabled = defaults.object(forKey: "comfort.curtainEnabled") == nil ? initialStyle == .pose : defaults.bool(forKey: "comfort.curtainEnabled")
        cuesEnabled = defaults.object(forKey: "comfort.cuesEnabled") == nil ? false : defaults.bool(forKey: "comfort.cuesEnabled")
        if migrateComfort { defaults.set(unlockTolerance, forKey: "tracking.unlockTolerance") }
        defaults.set(2, forKey: "comfort.version")
        if !ViewingStyle.allCases.map(\.rawValue).contains(selectedPresetID) && !savedPresets.contains(where: { $0.id == selectedPresetID }) {
            selectedPresetID = initialStyle.rawValue
        }
    }

    func restoreDefaults() {
        responseTime = 0.24; reversed = false; autoLock = true
        lockDuration = 4; stabilityTolerance = 1.5; unlockTolerance = 20
        rotationLimit = 45; fixedVideoSize = true; videoScale = 1
        fullscreenScale = 0.8; boundary = .complete; transparentBackground = false
        backdrop = .color; backgroundHex = "000000"; backgroundOpacity = 1
        backgroundBlur = 0; backgroundDim = 0.3
        guides = false; gridSpacing = 64; gridFollowsVideo = true; gridFadeOnMotion = true; guideHex = "B5D9D1"
        guideOpacity = 0.2; guideWidth = 1; guideOutsideOnly = true
        applyBuiltIn(.pose)
    }
}
