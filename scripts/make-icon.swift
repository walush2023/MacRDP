// Turns a generated icon picture (a rounded square on a plain light background) into
// Resources/AppIcon.icns: finds the coloured tile, crops it, masks it to a macOS squircle with a
// transparent margin, and writes every iconset size.
// Usage: swift scripts/make-icon.swift Resources/icon-source.png Resources/AppIcon.icns
import AppKit
import CoreGraphics

let args = CommandLine.arguments
guard args.count == 3, let src = NSImage(contentsOfFile: args[1]),
      let cg = src.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    print("usage: make-icon.swift <source.png> <out.icns>"); exit(1)
}

// 1. Bounding box of saturated (non-background) pixels.
let w = cg.width, h = cg.height
var pixels = [UInt8](repeating: 0, count: w * h * 4)
let rgbCtx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
rgbCtx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
var minX = w, minY = h, maxX = 0, maxY = 0
for y in 0..<h {
    for x in 0..<w {
        let i = (y * w + x) * 4
        let r = Int(pixels[i]), g = Int(pixels[i + 1]), b = Int(pixels[i + 2])
        if max(r, g, b) - min(r, g, b) > 60 && b > 150 { // the blue tile
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        }
    }
}
let side = max(maxX - minX, maxY - minY)
let cx = (minX + maxX) / 2, cy = (minY + maxY) / 2
// CGContext rows start at the bottom; pixels[] was drawn in that space, so the box is already in CG coords.
let crop = CGRect(x: cx - side / 2, y: cy - side / 2, width: side, height: side)
guard let tile = cg.cropping(to: crop.insetBy(dx: CGFloat(side) * 0.035, dy: CGFloat(side) * 0.035)) else { exit(1) }

// 2. Render at a size with Apple's icon grid: 824/1024 tile, radius ~185.
func render(_ size: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let s = CGFloat(size)
    let rect = CGRect(x: s * 100 / 1024, y: s * 100 / 1024, width: s * 824 / 1024, height: s * 824 / 1024)
    ctx.interpolationQuality = .high
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: s * 185 / 1024, cornerHeight: s * 185 / 1024, transform: nil))
    ctx.clip()
    ctx.draw(tile, in: rect.insetBy(dx: -s * 0.02, dy: -s * 0.02))
    return ctx.makeImage()!
}

// 3. Write the iconset and convert with iconutil.
let out = URL(fileURLWithPath: args[2])
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let rep = NSBitmapImageRep(cgImage: render(base * scale))
        try! rep.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
    }
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try! p.run(); p.waitUntilExit()
try! NSBitmapImageRep(cgImage: render(512)).representation(using: .png, properties: [:])!
    .write(to: out.deletingPathExtension().appendingPathExtension("png"))
print("wrote \(out.path)")
