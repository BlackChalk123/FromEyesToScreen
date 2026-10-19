import AppKit
import AVFoundation

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

func drawScene(_ context: CGContext, width: Int, height: Int, phase: Double) {
    let w = CGFloat(width), h = CGFloat(height)
    let colors = [NSColor(red: 0.06, green: 0.12, blue: 0.18, alpha: 1).cgColor,
                  NSColor(red: 0.22, green: 0.39, blue: 0.41, alpha: 1).cgColor,
                  NSColor(red: 0.70, green: 0.76, blue: 0.58, alpha: 1).cgColor]
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 0.65, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: h), end: .zero, options: [])
    context.setFillColor(NSColor.white.withAlphaComponent(0.5).cgColor)
    for i in 0..<43 {
        let x = CGFloat((i * 173 + 27) % width)
        let y = h * (0.40 + CGFloat((i * 97) % 100) / 170)
        let r = CGFloat(i % 3 + 1) * 0.6
        context.fillEllipse(in: CGRect(x: x, y: y, width: r, height: r))
    }
    let sun = CGPoint(x: w * 0.74, y: h * 0.52 + sin(phase * .pi * 2) * 4)
    context.setFillColor(NSColor(red: 0.91, green: 0.86, blue: 0.63, alpha: 0.07).cgColor)
    context.fillEllipse(in: CGRect(x: sun.x - 94, y: sun.y - 94, width: 188, height: 188))
    context.setFillColor(NSColor(red: 0.91, green: 0.86, blue: 0.63, alpha: 0.13).cgColor)
    context.fillEllipse(in: CGRect(x: sun.x - 72, y: sun.y - 72, width: 144, height: 144))
    context.setFillColor(NSColor(red: 0.91, green: 0.86, blue: 0.68, alpha: 1).cgColor)
    context.fillEllipse(in: CGRect(x: sun.x - 48, y: sun.y - 48, width: 96, height: 96))
    for layer in 0..<4 {
        let path = CGMutablePath()
        path.move(to: .zero)
        let baseline = h * (0.32 - CGFloat(layer) * 0.055)
        for x in stride(from: 0, through: width, by: 4) {
            let y = baseline + sin(CGFloat(x) / (100 + CGFloat(layer) * 47) + CGFloat(layer) * 2 + phase * 0.15) * (29 + CGFloat(layer) * 7)
            path.addLine(to: CGPoint(x: CGFloat(x), y: y))
        }
        path.addLine(to: CGPoint(x: w, y: 0)); path.closeSubpath()
        context.setFillColor(NSColor(red: 0.08 - CGFloat(layer) * 0.012,
                                     green: 0.23 - CGFloat(layer) * 0.035,
                                     blue: 0.25 - CGFloat(layer) * 0.035, alpha: 1).cgColor)
        context.addPath(path); context.fillPath()
    }
    context.saveGState()
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    let label = "让画面，跟随视线。"
    label.draw(at: CGPoint(x: w * 0.075, y: h * 0.55), withAttributes: [
        .font: NSFont.systemFont(ofSize: 34, weight: .light), .foregroundColor: NSColor.white.withAlphaComponent(0.93)
    ])
    "A DIFFERENT POINT OF VIEW".draw(at: CGPoint(x: w * 0.078, y: h * 0.49), withAttributes: [
        .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .medium), .kern: 3,
        .foregroundColor: NSColor.white.withAlphaComponent(0.6)
    ])
    "随视 / FROM EYES TO SCREEN".draw(at: CGPoint(x: w * 0.078, y: h * 0.10), withAttributes: [
        .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .regular), .kern: 1.8,
        .foregroundColor: NSColor.white.withAlphaComponent(0.5)
    ])
    NSGraphicsContext.restoreGraphicsState()
    context.restoreGState()
}

let movieURL = directory.appendingPathComponent("Example.mov")
if !FileManager.default.fileExists(atPath: movieURL.path) {
    let writer = try AVAssetWriter(outputURL: movieURL, fileType: .mov)
    let width = 960, height = 540, frameCount = 240
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
        AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 1_500_000]
    ])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
        kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
        kCVPixelBufferCGImageCompatibilityKey as String: true,
        kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
    ])
    writer.add(input)
    guard writer.startWriting() else { fatalError("Could not start sample video: \(String(describing: writer.error))") }
    writer.startSession(atSourceTime: .zero)
    for frame in 0..<frameCount {
        while !input.isReadyForMoreMediaData {
            if writer.status == .failed { fatalError("Sample video failed: \(String(describing: writer.error))") }
            Thread.sleep(forTimeInterval: 0.002)
        }
        var buffer: CVPixelBuffer?
        guard let pool = adaptor.pixelBufferPool,
              CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let buffer else { fatalError("No pixel buffer") }
        CVPixelBufferLockBaseAddress(buffer, [])
        autoreleasepool {
            let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)!
            drawScene(context, width: width, height: height, phase: Double(frame) / Double(frameCount))
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 24)) else { fatalError("Could not append sample frame") }
    }
    input.markAsFinished()
    let done = DispatchSemaphore(value: 0)
    writer.finishWriting { done.signal() }
    done.wait()
    guard writer.status == .completed else { fatalError("Sample video failed: \(String(describing: writer.error))") }
}

let iconset = directory.appendingPathComponent("AppIcon.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for (name, pixels) in [("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
                       ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
                       ("icon_512x512", 512), ("icon_512x512@2x", 1024)] {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let c = NSGraphicsContext.current!.cgContext
    let scale = CGFloat(pixels) / 1024
    c.scaleBy(x: scale, y: scale)
    NSColor(red: 0.06, green: 0.09, blue: 0.11, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 40, y: 40, width: 944, height: 944), xRadius: 215, yRadius: 215).fill()
    c.translateBy(x: 512, y: 512); c.rotate(by: -.pi / 12)
    c.setStrokeColor(NSColor(red: 0.67, green: 0.91, blue: 0.78, alpha: 1).cgColor); c.setLineWidth(36)
    c.addPath(CGPath(roundedRect: CGRect(x: -310, y: -205, width: 620, height: 410), cornerWidth: 60, cornerHeight: 60, transform: nil))
    c.strokePath()
    c.setFillColor(NSColor(red: 0.67, green: 0.91, blue: 0.78, alpha: 1).cgColor)
    c.move(to: CGPoint(x: -55, y: -90)); c.addLine(to: CGPoint(x: 95, y: 0)); c.addLine(to: CGPoint(x: -55, y: 90)); c.closePath(); c.fillPath()
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name + ".png"))
}
// Package PNG-backed ICNS entries directly; no external icon conversion service is needed.
func bigEndianSize(_ size: Int) -> Data {
    var value = UInt32(size).bigEndian
    return withUnsafeBytes(of: &value) { Data($0) }
}
var iconBody = Data()
for (type, filename) in [("ic07", "icon_128x128"), ("ic08", "icon_256x256"), ("ic09", "icon_512x512"),
                         ("ic10", "icon_512x512@2x"), ("ic11", "icon_16x16@2x"), ("ic12", "icon_32x32@2x"),
                         ("ic13", "icon_128x128@2x"), ("ic14", "icon_256x256@2x")] {
    let png = try Data(contentsOf: iconset.appendingPathComponent(filename + ".png"))
    iconBody.append(Data(type.utf8)); iconBody.append(bigEndianSize(png.count + 8)); iconBody.append(png)
}
var icon = Data("icns".utf8)
icon.append(bigEndianSize(iconBody.count + 8)); icon.append(iconBody)
try icon.write(to: directory.appendingPathComponent("AppIcon.icns"))
print("Created local sample video and icon assets.")
