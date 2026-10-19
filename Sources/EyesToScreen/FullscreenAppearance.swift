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

struct ReferenceGuides: View {
    @ObservedObject var settings: AppSettings
    var body: some View {
        Canvas { context, size in
            var path = Path()
            func horizontal(_ fraction: CGFloat) {
                path.move(to: CGPoint(x: 0, y: size.height * fraction))
                path.addLine(to: CGPoint(x: size.width, y: size.height * fraction))
            }
            func vertical(_ fraction: CGFloat) {
                path.move(to: CGPoint(x: size.width * fraction, y: 0))
                path.addLine(to: CGPoint(x: size.width * fraction, y: size.height))
            }
            switch settings.guideStyle {
            case .horizontal: horizontal(0.5)
            case .cross: horizontal(0.5); vertical(0.5)
            case .thirds: horizontal(1/3); horizontal(2/3); vertical(1/3); vertical(2/3)
            case .square:
                let side = min(size.width, size.height) * 0.65
                path.addRect(CGRect(x: (size.width - side) / 2, y: (size.height - side) / 2, width: side, height: side))
            case .rectangle:
                path.addRect(CGRect(x: size.width * 0.15, y: size.height * 0.18, width: size.width * 0.7, height: size.height * 0.64))
            }
            context.stroke(path, with: .color(ScreenColor.color(settings.guideHex).opacity(settings.guideOpacity)),
                           style: StrokeStyle(lineWidth: settings.guideWidth))
        }
    }
}
