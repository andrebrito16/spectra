// Generates spectra/Assets.xcassets/AppIconCanary.appiconset from the stable
// AppIcon: the near-white background becomes canary yellow while the prism and
// the rainbow beam are kept, so a Dock full of icons still reads at a glance.
// Run: swift scripts/make-canary-icon.swift
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments.first ?? "")
    .deletingLastPathComponent().deletingLastPathComponent()
let source = root.appendingPathComponent("spectra/Assets.xcassets/AppIcon.appiconset")
let dest = root.appendingPathComponent("spectra/Assets.xcassets/AppIconCanary.appiconset")

// Canary yellow (sRGB). Neutral pixels get scaled by their brightness so white
// turns this colour, black stays black and anti-aliased edges stay smooth.
let yellow: (r: CGFloat, g: CGFloat, b: CGFloat) = (1.0, 0.80, 0.10)

func tinted(_ image: NSImage) -> NSBitmapImageRep {
    guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        fatalError("Cannot decode source icon")
    }
    let w = cg.width, h = cg.height
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

    let data = rep.bitmapData!
    let bytesPerRow = rep.bytesPerRow
    for y in 0..<h {
        for x in 0..<w {
            let i = y * bytesPerRow + x * 4
            let a = CGFloat(data[i + 3]) / 255
            guard a > 0 else { continue }
            // Un-premultiply.
            var r = CGFloat(data[i]) / 255 / a
            var g = CGFloat(data[i + 1]) / 255 / a
            var b = CGFloat(data[i + 2]) / 255 / a
            let hi = max(r, g, b), lo = min(r, g, b)
            let sat = hi > 0 ? (hi - lo) / hi : 0
            // 0 = neutral (recolour), 1 = saturated (keep the rainbow).
            let t = min(max((sat - 0.10) / 0.25, 0), 1)
            let s = t * t * (3 - 2 * t)
            r = (yellow.r * hi) * (1 - s) + r * s
            g = (yellow.g * hi) * (1 - s) + g * s
            b = (yellow.b * hi) * (1 - s) + b * s
            data[i] = UInt8(max(0, min(255, (r * a * 255).rounded())))
            data[i + 1] = UInt8(max(0, min(255, (g * a * 255).rounded())))
            data[i + 2] = UInt8(max(0, min(255, (b * a * 255).rounded())))
        }
    }
    return rep
}

func resized(_ rep: NSBitmapImageRep, to px: Int) -> Data {
    let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let gctx = NSGraphicsContext(bitmapImageRep: out)!
    NSGraphicsContext.current = gctx
    gctx.cgContext.interpolationQuality = .high
    gctx.cgContext.draw(rep.cgImage!, in: CGRect(x: 0, y: 0, width: px, height: px))
    NSGraphicsContext.restoreGraphicsState()
    return out.representation(using: .png, properties: [:])!
}

let master = NSImage(contentsOf: source.appendingPathComponent("icon_512x512-2x.png"))!
let big = tinted(master)

try? FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    try resized(big, to: size).write(to: dest.appendingPathComponent("icon_\(size)x\(size).png"))
    try resized(big, to: size * 2).write(to: dest.appendingPathComponent("icon_\(size)x\(size)-2x.png"))
}
try? FileManager.default.removeItem(at: dest.appendingPathComponent("Contents.json"))
try? FileManager.default.copyItem(at: source.appendingPathComponent("Contents.json"),
                                  to: dest.appendingPathComponent("Contents.json"))
print("Wrote \(dest.path)")
