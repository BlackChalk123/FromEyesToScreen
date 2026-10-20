import Foundation

struct SavedViewingPreset: Codable, Identifiable {
    var id: String
    var name: String
    var numbers: [String: Double]
    var switches: [String: Bool]
    var strings: [String: String]
}

extension AppSettings {
    private static var numbers: [(String, ReferenceWritableKeyPath<AppSettings, Double>, ClosedRange<Double>)] {
        [
            ("responseTime", \.responseTime, 0.1...0.55),
            ("lockDuration", \.lockDuration, 1...10),
            ("stabilityTolerance", \.stabilityTolerance, 0.5...3),
            ("unlockTolerance", \.unlockTolerance, 1...60),
            ("rotationLimit", \.rotationLimit, 15...90),
            ("videoScale", \.videoScale, 0.4...1),
            ("fullscreenScale", \.fullscreenScale, 0.25...16),
            ("backgroundOpacity", \.backgroundOpacity, 0...1),
            ("backgroundBlur", \.backgroundBlur, 0...30),
            ("backgroundDim", \.backgroundDim, 0...1),
            ("gridSpacing", \.gridSpacing, 24...180),
            ("guideOpacity", \.guideOpacity, 0...1),
            ("guideWidth", \.guideWidth, 0.5...4),
            ("followGain", \.followGain, 0.25...1),
            ("maximumSpeed", \.maximumSpeed, 5...120),
            ("unlockDuration", \.unlockDuration, 0.1...2),
            ("compensationThreshold", \.compensationThreshold, 0...60),
            ("compensationLeft", \.compensationLeft, 0...15),
            ("compensationRight", \.compensationRight, 0...15),
            ("compensationBlend", \.compensationBlend, 1...40),
            ("curtainThreshold", \.curtainThreshold, 2...45),
            ("curtainConfirmation", \.curtainConfirmation, 0.05...0.6),
            ("curtainFadeOut", \.curtainFadeOut, 0.05...0.3),
            ("curtainCovered", \.curtainCovered, 0.02...0.3),
            ("curtainFadeIn", \.curtainFadeIn, 0.05...0.4),
            ("curtainInterval", \.curtainInterval, 0.5...5),
            ("cueStrength", \.cueStrength, 0...2),
            ("cueMaximumSpeed", \.cueMaximumSpeed, 5...180),
            ("cueCount", \.cueCount, 8...40),
            ("cueOpacity", \.cueOpacity, 0.05...1),
            ("cueSize", \.cueSize, 2...8)
        ]
    }
    private static var switches: [(String, ReferenceWritableKeyPath<AppSettings, Bool>)] {
        [
            ("reversed", \.reversed),
            ("autoLock", \.autoLock),
            ("fixedVideoSize", \.fixedVideoSize),
            ("transparentBackground", \.transparentBackground),
            ("guides", \.guides),
            ("guideOutsideOnly", \.guideOutsideOnly),
            ("gridFollowsVideo", \.gridFollowsVideo),
            ("gridFadeOnMotion", \.gridFadeOnMotion),
            ("manualUnlockOnly", \.manualUnlockOnly),
            ("compensationEnabled", \.compensationEnabled),
            ("curtainEnabled", \.curtainEnabled),
            ("cuesEnabled", \.cuesEnabled)
        ]
    }
    private static var strings: [(String, ReferenceWritableKeyPath<AppSettings, String>)] {
        [
            ("backgroundHex", \.backgroundHex),
            ("backgroundImagePath", \.backgroundImagePath),
            ("guideHex", \.guideHex)
        ]
    }

    var presetTitle: String {
        savedPresets.first(where: { $0.id == selectedPresetID })?.name ?? viewingStyle.title
    }

    @discardableResult
    func savePreset(name: String) -> Bool {
        let name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        guard !name.isEmpty, savedPresets.count < 20 else { return false }
        var text = Dictionary(uniqueKeysWithValues: Self.strings.map { ($0.0, self[keyPath: $0.1]) })
        text["style"] = viewingStyle.rawValue; text["boundary"] = boundary.rawValue; text["backdrop"] = backdrop.rawValue
        let preset = SavedViewingPreset(id: "saved-" + UUID().uuidString, name: name,
            numbers: Dictionary(uniqueKeysWithValues: Self.numbers.map { ($0.0, self[keyPath: $0.1]) }),
            switches: Dictionary(uniqueKeysWithValues: Self.switches.map { ($0.0, self[keyPath: $0.1]) }), strings: text)
        savedPresets.append(preset)
        selectedPresetID = preset.id
        return true
    }

    func applyPreset(id: String) {
        if let style = ViewingStyle(rawValue: id) { applyBuiltIn(style); return }
        guard let preset = savedPresets.first(where: { $0.id == id }) else { return }
        viewingStyle = ViewingStyle(rawValue: preset.strings["style"] ?? "") ?? .pose
        boundary = RotationBoundary(rawValue: preset.strings["boundary"] ?? "") ?? .complete
        backdrop = BackdropKind(rawValue: preset.strings["backdrop"] ?? "") ?? .color
        for (name, path, range) in Self.numbers {
            if let value = preset.numbers[name], value.isFinite { self[keyPath: path] = min(range.upperBound, max(range.lowerBound, value)) }
        }
        for (name, path) in Self.switches { if let value = preset.switches[name] { self[keyPath: path] = value } }
        for (name, path) in Self.strings { if let value = preset.strings[name] { self[keyPath: path] = value } }
        if boundary == .complete && fullscreenScale > 1 { fullscreenScale = 1 }
        unlockTolerance = max(stabilityTolerance + 0.5, unlockTolerance)
        selectedPresetID = preset.id
    }

    func deleteSelectedPreset() {
        let id = selectedPresetID
        savedPresets.removeAll { $0.id == id }
        selectedPresetID = viewingStyle.rawValue
    }

    func applyBuiltIn(_ style: ViewingStyle) {
        viewingStyle = style
        responseTime = style == .pose ? 0.24 : 0.3
        autoLock = style == .pose; manualUnlockOnly = false
        lockDuration = 4; stabilityTolerance = 1.5; unlockTolerance = 20; unlockDuration = 0.45
        followGain = style == .pose ? 1 : 0.65; maximumSpeed = 30
        compensationEnabled = true; compensationThreshold = 15
        compensationLeft = 4; compensationRight = 4; compensationBlend = 15
        curtainEnabled = style == .pose; curtainThreshold = 8; curtainConfirmation = 0.18
        curtainFadeOut = 0.1; curtainCovered = 0.08; curtainFadeIn = 0.15; curtainInterval = 1.5
        cuesEnabled = false; cueStrength = 0.5; cueMaximumSpeed = 60; cueCount = 20; cueOpacity = 0.3; cueSize = 3
        selectedPresetID = style.rawValue
    }
}
