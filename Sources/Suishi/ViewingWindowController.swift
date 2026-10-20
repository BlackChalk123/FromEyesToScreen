import AppKit
import SwiftUI
import Combine

private final class ClearHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }
}

final class WatchingWindow: NSWindow {
    var onEscape: (() -> Void)?
    var onShortcut: ((String) -> Void)?
    var onMovePicture: ((CGSize, Bool) -> Void)?
    var onCenter: (() -> Void)?
    private var dragStart: NSPoint?
    private var consumingMouse = false
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .keyDown:
            let text = event.charactersIgnoringModifiers?.lowercased() ?? ""
            if event.keyCode == 53 { onEscape?(); return }
            let mods = event.modifierFlags.intersection([.command, .control, .option])
            if mods.isEmpty && ["g", "f", " "].contains(text) { onShortcut?(text); return }
        case .leftMouseDown where event.modifierFlags.contains(.option):
            consumingMouse = true
            if event.clickCount == 2 { dragStart = nil; onCenter?() }
            else { dragStart = event.locationInWindow; onMovePicture?(.zero, true) }
            return
        case .leftMouseDragged where dragStart != nil:
            if let dragStart {
                onMovePicture?(CGSize(width: event.locationInWindow.x - dragStart.x, height: dragStart.y - event.locationInWindow.y), false)
            }
            return
        case .leftMouseUp where consumingMouse: consumingMouse = false; dragStart = nil; return
        default: break
        }
        super.sendEvent(event)
    }
}

@MainActor final class ViewingWindowController: NSObject, NSWindowDelegate, NSPopoverDelegate, ObservableObject {
    private unowned let app: AppCoordinator
    private(set) var window: WatchingWindow?
    private(set) var orbPanel: NSPanel?
    private(set) var controls: NSPopover?
    var isScreenFilled: Bool { app.preferences.value.scale >= 0.999 }
    @Published private(set) var dragging = false
    @Published private(set) var availableScreens = NSScreen.screens
    private var previousScale = 0.6
    private var dragPosition = CGPoint.zero
    private var dragOrigin: CGPoint?
    private var dragOrbFrame = CGRect.zero
    private var subscription: AnyCancellable?
    private var screenObserver: NSObjectProtocol?
    private var fullscreenExitObserver: NSObjectProtocol?
    private var presentationScreen: NSScreen?

