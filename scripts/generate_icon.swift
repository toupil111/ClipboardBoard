import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: swift generate_icon.swift <output-path>\n", stderr)
    exit(1)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let size = NSSize(width: 1024, height: 1024)
let rect = NSRect(origin: .zero, size: size)
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(size.width),
    pixelsHigh: Int(size.height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fputs("Failed to create bitmap context.\n", stderr)
    exit(1)
}

guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fputs("Failed to create graphics context.\n", stderr)
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
defer {
    NSGraphicsContext.restoreGraphicsState()
}

NSColor.clear.setFill()
rect.fill()

let outerRect = rect.insetBy(dx: 72, dy: 72)
let outerPath = NSBezierPath(roundedRect: outerRect, xRadius: 240, yRadius: 240)
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.26, green: 0.45, blue: 0.98, alpha: 1),
    NSColor(calibratedRed: 0.17, green: 0.27, blue: 0.82, alpha: 1)
])!
gradient.draw(in: outerPath, angle: -90)

NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowBlurRadius = 36
shadow.shadowOffset = NSSize(width: 0, height: -18)
shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
shadow.set()
NSColor.white.withAlphaComponent(0.16).setStroke()
outerPath.lineWidth = 8
outerPath.stroke()
NSGraphicsContext.restoreGraphicsState()

let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center

let textAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 560, weight: .black),
    .foregroundColor: NSColor.white,
    .paragraphStyle: paragraph
]

NSString(string: "C").draw(in: NSRect(x: 0, y: 250, width: size.width, height: 560), withAttributes: textAttributes)

guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Failed to create PNG data.\n", stderr)
    exit(1)
}

try pngData.write(to: outputURL, options: .atomic)
print(outputURL.path)
