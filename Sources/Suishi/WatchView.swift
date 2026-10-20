import SwiftUI
import RotationCore

struct WatchView<Content: ViewingContent>: View {
    @ObservedObject var app: AppCoordinator
    @ObservedObject var preferences: Preferences
    @ObservedObject var player: Content
    var body: some View {
        GeometryReader { geo in
            let layout = ViewingLayout(viewport: geo.size, aspect: player.aspect, scale: preferences.value.scale,
                                       position: app.position, crop: preferences.value.crop)
            ZStack {
                RotatingPicture(player: player, rotation: app.rotation, layout: layout,
                                guides: preferences.value.guides, opacity: preferences.value.guideOpacity)
                if player.loading {
                    HStack(spacing: 12) { ProgressView().controlSize(.small); Text("正在加载观看内容…").font(.system(size: 14)) }
                        .padding(16).background(UI.raised, in: RoundedRectangle(cornerRadius: 12))
                }
                if let error = player.failure {
                    MessageCard(title: "视频加载失败", message: error, actionTitle: "重新加载") { player.reload() }
                } else if let error = app.cameraError {
                    MessageCard(title: "摄像头不可用", message: error, actionTitle: "重试头部跟随") { app.toggleFollowing() }
                }

            }.frame(width: geo.size.width, height: geo.size.height).clipped()
                .onAppear { app.viewport = geo.size }
                .onChange(of: geo.size) { _, size in app.viewport = size; app.tick() }
        }.background(Color.clear).foregroundStyle(UI.ink).preferredColorScheme(.light)
    }

}

private struct RotatingPicture<Content: ViewingContent>: View {
    let player: Content
    @ObservedObject var rotation: RotationPresentation
    let layout: ViewingLayout
    let guides: Bool
    let opacity: Double
    var body: some View {
        ZStack {
            player.surface(size: layout.size)
                .rotationEffect(.degrees(rotation.angle)).position(layout.center)
            if guides {
                GuideLines(layout: layout, angle: rotation.angle, opacity: opacity)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        }
    }
}

private struct GuideLines: View {
    let layout: ViewingLayout
    let angle: Double
    let opacity: Double
    var body: some View {
        Canvas { context, size in
            var mask = Path(CGRect(origin: .zero, size: size))
            let radians = angle * .pi / 180
            let corners = [CGPoint(x: -1, y: -1), CGPoint(x: 1, y: -1), CGPoint(x: 1, y: 1), CGPoint(x: -1, y: 1)]
            var hole = Path()
            for (index, point) in corners.enumerated() {
                let x = point.x * layout.size.width / 2, y = point.y * layout.size.height / 2
                let point = CGPoint(x: layout.center.x + x * cos(radians) - y * sin(radians),
                                    y: layout.center.y + x * sin(radians) + y * cos(radians))
                if index == 0 { hole.move(to: point) } else { hole.addLine(to: point) }
            }
            hole.closeSubpath(); mask.addPath(hole)
            context.clip(to: mask, style: FillStyle(eoFill: true))
            var lines = Path()
            for fraction in [1.0 / 3, 2.0 / 3] {
                lines.move(to: CGPoint(x: size.width * fraction, y: 0)); lines.addLine(to: CGPoint(x: size.width * fraction, y: size.height))
                lines.move(to: CGPoint(x: 0, y: size.height * fraction)); lines.addLine(to: CGPoint(x: size.width, y: size.height * fraction))
            }
            context.stroke(lines, with: .color(UI.secondary.opacity(opacity)), lineWidth: 1)
        }
    }
}
