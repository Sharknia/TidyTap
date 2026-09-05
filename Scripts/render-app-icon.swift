import AppKit

// Editable, dependency-free artwork. Run from the repository root.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("build/TidyTap.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
}
func draw() {
    let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 186, yRadius: 186)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
    shadow.shadowOffset = NSSize(width: 0, height: -16); shadow.shadowBlurRadius = 24; shadow.set()
    color(0.04, 0.29, 0.36).setFill(); tile.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: color(0.06, 0.27, 0.36), ending: color(0.12, 0.69, 0.70))!.draw(in: tile, angle: 70)
    NSColor.white.withAlphaComponent(0.18).setStroke(); tile.lineWidth = 3; tile.stroke()

    // A single tactile keycap and cursor: keyboard + mouse, without tiny text.
    let keyBase = NSBezierPath(roundedRect: NSRect(x: 258, y: 296, width: 474, height: 462), xRadius: 100, yRadius: 100)
    color(0.46, 0.76, 0.77).setFill(); keyBase.fill()
    let key = NSBezierPath(roundedRect: NSRect(x: 258, y: 330, width: 474, height: 446), xRadius: 100, yRadius: 100)
    NSGradient(starting: color(0.81, 0.94, 0.92), ending: color(0.98, 1, 0.97))!.draw(in: key, angle: 90)
    color(0.06, 0.36, 0.42).setFill()
    NSBezierPath(roundedRect: NSRect(x: 370, y: 597, width: 240, height: 58), xRadius: 17, yRadius: 17).fill()
    NSBezierPath(roundedRect: NSRect(x: 459, y: 454, width: 62, height: 180), xRadius: 17, yRadius: 17).fill()

    let cursor = NSBezierPath()
    cursor.move(to: NSPoint(x: 610, y: 528))
    for point in [NSPoint(x: 806, y: 382), NSPoint(x: 716, y: 364), NSPoint(x: 671, y: 278)] { cursor.line(to: point) }
    cursor.close()
    cursor.lineJoinStyle = .round; cursor.lineWidth = 22
    color(0.94, 1, 0.96).setStroke(); cursor.stroke()
    color(0.04, 0.21, 0.27).setFill(); cursor.fill()
}

for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        draw()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        let name = "icon_\(size)x\(size)\(suffix).png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
    }
}
print("Rendered build/TidyTap.iconset; run iconutil -c icns build/TidyTap.iconset -o Resources/TidyTap.icns")
