import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func render(size: Int, mac: Bool, to path: String) {
    let s = CGFloat(size)
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: (mac ? CGImageAlphaInfo.premultipliedLast : CGImageAlphaInfo.noneSkipLast).rawValue)!
    ctx.scaleBy(x: s / 1024, y: s / 1024)
    // CG origin is bottom-left; flip so y grows downward.
    ctx.translateBy(x: 0, y: 1024)
    ctx.scaleBy(x: 1, y: -1)

    var canvas = CGRect(x: 0, y: 0, width: 1024, height: 1024)
    if mac {
        canvas = canvas.insetBy(dx: 100, dy: 100)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 24, color: color(0x000000, 0.45))
        ctx.addPath(CGPath(roundedRect: canvas, cornerWidth: 185, cornerHeight: 185, transform: nil))
        ctx.setFillColor(color(0x0B0C0E))
        ctx.fillPath()
        ctx.restoreGState()
        ctx.addPath(CGPath(roundedRect: canvas, cornerWidth: 185, cornerHeight: 185, transform: nil))
        ctx.clip()
    }
    let k = canvas.width / 1024
    func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
        CGRect(x: canvas.minX + x * k, y: canvas.minY + y * k, width: w * k, height: h * k)
    }

    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let bg = CGGradient(colorsSpace: space, colors: [color(0x1C2026), color(0x08090B)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: canvas.midX, y: canvas.minY), end: CGPoint(x: canvas.midX, y: canvas.maxY), options: [])

    // Soft mint glow behind the remote.
    let glow = CGGradient(colorsSpace: space, colors: [color(0x5CE3A6, 0.28), color(0x5CE3A6, 0)] as CFArray, locations: [0, 1])!
    let gc = CGPoint(x: canvas.midX, y: canvas.minY + 400 * k)
    ctx.drawRadialGradient(glow, startCenter: gc, startRadius: 0, endCenter: gc, endRadius: 460 * k, options: [])

    // Remote body.
    let body = r(302, 150, 420, 800)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 24 * k), blur: 50 * k, color: color(0x000000, 0.6))
    ctx.addPath(CGPath(roundedRect: body, cornerWidth: 200 * k, cornerHeight: 200 * k, transform: nil))
    ctx.setFillColor(color(0x24282F))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: body, cornerWidth: 200 * k, cornerHeight: 200 * k, transform: nil))
    ctx.clip()
    let bodyGrad = CGGradient(colorsSpace: space, colors: [color(0x353A43), color(0x1A1D22)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bodyGrad, start: CGPoint(x: body.midX, y: body.minY), end: CGPoint(x: body.midX, y: body.maxY), options: [])
    ctx.restoreGState()
    ctx.addPath(CGPath(roundedRect: body.insetBy(dx: 2 * k, dy: 2 * k), cornerWidth: 198 * k, cornerHeight: 198 * k, transform: nil))
    ctx.setStrokeColor(color(0xFFFFFF, 0.10))
    ctx.setLineWidth(4 * k)
    ctx.strokePath()

    // D-pad ring + OK.
    let center = CGPoint(x: canvas.minX + 512 * k, y: canvas.minY + 400 * k)
    ctx.setStrokeColor(color(0x5CE3A6))
    ctx.setLineWidth(40 * k)
    ctx.addArc(center: center, radius: 138 * k, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.strokePath()
    ctx.setFillColor(color(0x5CE3A6))
    ctx.fillEllipse(in: CGRect(x: center.x - 62 * k, y: center.y - 62 * k, width: 124 * k, height: 124 * k))

    // A grid of small keys.
    ctx.setFillColor(color(0x4A505B))
    for row in 0..<2 {
        for col in 0..<3 {
            let x = 376 + CGFloat(col) * 100
            let y = 628 + CGFloat(row) * 100
            ctx.addPath(CGPath(roundedRect: r(x, y, 72, 72), cornerWidth: 22 * k, cornerHeight: 22 * k, transform: nil))
        }
    }
    ctx.fillPath()

    let image = ctx.makeImage()!
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

let out = CommandLine.arguments[1]
render(size: 1024, mac: false, to: "\(out)/icon-ios-1024.png")
for (pt, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    render(size: pt * scale, mac: true, to: "\(out)/icon-mac-\(pt)@\(scale)x.png")
}
