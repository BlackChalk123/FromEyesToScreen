import AppKit
import AVFoundation
import Combine
import UniformTypeIdentifiers
import MotionCore
import MediaCore

@MainActor
final class AppModel: ObservableObject {
    let player = AVPlayer()
    let camera = CameraTracker()
    let webPlayer = WebPlayerController()
    let settings: AppSettings
    let viewingWindows = ViewingWindowController()
    @Published var showingSettings = false
    @Published var showingFullscreenSettings = false
    @Published var fullscreenViewport = CGSize.zero
    @Published var backgroundImage: NSImage?
    @Published var backgroundError: String?
    private var loadedBackgroundPath = ""
    @Published var viewingMode = ViewingMode.workbench
    @Published var viewingPosition = CGPoint.zero
    @Published var isAngleLocked = false
    @Published var lockProgress = 0.0
    @Published var bilibiliLink: BilibiliVideoLink?
    @Published var showingBilibiliSheet = false
    @Published var bilibiliInput = ""
    @Published var resolvingBilibili = false
    @Published var bilibiliError: String?
    @Published var videoURL: URL?
    @Published var videoTitle = "你的下一段视界"
    @Published var videoAspect = 16.0 / 9
    @Published var duration = 0.0
    @Published var currentTime = 0.0
    @Published var isPlaying = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var cameraRequested = false
    @Published var cameraRunning = false
    @Published var cameraMessage = "摄像头已关闭"
    @Published var faceVisible = false
    @Published var rawAngle: Double?
    @Published var displayAngle = 0.0
    @Published var following = true {
        didSet { if !following { filter.cancelLock(); syncLockStatus() } }
    }
    @Published var manualMode = false
    @Published var manualAngle = 0.0
    @Published var volume = 0.8 { didSet { player.volume = Float(volume) } }
    @Published var seeking = false
    @Published var calibrationMessage = "坐姿自然时，点一下校准"
    private var filter = HeadMotionFilter()
    private var lastMeasurement = 0.0
    private var loadID = UUID()
    private var timeObserver: Any?
    private var itemStatus: NSKeyValueObservation?
    private var rateObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var failedObserver: NSObjectProtocol?
    private var activeURL: URL?
    private var hasSecurityAccess = false
    private var linkTask: Task<Void, Never>?
    private var settingsSubscription: AnyCancellable?
    private var trackingConfiguration: [Double] = []

    var hasContent: Bool { videoURL != nil || bilibiliLink != nil }
    var isBilibili: Bool { bilibiliLink != nil }

    var canCalibrate: Bool { manualMode || (cameraRunning && faceVisible && rawAngle != nil) }
    var trackingLabel: String {
        if manualMode { return "手动体验" }
        if !cameraRunning { return cameraRequested ? "正在启动" : "未开启" }
        if !faceVisible { return "等待人脸 · 保持角度" }
        if !following { return "跟随已暂停" }
        if isAngleLocked { return "角度已锁定" }
        if settings.autoLock && lockProgress > 0 { return "稳定计时中" }
        return "正在跟随"
    }

