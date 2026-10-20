import SwiftUI
import UniformTypeIdentifiers
import MotionCore

enum Theme {
    static let background = Color(red: 0.047, green: 0.063, blue: 0.075)
    static let sidebar = Color(red: 0.071, green: 0.086, blue: 0.098)
    static let surface = Color(red: 0.102, green: 0.122, blue: 0.137)
    static let mint = Color(red: 0.67, green: 0.91, blue: 0.78)
    static let secondary = Color(red: 0.59, green: 0.65, blue: 0.66)
    static let line = Color.white.opacity(0.085)
}

struct MainView: View {
    @ObservedObject var model: AppModel
    @State private var dropTarget = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 276)
            Rectangle().fill(Theme.line).frame(width: 1)
            workspace
        }
        .background(Theme.background)
        .foregroundStyle(Color.white.opacity(0.92))
        .tint(Theme.mint)
        .preferredColorScheme(.dark)
        .frame(minWidth: 1020, minHeight: 740)
        .sheet(isPresented: $model.showingBilibiliSheet) { BilibiliLinkSheet(model: model) }
        .alert("视频提示", isPresented: Binding(get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } })) {
                Button("知道了", role: .cancel) { model.errorMessage = nil }
            } message: { Text(model.errorMessage ?? "") }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "viewfinder").font(.system(size: 25, weight: .light)).foregroundStyle(Theme.mint)
                    .rotationEffect(.degrees(-12))
                VStack(alignment: .leading, spacing: 3) {
                    Text("随视").font(.system(size: 20, weight: .semibold))
                    Text("FROM EYES TO SCREEN").font(.system(size: 8.5, weight: .medium, design: .monospaced)).tracking(1.1).foregroundStyle(Theme.secondary)
                }
                Spacer()
                Text("DEMO").font(.system(size: 8, weight: .bold, design: .monospaced)).padding(5)
                    .background(Theme.mint.opacity(0.1), in: RoundedRectangle(cornerRadius: 4)).foregroundStyle(Theme.mint)
            }.padding(.horizontal, 22).padding(.top, 32).padding(.bottom, 27)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 12) {
                        sectionLabel("01", "视频源")
                        Button(action: model.importVideo) {
                            HStack { Image(systemName: "plus.rectangle"); Text("导入本地视频"); Spacer(); Text("⌘O").font(.system(size: 11)) }
                                .font(.system(size: 12, weight: .medium)).padding(12)
                                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 9))
                                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.line))
                        }.buttonStyle(.plain).accessibilityIdentifier("importVideo")
                        Button { model.showingBilibiliSheet = true } label: {
                            HStack {
                                Image(systemName: "link")
                                Text("打开 B 站视频")
                                Spacer()
                                Text("⌘L").font(.system(size: 11))
                            }.font(.system(size: 12, weight: .medium)).padding(12)
                                .foregroundStyle(Theme.mint)
                                .background(Theme.mint.opacity(0.065), in: RoundedRectangle(cornerRadius: 9))
                                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.mint.opacity(0.18)))
                        }.buttonStyle(.plain).accessibilityIdentifier("showBilibiliLink")
                        Text("MP4 / MOV 等系统支持的格式").font(.system(size: 10)).foregroundStyle(Theme.secondary)
                    }
                    Rectangle().fill(Theme.line).frame(height: 1)
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            sectionLabel("02", "头部追踪")
                            Spacer()
                            Circle().fill(model.cameraRunning ? Theme.mint : Theme.secondary.opacity(0.4)).frame(width: 5, height: 5)
                        }
                        cameraTile
                        Button(action: model.toggleCamera) {
                            HStack {
                                Image(systemName: model.cameraRunning ? "video.slash" : "video")
                                Text(model.cameraRequested ? "关闭摄像头" : "开启摄像头")
                                Spacer()
                                Image(systemName: "arrow.up.right").font(.system(size: 10))
                            }.font(.system(size: 12, weight: .medium)).padding(11)
                                .background(model.cameraRequested ? Theme.surface : Theme.mint,
                                            in: RoundedRectangle(cornerRadius: 8))
                                .foregroundStyle(model.cameraRequested ? Color.white : Theme.background)
                        }.buttonStyle(.plain).accessibilityIdentifier("toggleCamera")
                        Text(model.cameraMessage).font(.system(size: 10)).foregroundStyle(Theme.secondary)
                            .fixedSize(horizontal: false, vertical: true).lineSpacing(3)
                    }
                    Rectangle().fill(Theme.line).frame(height: 1)
                    VStack(alignment: .leading, spacing: 12) {
                        sectionLabel("03", "观看与设置")
                        HStack(spacing: 8) {
                            Button { model.enterViewing(.fullscreen) } label: { Label("全屏观看", systemImage: "arrow.up.left.and.arrow.down.right") }
                        }.buttonStyle(.bordered).font(.system(size: 11)).disabled(!model.hasContent)
                        Button { model.showingSettings = true } label: {
                            HStack {
                                Image(systemName: "slider.horizontal.3")
                                Text("随视设置")
                                Spacer()
                                Text("⌘,").font(.system(size: 11))
                            }.font(.system(size: 12)).padding(12)
                                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 9))
                        }.buttonStyle(.plain).accessibilityIdentifier("openSettings")
                        Text(model.settings.autoLock ? String(format: "稳定 %.1f 秒后锁定角度", model.settings.lockDuration) : "持续平滑跟随")
                            .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                    }
                }.padding(.horizontal, 22).padding(.bottom, 18)
            }.scrollIndicators(.hidden)
            VStack(alignment: .leading, spacing: 6) {
                Label("本机处理 · 不上传摄像头画面", systemImage: "lock.shield")
                Text("让视界，顺着你的角度。")
                    .foregroundStyle(Theme.secondary.opacity(0.65))
            }.font(.system(size: 9)).foregroundStyle(Theme.secondary)
                .padding(.horizontal, 22).padding(.vertical, 17)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
        }.background(Theme.sidebar)
    }

    private var cameraTile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(Theme.background)
            if model.cameraRunning {
                CameraPreview(session: model.camera.session, running: model.cameraRunning)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                VStack {
                    HStack {
                        Spacer()
                        Label(model.faceVisible ? "检测到人脸" : "寻找人脸", systemImage: model.faceVisible ? "checkmark.circle.fill" : "viewfinder")
                            .font(.system(size: 9)).padding(6).background(.black.opacity(0.5), in: Capsule())
                    }
                    Spacer()
                    HStack {
                        Text("镜像预览").font(.system(size: 9))
                        Spacer()
                        Text(model.rawAngle.map { String(format: "%+.1f°", $0) } ?? "—")
                            .font(.system(size: 11, design: .monospaced))
                    }.padding(6).background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 5))
                }.padding(8)
            } else {
                VStack(spacing: 9) {
                    Image(systemName: "person.crop.rectangle.dashed").font(.system(size: 30, weight: .ultraLight))
                    Text("准备好后，开启摄像头").font(.system(size: 10))
                }.foregroundStyle(Theme.secondary.opacity(0.7))
            }
        }.frame(height: 137).overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line))
    }

    private var workspace: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("VIEWING ROOM / 观看室").font(.system(size: 9, weight: .medium, design: .monospaced))
                        .tracking(2).foregroundStyle(Theme.secondary)
                    Text(model.videoTitle).font(.system(size: 23, weight: .medium)).lineLimit(1)
                }
                Spacer(minLength: 12)
                HStack(spacing: 7) {
                    Circle().fill(model.cameraRunning && model.faceVisible || model.manualMode ? Theme.mint : Theme.secondary).frame(width: 5, height: 5)
                    Text(model.trackingLabel).font(.system(size: 10))
                }.padding(.horizontal, 11).padding(.vertical, 8)
                    .background(Theme.surface, in: Capsule()).foregroundStyle(Theme.secondary)
            }.padding(.top, 33)

            stage.frame(maxWidth: .infinity, maxHeight: .infinity)
            if model.isBilibili {
                BilibiliPlaybackBar(controller: model.webPlayer, openOriginal: model.openOriginalBilibili,
                    fullscreen: model.toggleFullscreen)
            } else { playbackControls }
            angleControls
            HStack {
                Text(model.isBilibili ? "B 站播放器随画面旋转 · 随视全屏保留跟随效果" : "旋转的是视频画面，控制区始终保持水平。")
                Spacer()
                Text(model.isBilibili ? "BILIBILI · v0.6.0" : "LOCAL VIDEO · v0.6.0").font(.system(size: 8, design: .monospaced)).tracking(1)
            }.font(.system(size: 10)).foregroundStyle(Theme.secondary.opacity(0.65)).padding(.bottom, 18)
        }.padding(.horizontal, 30)
    }

    private var stage: some View {
        GeometryReader { geo in
            ZStack {
                Theme.background
                Canvas { context, size in
                    var path = Path()
                    for x in stride(from: 0.0, to: size.width, by: 32) {
                        for y in stride(from: 0.0, to: size.height, by: 32) {
                            path.addEllipse(in: CGRect(x: x, y: y, width: 1, height: 1))
                        }
                    }
                    context.fill(path, with: .color(.white.opacity(0.11)))
                    var horizon = Path()
                    horizon.move(to: CGPoint(x: 0, y: size.height / 2))
                    horizon.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                    context.stroke(horizon, with: .color(Theme.mint.opacity(0.1)), style: StrokeStyle(lineWidth: 1, dash: [5, 7]))
                }
                if model.hasContent {
                    ViewingSurface(model: model,
                        container: CGSize(width: max(0, geo.size.width - 48), height: max(0, geo.size.height - 70)))
                        .shadow(color: .black.opacity(0.5), radius: 20, y: 12)
                } else { emptyStage }
                SoftCurtain(model: model)
                if model.settings.cuesEnabled { EdgeMotionCues(model: model) }
                VStack {
                    HStack {
                        Label("完整画面 · 旋转留白", systemImage: "arrow.up.left.and.arrow.down.right")
                        Spacer()
                        Text(String(format: "%+.1f°", model.displayAngle)).monospacedDigit()
                    }.font(.system(size: 9, design: .monospaced)).foregroundStyle(Theme.secondary).padding(15)
                    Spacer()
                    if dropTarget {
                        Text("松开以导入视频").font(.system(size: 12, weight: .medium)).padding(12)
                            .background(Theme.mint, in: Capsule()).foregroundStyle(Theme.background).padding(.bottom, 16)
                    }
                }.allowsHitTesting(false)
                if model.isLoading { ProgressView("正在读取视频…").padding(18).background(Theme.surface, in: RoundedRectangle(cornerRadius: 12)) }
                if model.isBilibili { WebPlayerStatus(controller: model.webPlayer) }
            }.frame(width: geo.size.width, height: geo.size.height)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(dropTarget ? Theme.mint : Theme.line, lineWidth: 1))
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $dropTarget) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: NSURL.self) { object, _ in
                guard let url = object as? URL else { return }
                DispatchQueue.main.async { model.openVideo(url) }
            }
            return true
        }
    }

    private var emptyStage: some View {
        VStack(spacing: 17) {
            ZStack {
                RoundedRectangle(cornerRadius: 13).stroke(Theme.mint.opacity(0.12), lineWidth: 1)
                    .frame(width: 122, height: 76).rotationEffect(.degrees(-15)).offset(x: -9, y: -5)
                RoundedRectangle(cornerRadius: 13).fill(Theme.surface)
                    .overlay(RoundedRectangle(cornerRadius: 13).stroke(Theme.mint.opacity(0.5), lineWidth: 1))
                    .frame(width: 122, height: 76).rotationEffect(.degrees(9))
                Image(systemName: "play.fill").font(.system(size: 21)).foregroundStyle(Theme.mint).offset(x: 2)
            }.frame(height: 100)
            VStack(spacing: 8) {
                Text("把视频放进来，换个角度看。 ").font(.system(size: 21, weight: .medium))
                Text("导入本地视频或打开 B 站链接，让画面随头部轻轻转动。")
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary)
            }
            HStack(spacing: 12) {
                Button(action: model.importVideo) { Label("导入视频", systemImage: "plus").padding(.horizontal, 8).padding(.vertical, 5) }
                    .buttonStyle(.borderedProminent).foregroundStyle(Theme.background)
                Button("试播演示", action: model.openExample).buttonStyle(.bordered).accessibilityIdentifier("openExample")
                Button("打开 B 站") { model.showingBilibiliSheet = true }.buttonStyle(.bordered)
            }.font(.system(size: 11)).padding(.top, 3)
            Text("也可以将文件拖到这里").font(.system(size: 10)).foregroundStyle(Theme.secondary.opacity(0.6))
        }.padding(20)
    }

    private var playbackControls: some View {
        VStack(spacing: 11) {
            HStack(spacing: 11) {
                Text(timeString(model.currentTime)).frame(width: 43, alignment: .leading)
                Slider(value: $model.currentTime, in: 0...max(model.duration, 1), onEditingChanged: { editing in
                    model.seeking = editing
                    if !editing { model.seek(to: model.currentTime) }
                }).controlSize(.small).disabled(model.videoURL == nil || model.duration <= 0).accessibilityLabel("播放进度")
                Text(timeString(model.duration)).frame(width: 43, alignment: .trailing)
            }.font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.secondary)
            HStack(spacing: 17) {
                Button { model.seek(to: model.currentTime - 10) } label: { Image(systemName: "gobackward.10") }
                    .help("后退 10 秒").accessibilityLabel("后退10秒")
                Button(action: model.togglePlayback) {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 16))
                        .frame(width: 37, height: 33).background(Theme.surface, in: RoundedRectangle(cornerRadius: 9))
                }.help("播放 / 暂停（空格）").accessibilityLabel(model.isPlaying ? "暂停" : "播放")
                Button { model.seek(to: model.currentTime + 10) } label: { Image(systemName: "goforward.10") }
                    .help("前进 10 秒").accessibilityLabel("前进10秒")
                Spacer()
                Image(systemName: model.volume == 0 ? "speaker.slash" : "speaker.wave.2").foregroundStyle(Theme.secondary)
                Slider(value: $model.volume, in: 0...1).frame(width: 79).controlSize(.mini).accessibilityLabel("音量")
                Rectangle().fill(Theme.line).frame(width: 1, height: 16)
                Button(action: model.toggleFullscreen) { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                    .help("全屏").accessibilityLabel("全屏")
            }.buttonStyle(.plain).font(.system(size: 14)).disabled(model.videoURL == nil)
        }
    }

    private var angleControls: some View {
        HStack(spacing: 19) {
            ZStack {
                Circle().stroke(Theme.line, lineWidth: 1)
                Rectangle().fill(Theme.secondary.opacity(0.4)).frame(width: 40, height: 1)
                Capsule().fill(Theme.mint).frame(width: 39, height: 2).rotationEffect(.degrees(model.displayAngle))
                Circle().fill(Theme.mint).frame(width: 5, height: 5)
            }.frame(width: 57, height: 57)
            VStack(alignment: .leading, spacing: 4) {
                Text("画面角度").font(.system(size: 10)).foregroundStyle(Theme.secondary)
                Text(String(format: "%+.1f", model.displayAngle))
                    .font(.system(size: 26, weight: .light, design: .monospaced)).monospacedDigit()
                    + Text(" °").font(.system(size: 14)).foregroundColor(Theme.secondary)
            }.frame(width: 121, alignment: .leading)
            Rectangle().fill(Theme.line).frame(width: 1, height: 36)
            VStack(alignment: .leading, spacing: 7) {
                Text(model.manualMode ? "在设置中调整手动角度" : model.isAngleLocked ? "姿势稳定，画面角度已锁定" : model.settings.autoLock && model.lockProgress > 0 ? String(format: "稳定计时 %.1f / %.1f 秒", model.lockProgress * model.settings.lockDuration, model.settings.lockDuration) : model.calibrationMessage)
                    .font(.system(size: 11)).lineLimit(2)
                Text("±\(Int(model.settings.rotationLimit))° 旋转范围 · \(model.settings.fixedVideoSize ? "固定画面大小" : "随角度适配大小")").font(.system(size: 9)).foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 4)
            VStack(spacing: 8) {
                Button(action: model.calibrate) {
                    Label("校准水平", systemImage: "scope").frame(width: 100)
                }.buttonStyle(.bordered).disabled(!model.canCalibrate).accessibilityIdentifier("calibrate")
                HStack(spacing: 12) {
                    Button(model.following ? "暂停跟随" : "恢复跟随") { model.following.toggle() }
                        .disabled(model.manualMode)
                    Button("手动解锁", action: model.unlockAngle).disabled(!model.canUnlockAngle)
                    Button("回正") { model.resetAngle() }
                }.buttonStyle(.plain).foregroundStyle(Theme.secondary).font(.system(size: 10))
            }.font(.system(size: 11))
        }.padding(18).background(Theme.surface.opacity(0.72), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
    }

    private func sectionLabel(_ number: String, _ title: String) -> some View {
        HStack(spacing: 8) {
            Text(number).font(.system(size: 9, design: .monospaced)).foregroundStyle(Theme.mint.opacity(0.7))
            Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.secondary)
        }
    }

    private func timeString(_ value: Double) -> String {
        let seconds = Int(value.isFinite ? max(0, value) : 0)
        if seconds >= 3600 { return String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60) }
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
