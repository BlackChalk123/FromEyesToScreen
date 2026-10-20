import Foundation
import Combine
import RotationCore

struct ViewingPreferences: Codable, Equatable {
    var scale = 0.6
    var crop = false
    var response: FollowResponse = .balanced
    var offset = 0.0
    var guides = false
    var guideOpacity = 0.24

    mutating func sanitize() {
        scale = scale.isFinite ? min(1, max(0.35, scale)) : 0.6
        offset = offset.isFinite ? min(5, max(-5, offset)) : 0
        guideOpacity = guideOpacity.isFinite ? min(0.6, max(0.1, guideOpacity)) : 0.24
    }
}

@MainActor final class Preferences: ObservableObject {
    @Published var value: ViewingPreferences { didSet { save() } }
    private let defaults: UserDefaults
    private let key = "viewing.v1"
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var loaded = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(ViewingPreferences.self, from: $0) } ?? ViewingPreferences()
        loaded.sanitize()
        value = loaded
    }
    private func save() {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }
    func reset() { value = ViewingPreferences() }
}
