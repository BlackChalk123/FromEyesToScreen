import SwiftUI
import AppKit

enum ScreenColor {
    static func components(_ hex: String) -> [Int] {
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return [0, 0, 0] }
        return [Int((value >> 16) & 255), Int((value >> 8) & 255), Int(value & 255)]
    }
    static func color(_ hex: String) -> Color {
        let c = components(hex)
        return Color(.sRGB, red: Double(c[0]) / 255, green: Double(c[1]) / 255, blue: Double(c[2]) / 255, opacity: 1)
    }
    static func hex(_ color: Color) -> String {
        let c = NSColor(color).usingColorSpace(.sRGB) ?? .black
        return String(format: "%02X%02X%02X", min(255, max(0, Int((c.redComponent * 255).rounded()))),
                      min(255, max(0, Int((c.greenComponent * 255).rounded()))), min(255, max(0, Int((c.blueComponent * 255).rounded()))))
    }
}

struct FullscreenBackdrop: View {
    @ObservedObject var model: AppModel
    let size: CGSize
    var body: some View {
        if !model.settings.transparentBackground {
            ZStack {
                ScreenColor.color(model.settings.backgroundHex)
                if model.settings.backdrop == .image, let image = model.backgroundImage {
                    Image(nsImage: image).resizable().scaledToFill()
                        .frame(width: size.width, height: size.height).clipped()
                        .blur(radius: model.settings.backgroundBlur)
                        .overlay(Color.black.opacity(model.settings.backgroundDim))
                }
            }.frame(width: size.width, height: size.height)
                .opacity(model.settings.backgroundOpacity).allowsHitTesting(false)
        }
    }
}

/// One configurable square grid. Preserve the existing video-axis attachment;
/// users may also choose a fixed screen reference.
struct ReferenceGuides: View {
    @ObservedObject var settings: AppSettings
    var videoCenter: CGPoint
    var videoSize: CGSize
    var angle: Double
    var body: some View {
        Canvas { context, size in
            let radians = (settings.gridFollowsVideo ? angle : 0) * .pi / 180
            let origin = settings.gridFollowsVideo ? videoCenter : CGPoint(x: size.width / 2, y: size.height / 2)
            let ux = CGPoint(x: cos(radians), y: sin(radians))
            let uy = CGPoint(x: -sin(radians), y: cos(radians))
            let reach = hypot(size.width, size.height) * 2
            let spacing = max(24, min(180, settings.gridSpacing))
            let count = Int(ceil(reach / spacing))
            var path = Path()
            func line(_ point: CGPoint, _ direction: CGPoint) {
                path.move(to: CGPoint(x: point.x - direction.x * reach, y: point.y - direction.y * reach))
                path.addLine(to: CGPoint(x: point.x + direction.x * reach, y: point.y + direction.y * reach))
            }
            for index in -count...count {
                let offset = CGFloat(index) * spacing
                line(CGPoint(x: origin.x + uy.x * offset, y: origin.y + uy.y * offset), ux)
                line(CGPoint(x: origin.x + ux.x * offset, y: origin.y + ux.y * offset), uy)
            }
            context.stroke(path, with: .color(ScreenColor.color(settings.guideHex).opacity(settings.guideOpacity)),
                           style: StrokeStyle(lineWidth: settings.guideWidth))
        }
    }
}

struct EdgeMotionCues: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Canvas { context, size in
            let count = Int(model.settings.cueCount.rounded())
            let radius = CGFloat(model.settings.cueSize)
            let rx = max(0, size.width / 2 - 18 - radius)
            let ry = max(0, size.height / 2 - 18 - radius)
            for index in 0..<max(8, min(40, count)) {
                let angle = (Double(index) / Double(max(8, min(40, count))) * 360 + model.cuePhase) * .pi / 180
                let c = cos(angle), s = sin(angle)
                // A smooth rectangular ring keeps the cues near the screen edges.
                let x = size.width / 2 + rx * CGFloat((c < 0 ? -1.0 : 1.0) * pow(abs(c), 0.25))
                let y = size.height / 2 + ry * CGFloat((s < 0 ? -1.0 : 1.0) * pow(abs(s), 0.25))
                context.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                    with: .color(ScreenColor.color(model.settings.guideHex).opacity(model.settings.cueOpacity)))
            }
        }.opacity(1 - model.veilOpacity).allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct SoftCurtain: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Color.black.opacity(model.veilOpacity).allowsHitTesting(false).accessibilityHidden(true)
    }
}
