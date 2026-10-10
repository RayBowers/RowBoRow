// Renders one looping video per character in the RowBoRow app, using the app's own drawing code.
// Usage: render_rower_videos <out_dir>   (also writes <out_dir>/manifest.json)
// Compiled together with the app's figure sources by tools/make_rower_videos.sh.
// One full stroke (drive + hold + recovery) at 20 spm and a 1:2 ratio = 3 s, 90 frames at 30 fps,
// starting at the catch so the loop is seamless. 500x500, black background, cyan foreground.
import SwiftUI
import AVFoundation
import AppKit

let side = 500
let fps = 30
let frames = 90
let ratio = 2.0
let cyan = Color(red: 73 / 255, green: 224 / 255, blue: 250 / 255)

/// "T. rex" -> "t_rex", "WiFi Bars" -> "wifi_bars", "Handle, vertical" -> "handle_vertical"
func slug(_ name: String) -> String {
    name.lowercased()
        .map { $0.isLetter || $0.isNumber ? String($0) : "_" }.joined()
        .split(separator: "_", omittingEmptySubsequences: true).joined(separator: "_")
}

@MainActor func frame(_ figure: Figure, _ cycle: Double) -> CGImage {
    let view = Canvas { context, size in
        RowingScene(cycle: cycle, recoveryRatio: ratio, facing: .right, size: size, ink: cyan, figure: figure)
            .draw(in: context)
    }
    .backgroundStyle(Color.black)
    .frame(width: CGFloat(side), height: CGFloat(side))
    .background(Color.black)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 1
    return renderer.cgImage!
}

@MainActor func pixelBuffer(_ img: CGImage, _ pool: CVPixelBufferPool) -> CVPixelBuffer {
    var pb: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb)
    let buf = pb!
    CVPixelBufferLockBaseAddress(buf, [])
    let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buf), width: side, height: side, bitsPerComponent: 8,
                        bytesPerRow: CVPixelBufferGetBytesPerRow(buf), space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: side, height: side))
    CVPixelBufferUnlockBaseAddress(buf, [])
    return buf
}

@MainActor func render(_ figure: Figure, to url: URL) async {
    try? FileManager.default.removeItem(at: url)
    let writer = try! AVAssetWriter(outputURL: url, fileType: .mp4)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: side, AVVideoHeightKey: side,
        AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 1_200_000, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                                          AVVideoMaxKeyFrameIntervalKey: fps],
    ])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: side, kCVPixelBufferHeightKey as String: side,
    ])
    writer.add(input)
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)
    for i in 0..<frames {
        while !input.isReadyForMoreMediaData { try? await Task.sleep(nanoseconds: 2_000_000) }
        let buf = pixelBuffer(frame(figure, Double(i) / Double(frames)), adaptor.pixelBufferPool!)
        adaptor.append(buf, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: CMTimeScale(fps)))
    }
    input.markAsFinished()
    await writer.finishWriting()
    if writer.status != .completed { print("failed: \(figure.name): \(String(describing: writer.error))"); exit(1) }
}

@main struct Main {
    @MainActor static func main() async {
        guard CommandLine.arguments.count == 2 else { print("usage: render_rower_videos <out_dir>"); exit(1) }
        let dir = URL(fileURLWithPath: CommandLine.arguments[1])
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // manifest.json lists the characters in picker order (group order from FigureCategory, figures alphabetical within a group; see Figure.ordered).
        var manifest: [[String: String]] = []
        for category in FigureCategory.ordered {
            for figure in Figure.ordered(in: category) {
                let name = slug(figure.name)
                await render(figure, to: dir.appendingPathComponent("\(name).mp4"))
                manifest.append(["file": name, "name": figure.name, "category": category.rawValue])
                print("rendered \(name)")
            }
        }
        let json = try! JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted])
        try! json.write(to: dir.appendingPathComponent("manifest.json"))
    }
}
