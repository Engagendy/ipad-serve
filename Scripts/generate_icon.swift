import AppKit

let size = 1024
let scale = CGFloat(size)
let output = URL(fileURLWithPath: "iPadServe/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png")

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let rect = NSRect(x: 0, y: 0, width: scale, height: scale)
let background = NSGradient(colors: [
    NSColor(calibratedRed: 0.04, green: 0.18, blue: 0.29, alpha: 1),
    NSColor(calibratedRed: 0.02, green: 0.47, blue: 0.58, alpha: 1)
])!
background.draw(in: rect, angle: 135)

func roundedRect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: r, yRadius: r)
}

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

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not render app icon")
}

try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
try png.write(to: output)
