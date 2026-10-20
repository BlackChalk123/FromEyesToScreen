import SwiftUI

// Native translation of prototypes/suishi-v1/design-tokens.json.
// Primary: content / follow action. Secondary: navigation and calibration.
// Tertiary: guides/settings. Grayscale; type 12/14/16/18/20/24, spacing 4/8/12/16/24/32.
enum UI {
    static let surface = Color(white: 250.0 / 255)
    static let raised = Color(white: 253.0 / 255)
    static let sunken = Color(white: 241.0 / 255)
    static let ink = Color(white: 24.0 / 255)
    static let secondary = Color(white: 85.0 / 255)
    static let muted = Color(white: 106.0 / 255)
    static let border = Color(white: 219.0 / 255)
}

struct ActionStyle: ButtonStyle {
    var primary = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 14, weight: .semibold))
            .padding(.horizontal, 16).frame(height: 40)
            .foregroundStyle(primary ? UI.surface : UI.ink)
            .background(primary ? (configuration.isPressed ? UI.secondary : UI.ink) : (configuration.isPressed ? UI.border : UI.sunken), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct ToolButton: View {
    let title: String
    let symbol: String
    var selected = false
    var action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 16)).frame(width: 40, height: 40) }
            .buttonStyle(.plain).foregroundStyle(UI.ink)
            .background(selected ? UI.sunken : .clear, in: RoundedRectangle(cornerRadius: 8))
            .help(title).accessibilityLabel(title)
    }
}

struct MessageCard: View {
    let title: String
    let message: String
    let actionTitle: String
    let action: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 24)).foregroundStyle(UI.secondary)
            Text(title).font(.system(size: 18, weight: .semibold))
            Text(message).font(.system(size: 14)).foregroundStyle(UI.secondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            Button(actionTitle, action: action).buttonStyle(ActionStyle())
        }.padding(24).frame(maxWidth: 360).background(UI.raised, in: RoundedRectangle(cornerRadius: 16)).foregroundStyle(UI.ink)
    }
}

func playbackTime(_ seconds: Double) -> String {
    let value = seconds.isFinite ? Int(max(0, min(seconds, 31_536_000))) : 0
    return value >= 3600 ? String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60) : String(format: "%02d:%02d", value / 60, value % 60)
}
