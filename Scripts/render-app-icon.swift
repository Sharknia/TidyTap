import AppKit

// Editable, dependency-free artwork. Run from the repository root.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("build/TidyTap.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
}

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat) -> NSColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: a)
}

func draw() {
    // One quiet, frosted-glass squircle on a transparent canvas. The broad margin
    // keeps the material legible in the Finder's small icon well.
    let tile = NSBezierPath(roundedRect: NSRect(x: 94, y: 94, width: 836, height: 836), xRadius: 205, yRadius: 205)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.16)
    shadow.shadowOffset = NSSize(width: 0, height: -13); shadow.shadowBlurRadius = 23; shadow.set()
    color(0.49, 0.57, 0.60, 0.30).setFill(); tile.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Pale blue-grey translucency; the narrow white rim is the icon's only bevel.
    NSGradient(colors: [
        color(0.88, 0.93, 0.94, 0.91),
        color(0.67, 0.76, 0.79, 0.87)
    ])!.draw(in: tile, angle: 90)
    color(1, 1, 1, 0.72).setStroke(); tile.lineWidth = 7; tile.stroke()

    // A clean raised T: enough depth to read as a control without becoming a keycap.
    let letter = NSBezierPath()
    letter.appendRoundedRect(NSRect(x: 318, y: 635, width: 388, height: 106), xRadius: 48, yRadius: 48)
    letter.appendRoundedRect(NSRect(x: 462, y: 335, width: 100, height: 350), xRadius: 46, yRadius: 46)
    NSGraphicsContext.saveGraphicsState()
    let letterShadow = NSShadow(); letterShadow.shadowColor = NSColor.black.withAlphaComponent(0.23)
    letterShadow.shadowOffset = NSSize(width: 0, height: -9); letterShadow.shadowBlurRadius = 10; letterShadow.set()
    color(1, 1, 1, 0.94).setFill(); letter.fill()
    NSGraphicsContext.restoreGraphicsState()
    color(1, 1, 1, 0.64).setStroke(); letter.lineWidth = 3; letter.stroke()

    let cursor = NSBezierPath()
    // The pointer faces the T from the lower-right rather than forming another frame.
    cursor.move(to: NSPoint(x: 654, y: 486))
    cursor.line(to: NSPoint(x: 810, y: 352))
    cursor.line(to: NSPoint(x: 748, y: 330))
    cursor.line(to: NSPoint(x: 724, y: 264))
    cursor.line(to: NSPoint(x: 671, y: 293))
    cursor.close()
    cursor.lineJoinStyle = .round
    NSGraphicsContext.saveGraphicsState()
    let cursorShadow = NSShadow(); cursorShadow.shadowColor = NSColor.black.withAlphaComponent(0.20)
    cursorShadow.shadowOffset = NSSize(width: 0, height: -7); cursorShadow.shadowBlurRadius = 8; cursorShadow.set()
    color(1, 1, 1, 0.96).setFill(); cursor.fill()
    NSGraphicsContext.restoreGraphicsState()
    color(0.88, 0.92, 0.93, 0.85).setStroke(); cursor.lineWidth = 5; cursor.stroke()
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
