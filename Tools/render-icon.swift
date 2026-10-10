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
    let bg = CGGradient(colorsSpace: space, colors: [color(0x16181B), color(0x060708)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: canvas.midX, y: canvas.minY), end: CGPoint(x: canvas.midX, y: canvas.maxY), options: [])

    // The app's power key: a raised dark disc with a coral power symbol.
    let center = CGPoint(x: canvas.midX, y: canvas.midY)
    let radius = 330 * k
    let disc = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 28 * k), blur: 70 * k, color: color(0x000000, 0.75))
    ctx.setFillColor(color(0x26282C))
    ctx.fillEllipse(in: disc)
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addEllipse(in: disc)
    ctx.clip()
    let discGrad = CGGradient(colorsSpace: space, colors: [color(0x323439), color(0x1F2124)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(discGrad, start: CGPoint(x: center.x, y: disc.minY), end: CGPoint(x: center.x, y: disc.maxY), options: [])
    ctx.restoreGState()
    ctx.setStrokeColor(color(0xFFFFFF, 0.09))
    ctx.setLineWidth(5 * k)
    ctx.strokeEllipse(in: disc.insetBy(dx: 2.5 * k, dy: 2.5 * k))

    // Power symbol. y grows downward here, so -90° points up.
    let coral = color(0xFF5C54)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 40 * k, color: color(0xFF5C54, 0.35))
    ctx.setStrokeColor(coral)
    ctx.setLineWidth(46 * k)
    ctx.setLineCap(.round)
    let gap: CGFloat = 0.30 * .pi
    ctx.addArc(center: CGPoint(x: center.x, y: center.y + 18 * k), radius: 158 * k,
               startAngle: -.pi / 2 + gap, endAngle: -.pi / 2 - gap + 2 * .pi, clockwise: false)
    ctx.move(to: CGPoint(x: center.x, y: center.y - 190 * k))
    ctx.addLine(to: CGPoint(x: center.x, y: center.y - 10 * k))
    ctx.strokePath()
    ctx.restoreGState()

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
