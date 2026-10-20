import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings
    let inFullscreen: Bool
    @State private var section: Int
    @State private var presetName = ""
    @State private var presetMessage = ""

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
                    Text("当前参数自动保存；可另存为个人观看预设。").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                }
                Spacer()
            }
            Picker("设置分类", selection: $section) {
                Text("头部跟随").tag(0)
                Text("画面与全屏").tag(1)
                Text("背景与网格").tag(2)
                Text("补偿与遮幕").tag(4)
                Text("手动体验").tag(3)
            }.pickerStyle(.segmented).labelsHidden().accessibilityIdentifier("settingsSection")
            ScrollView {
                VStack(alignment: .leading, spacing: 19) {
                    if section == 0 { trackingSettings }
                    else if section == 1 { viewingSettings }
                    else if section == 2 { appearanceSettings }
                    else if section == 4 { comfortSettings }
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
            presetControls
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
            Text("定姿预设默认锁定后保持，需大幅持续偏转或手动解锁；连续预设默认关闭自动锁定。")
                .font(.system(size: 11)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            Group {
                settingSlider("稳定时间", value: $settings.lockDuration, range: 1...10,
                              formatted: String(format: "%.1f 秒", settings.lockDuration), step: 0.5)
                settingSlider("稳定容差", value: $settings.stabilityTolerance, range: 0.5...3,
                              formatted: String(format: "±%.1f°", settings.stabilityTolerance), step: 0.5)
                Toggle("仅手动解锁", isOn: $settings.manualUnlockOnly).accessibilityIdentifier("manualUnlockOnly")
                settingSlider("自动解锁偏差", value: $settings.unlockTolerance, range: (settings.stabilityTolerance + 0.5)...60,
                              formatted: String(format: "±%.1f°", settings.unlockTolerance), step: 0.5).disabled(settings.manualUnlockOnly)
                settingSlider("自动解锁持续时间", value: $settings.unlockDuration, range: 0.1...2,
                              formatted: String(format: "%.2f 秒", settings.unlockDuration), step: 0.05).disabled(settings.manualUnlockOnly)
            }.disabled(!settings.autoLock)
            HStack {
                Button("手动解锁", action: model.unlockAngle).disabled(!model.canUnlockAngle).accessibilityIdentifier("unlockAngle")
                Button("锁定当前角度", action: model.lockCurrentAngle).disabled(model.manualMode)
            }.buttonStyle(.bordered)
            Text("比较当前头部与锁定姿势的差值；短暂误识别、低可信度或丢失人脸不会触发解锁。⌘U 手动解锁，⌘K 锁定当前角度。")
                .font(.system(size: 10)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
        }.font(.system(size: 12)).toggleStyle(.switch).controlSize(.small)
    }

    private var viewingSettings: some View {
        Group {
            HStack {
                Text("最大旋转角度")
                Spacer()
                Picker("最大旋转角度", selection: $settings.rotationLimit) {
                    Text("±15°").tag(15.0); Text("±30°").tag(30.0); Text("±45°").tag(45.0); Text("±60°").tag(60.0); Text("±90°").tag(90.0)
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
            Text("视频保持不透明；网格可随视频旋转，也可固定在屏幕上。转向遮幕期间网格一起淡出。")
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
            Toggle("显示网格", isOn: $settings.guides).accessibilityIdentifier("showGuides")
            Group {
                settingSlider("网格间距", value: $settings.gridSpacing, range: 24...180,
                              formatted: "\(Int(settings.gridSpacing)) 点 · 越小越密", step: 4)
                Toggle("网格随视频旋转", isOn: $settings.gridFollowsVideo)
                Toggle("旋转时淡出网格", isOn: $settings.gridFadeOnMotion)
                colorControls("网格颜色", hex: $settings.guideHex)
                settingSlider("网格不透明度", value: $settings.guideOpacity, range: 0...1,
                              formatted: "\(Int((settings.guideOpacity * 100).rounded()))%", step: 0.05)
                settingSlider("网格粗细", value: $settings.guideWidth, range: 0.5...4,
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

    private var presetControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("观看预设", selection: Binding(get: { settings.selectedPresetID }, set: model.applyPreset)) {
                Text("定姿观看").tag("pose")
                Text("连续跟随").tag("continuous")
                ForEach(settings.savedPresets) { preset in Text(preset.name).tag(preset.id) }
            }.accessibilityIdentifier("viewingPreset")
            HStack {
                TextField("个人预设名称", text: $presetName).textFieldStyle(.roundedBorder)
                Button("另存预设") {
                    if settings.savePreset(name: presetName) { presetName = ""; presetMessage = "已保存当前全部参数。" }
                    else { presetMessage = "请输入名称；最多保存 20 个个人预设。" }
                }.accessibilityIdentifier("saveViewingPreset")
                Button("删除") { settings.deleteSelectedPreset(); presetMessage = "预设已删除，当前参数保留。" }
                    .disabled(!settings.selectedPresetID.hasPrefix("saved-"))
            }
            if !presetMessage.isEmpty { Text(presetMessage).font(.system(size: 10)).foregroundStyle(Theme.mint) }
            Text("切换内置预设调整跟随行为，保留背景与大小；个人预设保存当前全部参数。修改后可另存。")
                .font(.system(size: 10)).foregroundStyle(Theme.secondary)
            Divider()
        }
    }

    private var comfortSettings: some View {
        Group {
            Toggle("大角度补偿", isOn: $settings.compensationEnabled).accessibilityIdentifier("angleCompensation")
            Text("先计算修正目标，再平滑转向。左右可分别设置向水平回收的角度，锁定后不会自行漂移。")
                .font(.system(size: 11)).foregroundStyle(Theme.secondary)
            Group {
                settingSlider("补偿起点", value: $settings.compensationThreshold, range: 0...60,
                              formatted: "\(Int(settings.compensationThreshold))°", step: 1)
                settingSlider("左倾最大回收", value: $settings.compensationLeft, range: 0...15,
                              formatted: String(format: "%.1f°", settings.compensationLeft), step: 0.5)
                settingSlider("右倾最大回收", value: $settings.compensationRight, range: 0...15,
                              formatted: String(format: "%.1f°", settings.compensationRight), step: 0.5)
                settingSlider("渐入角度范围", value: $settings.compensationBlend, range: 1...40,
                              formatted: "\(Int(settings.compensationBlend))°", step: 1)
            }.disabled(!settings.compensationEnabled)
            Divider()
            Toggle("柔性遮幕", isOn: $settings.curtainEnabled).accessibilityIdentifier("softCurtain")
            Text("确认新的姿势后，视频与网格淡出，在暗幕下转向再淡入。声音和播放继续。连续跟随预设默认关闭。")
                .font(.system(size: 11)).foregroundStyle(Theme.secondary)
            Group {
                settingSlider("遮幕触发偏差", value: $settings.curtainThreshold, range: 2...45,
                              formatted: "\(Int(settings.curtainThreshold))°", step: 1)
                settingSlider("新姿势确认时间", value: $settings.curtainConfirmation, range: 0.05...0.6,
                              formatted: String(format: "%.0f ms", settings.curtainConfirmation * 1000), step: 0.01)
                settingSlider("淡出时间", value: $settings.curtainFadeOut, range: 0.05...0.3,
                              formatted: String(format: "%.0f ms", settings.curtainFadeOut * 1000), step: 0.01)
                settingSlider("暗幕转向时间", value: $settings.curtainCovered, range: 0.02...0.3,
                              formatted: String(format: "%.0f ms", settings.curtainCovered * 1000), step: 0.01)
                settingSlider("淡入时间", value: $settings.curtainFadeIn, range: 0.05...0.4,
                              formatted: String(format: "%.0f ms", settings.curtainFadeIn * 1000), step: 0.01)
                settingSlider("两次遮幕最短间隔", value: $settings.curtainInterval, range: 0.5...5,
                              formatted: String(format: "%.1f 秒", settings.curtainInterval), step: 0.1)
            }.disabled(!settings.curtainEnabled)
            Divider()
            Toggle("实验性反向运动点", isOn: $settings.cuesEnabled).accessibilityIdentifier("edgeMotionCues")
            Text("根据最终可见画面的实际转速反向移动。到达旋转边界后减速停下，遮幕时淡出；效果需个人体验比较。提示点使用网格颜色。")
                .font(.system(size: 11)).foregroundStyle(Theme.secondary)
            Group {
                settingSlider("反向提示强度", value: $settings.cueStrength, range: 0...2,
                              formatted: String(format: "%.2f 倍", settings.cueStrength), step: 0.05)
                settingSlider("提示点速度上限", value: $settings.cueMaximumSpeed, range: 5...180,
                              formatted: "\(Int(settings.cueMaximumSpeed))° / 秒", step: 5)
                settingSlider("提示点数量", value: $settings.cueCount, range: 8...40,
                              formatted: "\(Int(settings.cueCount))", step: 1)
                settingSlider("提示点不透明度", value: $settings.cueOpacity, range: 0.05...1,
                              formatted: "\(Int(settings.cueOpacity * 100))%", step: 0.05)
                settingSlider("提示点半径", value: $settings.cueSize, range: 2...8,
                              formatted: String(format: "%.1f 点", settings.cueSize), step: 0.5)
            }.disabled(!settings.cuesEnabled)
        }.font(.system(size: 12)).toggleStyle(.switch).controlSize(.small)
    }

    private var manualSettings: some View {
        Group {
            Toggle("手动角度体验", isOn: Binding(get: { model.manualMode }, set: model.setManualMode))
                .accessibilityIdentifier("manualMode")
            Text("开启后关闭摄像头，用滑杆体验补偿、遮幕和运动点。设置的角度是补偿前输入，画面显示实际角度。")
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
