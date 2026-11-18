import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 3,
      let data = FileManager.default.contents(atPath: arguments[1]),
      let window = NSBitmapImageRep(data: data)?.cgImage else {
    FileHandle.standardError.write(Data("usage: frame-screenshot.swift <window.png> <out.png>\n".utf8))
    exit(1)
}

let margin = 220
let width = window.width + margin * 2
let height = window.height + margin * 2
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [
        CGFloat((hex >> 16) & 255) / 255, CGFloat((hex >> 8) & 255) / 255, CGFloat(hex & 255) / 255, alpha,
    ])!
}

func gradient(_ stops: [(UInt32, CGFloat, CGFloat)]) -> CGGradient {
    CGGradient(colorSpace: space,
               colorComponents: stops.flatMap { hex, alpha, _ in
                   let c = color(hex, alpha).components!
                   return [c[0], c[1], c[2], c[3]]
               },
               locations: stops.map { $0.2 }, count: stops.count)!
}

let canvas = CGPoint(x: width, y: height)
context.drawLinearGradient(
    gradient([(0x1b1464, 1, 0), (0x6a2c9e, 1, 0.45), (0xd1507c, 1, 0.75), (0xf2a65a, 1, 1)]),
    start: CGPoint(x: 0, y: canvas.y), end: CGPoint(x: canvas.x, y: 0), options: [])

let blobs: [(CGFloat, CGFloat, CGFloat, UInt32, CGFloat)] = [
    (0.15, 0.85, 0.55, 0x3f7bff, 0.55),
    (0.85, 0.15, 0.50, 0xffc371, 0.60),
    (0.80, 0.90, 0.40, 0xff5fa2, 0.45),
    (0.10, 0.10, 0.45, 0x2a0f5c, 0.60),
]
for (x, y, radius, hex, alpha) in blobs {
    context.drawRadialGradient(
        gradient([(hex, alpha, 0), (hex, 0, 1)]),
        startCenter: CGPoint(x: canvas.x * x, y: canvas.y * y), startRadius: 0,
        endCenter: CGPoint(x: canvas.x * x, y: canvas.y * y), endRadius: canvas.x * radius, options: [])
}

let frame = CGRect(x: margin, y: margin, width: window.width, height: window.height)
let shape = CGPath(roundedRect: frame, cornerWidth: 52, cornerHeight: 52, transform: nil)

context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -50), blur: 140, color: color(0x000000, 0.55))
context.addPath(shape)
context.setFillColor(color(0x161616))
context.fillPath()
context.restoreGState()

context.saveGState()
context.addPath(shape)
context.clip()
context.draw(window, in: frame)
context.restoreGState()

context.addPath(CGPath(roundedRect: frame.insetBy(dx: 1, dy: 1), cornerWidth: 51, cornerHeight: 51, transform: nil))
context.setStrokeColor(color(0xffffff, 0.18))
context.setLineWidth(2)
context.strokePath()

let output = NSBitmapImageRep(cgImage: context.makeImage()!)
try! output.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: arguments[2]))
