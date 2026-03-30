#!/usr/bin/env swift
// Generates an Apple-style squircle icon for README / website use.
// Usage: swift generate_readme_icon.swift [input.png] [output.png] [size]

import AppKit
import CoreGraphics

// MARK: - Superellipse path (Apple squircle approximation)

/// Build a continuous-corner (squircle) path that closely matches Apple's icon shape.
/// Uses a superellipse exponent of ~5 which approximates Apple's continuous corner curve.
func squirclePath(in rect: CGRect, cornerFraction: CGFloat = 0.2237) -> CGPath {
    let w = rect.width, h = rect.height
    let r = min(w, h) * cornerFraction

    // Control point factor for continuous curvature (~1.528 magic number)
    let k: CGFloat = 1.528

    let path = CGMutablePath()

    // Start at top-left, just past the corner
    path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))

    // Top edge → top-right corner
    path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
    path.addCurve(
        to: CGPoint(x: rect.maxX, y: rect.minY + r),
        control1: CGPoint(x: rect.maxX - r + r / k, y: rect.minY),
        control2: CGPoint(x: rect.maxX, y: rect.minY + r - r / k)
    )

    // Right edge → bottom-right corner
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
    path.addCurve(
        to: CGPoint(x: rect.maxX - r, y: rect.maxY),
        control1: CGPoint(x: rect.maxX, y: rect.maxY - r + r / k),
        control2: CGPoint(x: rect.maxX - r + r / k, y: rect.maxY)
    )

    // Bottom edge → bottom-left corner
    path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
    path.addCurve(
        to: CGPoint(x: rect.minX, y: rect.maxY - r),
        control1: CGPoint(x: rect.minX + r - r / k, y: rect.maxY),
        control2: CGPoint(x: rect.minX, y: rect.maxY - r + r / k)
    )

    // Left edge → top-left corner
    path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
    path.addCurve(
        to: CGPoint(x: rect.minX + r, y: rect.minY),
        control1: CGPoint(x: rect.minX, y: rect.minY + r - r / k),
        control2: CGPoint(x: rect.minX + r - r / k, y: rect.minY)
    )

    path.closeSubpath()
    return path
}

// MARK: - Main

let args = CommandLine.arguments
let inputPath = args.count > 1
    ? args[1]
    : "openmeow/openmeow/Assets.xcassets/AppIcon.appiconset/icon_1024x1024.png"
let outputPath = args.count > 2
    ? args[2]
    : "assets/icon_readme.png"
let outputSize = args.count > 3
    ? Int(args[3]) ?? 512
    : 512

guard let srcImage = NSImage(contentsOfFile: inputPath) else {
    fputs("Error: cannot load \(inputPath)\n", stderr)
    exit(1)
}

let size = CGFloat(outputSize)
let padding: CGFloat = size * 0.04          // breathing room for the shadow
let canvas = CGFloat(outputSize) + padding * 2

guard let ctx = CGContext(
    data: nil,
    width: Int(canvas),
    height: Int(canvas),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fputs("Error: cannot create CGContext\n", stderr)
    exit(1)
}

let iconRect = CGRect(x: padding, y: padding, width: size, height: size)
let mask = squirclePath(in: iconRect)

// Drop shadow
ctx.setShadow(
    offset: CGSize(width: 0, height: -size * 0.01),
    blur: size * 0.035,
    color: CGColor(gray: 0, alpha: 0.25)
)

// Draw clipped icon
ctx.saveGState()
ctx.addPath(mask)
ctx.clip()
ctx.setShadow(offset: .zero, blur: 0)  // no shadow inside the clip

if let cgImage = srcImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
    ctx.draw(cgImage, in: iconRect)
}
ctx.restoreGState()

// Subtle border stroke
ctx.addPath(mask)
ctx.setStrokeColor(CGColor(gray: 0, alpha: 0.08))
ctx.setLineWidth(size * 0.002)
ctx.strokePath()

guard let result = ctx.makeImage() else {
    fputs("Error: cannot render image\n", stderr)
    exit(1)
}

// Ensure output directory exists
let outputURL = URL(fileURLWithPath: outputPath)
try? FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)

let dest = CGImageDestinationCreateWithURL(outputURL as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(dest, result, nil)
guard CGImageDestinationFinalize(dest) else {
    fputs("Error: cannot write \(outputPath)\n", stderr)
    exit(1)
}

print("Generated \(outputSize)px squircle icon → \(outputPath)")
