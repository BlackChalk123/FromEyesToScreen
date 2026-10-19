import SwiftUI
import MotionCore

struct ViewingSurface: View {
    @ObservedObject var model: AppModel
    let container: CGSize
    var alwaysFixed = false
    var border = true
    var explicitSize: CGSize?
    var explicitAngle: Double?
    var body: some View {
        let fixed = alwaysFixed || model.settings.fixedVideoSize
        let base = fixed ? MotionGeometry.constantSize(aspect: model.videoAspect, maximumAngle: model.settings.rotationLimit, container: container)
            : MotionGeometry.fittedSize(aspect: model.videoAspect, angle: model.displayAngle, container: container)
        let size = explicitSize ?? CGSize(width: base.width * model.settings.videoScale, height: base.height * model.settings.videoScale)
        Group {
            if model.isBilibili {
                BilibiliSurface(controller: model.webPlayer,
                    active: alwaysFixed ? model.viewingMode != .workbench : model.viewingMode == .workbench)
                    .frame(width: 960, height: 540).scaleEffect(size.width / 960)
            } else { VideoSurface(player: model.player) }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: alwaysFixed ? 0 : 5))
        .overlay(RoundedRectangle(cornerRadius: alwaysFixed ? 0 : 5).stroke(Color.white.opacity(border ? 0.15 : 0), lineWidth: 1))
        .rotationEffect(.degrees(explicitAngle ?? model.displayAngle))
    }
}

struct PresentationView: View {
    @ObservedObject var model: AppModel
    let topInset: CGFloat
    var body: some View {
        GeometryReader { geo in
            let layout = model.fullscreenLayout(in: geo.size)
            let angle = layout.angle(model.displayAngle)
            ZStack {
                FullscreenBackdrop(model: model, size: geo.size)
                ViewingSurface(model: model, container: geo.size, alwaysFixed: true, border: false,
                    explicitSize: layout.videoSize, explicitAngle: angle)
                    .position(layout.center)
                if model.settings.guides {
                    ReferenceGuides(settings: model.settings)
                        .mask {
                            ZStack {
                                Color.white
                                if model.settings.guideOutsideOnly {
                                    Rectangle().frame(width: layout.videoSize.width, height: layout.videoSize.height)
                                        .rotationEffect(.degrees(angle)).position(layout.center).blendMode(.destinationOut)
                                }
                            }.compositingGroup()
                        }.allowsHitTesting(false).accessibilityHidden(true)
                }
                VStack {
                    HStack {
                        Spacer()
                        Button(action: model.leaveViewing) {
                            Label("退出全屏 · Esc", systemImage: "xmark")
                                .font(.system(size: 12, weight: .medium)).padding(.horizontal, 15).padding(.vertical, 10)
                                .foregroundStyle(Color.white).background(Color.black.opacity(0.75), in: Capsule())
                                .overlay(Capsule().stroke(Color.white.opacity(0.2)))
                        }.buttonStyle(.plain).accessibilityIdentifier("exitViewingMode")
                            .help("⌘, 全屏设置；⌥ 拖动移动画面，⌥ 双击居中。右键查看更多操作。")
                            .contextMenu {
                                Button("全屏设置…", action: model.openSettings)
                                Toggle("透明背景", isOn: Binding(get: { model.settings.transparentBackground }, set: { model.settings.transparentBackground = $0 }))
                                Toggle("显示引导线", isOn: Binding(get: { model.settings.guides }, set: { model.settings.guides = $0 }))
                                Divider()
                                Button(model.following ? "冻结当前角度" : "恢复跟随") { model.following.toggle() }
                                    .disabled(model.manualMode)
                                Button("画面居中", action: model.centerViewing)
                                Button("完整适配屏幕") { model.settings.boundary = .complete; model.settings.fullscreenScale = 1; model.centerViewing() }
                                Button("铺满屏幕（允许裁切）", action: model.fillScreen)
                            }
                    }.padding(.top, topInset).padding(.horizontal, 24)
                    Spacer()
                }
            }.frame(width: geo.size.width, height: geo.size.height).clipped()
                .onAppear { model.fullscreenViewport = geo.size }
                .onChange(of: geo.size) { _, size in model.fullscreenViewport = size }
        }.background(Color.clear).ignoresSafeArea().preferredColorScheme(.dark)
            .sheet(isPresented: $model.showingFullscreenSettings) {
                SettingsView(model: model, settings: model.settings, inFullscreen: true)
            }
    }
}
