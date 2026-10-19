import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings
    let inFullscreen: Bool
    @State private var section: Int

    init(model: AppModel, settings: AppSettings, inFullscreen: Bool = false) {
        self.model = model; self.settings = settings; self.inFullscreen = inFullscreen
        _section = State(initialValue: inFullscreen ? 1 : 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image(systemName: "slider.horizontal.3").foregroundStyle(Theme.mint).font(.system(size: 22))
                VStack(alignment: .leading, spacing: 4) {
                    Text("随视设置").font(.system(size: 22, weight: .medium))
                    Text("调整你的观看方式，参数会自动保存。").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                }
                Spacer()
            }
            Picker("设置分类", selection: $section) {
                Text("头部跟随").tag(0)
                Text("画面与全屏").tag(1)
                Text("背景与引导").tag(2)
                Text("手动体验").tag(3)
            }.pickerStyle(.segmented).labelsHidden().accessibilityIdentifier("settingsSection")
            ScrollView {
                VStack(alignment: .leading, spacing: 19) {
                    if section == 0 { trackingSettings }
                    else if section == 1 { viewingSettings }
                    else if section == 2 { appearanceSettings }
                    else { manualSettings }
                }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            }.frame(height: 400).background(Theme.background, in: RoundedRectangle(cornerRadius: 12))
            HStack {
                Button("恢复默认参数", action: settings.restoreDefaults).buttonStyle(.plain).foregroundStyle(Theme.secondary)
                Spacer()
                Button("完成") { if inFullscreen { model.showingFullscreenSettings = false } else { model.showingSettings = false } }
                    .keyboardShortcut(.defaultAction).buttonStyle(.plain)
                    .padding(.horizontal, 18).padding(.vertical, 9)
                    .background(Theme.mint, in: RoundedRectangle(cornerRadius: 7)).foregroundStyle(Theme.background)
                    .accessibilityIdentifier("closeSettings")
            }.font(.system(size: 12))
        }.padding(26).frame(width: 580).background(Theme.sidebar)
            .tint(Theme.mint).preferredColorScheme(.dark)
    }

    private var trackingSettings: some View {
        Group {
            settingSlider("平滑程度", value: $settings.responseTime, range: 0.10...0.55,
                          formatted: settings.responseTime < 0.22 ? "灵敏" : settings.responseTime > 0.37 ? "柔和" : "均衡")
            settingSlider("跟随比例", value: $settings.followGain, range: 0.25...1,
                          formatted: "\(Int((settings.followGain * 100).rounded()))%", step: 0.05)
            settingSlider("最大旋转速度", value: $settings.maximumSpeed, range: 5...120,
                          formatted: "\(Int(settings.maximumSpeed))° / 秒", step: 5)
            Text("降低跟随比例可减少运动幅度；速度上限控制突然转头或重新识别人脸时的追赶速度。⇧⌘空格可冻结 / 恢复角度。")
                .font(.system(size: 11)).foregroundStyle(Theme.secondary)
            Toggle("反向跟随", isOn: $settings.reversed).disabled(model.manualMode)
            Divider()
            Toggle("稳定后自动锁定角度", isOn: $settings.autoLock).accessibilityIdentifier("autoLock")
            Text("姿势保持稳定后冻结画面；明显改变姿势时，恢复平滑跟随。")
                .font(.system(size: 11)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            Group {
                settingSlider("稳定时间", value: $settings.lockDuration, range: 1...10,
                              formatted: String(format: "%.1f 秒", settings.lockDuration), step: 0.5)
                settingSlider("稳定容差", value: $settings.stabilityTolerance, range: 0.5...3,
                              formatted: String(format: "±%.1f°", settings.stabilityTolerance), step: 0.5)
                settingSlider("恢复跟随的偏差", value: $settings.unlockTolerance, range: (settings.stabilityTolerance + 0.5)...10,
                              formatted: String(format: "±%.1f°", settings.unlockTolerance), step: 0.5)
            }.disabled(!settings.autoLock)
            Text("越过恢复阈值约 0.25 秒后解锁；识别丢失时保持画面，不累计稳定时间。")
                .font(.system(size: 10)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
        }.font(.system(size: 12)).toggleStyle(.switch).controlSize(.small)
    }

    private var viewingSettings: some View {
        Group {
            HStack {
                Text("最大旋转角度")
                Spacer()
                Picker("最大旋转角度", selection: $settings.rotationLimit) {
                    Text("±15°").tag(15.0); Text("±30°").tag(30.0); Text("±45°").tag(45.0)
                }.labelsHidden().frame(width: 170)
            }
            Divider()
            Text("全屏画面").foregroundStyle(Theme.mint)
            Picker("旋转边界", selection: $settings.boundary) {
                Text("完整显示 · 到边界停止旋转").tag(RotationBoundary.complete)
                Text("自由旋转 · 允许边角裁切").tag(RotationBoundary.crop)
            }.accessibilityIdentifier("rotationBoundary")
            settingSlider("全屏画面大小", value: $settings.fullscreenScale, range: 0.25...(settings.boundary == .complete ? 1 : max(4, settings.fullscreenScale)),
                formatted: "\(Int((settings.fullscreenScale * 100).rounded()))%", step: 0.01)
            let viewport = model.fullscreenViewport.width > 0 ? model.fullscreenViewport : (NSScreen.main?.frame.size ?? CGSize(width: 1920, height: 1080))
            let layout = model.fullscreenLayout(in: viewport)
            Text(settings.boundary == .complete ? String(format: "当前大小和位置可完整旋转约 ±%.1f°。放大或靠近边缘时，可用角度会减小。", layout.safeAngle) : "保持画面尺寸，按最大角度旋转；超出屏幕的部分会被裁切。")
                .font(.system(size: 11)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("完整适配") { settings.boundary = .complete; settings.fullscreenScale = 1; model.centerViewing() }
                Button("铺满屏幕", action: model.fillScreen)
                Button("画面居中", action: model.centerViewing)
            }.buttonStyle(.bordered)
            Text("100% 表示零度时完整适配屏幕。铺满会启用自由裁切。转头时画面不会自动缩放。按住 ⌥ 拖动移动，⌥ 双击居中；全屏中可按 ⌘, 调整设置。")
                .font(.system(size: 11)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            if model.viewingMode == .workbench {
                Button { model.enterViewing(.fullscreen) } label: { Label("进入全屏观看", systemImage: "arrow.up.left.and.arrow.down.right") }
                    .buttonStyle(.bordered).disabled(!model.hasContent)
            }
            Divider()
            Toggle("窗口内保持固定画面大小", isOn: $settings.fixedVideoSize)
            settingSlider("窗口内画面大小", value: $settings.videoScale, range: 0.4...1,
                          formatted: "\(Int((settings.videoScale * 100).rounded()))%", step: 0.05)
        }.font(.system(size: 12)).toggleStyle(.switch).controlSize(.small)
    }

    private var appearanceSettings: some View {
        Group {
            Toggle("透明背景", isOn: $settings.transparentBackground).accessibilityIdentifier("transparentBackground")
            Text("背景和引导线保持静止，视频始终不透明。透明背景下也可以单独开启引导线。")
                .font(.system(size: 11)).foregroundStyle(Theme.secondary)
            Group {
                Picker("背景类型", selection: $settings.backdrop) {
                    Text("RGB 纯色").tag(BackdropKind.color)
                    Text("自定义图片").tag(BackdropKind.image)
                }
                if settings.backdrop == .color { colorControls("背景颜色", hex: $settings.backgroundHex) }
                else {
                    HStack {
                        Button("选择背景图片…", action: model.importBackground).accessibilityIdentifier("importBackground")
                        Text(model.backgroundImage == nil ? "尚未选择图片" : "已载入本地背景图片").foregroundStyle(Theme.secondary)
                    }
                    if let error = model.backgroundError { Text(error).foregroundStyle(.orange).font(.system(size: 11)) }
                    settingSlider("背景模糊", value: $settings.backgroundBlur, range: 0...30,
                                  formatted: "\(Int(settings.backgroundBlur))", step: 1)
                    settingSlider("图片压暗", value: $settings.backgroundDim, range: 0...1,
                                  formatted: "\(Int((settings.backgroundDim * 100).rounded()))%", step: 0.05)
                }
                settingSlider("背景不透明度", value: $settings.backgroundOpacity, range: 0...1,
                              formatted: "\(Int((settings.backgroundOpacity * 100).rounded()))%", step: 0.05)
            }.disabled(settings.transparentBackground)
            Divider()
            Toggle("显示引导线", isOn: $settings.guides).accessibilityIdentifier("showGuides")
            Group {
                Picker("引导线样式", selection: $settings.guideStyle) {
                    Text("水平线").tag(GuideStyle.horizontal); Text("十字线").tag(GuideStyle.cross)
                    Text("井字线").tag(GuideStyle.thirds); Text("正方形").tag(GuideStyle.square)
                    Text("长方形").tag(GuideStyle.rectangle)
                }.accessibilityIdentifier("guideStyle")
                colorControls("引导线颜色", hex: $settings.guideHex)
                settingSlider("引导线不透明度", value: $settings.guideOpacity, range: 0...1,
                              formatted: "\(Int((settings.guideOpacity * 100).rounded()))%", step: 0.05)
                settingSlider("引导线粗细", value: $settings.guideWidth, range: 0.5...4,
                              formatted: String(format: "%.1f 点", settings.guideWidth), step: 0.5)
                Toggle("仅在视频周围显示", isOn: $settings.guideOutsideOnly)
            }.disabled(!settings.guides)
        }.font(.system(size: 12)).toggleStyle(.switch).controlSize(.small)
    }

    private func colorControls(_ title: String, hex: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ColorPicker(title, selection: Binding(get: { ScreenColor.color(hex.wrappedValue) },
                set: { hex.wrappedValue = ScreenColor.hex($0) }), supportsOpacity: false)
            HStack {
                ForEach(0..<3) { index in
                    Text(["R", "G", "B"][index]).foregroundStyle(Theme.secondary)
                    TextField(title + [" R", " G", " B"][index], value: Binding<Int>(
                        get: { ScreenColor.components(hex.wrappedValue)[index] },
                        set: { value in
                            var c = ScreenColor.components(hex.wrappedValue); c[index] = min(255, max(0, value))
                            hex.wrappedValue = String(format: "%02X%02X%02X", c[0], c[1], c[2])
                        }), format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder).frame(width: 64)
                }
                Spacer()
            }
        }
    }

    private var manualSettings: some View {
        Group {
            Toggle("手动角度体验", isOn: Binding(get: { model.manualMode }, set: model.setManualMode))
                .accessibilityIdentifier("manualMode")
            Text("开启后关闭摄像头，用滑杆体验旋转。关闭后可重新开启摄像头。")
                .font(.system(size: 11)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            settingSlider("手动角度", value: Binding(get: { model.manualAngle }, set: model.setManualAngle),
                          range: -settings.rotationLimit...settings.rotationLimit,
                          formatted: String(format: "%+.1f°", model.manualAngle))
                .disabled(!model.manualMode)
            HStack(spacing: 20) {
                Button("−\(Int(min(30, settings.rotationLimit)))°") { model.setManualAngle(-min(30, settings.rotationLimit)) }
                Button("0°") { model.setManualAngle(0) }
                Button("+\(Int(min(30, settings.rotationLimit)))°") { model.setManualAngle(min(30, settings.rotationLimit)) }
            }.buttonStyle(.bordered).disabled(!model.manualMode)
        }.font(.system(size: 12)).toggleStyle(.switch).controlSize(.small)
    }

    private func settingSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, formatted: String, step: Double? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Text(title); Spacer(); Text(formatted).monospacedDigit().foregroundStyle(Theme.mint) }
            if let step { Slider(value: value, in: range, step: step).accessibilityLabel(title) }
            else { Slider(value: value, in: range).accessibilityLabel(title) }
        }
    }
}
