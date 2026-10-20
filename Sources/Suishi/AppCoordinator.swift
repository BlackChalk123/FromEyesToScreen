import AppKit
import Combine
import RotationCore
import MediaCore

/// Only the picture and its guides subscribe at frame rate; controls update separately.
@MainActor final class RotationPresentation: ObservableObject {
    @Published private(set) var angle = 0.0
    func present(_ value: Double) {
        if abs(value - angle) > 0.0001 { angle = value }
    }
}

@MainActor final class AppCoordinator: ObservableObject {
    let preferences: Preferences
    let library: RecentStore
    let content: BilibiliSession
    let camera: any HeadTrackingSource
    lazy var viewingWindow = ViewingWindowController(app: self)
    weak var browserWindow: NSWindow?
    @Published private(set) var watching = false
    @Published var showingSettings = false
    @Published private(set) var following = false
    @Published private(set) var cameraRunning = false
    @Published private(set) var tracking = false
    let rotation = RotationPresentation()
    var angle: Double { rotation.angle }
    @Published private(set) var statusAngle = 0.0
    @Published private(set) var trackingMessage = "头部跟随未开启"
    @Published private(set) var cameraError: String?
    @Published private(set) var recent: RecentContent?
    @Published var notice: String?
    @Published private(set) var resolving = false
    @Published var viewport = CGSize(width: 1180, height: 760)
    @Published var position = CGPoint.zero
    private var engine = RotationEngine()
    private var sample: HeadSample?
    private var timer: Timer?
    private var inputTask: Task<Void, Never>?
    private var subscriptions = Set<AnyCancellable>()
    private var lastSave = 0.0
    private var lastStored: RecentContent?
    private var noticeTask: Task<Void, Never>?
    private var lastStatusUpdate = 0.0
    private var followRequested = false // Session-only intent. Never restored after relaunch.

    convenience init() { self.init(preferences: Preferences(), library: RecentStore(), content: BilibiliSession()) }

    init(preferences: Preferences, library: RecentStore, content: BilibiliSession, trackingSource: (any HeadTrackingSource)? = nil) {
        self.preferences = preferences; self.library = library; self.content = content
        self.camera = trackingSource ?? HeadCamera()
        recent = library.load(); lastStored = recent
        content.browser.onSelect = { [weak self] in self?.select($0) }
        content.player.onSelect = { [weak self] in self?.select($0) }
        content.player.onBrowse = { [weak self] url in self?.showBrowser(url: url) }
        content.player.onProgress = { [weak self] in self?.persistProgress() }
        content.browser.onAccountInteraction = { [weak content] in content?.player.markAuthRefreshNeeded() }
        content.browser.onUnsupported = { [weak self] in self?.notify("首版支持普通投稿视频，暂不支持番剧、直播和付费课程。") }
        content.player.onUnsupported = content.browser.onUnsupported
        camera.onState = { [weak self] running, message in
            guard let self else { return }
            guard self.following else { self.cameraRunning = false; return }
            self.cameraRunning = running
            if running, self.following { self.trackingMessage = "等待识别人脸" }
            else if !running, self.following {
                self.following = false; self.tracking = false; self.sample = nil; self.engine.hold()
                self.cameraError = message; self.trackingMessage = "摄像头不可用"
            }
        }
        preferences.$value.dropFirst().sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }.store(in: &subscriptions)
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    var layout: ViewingLayout {
        ViewingLayout(viewport: viewport, aspect: content.player.aspect,
                      scale: preferences.value.scale, position: position, crop: preferences.value.crop)
    }
    var atBoundary: Bool {
        following && tracking && !preferences.value.crop && abs(engine.target) >= layout.safeAngle - 0.1 &&
            sample.map { abs(($0.angle ?? 0) - engine.baseline + preferences.value.offset) > layout.safeAngle + 0.5 } == true
    }
    var canCalibrate: Bool { following && sample?.isReliable(at: ProcessInfo.processInfo.systemUptime) == true }