    init(settings: AppSettings = AppSettings()) {
        self.settings = settings
        applySettings()
        loadBackgroundImage()
        settingsSubscription = settings.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.applySettings()
                self?.loadBackgroundImage()
                self?.viewingWindows.updateAppearance()
                self?.objectWillChange.send()
            }
        }
        player.volume = Float(volume)
        player.actionAtItemEnd = .pause
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.2, preferredTimescale: 600),
                                                     queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self, !self.isBilibili, !self.seeking, time.seconds.isFinite else { return }
                self.currentTime = time.seconds
            }
        }
        rateObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            let playing = player.timeControlStatus == .playing
            DispatchQueue.main.async { self?.isPlaying = playing }
        }
        camera.onState = { [weak self] running, message in
            guard let self else { return }
            self.cameraRunning = running
            self.cameraMessage = message
            if !running {
                self.cameraRequested = false
                self.faceVisible = false
                self.rawAngle = nil
                self.lastMeasurement = 0
                self.filter.cancelLock()
                self.syncLockStatus()
            }
        }
        camera.onMeasurement = { [weak self] measurement in self?.receive(measurement) }
    }

    func importVideo() {
        let panel = NSOpenPanel()
        panel.title = "选择本地视频"
        panel.prompt = "导入视频"
        panel.allowedContentTypes = [.movie, .video, .mpeg4Movie, .quickTimeMovie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { [weak self] result in
            if result == .OK, let url = panel.url { self?.openVideo(url) }
        }
    }

    func openExample() {
        guard let url = Bundle.main.url(forResource: "Example", withExtension: "mov") else {
            errorMessage = "未找到试播视频，请先导入本地视频。"
            return
        }
        openVideo(url)
    }

    func openVideo(_ url: URL) {
        guard url.isFileURL else {
            errorMessage = "这个 demo 暂时支持本地视频文件。"
            return
        }
        let id = UUID()
        cancelBilibiliResolution()
        loadID = id
        isLoading = true
        errorMessage = nil
        let access = url.startAccessingSecurityScopedResource()
        Task {
            do {
                let asset = AVURLAsset(url: url)
                guard try await asset.load(.isPlayable) else { throw VideoError.unplayable }
                let tracks = try await asset.loadTracks(withMediaType: .video)
                guard let track = tracks.first else { throw VideoError.noVideo }
                let naturalSize = try await track.load(.naturalSize)
                let transform = try await track.load(.preferredTransform)
                let size = naturalSize.applying(transform)
                let time = try await asset.load(.duration).seconds
                guard id == loadID else {
                    if access { url.stopAccessingSecurityScopedResource() }
                    return
                }
                releaseVideo()
                webPlayer.stop()
                bilibiliLink = nil
                activeURL = url
                hasSecurityAccess = access
                let item = AVPlayerItem(asset: asset)
                videoURL = url
                videoTitle = url.deletingPathExtension().lastPathComponent == "Example" ? "视线漫游 · 试播影片" : url.lastPathComponent
                videoAspect = abs(size.height) > 0 ? abs(size.width / size.height) : 16.0 / 9
                duration = time.isFinite ? max(0, time) : 0
                currentTime = 0
                itemStatus = item.observe(\.status, options: [.new]) { [weak self] item, _ in
                    guard item.status == .failed else { return }
                    let reason = item.error?.localizedDescription ?? "无法解码此视频。"
                    DispatchQueue.main.async { self?.errorMessage = reason; self?.isLoading = false }
                }
                endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                    object: item, queue: .main) { [weak self] _ in
                        Task { @MainActor [weak self] in self?.isPlaying = false }
                    }
                failedObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime,
                    object: item, queue: .main) { [weak self] note in
                        let message = (note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?.localizedDescription ?? "视频播放中断。"
                        Task { @MainActor [weak self] in self?.errorMessage = message }
                    }
                player.replaceCurrentItem(with: item)
                isLoading = false
                player.play()
            } catch {
                if access { url.stopAccessingSecurityScopedResource() }
                guard id == loadID else { return }
                isLoading = false
                errorMessage = "无法导入视频：\(error.localizedDescription)\n请尝试使用 H.264 或 HEVC 编码的 MP4 / MOV 文件。"
            }
        }
    }

    func togglePlayback() {
        guard !isBilibili, videoURL != nil else { return }
        if player.timeControlStatus != .paused { player.pause() }
        else if duration > 0 && currentTime >= duration - 0.1 {
            player.seek(to: .zero) { [weak self] _ in DispatchQueue.main.async { self?.player.play() } }
        } else { player.play() }
    }

    func seek(to seconds: Double) {
        guard !isBilibili else { return }
        let value = max(0, min(duration, seconds))
        currentTime = value
        player.seek(to: CMTime(seconds: value, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func toggleCamera() {
        if cameraRequested || cameraRunning {
            cameraRequested = false
            cameraRunning = false
            faceVisible = false
            rawAngle = nil
            camera.stop()
        } else {
            setManualMode(false)
            cameraRequested = true
            cameraMessage = "正在请求摄像头…"
            camera.start()
        }
    }

    func setManualMode(_ enabled: Bool) {
        filter.cancelLock()
        syncLockStatus()
        manualMode = enabled
        if enabled {
            cameraRequested = false
            cameraRunning = false
            faceVisible = false
            rawAngle = nil
            camera.stop()
            following = true
            manualAngle = displayAngle
        } else {
            lastMeasurement = 0
            filter.hold(angle: displayAngle)
        }
    }

    func setManualAngle(_ angle: Double) {
        let bounded = max(-settings.rotationLimit, min(settings.rotationLimit, angle))
        manualAngle = bounded
        displayAngle = bounded
    }

    func calibrate() {
        if manualMode { setManualAngle(0); return }
        guard let rawAngle, faceVisible, cameraRunning else { return }
        filter.calibrate(rawAngle: rawAngle)
        syncLockStatus()
        following = true
        calibrationMessage = "已将当前坐姿设为水平"
        // Filter moves toward zero on subsequent camera frames.
    }

    func resetAngle() {
        filter.reset()
        syncLockStatus()
        displayAngle = 0
        manualAngle = 0
        following = false
        calibrationMessage = "已回正 · 恢复跟随后重新随头部转动"
    }

    private func receive(_ measurement: FaceMeasurement) {
        guard cameraRequested, cameraRunning, !manualMode else { return }
        faceVisible = measurement.angle != nil
        rawAngle = measurement.angle
        let dt = lastMeasurement > 0 ? measurement.timestamp - lastMeasurement : 1.0 / 24
        lastMeasurement = measurement.timestamp
        guard following else { return }
        displayAngle = filter.update(rawAngle: measurement.angle, deltaTime: dt)
        syncLockStatus()
        let status = !faceVisible ? "未检测到人脸，保持当前角度" : isAngleLocked ? "姿势稳定 · 明显转头后恢复跟随" : "正在本机识别头部角度"
        if cameraMessage != status { cameraMessage = status }
    }

    private func syncLockStatus() {
        isAngleLocked = filter.isLocked
        lockProgress = filter.stabilityProgress
    }

    private func applySettings() {
        let configuration = [settings.responseTime, settings.reversed ? 1 : 0, settings.autoLock ? 1 : 0,
                             settings.lockDuration, settings.stabilityTolerance, settings.unlockTolerance, settings.rotationLimit,
                             settings.followGain, settings.maximumSpeed]
        if trackingConfiguration != configuration {
            filter.cancelLock()
            trackingConfiguration = configuration
        }
        filter.responseTime = settings.responseTime
        filter.reversed = settings.reversed
        filter.lockingEnabled = settings.autoLock
        filter.lockDuration = settings.lockDuration
        filter.stabilityTolerance = settings.stabilityTolerance
        filter.unlockTolerance = settings.unlockTolerance
        filter.limit = settings.rotationLimit
        filter.gain = settings.followGain
        filter.maximumSpeed = settings.maximumSpeed
        let bounded = max(-filter.limit, min(filter.limit, displayAngle))
        if bounded != displayAngle { filter.hold(angle: bounded); displayAngle = bounded; manualAngle = bounded }
        syncLockStatus()
    }

    private func releaseVideo() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        itemStatus = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let failedObserver { NotificationCenter.default.removeObserver(failedObserver) }
        endObserver = nil
        failedObserver = nil
        if hasSecurityAccess { activeURL?.stopAccessingSecurityScopedResource() }
        hasSecurityAccess = false
        activeURL = nil
    }

    func shutdown() {
        viewingWindows.dismiss()
        loadID = UUID()
        cancelBilibiliResolution()
        webPlayer.stop()
        camera.stop()
        releaseVideo()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
    }

    func openBilibili() {
        linkTask?.cancel()
        let text = bilibiliInput
        let id = UUID()
        loadID = id
        isLoading = false
        resolvingBilibili = true
        bilibiliError = nil
        linkTask = Task { [weak self] in
            do {
                let link = try await BilibiliLinkResolver().resolve(text)
                guard let self, !Task.isCancelled, self.loadID == id else { return }
                self.releaseVideo()
                self.videoURL = nil
                self.bilibiliLink = link
                self.videoTitle = link.title
                self.videoAspect = 16.0 / 9
                self.duration = 0
                self.currentTime = 0
                self.isPlaying = false
                self.resolvingBilibili = false
                self.showingBilibiliSheet = false
                self.errorMessage = nil
                self.webPlayer.load(link)
            } catch {
                guard let self, !Task.isCancelled, self.loadID == id else { return }
                self.resolvingBilibili = false
                self.bilibiliError = error is BilibiliLinkError ? error.localizedDescription :
                    "链接连接失败：\(error.localizedDescription)\n短链接无法解析时，请使用完整的 bilibili.com/video/… 链接。"
            }
        }
    }

    func cancelBilibiliResolution() {
        linkTask?.cancel()
        linkTask = nil
        resolvingBilibili = false
    }

    func openOriginalBilibili() {
        if let url = bilibiliLink?.pageURL { NSWorkspace.shared.open(url) }
    }

    func toggleFullscreen() {
        if viewingMode == .workbench { enterViewing(.fullscreen) } else { leaveViewing() }
    }

    func enterViewing(_ mode: ViewingMode) {
        guard hasContent else { return }
        if showingSettings {
            showingSettings = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self else { return }
                self.viewingWindows.present(mode, model: self)
            }
        } else { viewingWindows.present(mode, model: self) }
    }

    func leaveViewing() { viewingWindows.dismiss() }

    func centerViewing() { viewingPosition = .zero }

    func fullscreenLayout(in viewport: CGSize) -> PresentationLayout {
        PresentationLayout(viewport: viewport, aspect: videoAspect, maximumAngle: settings.rotationLimit,
            scale: settings.fullscreenScale, position: viewingPosition, allowsCropping: settings.boundary == .crop)
    }

    func openSettings() {
        if viewingMode == .workbench { showingSettings = true } else { showingFullscreenSettings = true }
    }

    func fillScreen() {
        settings.boundary = .crop
        let size = fullscreenViewport.width > 0 ? fullscreenViewport : (NSScreen.main?.frame.size ?? CGSize(width: 1920, height: 1080))
        let fit = MotionGeometry.fittedSize(aspect: videoAspect, angle: 0, container: size)
        settings.fullscreenScale = min(16, max(size.width / max(1, fit.width), size.height / max(1, fit.height)))
        centerViewing()
    }

    func importBackground() {
        let panel = NSOpenPanel()
        panel.title = "选择全屏背景图片"
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { [weak self] response in
            guard response == .OK, let self, let url = panel.url else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do { try self.installBackground(from: url) }
            catch { self.backgroundError = "无法导入背景图片：\(error.localizedDescription)" }
        }
    }

    func installBackground(from url: URL) throws {
        guard let image = NSImage(contentsOf: url), image.isValid else {
            throw NSError(domain: "BackgroundImage", code: 1, userInfo: [NSLocalizedDescriptionKey: "请选择可读取的图片文件。"])
        }
        let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true).appendingPathComponent("FromEyesToScreen/Backgrounds", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension(url.pathExtension)
        try FileManager.default.copyItem(at: url, to: destination)
        settings.backgroundImagePath = destination.path
        settings.backdrop = .image
        settings.transparentBackground = false
        loadBackgroundImage()
    }

    private func loadBackgroundImage() {
        let path = settings.backgroundImagePath
        guard path != loadedBackgroundPath else { return }
        loadedBackgroundPath = path
        backgroundImage = path.isEmpty ? nil : NSImage(contentsOfFile: path)
        backgroundError = !path.isEmpty && backgroundImage == nil ? "背景图片不可用，请重新选择。" : nil
    }

    enum VideoError: LocalizedError {
        case unplayable, noVideo
        var errorDescription: String? {
            switch self {
            case .unplayable: return "系统无法播放这种格式。"
            case .noVideo: return "文件中没有视频画面。"
            }
        }
    }
}
