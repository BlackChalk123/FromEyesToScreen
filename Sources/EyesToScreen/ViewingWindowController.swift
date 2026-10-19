import SwiftUI
import AppKit
import MotionCore

enum ViewingMode: String { case workbench, fullscreen }

private final class ViewingWindow: NSWindow {
    var movePicture: ((CGPoint, CGSize) -> Void)?
    var picturePosition: (() -> CGPoint)?
    var centerPicture: (() -> Void)?
    private var dragStart: NSPoint?
    private var consumesMouseUp = false
    private var startPosition = CGPoint.zero
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        // Intercept only Option-drag. Plain clicks and drags still reach WebKit's controls.
        switch event.type {
        case .leftMouseDown where event.modifierFlags.contains(.option):
            consumesMouseUp = true
            if event.clickCount == 2 { centerPicture?(); dragStart = nil }
            else { dragStart = event.locationInWindow; startPosition = picturePosition?() ?? .zero }
            return
        case .leftMouseDragged where dragStart != nil:
            if let dragStart {
                movePicture?(startPosition, CGSize(width: event.locationInWindow.x - dragStart.x,
                                                   height: dragStart.y - event.locationInWindow.y))
            }
            return
        case .leftMouseUp where consumesMouseUp:
            dragStart = nil
            consumesMouseUp = false
            return
        default: break
        }
        super.sendEvent(event)
    }
}

private final class TransparentHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }
}

@MainActor
final class ViewingWindowController: NSObject, NSWindowDelegate {
    weak var mainWindow: NSWindow?
    private var viewingWindow: NSWindow?
    private var escapeMonitor: Any?
    private var fullscreenObserver: NSObjectProtocol?
    private weak var model: AppModel?

    func present(_ mode: ViewingMode, model: AppModel) {
        guard mode != .workbench else { dismiss(); return }
        self.model = model
        guard let mainWindow else { return }
        if mainWindow.styleMask.contains(.fullScreen) {
            guard fullscreenObserver == nil else { return }
            fullscreenObserver = NotificationCenter.default.addObserver(forName: NSWindow.didExitFullScreenNotification,
                object: mainWindow, queue: .main) { [weak self, weak model] _ in
                    Task { @MainActor in
                        guard let self, let model else { return }
                        if let observer = self.fullscreenObserver { NotificationCenter.default.removeObserver(observer) }
                        self.fullscreenObserver = nil
                        self.present(mode, model: model)
                    }
                }
            mainWindow.toggleFullScreen(nil)
            return
        }
        model.viewingMode = mode
        if let viewingWindow {
            configure(viewingWindow, mode: mode)
            return
        }
        let screen = mainWindow.screen ?? NSScreen.main
        guard let screen else { model.viewingMode = .workbench; return }
        let window = ViewingWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.title = "随视 · 专注观看"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.collectionBehavior = [.fullScreenAuxiliary]
        configure(window, mode: mode)
        let topInset = max(16, screen.frame.maxY - screen.visibleFrame.maxY + 12)
        window.picturePosition = { [weak model] in model?.viewingPosition ?? .zero }
        window.centerPicture = { [weak model] in model?.centerViewing() }
        window.movePicture = { [weak model, weak window] position, translation in
            guard let model, let window else { return }
            let layout = model.fullscreenLayout(in: window.contentView?.bounds.size ?? window.frame.size)
            model.viewingPosition = layout.moved(from: position, translation: translation)
        }
        let host = TransparentHostingView(rootView: PresentationView(model: model, topInset: topInset))
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.clear.cgColor
        window.contentView = host
        viewingWindow = window
        model.fullscreenViewport = screen.frame.size
        mainWindow.orderOut(nil)
        window.makeKeyAndOrderFront(nil)
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                Task { @MainActor in
                    if let model = self?.model, model.showingFullscreenSettings { model.showingFullscreenSettings = false }
                    else { self?.dismiss() }
                }
                return nil
            }
            return event
        }
    }

    private func configure(_ window: NSWindow, mode: ViewingMode) {
        window.title = "随视 · 全屏观看"
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = model?.settings.transparentBackground == true || (model?.settings.backgroundOpacity ?? 1) < 1 ? .floating : .normal
        // Keep the video and the exit button interactive.
        window.ignoresMouseEvents = false
    }

    func updateAppearance() {
        if let viewingWindow { configure(viewingWindow, mode: .fullscreen) }
    }

    func dismiss() {
        if let fullscreenObserver { NotificationCenter.default.removeObserver(fullscreenObserver) }
        fullscreenObserver = nil
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil
        let exitingWindow = viewingWindow
        exitingWindow?.orderOut(nil)
        exitingWindow?.contentView = nil
        viewingWindow = nil
        model?.showingFullscreenSettings = false
        model?.viewingMode = .workbench
        mainWindow?.makeKeyAndOrderFront(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { dismiss(); return false }
}

struct MainWindowReader: NSViewRepresentable {
    let receive: (NSWindow) -> Void
    final class Reader: NativeCanvasView {
        var receive: ((NSWindow) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { DispatchQueue.main.async { [weak self] in self?.receive?(window) } }
        }
    }
    func makeNSView(context: Context) -> Reader { let view = Reader(); view.receive = receive; return view }
    func updateNSView(_ view: Reader, context: Context) { view.receive = receive }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: Reader, context: Context) -> CGSize? { .zero }
}
