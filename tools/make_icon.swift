// Renders the 1024×1024 app icon: run `swift tools/make_icon.swift <output.png>`.
import AppKit
import CoreGraphics

let size: CGFloat = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let context = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!  // opaque: iOS icons must have no alpha

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func linear(_ colors: [CGColor], from start: CGPoint, to end: CGPoint) {
    let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: nil)!
    context.drawLinearGradient(gradient, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

// Background: warm ember gradient with a soft highlight up top (CoreGraphics y points up).
linear([color(0xFFB347), color(0xFF7A1A), color(0xE5420C)], from: CGPoint(x: 0, y: size), to: CGPoint(x: size, y: 0))
let glow = CGGradient(colorsSpace: space, colors: [color(0xFFFFFF, 0.35), color(0xFFFFFF, 0)] as CFArray, locations: nil)!
context.drawRadialGradient(glow, startCenter: CGPoint(x: 330, y: 820), startRadius: 0, endCenter: CGPoint(x: 330, y: 820), endRadius: 620, options: [])

func card(center: CGPoint, angle: CGFloat, fill: CGColor, shadow: Bool) {
    context.saveGState()
    context.translateBy(x: center.x, y: center.y)
    context.rotate(by: angle * .pi / 180)
    let rect = CGRect(x: -250, y: -330, width: 500, height: 660)
    let path = CGPath(roundedRect: rect, cornerWidth: 64, cornerHeight: 64, transform: nil)
    if shadow { context.setShadow(offset: CGSize(width: 0, height: -26), blur: 60, color: color(0x7A1E00, 0.45)) }
    context.addPath(path)
    context.setFillColor(fill)
    context.fillPath()
    context.restoreGState()
}

// A ghost card behind, the main card in front: a deck mid-flip.
card(center: CGPoint(x: 560, y: 520), angle: 11, fill: color(0xFFFFFF, 0.32), shadow: false)
card(center: CGPoint(x: 492, y: 500), angle: -7, fill: color(0xFFF8F1), shadow: true)

// Lightning bolt on the front card, in the accent gradient.
context.saveGState()
context.translateBy(x: 492, y: 500)
context.rotate(by: -7 * .pi / 180)
let bolt = CGMutablePath()
bolt.move(to: CGPoint(x: 40, y: 250))
bolt.addLine(to: CGPoint(x: -130, y: -10))
bolt.addLine(to: CGPoint(x: -5, y: -10))
bolt.addLine(to: CGPoint(x: -55, y: -250))
bolt.addLine(to: CGPoint(x: 140, y: 40))
bolt.addLine(to: CGPoint(x: 15, y: 40))
bolt.closeSubpath()
context.addPath(bolt)
context.clip()
linear([color(0xFF9A2E), color(0xE5420C)], from: CGPoint(x: 0, y: 250), to: CGPoint(x: 0, y: -250))
context.restoreGState()

// The tutor's sparkle: a four-point star breaking out of the top-right corner, with a small companion.
func sparkle(center: CGPoint, radius: CGFloat, waist: CGFloat, fill: CGColor) {
    let path = CGMutablePath()
    for index in 0..<8 {
        let angle = CGFloat(index) * .pi / 4 + .pi / 2
        let r = index.isMultiple(of: 2) ? radius : waist
        let point = CGPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r)
        index == 0 ? path.move(to: point) : path.addLine(to: point)
    }
    path.closeSubpath()
    context.saveGState()
    context.setShadow(offset: .zero, blur: 30, color: color(0xFFFFFF, 0.8))
    context.addPath(path)
    context.setFillColor(fill)
    context.fillPath()
    context.restoreGState()
}
sparkle(center: CGPoint(x: 770, y: 800), radius: 120, waist: 30, fill: color(0xFFFFFF))
sparkle(center: CGPoint(x: 880, y: 650), radius: 52, waist: 14, fill: color(0xFFF1C2))

let image = context.makeImage()!
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let destination = CGImageDestinationCreateWithURL(output as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("could not write \(output.path)") }
print("wrote \(output.path)")
