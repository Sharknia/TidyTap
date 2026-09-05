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

    // Pale blue-grey translucency with a gently shaded center, rather than a flat tile.
    NSGradient(colors: [
        color(0.84, 0.90, 0.91, 0.91),
        color(0.67, 0.76, 0.79, 0.87)
    ])!.draw(in: tile, angle: 90)
    NSGradient(starting: color(0.94, 0.97, 0.97, 0.22), ending: color(0.57, 0.67, 0.70, 0.10))!
        .draw(in: tile, relativeCenterPosition: NSPoint(x: 0.48, y: 0.56))
    color(1, 1, 1, 0.48).setStroke(); tile.lineWidth = 4; tile.stroke()

    // A clipped, low-contrast inner highlight carries the glass perimeter softly.
    NSGraphicsContext.saveGraphicsState()
    tile.addClip()
    let innerPerimeter = NSBezierPath(roundedRect: NSRect(x: 112, y: 112, width: 800, height: 800), xRadius: 188, yRadius: 188)
    let innerGlow = NSShadow(); innerGlow.shadowColor = color(1, 1, 1, 0.18)
    innerGlow.shadowOffset = .zero; innerGlow.shadowBlurRadius = 11; innerGlow.set()
    color(1, 1, 1, 0.08).setStroke(); innerPerimeter.lineWidth = 3; innerPerimeter.stroke()
    NSGraphicsContext.restoreGraphicsState()

    // A clean raised T: enough depth to read as a control without becoming a keycap.
    let letter = NSBezierPath()
    // One continuous union contour prevents a seam where the bar meets the stem.
    letter.move(to: NSPoint(x: 366, y: 741))
    letter.curve(to: NSPoint(x: 318, y: 693), controlPoint1: NSPoint(x: 339, y: 741), controlPoint2: NSPoint(x: 318, y: 720))
    letter.line(to: NSPoint(x: 318, y: 683))
    letter.curve(to: NSPoint(x: 366, y: 635), controlPoint1: NSPoint(x: 318, y: 656), controlPoint2: NSPoint(x: 339, y: 635))
    letter.line(to: NSPoint(x: 438, y: 635))
    letter.curve(to: NSPoint(x: 462, y: 611), controlPoint1: NSPoint(x: 451, y: 635), controlPoint2: NSPoint(x: 462, y: 624))
    letter.line(to: NSPoint(x: 462, y: 383))
    letter.curve(to: NSPoint(x: 512, y: 335), controlPoint1: NSPoint(x: 462, y: 356), controlPoint2: NSPoint(x: 484, y: 335))
    letter.curve(to: NSPoint(x: 562, y: 383), controlPoint1: NSPoint(x: 540, y: 335), controlPoint2: NSPoint(x: 562, y: 356))
    letter.line(to: NSPoint(x: 562, y: 611))
    letter.curve(to: NSPoint(x: 586, y: 635), controlPoint1: NSPoint(x: 562, y: 624), controlPoint2: NSPoint(x: 573, y: 635))
    letter.line(to: NSPoint(x: 658, y: 635))
    letter.curve(to: NSPoint(x: 706, y: 683), controlPoint1: NSPoint(x: 685, y: 635), controlPoint2: NSPoint(x: 706, y: 656))
    letter.line(to: NSPoint(x: 706, y: 693))
    letter.curve(to: NSPoint(x: 658, y: 741), controlPoint1: NSPoint(x: 706, y: 720), controlPoint2: NSPoint(x: 685, y: 741))
    letter.close()
    NSGraphicsContext.saveGraphicsState()
    let letterShadow = NSShadow(); letterShadow.shadowColor = NSColor.black.withAlphaComponent(0.23)
    letterShadow.shadowOffset = NSSize(width: 0, height: -9); letterShadow.shadowBlurRadius = 10; letterShadow.set()
    color(1, 1, 1, 0.94).setFill(); letter.fill()
    NSGraphicsContext.restoreGraphicsState()
    color(1, 1, 1, 0.64).setStroke(); letter.lineWidth = 3; letter.stroke()

    let cursor = NSBezierPath()
    // The pointer faces the T from the lower-right rather than forming another frame.
    cursor.move(to: NSPoint(x: 661, y: 476))
    cursor.line(to: NSPoint(x: 790, y: 365))
    cursor.line(to: NSPoint(x: 748, y: 356))
    cursor.line(to: NSPoint(x: 770, y: 292))
    cursor.line(to: NSPoint(x: 738, y: 278))
    cursor.line(to: NSPoint(x: 710, y: 343))
    cursor.line(to: NSPoint(x: 681, y: 316))
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
