// Renders a character halfway through the drive as a square PNG, using the app's own drawing code.
// Usage: render_icon <Figure raw value, e.g. Robot> <side px> <out.png>
// Cyan on black, 1:2 ratio, so the drive is the first third of the stroke and halfway is cycle 1/6.
import SwiftUI
import AppKit

@main struct Main {
    @MainActor static func main() {
        let a = CommandLine.arguments
        guard a.count == 4, let figure = Figure(rawValue: a[1]), let side = Int(a[2]) else {
            print("usage: render_icon <figure> <side> <out.png>"); exit(1)
        }
        let cyan = Color(red: 73 / 255, green: 224 / 255, blue: 250 / 255)
        let view = Canvas { context, size in
            RowingScene(cycle: 1.0 / 6, recoveryRatio: 2, facing: .right, size: size, ink: cyan, figure: figure).draw(in: context)
        }
        .backgroundStyle(Color.black)
        .frame(width: CGFloat(side), height: CGFloat(side))
        .background(Color.black)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let rep = NSBitmapImageRep(cgImage: renderer.cgImage!)
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[3]))
    }
}
