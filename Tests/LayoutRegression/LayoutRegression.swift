import AppKit
import SwiftUI
import WebKit
import MediaCore
import MotionCore

/// Runs the production views in AppKit, including real layout passes and WebKit reparenting.
/// This fixture never enables the camera, changes preferences, or loads external websites.
@main
struct LayoutRegression {
    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = RegressionDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { application.run() }
    }
}

@MainActor
private final class RegressionDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var model: AppModel!
    private let resultURL = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("layout-regression-result.json")
    private var rotations = 0
    private var modeChanges = 0
    private let preferencesDomain = "local.fromeyestoscreen.layout-regression.\(UUID().uuidString)"
    private var fixtureImageURL: URL?
    private var installedImageURL: URL?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            do { try await run(); finish(success: true, message: "Layout regression passed") }
            catch { finish(success: false, message: error.localizedDescription) }
        }
    }

    private func check(_ condition: Bool, _ message: String) throws {
        if !condition { throw NSError(domain: "LayoutRegression", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }

    private func tick() async throws {
        try await Task.sleep(nanoseconds: 4_000_000)
        for window in NSApp.windows where window.isVisible { window.contentView?.layoutSubtreeIfNeeded() }
    }

    private func run() async throws {
        let fallback = CGSize(width: 960, height: 540)
        try check(NativeSurfaceLayout.size(for: .unspecified, fallback: fallback) == fallback, "Unspecified size must not consult AppKit")
        try check(NativeSurfaceLayout.size(for: .init(width: -.infinity, height: .nan), fallback: fallback) == fallback,
                  "Non-finite layout proposals must remain finite")
        try check(NativeSurfaceLayout.size(for: .init(width: -1, height: 40)) == CGSize(width: 0, height: 40), "Negative widths must be clamped")
        for view in [NativeCanvasView(), PlayerSurface(), CameraSurface(), WebPlayerContainer(), MainWindowReader.Reader()] {
            try check(view.fittingSize == .zero, "Native surfaces must bypass constraint-based fitting")
            try check(view.intrinsicContentSize.width == NSView.noIntrinsicMetric, "A media canvas must not infer content width")
        }

        let store = WKWebsiteDataStore.nonPersistent()
        let loginConfiguration = BilibiliWebConfiguration.make(dataStore: store)
        let playerConfiguration = BilibiliWebConfiguration.make(dataStore: store)
        try check(loginConfiguration.websiteDataStore === playerConfiguration.websiteDataStore,
                  "Login and player must share a website data store")
        try check(loginConfiguration.applicationNameForUserAgent?.contains("Version/") == true,
                  "Official website requires a desktop browser version token")
        model = AppModel(settings: AppSettings(defaults: UserDefaults(suiteName: preferencesDomain)!))
        let model = model!
        model.settings.videoScale = 0.6
        model.settings.fullscreenScale = 0.6
        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent("fullscreen-background-\(UUID().uuidString).tiff")
        let image = NSImage(size: NSSize(width: 64, height: 64))
        image.lockFocus(); NSColor.darkGray.setFill(); NSRect(x: 0, y: 0, width: 64, height: 64).fill(); image.unlockFocus()
        try image.tiffRepresentation!.write(to: fixture)
        fixtureImageURL = fixture
        try model.installBackground(from: fixture)
        installedImageURL = URL(fileURLWithPath: model.settings.backgroundImagePath)
        try check(model.backgroundImage != nil && model.settings.backdrop == .image, "Background import failed")
        try check(installedImageURL != fixture, "Background must be copied out of the selected source")
        window = NSWindow(contentRect: CGRect(x: 80, y: 80, width: 1240, height: 850),
                          styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "随视布局回归检查"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: RegressionRoot(model: model))
        model.viewingWindows.mainWindow = window
        window.makeKeyAndOrderFront(nil)
        model.setManualMode(true)
        model.openExample()
        for _ in 0..<250 {
            if model.videoURL != nil && !model.isLoading { break }
            try await tick()
        }
        try check(model.videoURL != nil, "Bundled local video failed to load")
        try await rotationStorm()
        try await modeStorm(checkWeb: false)

        model.player.pause()
        guard case .video(let link) = try BilibiliLinkInput.parse("BV1B7411m7LV") else { fatalError("Invalid fixture ID") }
        model.videoURL = nil
        model.bilibiliLink = link
        model.videoTitle = "WebKit layout fixture"
        let videoData = try Data(contentsOf: Bundle.main.url(forResource: "Example", withExtension: "mov")!).base64EncodedString()
        model.webPlayer.webView.loadHTMLString("""
        <html><head><style>html,body {margin:0;width:100%;height:100%;background:#13242a;color:white}
        video {width:100%;height:100%;object-fit:contain} #clock{position:absolute;top:20px;left:20px}</style></head>
        <body><h1 id='outside-player'>Outside player fixture</h1><div id='bilibili-player'><div class='bpx-player-container'><video id='video' muted controls src='data:video/mp4;base64,\(videoData)'></video><div id='clock'></div></div></div>
        <script>window.__layoutRegressionToken='preserved';setInterval(()=>{document.querySelector('#clock').textContent=performance.now().toFixed(0)},16)</script>
        </body></html>
        """, baseURL: URL(string: "https://www.bilibili.com/video/BV1B7411m7LV/"))
        for _ in 0..<250 {
            try await tick()
            if let value = try? await model.webPlayer.webView.evaluateJavaScript("window.__layoutRegressionToken"), value as? String == "preserved" { break }
        }
        try await checkWebDocument()
        let playerOnly = try await model.webPlayer.webView.evaluateJavaScript("document.documentElement.classList.contains('eyes-player-only')") as? Bool
        try check(playerOnly == true, "Desktop website player layout did not activate")
        let outsideVisibility = try await model.webPlayer.webView.evaluateJavaScript("getComputedStyle(document.querySelector('#outside-player')).visibility") as? String
        try check(outsideVisibility == "hidden", "Website content outside the player should be hidden")
        try await rotationStorm()
        try await modeStorm(checkWeb: true)
        for _ in 0..<6 {
            model.showingSettings = true
            for _ in 0..<10 { try await tick() }
            model.showingSettings = false
            for _ in 0..<10 { try await tick() }
        }
        try await checkWebDocument()
        model.shutdown()
    }

    private func rotationStorm() async throws {
        for index in 0..<720 {
            model.setManualAngle(sin(Double(index) * 0.08) * 45)
            if index % 12 == 0 {
                window.setContentSize(CGSize(width: 1060 + (index % 7) * 25, height: 760 + (index % 5) * 15))
            }
            rotations += 1
            try await tick()
        }
    }

    private func modeStorm(checkWeb: Bool) async throws {
        for index in 0..<24 {
            for transparent in [false, true] {
                let mode = ViewingMode.fullscreen
                model.settings.transparentBackground = transparent
                model.settings.guides = true
                model.settings.guideStyle = GuideStyle.allCases[index % GuideStyle.allCases.count]
                model.settings.guideOutsideOnly = index % 2 == 0
                model.settings.backgroundOpacity = index % 2 == 0 ? 0.5 : 1
                model.settings.backgroundBlur = Double(index % 3) * 5
                model.settings.boundary = index % 2 == 0 ? .complete : .crop
                model.enterViewing(mode)
                for _ in 0..<5 { try await tick() }
                try check(model.viewingMode == mode, "Viewing mode did not enter")
                if index == 0 { try await exerciseNativeDrag() }
                if index == 1 {
                    model.openSettings()
                    for _ in 0..<10 { try await tick() }
                    try check(model.showingFullscreenSettings && !model.showingSettings, "Fullscreen settings must stay in the viewing window")
                    model.showingFullscreenSettings = false
                    for _ in 0..<10 { try await tick() }
                }
                model.setManualAngle(Double(index % 3 - 1) * 30)
                model.viewingPosition = CGPoint(x: Double(index % 3 - 1), y: Double((index + 1) % 3 - 1))
                if checkWeb {
                    try check(model.webPlayer.webView.window !== window, "WebKit must belong to the visible viewing window")
                    try await checkWebDocument()
                }
                model.leaveViewing()
                for _ in 0..<5 { try await tick() }
                try check(model.viewingMode == .workbench && window.isVisible, "Workbench did not restore")
                model.centerViewing()
                try check(model.viewingPosition == .zero, "Centering did not reset the viewing position")
                if checkWeb {
                    try check(model.webPlayer.webView.window === window, "WebKit did not return to the workbench")
                    try await checkWebDocument()
                }
                modeChanges += 2
            }
        }
    }

    private func checkWebDocument() async throws {
        let token = try await model.webPlayer.webView.evaluateJavaScript("window.__layoutRegressionToken") as? String
        try check(token == "preserved", "The webpage was reloaded or destroyed during layout")
    }

    private func exerciseNativeDrag() async throws {
        guard let presentation = NSApp.windows.first(where: { $0.isVisible && $0 !== window }) else {
            throw NSError(domain: "LayoutRegression", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing presentation window"])
        }
        model.centerViewing()
        func event(_ type: NSEvent.EventType, point: CGPoint, clicks: Int = 1) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: point, modifierFlags: [.option], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: presentation.windowNumber, context: nil, eventNumber: 1, clickCount: clicks, pressure: 1)!
        }
        presentation.sendEvent(event(.leftMouseDown, point: CGPoint(x: 150, y: 150)))
        presentation.sendEvent(event(.leftMouseDragged, point: CGPoint(x: 250, y: 75)))
        presentation.sendEvent(event(.leftMouseUp, point: CGPoint(x: 250, y: 75)))
        try check(model.viewingPosition.x > 0 && model.viewingPosition.y > 0,
                  "Option-drag did not move the native presentation in both directions")
        try await tick()
        presentation.sendEvent(event(.leftMouseDown, point: CGPoint(x: 250, y: 75), clicks: 2))
        presentation.sendEvent(event(.leftMouseUp, point: CGPoint(x: 250, y: 75), clicks: 2))
        try check(model.viewingPosition == .zero, "Option-double-click did not center the presentation")
    }

    private func finish(success: Bool, message: String) {
        if let fixtureImageURL { try? FileManager.default.removeItem(at: fixtureImageURL) }
        if let installedImageURL { try? FileManager.default.removeItem(at: installedImageURL) }
        UserDefaults.standard.removePersistentDomain(forName: preferencesDomain)
        let report: [String: Any] = ["success": success, "message": message, "rotations": rotations,
                                   "modeChanges": modeChanges, "cameraUsed": false, "externalNetworkUsed": false]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: resultURL, options: .atomic)
        }
        print(message)
        NSApp.terminate(nil)
    }
}

private struct RegressionRoot: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Group {
            if model.viewingMode == .workbench { MainView(model: model) }
            else { Color.clear }
        }.frame(minWidth: 1020, minHeight: 740)
            .sheet(isPresented: $model.showingSettings) { SettingsView(model: model, settings: model.settings) }
    }
}
