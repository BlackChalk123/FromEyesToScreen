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

/// Composition guides locked to the video frame: they use the video's own axes
/// as horizontal/vertical, so they rotate and move exactly with the video.
struct ReferenceGuides: View {
    @ObservedObject var settings: AppSettings
    /// Video center in screen coordinates.
    var videoCenter: CGPoint
    /// Video size at zero rotation.
    var videoSize: CGSize
    /// Rotation applied to the video, in degrees.
    var angle: Double

    var body: some View {
        Canvas { context, size in
            let radians = angle * .pi / 180
            // Unit vectors of the video's local axes in screen space.
            let ux = CGPoint(x: cos(radians), y: sin(radians))
            let uy = CGPoint(x: -sin(radians), y: cos(radians))
            // Lines extend well past the screen so rotation never shortens them.
            let reach = hypot(size.width, size.height) * 2
            var path = Path()
            func through(_ point: CGPoint, along direction: CGPoint) {
                path.move(to: CGPoint(x: point.x - direction.x * reach, y: point.y - direction.y * reach))
                path.addLine(to: CGPoint(x: point.x + direction.x * reach, y: point.y + direction.y * reach))
            }
            // A guide parallel to the video's horizontal axis, offset along the video's vertical axis.
            func horizontal(_ offset: CGFloat) {
                through(CGPoint(x: videoCenter.x + uy.x * offset, y: videoCenter.y + uy.y * offset), along: ux)
            }
            // A guide parallel to the video's vertical axis, offset along the video's horizontal axis.
            func vertical(_ offset: CGFloat) {
                through(CGPoint(x: videoCenter.x + ux.x * offset, y: videoCenter.y + ux.y * offset), along: uy)
            }
            func rect(width: CGFloat, height: CGFloat) {
                let hx = width / 2
                let hy = height / 2
                let offsets: [(CGFloat, CGFloat)] = [(hx, hy), (-hx, hy), (-hx, -hy), (hx, -hy)]
                var corners: [CGPoint] = []
                for (dx, dy) in offsets {
                    let x = videoCenter.x + ux.x * dx + uy.x * dy
                    let y = videoCenter.y + ux.y * dx + uy.y * dy
                    corners.append(CGPoint(x: x, y: y))
                }
                path.move(to: corners[0])
                path.addLine(to: corners[1])
                path.addLine(to: corners[2])
                path.addLine(to: corners[3])
                path.closeSubpath()
            }
            switch settings.guideStyle {
            case .horizontal: horizontal(0)
            case .cross: horizontal(0); vertical(0)
            case .thirds:
                horizontal(-videoSize.height / 6); horizontal(videoSize.height / 6)
                vertical(-videoSize.width / 6); vertical(videoSize.width / 6)
            case .square:
                rect(width: min(videoSize.width, videoSize.height) * 0.65,
                     height: min(videoSize.width, videoSize.height) * 0.65)
            case .rectangle:
                rect(width: videoSize.width * 0.7, height: videoSize.height * 0.64)
            }
            context.stroke(path, with: .color(ScreenColor.color(settings.guideHex).opacity(settings.guideOpacity)),
                           style: StrokeStyle(lineWidth: settings.guideWidth))
        }
    }
}