    init(app: AppCoordinator) {
        self.app = app
        super.init()
        subscription = app.$showingSettings.dropFirst().sink { [weak self] showing in
            guard let self else { return }
            if showing && self.app.watching { self.showControls() }
            else { self.controls?.close() }
        }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        }
    }
    deinit {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        if let fullscreenExitObserver { NotificationCenter.default.removeObserver(fullscreenExitObserver) }
    }

    func show(on preferred: NSScreen?) {
        // Hiding a native-fullscreen browser first destroys its Space and can strand
        // the newly presented borderless window there. Leave that Space before presenting.
        if let browser = app.browserWindow, browser.styleMask.contains(.fullScreen) {
            guard fullscreenExitObserver == nil else { return }
            presentationScreen = preferred
            fullscreenExitObserver = NotificationCenter.default.addObserver(forName: NSWindow.didExitFullScreenNotification, object: browser, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let observer = self.fullscreenExitObserver { NotificationCenter.default.removeObserver(observer) }
                    self.fullscreenExitObserver = nil
                    if self.app.watching { self.show(on: self.presentationScreen) }
                    self.presentationScreen = nil
                }
            }
            browser.toggleFullScreen(nil)
            return
        }
        if window == nil {
            guard let screen = preferred ?? NSScreen.main ?? NSScreen.screens.first else { return }
            // A normal transparent canvas uses the display as its size reference.
            // This is not a macOS fullscreen Space; display selection stays independent.
            let frame = screen.frame
            let window = WatchingWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.title = "随视 · 透明观看"
            window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = false
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.fullScreenAuxiliary]
            window.minSize = NSSize(width: 480, height: 320)
            window.delegate = self
            let host = ClearHostingView(rootView: WatchView(app: app, preferences: app.preferences, player: app.content.player))
            host.wantsLayer = true; host.layer?.backgroundColor = NSColor.clear.cgColor
            window.contentView = host
            window.onEscape = { [weak app] in app?.escape() }
            window.onShortcut = { [weak self, weak app] key in
                guard let app, !app.showingSettings else { return }
                switch key { case "g": app.toggleGuides(); case "f": self?.toggleFullScreen(); case " ": app.content.player.togglePlayback(); default: break }
            }
            window.onMovePicture = { [weak self, weak app] delta, start in
                guard let self, let app, !app.showingSettings else { return }
                if start { self.dragPosition = app.position }
                else { app.position = app.layout.moved(from: self.dragPosition, translation: delta) }
            }
            window.onCenter = { [weak app] in app?.center() }
            self.window = window
            app.viewport = frame.size
            createOrb()
        }
        window?.makeKeyAndOrderFront(nil)
        orbPanel?.orderFrontRegardless()
        app.browserWindow?.orderOut(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func createOrb() {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 72, height: 72), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "随视 · 悬浮球"
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.isReleasedWhenClosed = false; panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.fullScreenAuxiliary]
        let host = ClearHostingView(rootView: FloatingOrb(app: app, controller: self))
        host.wantsLayer = true; host.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = host
        orbPanel = panel
        placeOrb()
    }
    private func placeOrb() {
        guard let window, let orbPanel else { return }
        let desired = NSRect(x: window.frame.maxX - 88, y: window.frame.minY + 16, width: 72, height: 72)
        let area = (window.screen ?? NSScreen.main)?.visibleFrame ?? window.frame
        orbPanel.setFrame(WindowPlacement.clamped(desired, to: area), display: true)
    }
    func toggleControls() { app.showingSettings.toggle() }
    private func showControls() {
        guard let anchor = orbPanel?.contentView else { return }
        if controls?.isShown == true { return }
        let popover = NSPopover()
        popover.behavior = .transient; popover.animates = true; popover.delegate = self
        let height = min(760, max(420, (orbPanel?.screen?.visibleFrame.height ?? 900) - 80))
        popover.contentSize = NSSize(width: 360, height: height)
        popover.contentViewController = NSHostingController(rootView: OrbControls(app: app, preferences: app.preferences, player: app.content.player, controller: self))
        controls = popover
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: anchor.bounds.insetBy(dx: 8, dy: 8), of: anchor, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
    func popoverDidClose(_ notification: Notification) {
        if app.showingSettings { app.showingSettings = false }
    }
    func hide() { controls?.close(); orbPanel?.orderOut(nil); window?.orderOut(nil) }

    func toggleFullScreen() {
        guard let window, let screen = window.screen ?? NSScreen.main else { return }
        if isScreenFilled { app.preferences.value.scale = previousScale }
        else { previousScale = app.preferences.value.scale; app.preferences.value.scale = 1 }
        window.setFrame(screen.frame, display: true)
        app.viewport = screen.frame.size
        app.center(); app.tick()
    }
    func move(to screen: NSScreen) {
        guard let window else { return }
        window.setFrame(screen.frame, display: true)
        app.viewport = screen.frame.size
        app.tick()
        // The ball belongs to the desktop, not to the video's destination display.
        window.orderFrontRegardless(); orbPanel?.orderFrontRegardless()
        objectWillChange.send()
    }

    // Dragging the control panel must never resize, move or recenter the video.
    func beginDragging(at point: CGPoint) {
        dragOrigin = point; dragOrbFrame = orbPanel?.frame ?? .zero
    }
    func drag(to point: CGPoint) {
        guard let origin = dragOrigin, let orbPanel else { return }
        if !dragging { app.showingSettings = false; dragging = true }
        orbPanel.setFrameOrigin(CGPoint(x: dragOrbFrame.minX + point.x - origin.x,
                                       y: dragOrbFrame.minY + point.y - origin.y))
    }
    func endDragging() {
        dragOrigin = nil; dragging = false
        recoverOrb()
    }
    private func recoverOrb() {
        guard let orbPanel else { return }
        let frame = WindowPlacement.recovered(orbPanel.frame, in: NSScreen.screens.map(\.visibleFrame))
        if frame != orbPanel.frame { orbPanel.setFrame(frame, display: true) }
    }
    private func screensChanged() {
        availableScreens = NSScreen.screens
        guard let window, let screen = window.screen ?? NSScreen.main else { return }
        window.setFrame(screen.frame, display: true)
        app.viewport = screen.frame.size
        recoverOrb()
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { app.showBrowser(); return false }
}
