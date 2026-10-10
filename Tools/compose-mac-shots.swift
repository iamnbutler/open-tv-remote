// Composites macOS window captures onto 2880x1800 App Store screenshot canvases.
// Usage: swift Tools/compose-mac-shots.swift <captures-dir> <out-dir>
import AppKit

let args = CommandLine.arguments
guard args.count == 3 else { fatalError("usage: compose-mac-shots <captures-dir> <out-dir>") }
let inDir = URL(fileURLWithPath: args[1])
let outDir = URL(fileURLWithPath: args[2])
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let shots: [(file: String, title: String, subtitle: String)] = [
    ("1-dpad", "A TV remote\nthat's actually free.", "No subscriptions, trials, ads or accounts."),
    ("2-touchpad", "Swipe to\nnavigate.", "A touchpad, D-pad and number keys."),
    ("3-keypad", "Every button\nyou need.", "Volume, channels, playback, power and keyboard."),
    ("4-apps", "Jump straight\nto your apps.", "Works with Google TV, Android TV, Roku, Samsung and LG."),
]

let size = CGSize(width: 2880, height: 1800)
let accent = NSColor(red: 0.36, green: 0.89, blue: 0.62, alpha: 1)

for shot in shots {
    guard let window = NSImage(contentsOf: inDir.appendingPathComponent("\(shot.file).png")),
          let rep = window.representations.first else { continue }
    let image = NSImage(size: size)
    image.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext

    let gradient = NSGradient(colors: [NSColor(white: 0.10, alpha: 1), NSColor(white: 0.02, alpha: 1)])!
    gradient.draw(in: CGRect(origin: .zero, size: size), angle: -60)

    // Window on the right, scaled to fill most of the height.
    let pixel = CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
    let scale = 1560 / pixel.height
    let w = pixel.width * scale, h = pixel.height * scale
    let frame = CGRect(x: size.width - w - 300, y: (size.height - h) / 2, width: w, height: h)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -30), blur: 90, color: NSColor.black.withAlphaComponent(0.7).cgColor)
    window.draw(in: frame)
    ctx.restoreGState()

    // Headline on the left.
    let left: CGFloat = 220
    let textWidth = frame.minX - left - 140
    let title = NSAttributedString(string: shot.title, attributes: [
        .font: NSFont.systemFont(ofSize: 150, weight: .heavy),
        .foregroundColor: NSColor.white,
    ])
    let subtitle = NSAttributedString(string: shot.subtitle, attributes: [
        .font: NSFont.systemFont(ofSize: 62, weight: .medium),
        .foregroundColor: NSColor(white: 0.62, alpha: 1),
    ])
    let titleRect = title.boundingRect(with: CGSize(width: textWidth, height: 1000), options: .usesLineFragmentOrigin)
    let subRect = subtitle.boundingRect(with: CGSize(width: textWidth, height: 600), options: .usesLineFragmentOrigin)
    let block = titleRect.height + 60 + subRect.height
    var y = (size.height + block) / 2
    let bar = CGRect(x: left, y: y + 50, width: 120, height: 14)
    accent.setFill()
    NSBezierPath(roundedRect: bar, xRadius: 7, yRadius: 7).fill()
    y -= titleRect.height
    title.draw(with: CGRect(x: left, y: y, width: textWidth, height: titleRect.height), options: .usesLineFragmentOrigin)
    y -= 60 + subRect.height
    subtitle.draw(with: CGRect(x: left, y: y, width: textWidth, height: subRect.height), options: .usesLineFragmentOrigin)

    image.unlockFocus()

    // Write exactly 2880x1800 regardless of screen scale.
    let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    out.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
    image.draw(in: CGRect(origin: .zero, size: size))
    NSGraphicsContext.restoreGraphicsState()
    try out.representation(using: .png, properties: [:])!.write(to: outDir.appendingPathComponent("mac-\(shot.file).png"))
    print("mac-\(shot.file).png")
}
