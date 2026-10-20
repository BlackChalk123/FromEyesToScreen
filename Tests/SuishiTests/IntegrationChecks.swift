import AppKit
import SwiftUI
import WebKit
import RotationCore
import MediaCore
import Combine

private final class FixtureCamera: HeadTrackingSource {
    private var latest: CameraMeasurement?
    var onState: ((Bool, String) -> Void)?
    func start() { onState?(true, "Synthetic input") }
    func stop() { latest = nil; onState?(false, "Synthetic input stopped") }
    func takeMeasurement() -> CameraMeasurement? { defer { latest = nil }; return latest }
    func emit(_ angle: Double?) {
        latest = CameraMeasurement(angle: angle, timestamp: ProcessInfo.processInfo.systemUptime, confidence: 1)
    }
}

@main struct IntegrationChecks {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = IntegrationDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor private final class IntegrationDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator!
    private var browserWindow: NSWindow!
    private var assertions = 0
    private var fixture: URL!
    private var domain = "local.suishi.integration.\(UUID().uuidString)"
    private var soakReport: [String: Any] = [:]
    private let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            do {
                if ProcessInfo.processInfo.environment["SUISHI_INSPECT_WEBSITE_ONLY"] != "1" { try await run() }
                if ProcessInfo.processInfo.environment["SUISHI_INSPECT_WEBSITE"] == "1" { try await inspectWebsite() }
                finish(true, ProcessInfo.processInfo.environment["SUISHI_INSPECT_WEBSITE_ONLY"] == "1" ? "Official website input checks passed" : "Native integration passed")
            }
            catch { finish(false, error.localizedDescription) }
        }
    }
    private func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        assertions += 1
        if !condition() { throw NSError(domain: "SuishiIntegration", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    private func settle(_ milliseconds: UInt64 = 20) async throws {
        try await Task.sleep(nanoseconds: milliseconds * 1_000_000)
        for window in NSApp.windows where window.isVisible { window.contentView?.layoutSubtreeIfNeeded() }
    }
    private func waitFor(_ message: String, timeout: Int = 15, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(Double(timeout))
        while !condition(), Date() < deadline { try await settle(100) }
        try check(condition(), message)
    }
    private func js(_ page: BilibiliPage, _ script: String) async throws -> Any? {
        try await page.webView.evaluateJavaScript(script)
    }
    private func capture(_ window: NSWindow, name: String) throws {
        guard let view = window.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        if name == "suishi-watch-1280" {
            try check((bitmap.colorAt(x: 4, y: bitmap.pixelsHigh / 2)?.alphaComponent ?? 1) == 0,
                      "Pixels outside the media and controls must have zero alpha")
        }
        if let data = bitmap.representation(using: .png, properties: [:]) {
            try data.write(to: root.appendingPathComponent(".build/checks/\(name).png"))
        }
    }
    private func run() async throws {
        fixture = FileManager.default.temporaryDirectory.appendingPathComponent("suishi-native-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
        let video = Bundle.main.url(forResource: "Example", withExtension: "mov")!
        try FileManager.default.copyItem(at: video, to: fixture.appendingPathComponent("Example.mov"))
        let playerFile = fixture.appendingPathComponent("player.html")
        try """
        <!doctype html><html><head><meta charset="utf-8"><style>
        body{margin:0} .bpx-player-container{width:100vw;height:100vh;background:#000}
        video{width:100%;height:100%;object-fit:contain}
        .bpx-player-ending-wrap{position:absolute;inset:0;z-index:55;visibility:hidden}
        </style></head><body><h1>离线回归影片</h1><div id="playerWrap" style="position:sticky;margin-left:200px;width:668px;height:422px"><div id="bilibili-player"><div class="bpx-player-container" data-screen="mini"><video controls muted loop src="Example.mov"></video><button class="bpx-player-mini-close" style="display:none" onclick="this.parentElement.dataset.screen='normal';window.miniCloseCount=(window.miniCloseCount||0)+1">关闭网页小窗</button><div class="bpx-player-ending-wrap"><div class="bpx-player-share-panel">隐藏的分享面板</div></div></div></div></div></body></html>
        """.write(to: playerFile, atomically: true, encoding: .utf8)
        let browseFile = fixture.appendingPathComponent("browse.html")
        try """
        <!doctype html><html><head><meta charset="utf-8"></head><body>
        <a id="video" href="https://www.bilibili.com/video/BV1B7411m7LV/?p=2&t=90">点开影片</a>
        <a id="popup" target="_blank" href="https://www.bilibili.com/video/BV1B7411m7LV/">新窗口影片</a>
        <video id="preview" muted loop src="Example.mov"></video>
        </body></html>
        """.write(to: browseFile, atomically: true, encoding: .utf8)
        let store = WKWebsiteDataStore.nonPersistent()
        let content = BilibiliSession(store: store, testing: true)
        content.browser.requestLoader = { view, _ in view.loadFileURL(browseFile, allowingReadAccessTo: browseFile.deletingLastPathComponent()) }
        content.player.requestLoader = { view, _ in view.loadFileURL(playerFile, allowingReadAccessTo: playerFile.deletingLastPathComponent()) }
        let prefs = Preferences(defaults: UserDefaults(suiteName: domain)!)
        let camera = FixtureCamera()
        coordinator = AppCoordinator(preferences: prefs, library: RecentStore(inMemory: true), content: content, trackingSource: camera)
        browserWindow = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 1180, height: 820), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        browserWindow.isReleasedWhenClosed = false
        browserWindow.contentView = NSHostingView(rootView: BrowseView(app: coordinator, browser: content.browser))
        coordinator.browserWindow = browserWindow
        browserWindow.makeKeyAndOrderFront(nil)
        content.browser.browse()
        try await waitFor("Offline browser document must load") { !content.browser.loading && content.browser.webView.url?.isFileURL == true }
        let scriptReady = try await js(content.browser, "window.__suishiBrowse === true") as? Bool
        try check(scriptReady == true, "Browser interception script must actually execute, rather than passing through navigation fallback")
        let encodedScripts = String(data: try JSONSerialization.data(withJSONObject: [BilibiliScripts.browser, BilibiliScripts.player]), encoding: .utf8)!
        let syntaxOK = try await js(content.browser, "\(encodedScripts).every(source => { new Function(source); return true; })") as? Bool
        try check(syntaxOK == true, "Both injected scripts must parse in the actual WebKit JavaScript engine")
        for host in ["www.bilibili.com", "search.bilibili.com", "space.bilibili.com"] {
            let page = BilibiliPage(role: .browse, store: store)
            var chosen: BilibiliVideoLink?
            page.onSelect = { chosen = $0 }
            page.webView.loadHTMLString("<html><body><a href='https://www.bilibili.com/video/BV1B7411m7LV/?p=2&t=90' onclick='window.websiteHandlerRan=true'><span id='nested'>视频</span></a></body></html>", baseURL: URL(string: "https://\(host)/")!)
            try await settle(600)
            _ = try await js(page, "document.getElementById('nested').click(); void 0")
            try await waitFor("Video clicks from \(host) must reach the production bridge") { chosen != nil }
            try check(chosen?.page == 2 && chosen?.startTime == 90, "Cross-page routing preserves P and time")
            let intercepted = try await js(page, "window.websiteHandlerRan !== true") as? Bool
            try check(intercepted == true, "Script routing must succeed even when the original webpage click is cancelled")
        }
        try check(content.browser.webView.configuration.websiteDataStore === content.player.webView.configuration.websiteDataStore, "Browser and player share one website store")
        try check(content.browser.webView !== content.player.webView, "Browser and player have distinct ownership")
        try check(!content.player.webView.configuration.preferences.isElementFullscreenEnabled, "Native rotation must retain fullscreen ownership")
        try check(!coordinator.following && !coordinator.cameraRunning, "Application never starts camera automatically")
        _ = try await js(content.browser, "document.getElementById('preview').play().catch(()=>{}); void 0")
        try await settle(150)
        let browserPaused = try await js(content.browser, "document.getElementById('preview').paused") as? Bool
        try check(browserPaused == true, "Browse previews must not leave background audio")

        _ = try await js(content.browser, "document.getElementById('video').click(); void 0")
        try await waitFor("Selecting a real link must open transparent watching") { self.coordinator.watching && content.player.ready }
        try check(content.player.link?.page == 2 && content.player.link?.startTime == 90, "Selection preserves P and time")
        let watchingWindow = coordinator.viewingWindow.window!
        try check(!watchingWindow.styleMask.contains(.fullScreen), "The display canvas must not create a native fullscreen Space")
        try check(coordinator.viewingWindow.orbPanel?.isVisible == true, "The floating control ball is available")
        let initialFrame = watchingWindow.frame
        let initialOrb = coordinator.viewingWindow.orbPanel!.frame
        let initialScale = prefs.value.scale
        let initialPosition = coordinator.position
        let anchor = CGPoint(x: 400, y: 400)
        coordinator.viewingWindow.beginDragging(at: anchor)
        coordinator.viewingWindow.drag(to: CGPoint(x: 520, y: 460))
        try check(coordinator.viewingWindow.orbPanel?.frame.origin == CGPoint(x: initialOrb.minX + 120, y: initialOrb.minY + 60), "Dragging moves only the control ball")
        coordinator.viewingWindow.endDragging()
        try check(watchingWindow.frame == initialFrame && prefs.value.scale == initialScale && coordinator.position == initialPosition, "Ball dragging leaves video position, canvas and size unchanged")
        let parkedOrb = coordinator.viewingWindow.orbPanel!.frame
        for screen in NSScreen.screens {
            coordinator.viewingWindow.move(to: screen)
            try check(watchingWindow.frame == screen.frame, "The video canvas matches its chosen display, including menu bar and Dock areas")
            try check(coordinator.viewingWindow.orbPanel?.frame == parkedOrb, "Changing the video's display must not move the ball")
            prefs.value.scale = 1; prefs.value.crop = false
            coordinator.center()
            try await settle(100)
            let fit = coordinator.layout
            try check(abs(fit.size.width - screen.frame.width) < 0.01 || abs(fit.size.height - screen.frame.height) < 0.01, "100 percent fits the display, not an inset window")
            try check(fit.size.width <= screen.frame.width + 0.01 && fit.size.height <= screen.frame.height + 0.01, "Complete mode keeps the original aspect without cropping")
            prefs.value.crop = true
            try await settle(100)
            let fill = coordinator.layout
            try check(fill.size.width >= screen.frame.width - 0.01 && fill.size.height >= screen.frame.height - 0.01, "100 percent crop mode covers the entire chosen display")
        }
        prefs.value.scale = initialScale; prefs.value.crop = false
        coordinator.viewingWindow.toggleFullScreen()
        try check(coordinator.viewingWindow.isScreenFilled && prefs.value.scale == 1, "The fit action sets the same 100 percent size as the slider")
        coordinator.viewingWindow.toggleFullScreen()
        try check(prefs.value.scale == initialScale, "The fit action restores the previous video size")
        try check(coordinator.viewingWindow.orbPanel?.frame == parkedOrb, "Changing video size must not reset the ball")
        if let other = NSScreen.screens.first(where: { $0 !== watchingWindow.screen }), let orb = coordinator.viewingWindow.orbPanel {
            let videoFrame = watchingWindow.frame
            let origin = CGPoint(x: orb.frame.midX, y: orb.frame.midY)
            let destination = CGPoint(x: other.visibleFrame.midX, y: other.visibleFrame.midY)
            prefs.value.scale = 1
            coordinator.viewingWindow.beginDragging(at: origin)
            coordinator.viewingWindow.drag(to: destination)
            coordinator.viewingWindow.endDragging()
            try check(other.visibleFrame.contains(orb.frame), "The ball can be parked independently on the other connected display")
            try check(watchingWindow.frame == videoFrame && prefs.value.scale == 1, "Cross-display ball dragging must not move or shrink 100 percent video")
            prefs.value.scale = initialScale
        }
        try check(!watchingWindow.isOpaque && watchingWindow.backgroundColor.alphaComponent == 0, "Watching window is actually transparent")
        try check(!browserWindow.isVisible, "Browsing window hides during watching")
        let webView = content.player.webView
        let parent = webView.superview
        try check(parent is WebCanvas, "Player has an explicitly sized native container")
        try check(parent?.fittingSize == .zero, "Native fitting-size solver is bypassed")
        let webSize = webView.frame.size
        let normalMode = try await js(content.player, "document.querySelector('.bpx-player-container').dataset.screen === 'normal' && window.miniCloseCount === 1") as? Bool
        try check(normalMode == true, "Initial mini mode exits through the official close action before reporting ready")
        let anchorAligned = try await js(content.player, "(()=>{const r=document.getElementById('playerWrap').getBoundingClientRect();return r.x===0 && r.y===0 && r.width===innerWidth && r.height===innerHeight})()") as? Bool
        try check(anchorAligned == true, "Sticky page ancestors must align with the fixed native website viewport")
        let hiddenPanel = try await js(content.player, "getComputedStyle(document.querySelector('.bpx-player-ending-wrap')).visibility") as? String
        try check(hiddenPanel == "hidden", "Player isolation must preserve the official player's hidden overlay state")
        // Send actual AppKit events at visible picture positions, not DOM .click().
        _ = try await js(content.player, "window.pictureClicks=[]; document.addEventListener('mousedown', e => window.pictureClicks.push([e.clientX,e.clientY]), true); void 0")
        for point in [CGPoint(x: 0.25, y: 0.25), CGPoint(x: 0.75, y: 0.25), CGPoint(x: 0.5, y: 0.65)] {
            let layout = coordinator.layout
            let location = NSPoint(x: layout.center.x + (point.x - 0.5) * layout.size.width,
                                   y: watchingWindow.frame.height - layout.center.y - (point.y - 0.5) * layout.size.height)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: watchingWindow.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
                watchingWindow.sendEvent(event)
            }
            try await settle(100)
        }
        let pictureClicks = try await js(content.player, "window.pictureClicks.length") as? Int ?? 0
        try check(pictureClicks == 3, "Clicks across the visible video body must reach WebKit, not only the bottom controls")
        _ = try await js(content.player, "window.persistedToken='same-document'; document.querySelector('video').play().catch(()=>{}); void 0")
        let start = try await js(content.player, "document.querySelector('video').currentTime") as? Double ?? 0
        try await settle(700)
        let playing = try await js(content.player, "document.querySelector('video').currentTime") as? Double ?? 0
        try check(playing > start, "Real local media advances through the production WebKit renderer")
        prefs.value.guides = true
        coordinator.toggleFollowing()
        var maximumObserved = 0.0
        for index in 0..<240 {
            camera.emit(sin(Double(index) / 24) * 30)
            prefs.value.offset = Double(index % 21) / 2 - 5
            if index % 12 == 0 {
                coordinator.showingSettings.toggle()
                try await settle(180)
                watchingWindow.setFrame(NSRect(x: 0, y: 0, width: index % 24 == 0 ? 1280 : 900, height: index % 24 == 0 ? 800 : 640), display: true)
            }
            coordinator.tick()
            maximumObserved = max(maximumObserved, abs(coordinator.angle))
            try await settle(3)
        }
        coordinator.showingSettings = false
        try check(maximumObserved > 5, "Synthetic camera input must rotate the actual production surface")
        let held = coordinator.angle
        camera.emit(nil)
        coordinator.tick()
        try check(coordinator.angle == held && !coordinator.tracking, "The actual surface holds on lost face")
        camera.emit(25)
        coordinator.tick()
        try check(abs(coordinator.angle - held) < 10, "Reacquisition must not jump the actual surface")
        coordinator.stopFollowing()
        // The same transform must map input coordinates, including the video body.
        prefs.value.crop = true
        for scale in [0.35, 0.6, 1.0] {
            prefs.value.scale = scale
            coordinator.toggleFollowing()
            for _ in 0..<60 { camera.emit(-25); coordinator.tick(); try await settle(17) }
            coordinator.stopFollowing()
            try await settle(100)
            _ = try await js(content.player, "window.pictureClicks=[]; void 0")
            let layout = coordinator.layout, radians = coordinator.angle * .pi / 180
            for point in [CGPoint(x: 0.35, y: 0.25), CGPoint(x: 0.65, y: 0.4)] {
                let x = (point.x - 0.5) * layout.size.width, y = (point.y - 0.5) * layout.size.height
                let location = CGPoint(x: layout.center.x + x * cos(radians) - y * sin(radians),
                    y: watchingWindow.frame.height - layout.center.y - x * sin(radians) - y * cos(radians))
                for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    watchingWindow.sendEvent(NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: watchingWindow.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 1)!)
                }
                try await settle(100)
            }
            let clicks = try await js(content.player, "window.pictureClicks") as? [[Double]] ?? []
            try check(clicks.count == 2, "Rotated video body remains clickable at \(scale) scale")
            try check(abs(clicks[0][0] - 960 * 0.35) < 5 && abs(clicks[0][1] - 540 * 0.25) < 5, "Visible and WebKit input coordinates agree after rotation and scaling")
        }
        prefs.value.crop = false; prefs.value.scale = initialScale
        let soakSeconds = max(2, min(600, Double(ProcessInfo.processInfo.environment["SUISHI_SOAK_SECONDS"] ?? "3") ?? 3))
        prefs.value.crop = true; prefs.value.scale = 0.6
        coordinator.toggleFollowing()
        try await settle(100)
        var publications = 0, motionUpdates = 0, frames = 0, lateFrames = 0
        let uiSubscription = coordinator.objectWillChange.sink { publications += 1 }
        let motionSubscription = coordinator.rotation.$angle.dropFirst().sink { _ in motionUpdates += 1 }
        let began = ProcessInfo.processInfo.systemUptime
        var lastFrame = began, worstInterval = 0.0
        while ProcessInfo.processInfo.systemUptime - began < soakSeconds {
            let now = ProcessInfo.processInfo.systemUptime
            camera.emit(sin((now - began) * 0.8) * 35)
            try await settle(17)
            let end = ProcessInfo.processInfo.systemUptime, interval = end - lastFrame
            worstInterval = max(worstInterval, interval)
            if interval > 0.05 { lateFrames += 1 }
            lastFrame = end; frames += 1
        }
        uiSubscription.cancel(); motionSubscription.cancel()
        soakReport = ["seconds": soakSeconds, "frames": frames, "motionUpdates": motionUpdates,
                      "globalUIUpdates": publications, "intervalsOver50ms": lateFrames, "worstIntervalMs": worstInterval * 1000]
        try check(motionUpdates > frames / 2, "Sustained rotation continues to update the production viewing surface")
        try check(publications < frames / 4, "Frame-rate motion must not invalidate the application controls and browser")
        try check(content.player.webView === webView && webView.superview === parent && webView.frame.size == webSize,
                  "Sustained rotation keeps the same fixed WebKit viewport and native container")
        coordinator.stopFollowing()
        prefs.value.crop = false; prefs.value.scale = initialScale
        try check(content.player.webView === webView && webView.superview === parent, "Angle and settings changes must retain WebView and container identity")
        try check(webView.frame.size == webSize, "Head angle and window resize cannot relayout the fixed website viewport")
        let token = try await js(content.player, "window.persistedToken") as? String
        try check(token == "same-document" && content.player.loadCount == 1, "Settings never reload the page")
        watchingWindow.setFrame(NSRect(x: 0, y: 0, width: 1280, height: 800), display: true)
        try await settle(100)
        try capture(watchingWindow, name: "suishi-watch-1280")
        coordinator.showingSettings = true
        try await settle(250)
        try check(coordinator.viewingWindow.controls?.isShown == true, "All controls open from the floating ball without a fullscreen backdrop")
        if let panel = coordinator.viewingWindow.controls?.contentViewController?.view.window { try capture(panel, name: "suishi-orb-controls") }
        coordinator.escape()
        try check(coordinator.watching && !coordinator.showingSettings, "First Escape closes only settings")
        let loads = content.player.loadCount
        coordinator.toggleFollowing()
        coordinator.showBrowser()
        try check(!coordinator.following && !coordinator.cameraRunning, "Browsing suspends capture while retaining session intent")
        coordinator.resume()
        try check(coordinator.following && coordinator.cameraRunning, "Returning to watching resumes the user's session-only follow choice")
        let fresh = AppCoordinator(preferences: prefs, library: RecentStore(inMemory: true), content: BilibiliSession(store: .nonPersistent(), testing: true), trackingSource: FixtureCamera())
        try check(!fresh.following && !fresh.cameraRunning, "A new application session must never restore the camera-on state")
        fresh.shutdown()
        coordinator.toggleFollowing()
        coordinator.showBrowser(); coordinator.resume()
        try check(!coordinator.following, "An explicit follow-off choice also survives a browsing round trip")
        for _ in 0..<32 {
            coordinator.showBrowser()
            try await settle(15)
            coordinator.resume()
            try await settle(15)
        }
        try check(content.player.loadCount == loads && content.player.webView === webView && webView.superview === parent, "32 browser round trips keep player and document")
        let secondToken = try await js(content.player, "window.persistedToken") as? String
        try check(secondToken == "same-document", "Browser round trips retain the loaded document")
        coordinator.showBrowser()
        try await settle(100)
        let paused = try await js(content.player, "document.querySelector('video').paused") as? Bool
        try check(paused == true && !coordinator.following, "Returning to browser pauses media and stops camera tracking")
        try check(coordinator.library.load()?.link?.page == 2, "Last selected content is persisted")
        try capture(browserWindow, name: "suishi-browse-1180")

        let beforeAuth = content.player.loadCount
        content.browser.onAccountInteraction?()
        try check(content.player.needsAuthRefresh, "Account interaction marks the existing player for refresh")
        coordinator.resume()
        try await waitFor("Returning after login refreshes the current official player") { content.player.ready }
        try check(content.player.loadCount == beforeAuth + 1 && !content.player.needsAuthRefresh, "Authentication refresh occurs once rather than on every mode change")
        coordinator.showBrowser()

        _ = try await js(content.browser, "document.getElementById('popup').click(); void 0")
        try await waitFor("A target=_blank video uses the same viewing flow") { self.coordinator.watching && content.player.link?.page == 1 && content.player.ready }
        coordinator.showingSettings = true
        watchingWindow.setFrame(NSRect(x: 0, y: 0, width: 800, height: 600), display: true)
        try await settle(100)
        try capture(watchingWindow, name: "suishi-settings-800")
        coordinator.escape(); coordinator.escape()
        try check(!coordinator.watching, "Second Escape returns to browser")
        try check(!coordinator.cameraRunning && !coordinator.following, "Offline checks must never enable the camera")
    }
    private func inspectWebsite() async throws {
        let page = BilibiliPage(role: .playback, store: .nonPersistent())
        let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 960, height: 540), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = WebCanvas()
        (window.contentView as? WebCanvas)?.attach(page.webView)
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        page.open(BilibiliRoute.video(at: URL(string: "https://www.bilibili.com/video/BV1B7411m7LV/")!)!)
        try await settle(18000)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(page.webView)
        try await settle(200)
        let geometry = try await js(page, """
        JSON.stringify({viewport:[innerWidth,innerHeight,scrollX,scrollY], chain:(()=>{let a=[],e=document.querySelector('video');while(e&&e!==document.documentElement){let r=e.getBoundingClientRect(),s=getComputedStyle(e);a.push({cls:e.className,id:e.id,attrs:[...e.attributes].map(a=>[a.name,a.value]),rect:[r.x,r.y,r.width,r.height],position:s.position,transform:s.transform});e=e.parentElement;}return a})(), mini:[...document.querySelectorAll('[class*=mini]')].map(e=>({cls:e.className,style:e.getAttribute('style'),text:e.textContent.slice(0,40)}))})
        """) as? String ?? "{}"
        try geometry.write(to: root.appendingPathComponent(".build/checks/suishi-player-geometry.json"), atomically: true, encoding: .utf8)
        let aligned = try await js(page, "(()=>{const r=document.querySelector('.bpx-player-container')?.getBoundingClientRect();return !!r && Math.abs(r.x)<1 && Math.abs(r.y)<1 && Math.abs(r.width-innerWidth)<1 && Math.abs(r.height-innerHeight)<1;})()") as? Bool
        try check(aligned == true, "First load must use the normal player aligned to the viewport, without requiring the mini-player close button")
        let unobstructed = try await js(page, "!document.elementFromPoint(innerWidth/2, innerHeight/3)?.closest('.bpx-player-ending-wrap') || document.querySelector('video')?.ended === true") as? Bool
        try check(unobstructed == true, "A public official page must not expose inactive ending/share overlays over the video body")
        _ = try await js(page, "window.nativeBodyClicks=0; window.nativeClicks=[]; document.addEventListener('click', e=>window.nativeClicks.push({target:e.target.className,trusted:e.isTrusted,path:e.composedPath().slice(0,10).map(n=>n.className||n.tagName)}), true); document.querySelector('.bpx-player-video-area')?.addEventListener('click',()=>window.nativeBodyClicks++,true); void 0")
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            window.sendEvent(NSEvent.mouseEvent(with: type, location: CGPoint(x: 480, y: 340), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 3, clickCount: 1, pressure: 1)!)
        }
        try await settle(1000)
        let bodyClicks = try await js(page, "window.nativeBodyClicks") as? Int ?? 0
        let data = try await js(page, """
        JSON.stringify({ready:!!document.querySelector('video'), clicks:window.nativeClicks, paused:document.querySelector('video')?.paused, points:[.2,.5,.8].flatMap(y=>[.2,.5,.8].map(x=>({x,y,stack:document.elementsFromPoint(innerWidth*x,innerHeight*y).slice(0,10).map(e=>({tag:e.tagName,cls:e.className,id:e.id,pointer:getComputedStyle(e).pointerEvents,opacity:getComputedStyle(e).opacity,visibility:getComputedStyle(e).visibility,z:getComputedStyle(e).zIndex}))})))})
        """) as? String ?? "{}"
        try data.write(to: root.appendingPathComponent(".build/checks/suishi-website-inspect.json"), atomically: true, encoding: .utf8)
        try check(bodyClicks == 1, "Native clicks in the upper video body must reach the official site's video area")
        page.setActive(false)
    }
    private func finish(_ success: Bool, _ message: String) {
        coordinator?.shutdown()
        let fullSuite = ProcessInfo.processInfo.environment["SUISHI_INSPECT_WEBSITE_ONLY"] != "1"
        let result: [String: Any] = ["success": success, "message": message, "assertions": assertions, "settingsUpdates": fullSuite ? 240 : 0, "browserRoundTrips": fullSuite ? 32 : 0, "network": ProcessInfo.processInfo.environment["SUISHI_INSPECT_WEBSITE"] == "1", "camera": false, "connectedDisplays": NSScreen.screens.count, "sustainedRotation": soakReport]
        let target = root.appendingPathComponent(".build/checks/suishi-integration.json")
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: target) }
        UserDefaults.standard.removePersistentDomain(forName: domain)
        if let fixture { try? FileManager.default.removeItem(at: fixture) }
        print(message)
        NSApp.terminate(nil)
    }
}
