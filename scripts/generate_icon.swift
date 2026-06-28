#!/usr/bin/env swift
import CoreGraphics
import Foundation
import ImageIO

let sizes: [(name: String, px: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

let outputDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "ShortURL.iconset"

try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

for (name, px) in sizes {
    let s = CGFloat(px)
    let rect = CGRect(x: 0, y: 0, width: s, height: s)

    guard let ctx = CGContext(
        data: nil,
        width: px, height: px,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { continue }

    // ── Rounded rect clip ──
    let cornerRadius = s * 0.225
    let bgPath = CGPath(roundedRect: rect,
                         cornerWidth: cornerRadius,
                         cornerHeight: cornerRadius,
                         transform: nil)
    ctx.addPath(bgPath)
    ctx.clip()

    // ── Indigo gradient background ──
    let bgColors = [
        CGColor(red: 0.31, green: 0.27, blue: 0.85, alpha: 1.0),
        CGColor(red: 0.15, green: 0.12, blue: 0.60, alpha: 1.0),
    ]
    let bgGrad = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                             colors: bgColors as CFArray,
                             locations: [0.0, 1.0])!

    ctx.drawLinearGradient(bgGrad,
                            start: CGPoint(x: s/2, y: 0),
                            end: CGPoint(x: s/2, y: s),
                            options: [])

    // ── Subtle top highlight ──
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.10))
    ctx.fill(CGRect(x: 0, y: s * 0.72, width: s, height: s * 0.28))

    // ── Chain-link icon ──
    let cx = s / 2
    let cy = s / 2
    let linkW = s * 0.20
    let linkH = s * 0.075
    let linkGap = s * 0.12
    let lineW = max(s * 0.028, s > 64 ? 3 : 1.5)
    let corner = linkH / 2

    // Link 1 (top-left)
    ctx.saveGState()
    ctx.translateBy(x: cx - linkGap, y: cy - linkGap * 0.5)
    ctx.rotate(by: .pi / 5.5)
    let l1 = CGPath(roundedRect: CGRect(x: -linkW/2, y: -linkH/2, width: linkW, height: linkH),
                     cornerWidth: corner, cornerHeight: corner, transform: nil)
    ctx.addPath(l1)
    ctx.setLineWidth(lineW)
    ctx.setStrokeColor(CGColor.white)
    ctx.strokePath()
    ctx.restoreGState()

    // Link 2 (bottom-right)
    ctx.saveGState()
    ctx.translateBy(x: cx + linkGap, y: cy + linkGap * 0.5)
    ctx.rotate(by: .pi / 5.5)
    let l2 = CGPath(roundedRect: CGRect(x: -linkW/2, y: -linkH/2, width: linkW, height: linkH),
                     cornerWidth: corner, cornerHeight: corner, transform: nil)
    ctx.addPath(l2)
    ctx.setLineWidth(lineW)
    ctx.setStrokeColor(CGColor.white)
    ctx.strokePath()
    ctx.restoreGState()

    // ── Inner rim highlight ──
    ctx.resetClip()
    let inset: CGFloat = px > 64 ? 1.5 : 1
    let rimPath = CGPath(roundedRect: rect.insetBy(dx: inset, dy: inset),
                          cornerWidth: cornerRadius - inset,
                          cornerHeight: cornerRadius - inset,
                          transform: nil)
    ctx.addPath(rimPath)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.16))
    ctx.setLineWidth(px > 64 ? 2 : 1)
    ctx.strokePath()

    // ── Save ──
    guard let image = ctx.makeImage() else { continue }
    let url = URL(fileURLWithPath: "\(outputDir)/\(name)")
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { continue }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)

    print("  \(name) (\(px)×\(px))")
}

print("Iconset created at: \(outputDir)")
