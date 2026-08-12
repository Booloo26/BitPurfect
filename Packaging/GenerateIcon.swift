#!/usr/bin/env swift
//
// Draws the app icon from design 1d ("Sample bars") and writes a full .iconset.
// Run via `make icon`, which then feeds the iconset to iconutil.
//
// The design specifies its palette in OKLCH, so the conversion to sRGB is done here in full
// rather than by pasting in eyeballed hex values.
//
import AppKit
import Foundation

// MARK: - Palette (design's "Warm analog" mood)

/// OKLCH -> sRGB, via OKLab and the linear-sRGB matrix (Ottosson).
func oklch(_ lightness: Double, _ chroma: Double, _ hueDegrees: Double) -> NSColor {
    let hue = hueDegrees * .pi / 180
    let a = chroma * cos(hue)
    let b = chroma * sin(hue)

    let l_ = lightness + 0.3963377774 * a + 0.2158037573 * b
    let m_ = lightness - 0.1055613458 * a - 0.0638541728 * b
    let s_ = lightness - 0.0894841775 * a - 1.2914855480 * b

    let l = l_ * l_ * l_, m = m_ * m_ * m_, s = s_ * s_ * s_

    let red   =  4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
    let green = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
    let blue  = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s

    func gamma(_ c: Double) -> CGFloat {
        let clamped = min(max(c, 0), 1)
        let encoded = clamped <= 0.0031308
            ? 12.92 * clamped
            : 1.055 * pow(clamped, 1 / 2.4) - 0.055
        return CGFloat(min(max(encoded, 0), 1))
    }

    return NSColor(srgbRed: gamma(red), green: gamma(green), blue: gamma(blue), alpha: 1)
}

let ink     = oklch(0.26, 0.02, 60)   // tile
let paper   = oklch(0.95, 0.02, 85)   // centre bar
let accent  = oklch(0.78, 0.15, 68)   // warm pair (right)
let accent2 = oklch(0.62, 0.09, 200)  // cool pair (left)

// MARK: - Geometry

/// Bar metrics as fractions of the tile, so they scale to any canvas.
///
/// The design draws the mark slightly fatter at small sizes — 3pt bars in a 32px tile versus
/// 14pt in a 200px tile — so both sets are kept and picked by rendered size. That optical
/// adjustment is the difference between five bars and a grey smear at 32px and below.
struct BarMetrics {
    let width: Double
    let gap: Double
    /// Outer-to-centre heights; mirrored around the middle bar.
    let heights: [Double]

    /// From the design's 200px tile.
    static let large = BarMetrics(width: 14 / 200, gap: 11 / 200,
                                 heights: [34 / 200, 72 / 200, 112 / 200, 72 / 200, 34 / 200])
    /// From the design's 32px tile.
    static let small = BarMetrics(width: 3 / 32, gap: 2 / 32,
                                  heights: [6 / 32, 12 / 32, 19 / 32, 12 / 32, 6 / 32])
}

/// Apple's macOS icon proportions: the rounded tile fills 824 of a 1024 canvas, with a corner
/// radius 22.5% of the tile. The design's own 45px-in-200px radius is the same 22.5%, so the
/// mark keeps its shape while sitting correctly beside other Dock icons.
let tileScale = 824.0 / 1024.0
let cornerRatio = 45.0 / 200.0

let barColors = [accent2, accent2, paper, accent, accent]

func drawIcon(canvas: Double) -> NSImage {
    let image = NSImage(size: NSSize(width: canvas, height: canvas))
    image.lockFocus()

    NSGraphicsContext.current?.imageInterpolation = .high

    let tile = canvas * tileScale
    let origin = (canvas - tile) / 2
    let tileRect = NSRect(x: origin, y: origin, width: tile, height: tile)

    let radius = tile * cornerRatio
    let tilePath = NSBezierPath(roundedRect: tileRect, xRadius: radius, yRadius: radius)
    ink.setFill()
    tilePath.fill()

    let metrics = canvas <= 64 ? BarMetrics.small : BarMetrics.large
    let barWidth = tile * metrics.width
    let gap = tile * metrics.gap
    let totalWidth = barWidth * 5 + gap * 4
    var x = tileRect.midX - totalWidth / 2

    for (index, heightFraction) in metrics.heights.enumerated() {
        let height = tile * heightFraction
        let rect = NSRect(x: x, y: tileRect.midY - height / 2, width: barWidth, height: height)
        // Radius is half the width in the design (7 of 14), making every bar a capsule.
        let bar = NSBezierPath(roundedRect: rect, xRadius: barWidth / 2, yRadius: barWidth / 2)
        barColors[index].setFill()
        bar.fill()
        x += barWidth + gap
    }

    image.unlockFocus()
    return image
}

// MARK: - Output

/// The exact set iconutil expects for a complete .icns.
let variants: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024)
]

let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Packaging/AppIcon.iconset"
let outputURL = URL(fileURLWithPath: outputPath)

try? FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

for variant in variants {
    let size = Double(variant.pixels)
    let image = drawIcon(canvas: size)

    // Re-render through an explicit bitmap so the PNG is exactly N x N device pixels
    // regardless of the display's backing scale.
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: variant.pixels, pixelsHigh: variant.pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { continue }
    bitmap.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()

    guard let data = bitmap.representation(using: .png, properties: [:]) else { continue }
    try data.write(to: outputURL.appendingPathComponent("\(variant.name).png"))
    print("wrote \(variant.name).png (\(variant.pixels)px)")
}

print("iconset at \(outputPath)")
