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
        settings.guides = true; settings.guideStyle = .thirds; settings.guideHex = "ABCDEF"
        settings.guideWidth = 2; settings.guideOpacity = 0.25; settings.guideOutsideOnly = false
        settings.followGain = 0.5; settings.maximumSpeed = 20
        let restored = AppSettings(defaults: defaults)
        precondition(restored.boundary == .crop && restored.fullscreenScale == 3.2 && restored.transparentBackground)
        precondition(restored.backdrop == .image && restored.backgroundHex == "123ABC" && restored.backgroundOpacity == 0.35)
        precondition(restored.backgroundImagePath == "/fixture/image.png" && restored.backgroundBlur == 12 && restored.backgroundDim == 0.4)
        precondition(restored.guides && restored.guideStyle == .thirds && restored.guideHex == "ABCDEF")
        precondition(restored.guideWidth == 2 && restored.guideOpacity == 0.25 && !restored.guideOutsideOnly)
        precondition(restored.followGain == 0.5 && restored.maximumSpeed == 20)
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
        print("PASS: Fullscreen, background, guide and comfort preferences persist, reset and validate correctly.")
    }
}
