import AVFoundation
import Vision
import ImageIO
import MotionCore

struct FaceMeasurement {
    let angle: Double?
    let timestamp: TimeInterval
    var confidence: Double = 1
}

final class CameraTracker: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    var onMeasurement: ((FaceMeasurement) -> Void)?
    var onState: ((Bool, String) -> Void)?
    private let queue = DispatchQueue(label: "eyes.camera", qos: .userInitiated)
    private let request = VNDetectFaceLandmarksRequest()
    private var configured = false
    private var wanted = false // Accessed only on queue.
    private var generation = 0
    private var lastFrameTime = 0.0
    private var failureObservers: [NSObjectProtocol] = []

    override init() {
        super.init()
        for name in [AVCaptureSession.runtimeErrorNotification, AVCaptureSession.wasInterruptedNotification] {
            let observer = NotificationCenter.default.addObserver(forName: name, object: session, queue: nil) { [weak self] note in
                let message = (note.userInfo?[AVCaptureSessionErrorKey] as? Error)?.localizedDescription
                    ?? "摄像头暂时不可用，请检查设备后重新开启。"
                self?.queue.async { [weak self] in
                    guard let self, self.wanted else { return }
                    self.wanted = false
                    self.generation += 1
                    if self.session.isRunning { self.session.stopRunning() }
                    self.report(false, message)
                }
            }
            failureObservers.append(observer)
        }
    }

    deinit { failureObservers.forEach { NotificationCenter.default.removeObserver($0) } }

    func start() {
        queue.async { [weak self] in
            guard let self else { return }
            self.wanted = true
            self.generation += 1
            let token = self.generation
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: self.startAuthorized(token: token)
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                    self?.queue.async { [weak self] in
                        guard let self, self.wanted, self.generation == token else { return }
                        if granted { self.startAuthorized(token: token) }
                        else { self.report(false, "摄像头权限未开启，请在系统设置中允许访问。") }
                    }
                }
            default: self.report(false, "摄像头权限未开启，请前往系统设置 → 隐私与安全性 → 摄像头。")
            }
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.wanted = false
            self.generation += 1
            if self.session.isRunning { self.session.stopRunning() }
            self.report(false, "摄像头已关闭")
        }
    }

    private func startAuthorized(token: Int) {
        guard wanted, generation == token else { return }
        do {
            if !configured {
                session.beginConfiguration()
                defer { session.commitConfiguration() }
                session.sessionPreset = .vga640x480
                guard let camera = AVCaptureDevice.default(for: .video) else {
                    throw CameraError.unavailable
                }
                let input = try AVCaptureDeviceInput(device: camera)
                guard session.canAddInput(input) else { throw CameraError.unavailable }
                session.addInput(input)
                let output = AVCaptureVideoDataOutput()
                output.alwaysDiscardsLateVideoFrames = true
                output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                output.setSampleBufferDelegate(self, queue: queue)
                guard session.canAddOutput(output) else {
                    session.removeInput(input)
                    throw CameraError.unavailable
                }
                session.addOutput(output)
                if let connection = output.connection(with: .video), connection.isVideoMirroringSupported {
                    connection.automaticallyAdjustsVideoMirroring = false
                    connection.isVideoMirrored = false
                }
                configured = true
            }
            lastFrameTime = 0
            session.startRunning()
            report(session.isRunning, session.isRunning ? "等待人脸" : "摄像头启动失败，请检查是否被其他应用占用。")
        } catch {
            report(false, "无法使用摄像头：\(error.localizedDescription)")
        }
    }

    private func report(_ running: Bool, _ message: String) {
        DispatchQueue.main.async { [weak self] in self?.onState?(running, message) }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard wanted, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastFrameTime >= 1.0 / 24 else { return }
        lastFrameTime = now
        let angle: Double?
        var confidence = 0.0
        do {
            try VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up).perform([request])
            let face = request.results?.filter { $0.confidence >= 0.6 }
                .max(by: { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height })
            confidence = Double(face?.confidence ?? 0)
            if let face, let first = center(face.landmarks?.leftEye, in: face.boundingBox),
               let second = center(face.landmarks?.rightEye, in: face.boundingBox) {
                angle = MotionGeometry.eyeAngle(first: first, second: second,
                    imageSize: CGSize(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer)))
            } else { angle = face?.roll.map { $0.doubleValue * 180 / .pi } }
        } catch { angle = nil }
        DispatchQueue.main.async { [weak self] in
            self?.onMeasurement?(FaceMeasurement(angle: angle, timestamp: now, confidence: confidence))
        }
    }

    private func center(_ region: VNFaceLandmarkRegion2D?, in box: CGRect) -> CGPoint? {
        guard let region, region.pointCount > 0 else { return nil }
        let points = region.normalizedPoints
        let x = points.reduce(0.0) { $0 + Double($1.x) } / Double(points.count)
        let y = points.reduce(0.0) { $0 + Double($1.y) } / Double(points.count)
        return CGPoint(x: box.minX + x * box.width, y: box.minY + y * box.height)
    }

    enum CameraError: LocalizedError {
        case unavailable
        var errorDescription: String? { "未找到可用的摄像头。" }
    }
}
