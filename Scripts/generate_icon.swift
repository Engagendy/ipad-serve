import AppKit

let baseSize = 1024
let scale = CGFloat(baseSize)
let outputDirectory = URL(fileURLWithPath: "iPadServe/Resources/Assets.xcassets/AppIcon.appiconset")

let image = NSImage(size: NSSize(width: baseSize, height: baseSize))

func roundedRect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: width, height: height), xRadius: radius, yRadius: radius)
}

image.lockFocus()
let rect = NSRect(x: 0, y: 0, width: scale, height: scale)
let background = NSGradient(colors: [
    NSColor(calibratedRed: 0.04, green: 0.18, blue: 0.29, alpha: 1),
    NSColor(calibratedRed: 0.02, green: 0.47, blue: 0.58, alpha: 1)
])!
background.draw(in: rect, angle: 135)

NSColor(calibratedWhite: 1, alpha: 0.10).setFill()
roundedRect(116, 124, 792, 776, 92).fill()

NSColor(calibratedWhite: 1, alpha: 0.96).setFill()
roundedRect(190, 208, 644, 560, 58).fill()

NSColor(calibratedRed: 0.85, green: 0.91, blue: 0.94, alpha: 1).setStroke()
let screen = roundedRect(190, 208, 644, 560, 58)
screen.lineWidth = 18
screen.stroke()

NSColor(calibratedRed: 0.05, green: 0.20, blue: 0.30, alpha: 1).setFill()
roundedRect(236, 650, 552, 72, 24).fill()

NSColor(calibratedRed: 0.94, green: 0.71, blue: 0.26, alpha: 1).setFill()
NSBezierPath(ovalIn: NSRect(x: 266, y: 675, width: 22, height: 22)).fill()
NSBezierPath(ovalIn: NSRect(x: 304, y: 675, width: 22, height: 22)).fill()
NSBezierPath(ovalIn: NSRect(x: 342, y: 675, width: 22, height: 22)).fill()

NSColor(calibratedRed: 0.02, green: 0.47, blue: 0.58, alpha: 1).setFill()
roundedRect(258, 544, 382, 50, 18).fill()
roundedRect(258, 462, 494, 42, 16).fill()
roundedRect(258, 392, 438, 42, 16).fill()

NSColor(calibratedRed: 0.04, green: 0.18, blue: 0.29, alpha: 1).setFill()
let folder = NSBezierPath()
folder.move(to: NSPoint(x: 276, y: 290))
folder.line(to: NSPoint(x: 408, y: 290))
folder.curve(to: NSPoint(x: 448, y: 326), controlPoint1: NSPoint(x: 426, y: 290), controlPoint2: NSPoint(x: 432, y: 326))
folder.line(to: NSPoint(x: 736, y: 326))
folder.curve(to: NSPoint(x: 768, y: 358), controlPoint1: NSPoint(x: 754, y: 326), controlPoint2: NSPoint(x: 768, y: 340))
folder.line(to: NSPoint(x: 768, y: 520))
folder.curve(to: NSPoint(x: 736, y: 552), controlPoint1: NSPoint(x: 768, y: 538), controlPoint2: NSPoint(x: 754, y: 552))
folder.line(to: NSPoint(x: 276, y: 552))
folder.curve(to: NSPoint(x: 244, y: 520), controlPoint1: NSPoint(x: 258, y: 552), controlPoint2: NSPoint(x: 244, y: 538))
folder.line(to: NSPoint(x: 244, y: 322))
folder.curve(to: NSPoint(x: 276, y: 290), controlPoint1: NSPoint(x: 244, y: 304), controlPoint2: NSPoint(x: 258, y: 290))
folder.close()
folder.fill()

NSColor(calibratedRed: 0.94, green: 0.71, blue: 0.26, alpha: 1).setFill()
roundedRect(306, 366, 405, 60, 20).fill()
roundedRect(306, 448, 270, 46, 16).fill()

NSColor(calibratedRed: 0.95, green: 0.99, blue: 1.0, alpha: 1).setFill()
roundedRect(706, 172, 72, 26, 13).fill()

image.unlockFocus()

struct IconSlot {
    let filename: String
    let pixels: Int
}

let icons = [
    IconSlot(filename: "icon-ipad-20.png", pixels: 20),
    IconSlot(filename: "icon-ipad-20@2x.png", pixels: 40),
    IconSlot(filename: "icon-ipad-29.png", pixels: 29),
    IconSlot(filename: "icon-ipad-29@2x.png", pixels: 58),
    IconSlot(filename: "icon-ipad-40.png", pixels: 40),
    IconSlot(filename: "icon-ipad-40@2x.png", pixels: 80),
    IconSlot(filename: "icon-ipad-76.png", pixels: 76),
    IconSlot(filename: "icon-ipad-76@2x.png", pixels: 152),
    IconSlot(filename: "icon-ipad-83.5@2x.png", pixels: 167),
    IconSlot(filename: "icon-1024.png", pixels: 1024)
]

func pngData(from source: NSImage, pixels: Int) -> Data {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fatalError("Could not create \(pixels)x\(pixels) app icon bitmap")
    }

    let targetSize = NSSize(width: pixels, height: pixels)
    bitmap.size = targetSize

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current?.imageInterpolation = .high
    source.draw(in: NSRect(origin: .zero, size: targetSize), from: NSRect(origin: .zero, size: source.size), operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()

    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Could not render \(pixels)x\(pixels) app icon")
    }
    return png
}

try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

for icon in icons {
    try pngData(from: image, pixels: icon.pixels).write(to: outputDirectory.appendingPathComponent(icon.filename))
}
