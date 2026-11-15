import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func render(_ pixels: Int) -> Data {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let size = CGFloat(pixels)
    let inset = size * 0.1
    let tile = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let path = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225)
    NSGradient(starting: NSColor(white: 1, alpha: 1), ending: NSColor(white: 0.93, alpha: 1))!.draw(in: path, angle: -90)
    NSColor(white: 0, alpha: 0.12).setStroke()
    path.lineWidth = max(size / 512, 0.5)
    path.stroke()
    func unit(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
        NSRect(x: tile.minX + x * tile.width / 100, y: tile.maxY - (y + h) * tile.height / 100, width: w * tile.width / 100, height: h * tile.height / 100)
    }
    NSColor(white: 0.1, alpha: 1).setFill()
    NSBezierPath(ovalIn: unit(27, 58, 22, 22)).fill()
    NSColor(srgbRed: 0, green: 0.667, blue: 1, alpha: 1).setFill()
    let caret = unit(59, 20, 14, 60)
    NSBezierPath(roundedRect: caret, xRadius: caret.width / 2, yRadius: caret.width / 2).fill()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: output.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(base * 2).write(to: output.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