    func select(_ link: BilibiliVideoLink, resumeAt: Double? = nil) {
        inputTask?.cancel(); resolving = false; notice = nil
        content.browser.setActive(false)
        let same = content.player.link.map(BilibiliRoute.key) == BilibiliRoute.key(link)
        persistProgress()
        if !same || content.player.needsAuthRefresh || resumeAt == nil && link.startTime > 0 && abs(content.player.seconds - link.startTime) > 2 {
            let start = resumeAt ?? (same && content.player.needsAuthRefresh ? content.player.seconds : nil)
            content.player.open(link, at: start)
        }
        content.player.setActive(true)
        watching = true; showingSettings = false
        viewingWindow.show(on: browserWindow?.screen)
        if followRequested && !following { startFollowing() }
        persistProgress()
    }

    func openInput(_ text: String) {
        inputTask?.cancel(); resolving = true; notice = nil
        inputTask = Task { @MainActor [weak self] in
            do {
                let link = try await BilibiliLinkResolver().resolve(text)
                guard !Task.isCancelled else { return }
                self?.select(link)
            } catch {
                guard !Task.isCancelled else { return }
                self?.resolving = false; self?.notify(error.localizedDescription)
            }
        }
    }

    func resume() {
        guard let recent, let link = recent.link else { return }
        select(link, resumeAt: recent.seconds)
    }

    func showBrowser(url: URL? = nil) {
        inputTask?.cancel(); resolving = false
        if watching {
            content.player.setActive(false)
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.content.player.capturePosition()
                self.persistProgress()
            }
        }
        suspendFollowing()
        watching = false; showingSettings = false
        viewingWindow.hide()
        browserWindow?.makeKeyAndOrderFront(nil)
        if let url { content.browser.browse(url) }
        else { content.browser.startBrowsingIfNeeded() }
        NSApp.activate(ignoringOtherApps: true)
    }

    func toggleFollowing() {
        guard watching else { return }
        if following { stopFollowing(); return }
        followRequested = true
        startFollowing()
    }
    private func startFollowing() {
        cameraError = nil; sample = nil; engine.hold()
        following = true; trackingMessage = "正在开启摄像头…"
        camera.start()
    }
    func stopFollowing() {
        followRequested = false
        suspendFollowing()
    }
    private func suspendFollowing() {
        if following || cameraRunning { camera.stop() }
        following = false; cameraRunning = false; tracking = false
        sample = nil; engine.hold(); cameraError = nil
        trackingMessage = "头部跟随未开启"
    }
    func calibrate() {
        guard canCalibrate, let value = sample?.angle else { notify("请先开启头部跟随，并让摄像头看清双眼。"); return }
        engine.calibrate(rawAngle: value)
        notify("已将当前姿势校准为水平")
    }
    func tick(now: Double = ProcessInfo.processInfo.systemUptime) {
        guard watching else { return }
        if following && cameraRunning, let measurement = camera.takeMeasurement() {
            sample = HeadSample(angle: measurement.angle, confidence: measurement.confidence, timestamp: measurement.timestamp)
        }
        let value = engine.step(sample: following ? sample : nil, now: now, response: preferences.value.response,
                                offset: preferences.value.offset, limit: layout.safeAngle)
        rotation.present(value)
        if showingSettings && now - lastStatusUpdate >= 0.1 {
            lastStatusUpdate = now
            if abs(statusAngle - value) >= 0.05 { statusAngle = value }
        }
        let valid = following && engine.tracking
        if valid != tracking { tracking = valid }
        if following && cameraRunning {
            let text = valid ? "头部跟随中" : "暂未识别人脸 · 保持当前角度"
            if trackingMessage != text { trackingMessage = text }
        }
        if now - lastSave >= 5 { lastSave = now; persistProgress() }
    }
    func center() { position = .zero }
    func toggleGuides() { preferences.value.guides.toggle() }
    func escape() {
        if showingSettings { showingSettings = false }
        else if watching { showBrowser() }
    }
    func notify(_ text: String) {
        noticeTask?.cancel(); notice = text
        noticeTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 5_000_000_000) } catch { return }
            self?.notice = nil
        }
    }
    func persistProgress() {
        guard let link = content.player.link else { return }
        let value = RecentContent(url: link.pageURL.absoluteString, title: content.player.title, seconds: content.player.seconds)
        if value == lastStored { return }
        recent = value
        if library.save(value) { lastStored = value }
    }
    func shutdown() {
        timer?.invalidate(); timer = nil; inputTask?.cancel(); noticeTask?.cancel()
        stopFollowing(); content.player.setActive(false); content.browser.setActive(false)
        persistProgress()
    }
}
