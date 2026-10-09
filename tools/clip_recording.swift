// Turns a simulator screen recording into the site's one-stroke video and poster.
// Usage: [ROTATE=ccw] swift clip_recording.swift <in.mov> <out.mp4> <out.png> <width> <height> [seconds=3] [poster_seconds=0.5]
// The recording must contain the moment rowing is started with a tap while the rower was stopped:
// the clip starts at the first frame that moves after the last stretch of stillness (the catch),
// runs for <seconds> (one stroke), and the poster is the frame <poster_seconds> in (halfway
// through the drive at 20 spm and a 1:2 ratio). Both are scaled to width x height.
import AVFoundation
import AppKit

let args = CommandLine.arguments
guard args.count >= 6 else { print("usage: clip_recording <in.mov> <out.mp4> <out.png> <w> <h> [seconds] [poster_seconds]"); exit(1) }
let outW = Int(args[4])!, outH = Int(args[5])!
let clipSeconds = args.count > 6 ? Double(args[6])! : 3
let posterSeconds = args.count > 7 ? Double(args[7])! : 0.5

let asset = AVURLAsset(url: URL(fileURLWithPath: args[1]))
let track = asset.tracks(withMediaType: .video)[0]
let reader = try! AVAssetReader(asset: asset)
let readerOut = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
reader.add(readerOut)
reader.startReading()

struct Frame { let t: Double; let image: CGImage; let sig: [UInt8] }
// No color management: keep the recording's pixel values exactly as the app drew them.
let ciContext = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])

// Set ROTATE=ccw when the app was recorded in landscape: the simulator's framebuffer stays portrait.
let rotate = ProcessInfo.processInfo.environment["ROTATE"] == "ccw"
func source(_ pb: CVPixelBuffer) -> CIImage {
    var ci = CIImage(cvPixelBuffer: pb)
    if rotate { ci = ci.oriented(.left); ci = ci.transformed(by: CGAffineTransform(translationX: -ci.extent.minX, y: -ci.extent.minY)) }
    return ci
}

func signature(_ pb: CVPixelBuffer) -> [UInt8] {
    // 48x48 grayscale thumbnail, for cheap frame-to-frame motion detection.
    let ci = source(pb)
    let sx = 48 / ci.extent.width, sy = 48 / ci.extent.height
    let small = ci.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
    var px = [UInt8](repeating: 0, count: 48 * 48 * 4)
    ciContext.render(small, toBitmap: &px, rowBytes: 48 * 4, bounds: CGRect(x: 0, y: 0, width: 48, height: 48),
                     format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
    return stride(from: 0, to: px.count, by: 4).map { UInt8((Int(px[$0]) + Int(px[$0 + 1]) + Int(px[$0 + 2])) / 3) }
}

func scaled(_ pb: CVPixelBuffer) -> CGImage {
    let ci = source(pb)
    let s = ci.transformed(by: CGAffineTransform(scaleX: CGFloat(outW) / ci.extent.width, y: CGFloat(outH) / ci.extent.height))
    return ciContext.createCGImage(s, from: CGRect(x: 0, y: 0, width: outW, height: outH), format: .BGRA8, colorSpace: CGColorSpaceCreateDeviceRGB())!
}

var frames: [Frame] = []
var first: Double?
while let sb = readerOut.copyNextSampleBuffer() {
    guard let pb = CMSampleBufferGetImageBuffer(sb) else { continue }
    let t = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sb))
    if first == nil { first = t }
    frames.append(Frame(t: t - first!, image: scaled(pb), sig: signature(pb)))
}
print("read \(frames.count) frames, \(frames.last!.t)s")

func diff(_ a: [UInt8], _ b: [UInt8]) -> Int { zip(a, b).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) } }
let diffs = (1..<frames.count).map { diff(frames[$0].sig, frames[$0 - 1].sig) }
let threshold = 200
// The recording only emits frames when the screen changes, so stillness is measured in time:
// the onset is the last moving frame that follows at least half a second without motion.
var onset = -1, lastMotion = -1.0
for (i, d) in diffs.enumerated() where d >= threshold {
    let t = frames[i + 1].t
    if t - lastMotion >= 0.5 { onset = i + 1 }
    lastMotion = t
}
guard onset >= 0 else { print("no still-then-moving transition found"); exit(1) }
let t0 = frames[onset].t
print("onset frame \(onset) at \(t0)s")

func nearest(_ t: Double) -> Frame { frames.min { abs($0.t - t) < abs($1.t - t) }! }
let rep = NSBitmapImageRep(cgImage: nearest(t0 + posterSeconds).image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[3]))

let url = URL(fileURLWithPath: args[2])
try? FileManager.default.removeItem(at: url)
let writer = try! AVAssetWriter(outputURL: url, fileType: .mp4)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: outW, AVVideoHeightKey: outH,
    AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 1_500_000, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel],
])
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    kCVPixelBufferWidthKey as String: outW, kCVPixelBufferHeightKey as String: outH,
])
writer.add(input)
writer.startWriting()
writer.startSession(atSourceTime: .zero)
let fps = 30.0
for i in 0..<Int(clipSeconds * fps) {
    while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.002) }
    var pb: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pb)
    CVPixelBufferLockBaseAddress(pb!, [])
    let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb!), width: outW, height: outH, bitsPerComponent: 8,
                        bytesPerRow: CVPixelBufferGetBytesPerRow(pb!), space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    ctx.draw(nearest(t0 + Double(i) / fps).image, in: CGRect(x: 0, y: 0, width: outW, height: outH))
    CVPixelBufferUnlockBaseAddress(pb!, [])
    adaptor.append(pb!, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: CMTimeScale(fps)))
}
input.markAsFinished()
let sem = DispatchSemaphore(value: 0)
writer.finishWriting { sem.signal() }
sem.wait()
print(writer.status == .completed ? "wrote \(args[2]) and \(args[3])" : "failed: \(String(describing: writer.error))")
