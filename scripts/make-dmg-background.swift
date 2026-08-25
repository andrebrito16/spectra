// Generates scripts/dmg-background.tiff (retina, 600x400pt) for create-dmg.
// Window layout assumed by release.sh: 600x400, icon size 128,
// Spectra.app centered at (150,185), Applications link at (450,185).
// Run: swift scripts/make-dmg-background.swift
import AppKit

let pointSize = NSSize(width: 600, height: 400)

func render(scale: CGFloat, to url: URL) {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(pointSize.width * scale), pixelsHigh: Int(pointSize.height * scale),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let gctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = gctx
    gctx.cgContext.scaleBy(x: scale, y: scale)

    // Soft light gradient — Finder icon labels stay readable in both appearances.
    NSGradient(colors: [
        NSColor(calibratedRed: 0.97, green: 0.97, blue: 0.98, alpha: 1),
        NSColor(calibratedRed: 0.89, green: 0.89, blue: 0.92, alpha: 1),
    ])!.draw(in: NSRect(origin: .zero, size: pointSize), angle: -90)

    // Arrow between the icons. Icon centers y=185 from window top -> CG y = 400-185.
    let y: CGFloat = 400 - 185
    let arrow = NSBezierPath()
    arrow.lineWidth = 5
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    arrow.move(to: NSPoint(x: 240, y: y))
    arrow.line(to: NSPoint(x: 352, y: y))
    arrow.move(to: NSPoint(x: 332, y: y + 16))
    arrow.line(to: NSPoint(x: 356, y: y))
    arrow.line(to: NSPoint(x: 332, y: y - 16))
    NSColor(calibratedWhite: 0.45, alpha: 0.9).setStroke()
    arrow.stroke()

    // Caption under the icons.
    let caption = "Drag Spectra into the Applications folder to install"
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 13, weight: .medium),
        .foregroundColor: NSColor(calibratedWhite: 0.4, alpha: 1),
    ]
    let size = caption.size(withAttributes: attrs)
    caption.draw(at: NSPoint(x: (600 - size.width) / 2, y: 400 - 330), withAttributes: attrs)

    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let png1x = dir.appendingPathComponent("dmg-bg-1x.png")
let png2x = dir.appendingPathComponent("dmg-bg-2x.png")
render(scale: 1, to: png1x)
render(scale: 2, to: png2x)

// Combine into a HiDPI-aware TIFF so the background is crisp on retina.
let tiffutil = Process()
tiffutil.executableURL = URL(fileURLWithPath: "/usr/bin/tiffutil")
tiffutil.arguments = ["-cathidpicheck", png1x.path, png2x.path,
                      "-out", dir.appendingPathComponent("dmg-background.tiff").path]
try! tiffutil.run()
tiffutil.waitUntilExit()
try? FileManager.default.removeItem(at: png1x)
try? FileManager.default.removeItem(at: png2x)
print("Wrote \(dir.appendingPathComponent("dmg-background.tiff").path)")
