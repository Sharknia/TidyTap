import AppKit
import Foundation

// Native typography and an SF Symbol frame the real, draggable Finder icons.
// The image contains no app/folder lookalikes; Finder supplies those controls.
let canvas = NSSize(width: 640, height: 400)
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let destination = root.appendingPathComponent("Resources/DMGBackground.tiff")
let previewDestination = root.appendingPathComponent("build/dmg-design/background.png")

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
}

func text(_ value: String, top: CGFloat, size: CGFloat, weight: NSFont.Weight, color: NSColor) {
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    let height: CGFloat = size + 12
    (value as NSString).draw(
        in: NSRect(x: 36, y: canvas.height - top - height, width: canvas.width - 72, height: height),
        withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight),
                         .foregroundColor: color, .paragraphStyle: style]
    )
}

var representations: [NSBitmapImageRep] = []
for scale in [1, 2] {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(canvas.width) * scale,
        pixelsHigh: Int(canvas.height) * scale, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        fatalError("Could not create the installer background context")
    }
    bitmap.size = canvas
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
    let bounds = NSRect(origin: .zero, size: canvas)
    NSGradient(starting: rgb(0.96, 0.977, 0.979), ending: rgb(0.91, 0.947, 0.953))!
        .draw(in: bounds, angle: -90)
    text("TidyTap", top: 40, size: 28, weight: .semibold, color: rgb(0.16, 0.25, 0.28))

    let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 32, weight: .regular)
        .applying(NSImage.SymbolConfiguration(paletteColors: [rgb(0.40, 0.56, 0.59)]))
    guard let arrow = NSImage(systemSymbolName: "arrow.right", accessibilityDescription: nil)?
        .withSymbolConfiguration(symbolConfiguration) else {
        fatalError("The system arrow symbol is unavailable")
    }
    arrow.draw(in: NSRect(x: 300, y: 181, width: 40, height: 30))

    text("TidyTap을 응용 프로그램 폴더로 드래그하세요", top: 301, size: 13,
         weight: .medium, color: rgb(0.24, 0.35, 0.38))
    NSGraphicsContext.restoreGraphicsState()
    representations.append(bitmap)
}

guard let tiff = NSBitmapImageRep.representationOfImageReps(
    in: representations, using: .tiff,
    properties: [.compressionMethod: NSBitmapImageRep.TIFFCompression.lzw.rawValue]
), let preview = representations.last?.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode the installer background")
}
try FileManager.default.createDirectory(at: previewDestination.deletingLastPathComponent(),
                                      withIntermediateDirectories: true)
try tiff.write(to: destination, options: .atomic)
try preview.write(to: previewDestination, options: .atomic)
print("Rendered 640×400 installer background with 1× and 2× representations")
