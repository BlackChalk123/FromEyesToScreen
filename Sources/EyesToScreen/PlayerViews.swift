import SwiftUI
import AVFoundation

final class PlayerSurface: NativeCanvasView {
    let videoLayer = AVPlayerLayer()
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        videoLayer.videoGravity = .resizeAspect
        layer?.addSublayer(videoLayer)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        videoLayer.frame = bounds
        CATransaction.commit()
    }
}

struct VideoSurface: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> PlayerSurface {
        let view = PlayerSurface()
        view.videoLayer.player = player
        return view
    }
    func updateNSView(_ view: PlayerSurface, context: Context) {
        if view.videoLayer.player !== player { view.videoLayer.player = player }
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: PlayerSurface, context: Context) -> CGSize? {
        NativeSurfaceLayout.size(for: proposal)
    }
}

final class CameraSurface: NativeCanvasView {
    let preview = AVCaptureVideoPreviewLayer()
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        preview.videoGravity = .resizeAspectFill
        layer?.addSublayer(preview)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        preview.frame = bounds
        CATransaction.commit()
    }
    func mirror() {
        guard let connection = preview.connection, connection.isVideoMirroringSupported else { return }
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = true
    }
}

struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    let running: Bool
    func makeNSView(context: Context) -> CameraSurface {
        let view = CameraSurface()
        view.preview.session = session
        view.mirror()
        return view
    }
    func updateNSView(_ view: CameraSurface, context: Context) { view.mirror() }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: CameraSurface, context: Context) -> CGSize? {
        NativeSurfaceLayout.size(for: proposal)
    }
}
