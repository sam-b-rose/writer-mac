import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 4,
      let windowData = FileManager.default.contents(atPath: arguments[1]),
      let window = NSBitmapImageRep(data: windowData)?.cgImage,
      let backgroundImage = NSImage(contentsOfFile: arguments[2]),
      let background = backgroundImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write(Data("usage: frame-screenshot.swift <window.png> <background> <out.png>\n".utf8))
    exit(1)
}

let margin = min(220, window.width / 10)
let scale = CGFloat(margin) / 220
let radius = 52 * scale
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

let fill = max(CGFloat(width) / CGFloat(background.width), CGFloat(height) / CGFloat(background.height))
let fillSize = CGSize(width: CGFloat(background.width) * fill, height: CGFloat(background.height) * fill)
context.draw(background, in: CGRect(x: (CGFloat(width) - fillSize.width) / 2, y: (CGFloat(height) - fillSize.height) / 2,
                                    width: fillSize.width, height: fillSize.height))

let frame = CGRect(x: margin, y: margin, width: window.width, height: window.height)
let shape = CGPath(roundedRect: frame, cornerWidth: radius, cornerHeight: radius, transform: nil)

context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -50 * scale), blur: 140 * scale, color: color(0x000000, 0.55))
context.addPath(shape)
context.setFillColor(color(0x161616))
context.fillPath()
context.restoreGState()

context.saveGState()
context.addPath(shape)
context.clip()
context.draw(window, in: frame)
context.restoreGState()

context.addPath(CGPath(roundedRect: frame.insetBy(dx: 1, dy: 1), cornerWidth: radius - 1, cornerHeight: radius - 1, transform: nil))
context.setStrokeColor(color(0xffffff, 0.18))
context.setLineWidth(2 * scale)
context.strokePath()

let output = NSBitmapImageRep(cgImage: context.makeImage()!)
try! output.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: arguments[3]))
