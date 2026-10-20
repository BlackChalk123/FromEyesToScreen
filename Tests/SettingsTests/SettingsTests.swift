import Foundation

@main
struct SettingsTests {
    static func main() {
        let name = "local.fromeyestoscreen.settings-test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(defaults: defaults)
        settings.boundary = .crop; settings.fullscreenScale = 3.2
        settings.transparentBackground = true; settings.backdrop = .image
        settings.backgroundHex = "123ABC"; settings.backgroundOpacity = 0.35
        settings.backgroundImagePath = "/fixture/image.png"; settings.backgroundBlur = 12; settings.backgroundDim = 0.4
        settings.guides = true; settings.gridSpacing = 40; settings.gridFollowsVideo = false; settings.guideHex = "ABCDEF"
        settings.guideWidth = 2; settings.guideOpacity = 0.25; settings.guideOutsideOnly = false
        settings.followGain = 0.5; settings.maximumSpeed = 20
        settings.manualUnlockOnly = true; settings.unlockTolerance = 35; settings.unlockDuration = 0.8
        settings.compensationThreshold = 20; settings.compensationLeft = 3; settings.compensationRight = 5
        settings.curtainFadeOut = 0.12; settings.curtainFadeIn = 0.18; settings.cuesEnabled = true
        settings.cueStrength = 0.8
        precondition(settings.savePreset(name: "我的定姿"))
        let customID = settings.selectedPresetID
        let restored = AppSettings(defaults: defaults)
        precondition(restored.boundary == .crop && restored.fullscreenScale == 3.2 && restored.transparentBackground)
        precondition(restored.backdrop == .image && restored.backgroundHex == "123ABC" && restored.backgroundOpacity == 0.35)
        precondition(restored.backgroundImagePath == "/fixture/image.png" && restored.backgroundBlur == 12 && restored.backgroundDim == 0.4)
        precondition(restored.guides && restored.gridSpacing == 40 && !restored.gridFollowsVideo && restored.guideHex == "ABCDEF")
        precondition(restored.guideWidth == 2 && restored.guideOpacity == 0.25 && !restored.guideOutsideOnly)
        precondition(restored.followGain == 0.5 && restored.maximumSpeed == 20)
        precondition(restored.manualUnlockOnly && restored.unlockTolerance == 35 && restored.unlockDuration == 0.8)
        precondition(restored.compensationLeft == 3 && restored.compensationRight == 5)
        precondition(restored.curtainFadeOut == 0.12 && restored.cuesEnabled && restored.cueStrength == 0.8)
        restored.applyBuiltIn(.continuous)
        precondition(!restored.autoLock && !restored.curtainEnabled && !restored.cuesEnabled)
        precondition(restored.transparentBackground && restored.fullscreenScale == 3.2, "Built-ins preserve appearance")
        restored.applyPreset(id: customID)
        precondition(restored.manualUnlockOnly && restored.autoLock && restored.cuesEnabled && restored.gridSpacing == 40)
        precondition(restored.compensationRight == 5 && restored.curtainFadeIn == 0.18)
        precondition(!restored.savePreset(name: "  "))
        restored.boundary = .complete
        precondition(restored.fullscreenScale == 1, "Complete framing cannot retain an oversized crop scale")
        restored.restoreDefaults()
        let reset = AppSettings(defaults: defaults)
        precondition(reset.fullscreenScale == 0.8 && reset.boundary == .complete && !reset.transparentBackground)
        precondition(!reset.guides && reset.backgroundOpacity == 1 && reset.followGain == 1 && reset.maximumSpeed == 30)
        defaults.set(Double.nan, forKey: "fullscreen.scale")
        defaults.set(50, forKey: "tracking.gain")
        let invalid = AppSettings(defaults: defaults)
        precondition(invalid.fullscreenScale == 0.8 && invalid.followGain == 1)
        reset.deleteSelectedPreset()
        reset.selectedPresetID = customID
        reset.deleteSelectedPreset()
        precondition(reset.savedPresets.isEmpty)
        let legacyName = name + ".legacy"
        let legacy = UserDefaults(suiteName: legacyName)!
        legacy.set(4, forKey: "tracking.unlockTolerance")
        precondition(AppSettings(defaults: legacy).unlockTolerance == 20)
        precondition(AppSettings(defaults: legacy).unlockTolerance == 20, "Migration must persist across the next launch")
        legacy.removePersistentDomain(forName: legacyName)
        print("PASS: Settings and personal presets persist, migrate, restore, delete, validate and preserve appearance.")
    }
}
