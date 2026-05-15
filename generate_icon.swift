#!/usr/bin/swift
// Generates icon_1024.png — run with: swift generate_icon.swift
import Foundation
import CoreGraphics
import ImageIO

let sz = 1024
let cs = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(data: nil, width: sz, height: sz, bitsPerComponent: 8,
                   bytesPerRow: 0, space: cs,
                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

// ── Background ───────────────────────────────────────────────────────────────
ctx.setFillColor(rgb(0.07, 0.09, 0.13))
ctx.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: sz, height: sz),
                   cornerWidth: 200, cornerHeight: 200, transform: nil))
ctx.fillPath()

// ── 4 horizontal usage bars (like the floating window) ───────────────────────
// heights represent: Session (low), Weekly (near-limit), Sonnet (mid), Design (low)
let fractions: [CGFloat] = [0.22, 0.78, 0.48, 0.14]
let colors: [CGColor] = [
    rgb(0.18, 0.80, 0.38),   // green
    rgb(1.00, 0.56, 0.00),   // orange
    rgb(0.18, 0.80, 0.38),   // green
    rgb(0.18, 0.80, 0.38),   // green
]

let barH:   CGFloat = 95
let gap:    CGFloat = 48
let barMaxW: CGFloat = 730
let x0 = (CGFloat(sz) - barMaxW) / 2
let totalH = CGFloat(fractions.count) * barH + CGFloat(fractions.count - 1) * gap
let y0 = (CGFloat(sz) - totalH) / 2
let r = barH / 2   // fully rounded pill shape

for i in 0..<fractions.count {
    let y = y0 + CGFloat(i) * (barH + gap)

    // track (dim background)
    ctx.setFillColor(rgb(1, 1, 1, 0.08))
    ctx.addPath(CGPath(roundedRect: CGRect(x: x0, y: y, width: barMaxW, height: barH),
                       cornerWidth: r, cornerHeight: r, transform: nil))
    ctx.fillPath()

    // colored fill
    ctx.setFillColor(colors[i])
    let fillW = fractions[i] * barMaxW
    ctx.addPath(CGPath(roundedRect: CGRect(x: x0, y: y, width: fillW, height: barH),
                       cornerWidth: r, cornerHeight: r, transform: nil))
    ctx.fillPath()
}

// ── Save ─────────────────────────────────────────────────────────────────────
let outURL = URL(fileURLWithPath: "icon_1024.png")
if let img = ctx.makeImage(),
   let dest = CGImageDestinationCreateWithURL(outURL as CFURL, "public.png" as CFString, 1, nil) {
    CGImageDestinationAddImage(dest, img, nil)
    CGImageDestinationFinalize(dest)
    print("✓ icon_1024.png gespeichert")
} else {
    print("✗ Fehler beim Speichern"); exit(1)
}
