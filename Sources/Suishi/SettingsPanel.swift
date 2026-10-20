import SwiftUI
import RotationCore

struct SettingsPanel: View {
    @ObservedObject var app: AppCoordinator
    @ObservedObject var preferences: Preferences
    var embedded = false
    var body: some View {
        VStack(spacing: 0) {
            if !embedded { HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text("让画面更合适").font(.system(size: 12)).foregroundStyle(UI.muted)
                    Text("观看设置").font(.system(size: 24, weight: .semibold))
                }
                Spacer()
                ToolButton(title: "关闭设置", symbol: "xmark") { app.showingSettings = false }.accessibilityIdentifier("closeSettings")
            }.padding(24)
            Divider() }
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    VStack(alignment: .leading, spacing: 16) {
                        heading("画面")
                        valueLabel("画面大小", "\(Int(preferences.value.scale * 100))%")
                        Slider(value: $preferences.value.scale, in: 0.35...1, step: 0.01).accessibilityLabel("画面大小").accessibilityIdentifier("pictureScale")
                        HStack { Text("留出旋转空间"); Spacer(); Text(preferences.value.crop ? "铺满显示器" : "适配显示器") }.font(.system(size: 12)).foregroundStyle(UI.muted)
                        Picker("旋转边界", selection: $preferences.value.crop) {
                            Text("完整显示").tag(false); Text("允许裁切").tag(true)
                        }.pickerStyle(.segmented)
                        Text(preferences.value.crop ? "100% 保持比例铺满显示器，超出的边角会裁切。" : "100% 按显示器完整适配，比例不同时会留边。当前可完整旋转约 ±\(Int(app.layout.safeAngle))°。")
                            .font(.system(size: 12)).foregroundStyle(UI.secondary).fixedSize(horizontal: false, vertical: true)
                        Button { app.center() } label: { Label("画面居中", systemImage: "scope") }.buttonStyle(.plain).font(.system(size: 14))
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 16) {
                        heading("头部跟随")
                        Text("跟随响应").font(.system(size: 14))
                        Picker("跟随响应", selection: $preferences.value.response) {
                            Text("柔和").tag(FollowResponse.soft)
                            Text("平衡").tag(FollowResponse.balanced)
                            Text("灵敏").tag(FollowResponse.fast)
                        }.pickerStyle(.segmented).labelsHidden()
                        valueLabel("角度微调", String(format: "%+.1f°", preferences.value.offset))
                        Slider(value: $preferences.value.offset, in: -5...5, step: 0.5).accessibilityLabel("角度微调")
                        Text("觉得画面稍微转多或转少时，小幅调整。").font(.system(size: 12)).foregroundStyle(UI.secondary)
                        Button { app.calibrate() } label: { Label("将当前姿势校准为水平", systemImage: "scope") }
                            .buttonStyle(.plain).font(.system(size: 14)).disabled(!app.canCalibrate)
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 16) {
                        Toggle(isOn: $preferences.value.guides) {
                            VStack(alignment: .leading, spacing: 8) {
                                heading("井字引导线")
                                Text("为视线保留一个方向参照").font(.system(size: 12)).foregroundStyle(UI.secondary)
                            }
                        }.toggleStyle(.switch)
                        if preferences.value.guides {
                            valueLabel("引导线不透明度", "\(Int(preferences.value.guideOpacity * 100))%")
                            Slider(value: $preferences.value.guideOpacity, in: 0.1...0.6, step: 0.01).accessibilityLabel("引导线不透明度")
                            Text("保持水平，仅显示在视频周围。").font(.system(size: 12)).foregroundStyle(UI.secondary)
                        }
                    }
                    Label {
                        Text("摄像头仅在你开启后使用。在本机处理画面，不上传、不保存。")
                    } icon: { Image(systemName: "lock") }.font(.system(size: 12)).foregroundStyle(UI.secondary)
                        .padding(16).background(UI.sunken, in: RoundedRectangle(cornerRadius: 8))
                }.padding(24)
            }
            Divider()
            HStack {
                Label("偏好自动保存", systemImage: "checkmark").font(.system(size: 12)).foregroundStyle(UI.muted)
                Spacer()
                Button("恢复默认") { preferences.reset(); app.center() }.buttonStyle(.plain).font(.system(size: 12))
            }.padding(24)
        }.foregroundStyle(UI.ink).background(UI.surface).tint(UI.ink).preferredColorScheme(.light)
            .onExitCommand { app.showingSettings = false }
    }
    private func heading(_ value: String) -> some View { Text(value).font(.system(size: 14, weight: .semibold)) }
    private func valueLabel(_ title: String, _ value: String) -> some View {
        HStack { Text(title); Spacer(); Text(value).monospacedDigit().foregroundStyle(UI.secondary) }.font(.system(size: 14))
    }
}
