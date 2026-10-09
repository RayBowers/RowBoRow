// Usage: swift extract_frame.swift <video.mp4> <fraction 0..1> <out.png>
// Writes the frame at the given fraction of the video's duration as a 500x500 PNG.
// With fraction "sheet", writes a contact sheet of 12 evenly spaced frames instead.
import AVFoundation
import AppKit

let args = CommandLine.arguments
guard args.count == 4 else { print("usage: extract_frame <video> <fraction|sheet> <out.png>"); exit(1) }
let asset = AVURLAsset(url: URL(fileURLWithPath: args[1]))
let gen = AVAssetImageGenerator(asset: asset)
gen.requestedTimeToleranceBefore = .zero
gen.requestedTimeToleranceAfter = .zero
gen.appliesPreferredTrackTransform = true
let dur = CMTimeGetSeconds(asset.duration)

func frame(_ f: Double) -> CGImage {
    let t = CMTime(seconds: dur * f, preferredTimescale: 600)
    return try! gen.copyCGImage(at: t, actualTime: nil)
}
func write(_ img: CGImage, _ path: String) {
    let rep = NSBitmapImageRep(cgImage: img)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}
if args[2] == "sheet" {
    let n = 12, s = 200
    let ctx = CGContext(data: nil, width: s * 6, height: s * 2, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    for i in 0..<n {
        let img = frame(Double(i) / Double(n))
        ctx.draw(img, in: CGRect(x: (i % 6) * s, y: (1 - i / 6) * s, width: s, height: s))
    }
    write(ctx.makeImage()!, args[3])
} else {
    write(frame(Double(args[2])!), args[3])
}
