import AppKit
import SwiftUI

// Existing grayscale tokens. The collapsed ball is the only persistent app control;
// one primary follow action lives in the expanded panel. No screen-sized hit-test backdrop.
struct FloatingOrb: View {
    @ObservedObject var app: AppCoordinator
    @ObservedObject var controller: ViewingWindowController
    @State private var hovering = false
    var body: some View {
        ZStack {
            Circle().fill(UI.raised)
            Circle().strokeBorder(UI.border, lineWidth: 1)
            Image(systemName: app.following ? "viewfinder.circle" : "viewfinder")
                .font(.system(size: 24, weight: .semibold)).foregroundStyle(UI.ink)
        }.frame(width: 64, height: 64)
            .opacity(hovering || app.showingSettings || controller.dragging ? 1 : 0.45)
            .animation(.easeInOut(duration: 0.22), value: hovering || app.showingSettings || controller.dragging)
            .overlay {
                OrbHitTarget(onHover: { hovering = $0 },
                             onDown: { controller.beginDragging(at: $0) },
                             onDrag: { controller.drag(to: $0) },
                             onUp: { moved in controller.endDragging(); if !moved { controller.toggleControls() } },
                             onPress: { controller.toggleControls() })
            }.padding(4).background(Color.clear)
    }
}

private struct OrbHitTarget: NSViewRepresentable {
    let onHover: (Bool) -> Void
    let onDown: (CGPoint) -> Void
    let onDrag: (CGPoint) -> Void
    let onUp: (Bool) -> Void
    let onPress: () -> Void
    final class HitView: NSView {
        var onHover: ((Bool) -> Void)?
        var onDown: ((CGPoint) -> Void)?
        var onDrag: ((CGPoint) -> Void)?
        var onUp: ((Bool) -> Void)?
        var onPress: (() -> Void)?
        private var area: NSTrackingArea?
        private var start = CGPoint.zero
        private var moved = false
        override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric) }
        override var fittingSize: NSSize { .zero }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let area { removeTrackingArea(area) }
            let area = NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect], owner: self)
            addTrackingArea(area); self.area = area
        }
        override func mouseEntered(with event: NSEvent) { onHover?(true) }
        override func mouseExited(with event: NSEvent) { onHover?(false) }
        override func mouseDown(with event: NSEvent) { start = NSEvent.mouseLocation; moved = false; onDown?(start) }
        override func mouseDragged(with event: NSEvent) {
            let point = NSEvent.mouseLocation
            if hypot(point.x - start.x, point.y - start.y) > 4 { moved = true }
            if moved { onDrag?(point) }
        }
        override func mouseUp(with event: NSEvent) { onUp?(moved) }
        override func accessibilityPerformPress() -> Bool { onPress?(); return true }
    }
    func makeNSView(context: Context) -> HitView {
        let view = HitView()
        view.setAccessibilityElement(true); view.setAccessibilityRole(.button)
        view.setAccessibilityLabel("随视悬浮球")
        view.setAccessibilityIdentifier("viewingOrb")
        view.setAccessibilityHelp("点击打开全部观看控制；按住可独立拖动悬浮球，不移动视频。")
        return view
    }
    func updateNSView(_ view: HitView, context: Context) {
        view.onHover = onHover; view.onDown = onDown; view.onDrag = onDrag; view.onUp = onUp; view.onPress = onPress
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: HitView, context: Context) -> CGSize? { CGSize(width: 64, height: 64) }
}

struct OrbControls: View {
    @ObservedObject var app: AppCoordinator
    @ObservedObject var preferences: Preferences
    @ObservedObject var player: BilibiliPage
    @ObservedObject var controller: ViewingWindowController
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(player.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                        Text("\(app.trackingMessage) · \(String(format: "%+.1f°", app.statusAngle))")
                            .font(.system(size: 12)).foregroundStyle(UI.secondary).accessibilityIdentifier("trackingStatus")
                    }
                    Spacer(minLength: 0)
                    ToolButton(title: "收起控制", symbol: "xmark") { app.showingSettings = false }.accessibilityIdentifier("closeSettings")
                }
                HStack(spacing: 8) {
                    Button { app.toggleFollowing() } label: { Label(app.following ? "暂停头部跟随" : "开启头部跟随", systemImage: app.following ? "pause" : "faceid") }
                        .buttonStyle(ActionStyle(primary: true)).accessibilityIdentifier("toggleFollowing")
                    Button { app.calibrate() } label: { Label("校准", systemImage: "scope") }.buttonStyle(ActionStyle()).disabled(!app.canCalibrate)
                }
                HStack(spacing: 8) {
                    ToolButton(title: player.paused ? "播放" : "暂停", symbol: player.paused ? "play" : "pause") { player.togglePlayback() }
                    ToolButton(title: "重新加载视频", symbol: "arrow.clockwise") { player.reload() }
                    ToolButton(title: "井字引导线", symbol: "grid", selected: preferences.value.guides) { app.toggleGuides() }
                    ToolButton(title: controller.isScreenFilled ? "恢复画面大小" : "画面适配显示器（100%）", symbol: "arrow.up.left.and.arrow.down.right") { controller.toggleFullScreen() }
                    Spacer(minLength: 0)
                    Button("返回选片") { app.showBrowser() }.font(.system(size: 12)).buttonStyle(.plain).accessibilityIdentifier("returnToBrowse")
                }
                Menu {
                    ForEach(Array(controller.availableScreens.enumerated()), id: \.offset) { _, screen in
                        Button(screen.localizedName) { controller.move(to: screen) }
                    }
                } label: {
                    Label("视频显示器 · \(controller.window?.screen?.localizedName ?? "当前屏幕")", systemImage: "display")
                        .font(.system(size: 12))
                }.menuStyle(.borderlessButton).accessibilityIdentifier("chooseDisplay")
                Text(app.notice ?? (app.atBoundary ? "已到完整显示边界，缩小画面可继续转动。" : "悬浮球可独立拖动；按住 ⌥ 拖动视频可调整位置。"))
                    .font(.system(size: 12)).foregroundStyle(UI.secondary).fixedSize(horizontal: false, vertical: true)
            }.padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 16)
            Divider()
            SettingsPanel(app: app, preferences: preferences, embedded: true)
        }.frame(width: 360).foregroundStyle(UI.ink).background(UI.surface).preferredColorScheme(.light)
            .onExitCommand { app.showingSettings = false }
    }
}
