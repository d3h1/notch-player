import AppKit

// Renders the app icon PNGs into an .iconset folder: the icon is a screen
// with the notch hanging from its top edge, showing artwork and equalizer
// bars the way the app does.
let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let pink = NSColor(srgbRed: 1.0, green: 0.36, blue: 0.56, alpha: 1)
let orange = NSColor(srgbRed: 1.0, green: 0.66, blue: 0.32, alpha: 1)

/// Quadratic curve, as NSBezierPath only has cubic ones before macOS 14.
func quad(_ path: NSBezierPath, to end: NSPoint, control: NSPoint) {
    let start = path.currentPoint
    path.curve(to: end,
               controlPoint1: NSPoint(x: start.x + 2 / 3 * (control.x - start.x), y: start.y + 2 / 3 * (control.y - start.y)),
               controlPoint2: NSPoint(x: end.x + 2 / 3 * (control.x - end.x), y: end.y + 2 / 3 * (control.y - end.y)))
}

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: px, height: px)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    let detailed = px >= 64
    let inset = s * 0.09
    let body = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let shape = NSBezierPath(roundedRect: body, xRadius: body.width * 0.225, yRadius: body.width * 0.225)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = s * 0.025
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.012)
    shadow.set()
    NSColor.black.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    shape.addClip()

    // Night-sky screen.
    NSGradient(colors: [NSColor(srgbRed: 0.22, green: 0.11, blue: 0.38, alpha: 1),
                        NSColor(srgbRed: 0.07, green: 0.08, blue: 0.19, alpha: 1)])!
        .draw(in: body, angle: 90)

    // The notch.
    let w = body.width
    let cx = body.midX
    let top = body.maxY
    let notchWidth = w * 0.58
    let notchHeight = w * 0.27
    let ear = w * 0.04
    let bottomRadius = w * 0.09
    let bottom = top - notchHeight
    let leftWall = cx - notchWidth / 2 + ear
    let rightWall = cx + notchWidth / 2 - ear

    // Warm light spilling from the notch, with sound ripples.
    let glow = NSGradient(colors: [pink.withAlphaComponent(0.55), pink.withAlphaComponent(0.18), .clear],
                          atLocations: [0, 0.45, 1], colorSpace: .sRGB)!
    glow.draw(fromCenter: NSPoint(x: cx, y: bottom), radius: 0,
              toCenter: NSPoint(x: cx, y: bottom), radius: w * 0.72, options: [])
    if detailed {
        let center = NSPoint(x: cx, y: top - notchHeight / 2)
        for (i, radius) in [notchHeight * 1.05, notchHeight * 1.6, notchHeight * 2.15].enumerated() {
            let ripple = NSBezierPath()
            ripple.appendArc(withCenter: center, radius: radius, startAngle: 218, endAngle: 322)
            ripple.lineWidth = w * 0.026
            ripple.lineCapStyle = .round
            NSColor.white.withAlphaComponent([0.30, 0.18, 0.09][i]).setStroke()
            ripple.stroke()
        }
    }

    let notch = NSBezierPath()
    notch.move(to: NSPoint(x: cx - notchWidth / 2, y: top))
    quad(notch, to: NSPoint(x: leftWall, y: top - ear), control: NSPoint(x: leftWall, y: top))
    notch.line(to: NSPoint(x: leftWall, y: bottom + bottomRadius))
    quad(notch, to: NSPoint(x: leftWall + bottomRadius, y: bottom), control: NSPoint(x: leftWall, y: bottom))
    notch.line(to: NSPoint(x: rightWall - bottomRadius, y: bottom))
    quad(notch, to: NSPoint(x: rightWall, y: bottom + bottomRadius), control: NSPoint(x: rightWall, y: bottom))
    notch.line(to: NSPoint(x: rightWall, y: top - ear))
    quad(notch, to: NSPoint(x: cx + notchWidth / 2, y: top), control: NSPoint(x: rightWall, y: top))
    notch.close()
    NSColor.black.setFill()
    notch.fill()

    // Artwork on the left, equalizer on the right.
    let art = notchHeight * 0.56
    let pad = (notchHeight - art) / 2
    let midY = bottom + notchHeight / 2
    let artRect = NSRect(x: leftWall + pad, y: midY - art / 2, width: art, height: art)
    let artShape = NSBezierPath(roundedRect: artRect, xRadius: art * 0.24, yRadius: art * 0.24)
    NSGradient(colors: [orange, pink])!.draw(in: artShape, angle: -45)
    if detailed {
        let config = NSImage.SymbolConfiguration(pointSize: art * 0.5, weight: .bold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
        if let note = NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
            let size = note.size
            note.draw(in: NSRect(x: artRect.midX - size.width / 2, y: artRect.midY - size.height / 2,
                                 width: size.width, height: size.height))
        }
    }

    let barWidth = art * 0.16
    let gap = barWidth * 0.62
    let heights: [CGFloat] = [0.5, 0.95, 0.7, 0.4]
    var x = rightWall - pad - (barWidth * 4 + gap * 3)
    for height in heights {
        let bar = NSRect(x: x, y: midY - art * height / 2, width: barWidth, height: art * height)
        NSGradient(colors: [orange, pink])!
            .draw(in: NSBezierPath(roundedRect: bar, xRadius: barWidth / 2, yRadius: barWidth / 2), angle: 90)
        x += barWidth + gap
    }

    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                   ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try! render(px).write(to: URL(fileURLWithPath: "\(outDir)/icon_\(name).png"))
}
