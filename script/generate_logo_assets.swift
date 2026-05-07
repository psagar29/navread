import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else {
    fputs("usage: generate_logo_assets.swift <source-png> <resources-dir>\n", stderr)
    exit(2)
}

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let resourcesURL = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
try FileManager.default.createDirectory(at: resourcesURL, withIntermediateDirectories: true)

guard let image = NSImage(contentsOf: sourceURL),
      let tiff = image.tiffRepresentation,
      let sourceRep = NSBitmapImageRep(data: tiff) else {
    fputs("Could not read source image.\n", stderr)
    exit(1)
}

let width = sourceRep.pixelsWide
let height = sourceRep.pixelsHigh
var minX = width
var minY = height
var maxX = 0
var maxY = 0

func alphaForTemplatePixel(_ color: NSColor?) -> UInt8 {
    guard let rgb = color?.usingColorSpace(.deviceRGB) else { return 0 }
    let r = rgb.redComponent
    let g = rgb.greenComponent
    let b = rgb.blueComponent
    let high = max(r, max(g, b))
    let low = min(r, min(g, b))
    let saturation = high - low

    if high > 0.88 && saturation < 0.18 {
        let fade = max(0, min(1, (0.98 - high) / 0.10))
        return UInt8(fade * 255)
    }
    return UInt8(rgb.alphaComponent * 255)
}

for y in 0..<height {
    for x in 0..<width {
        let alpha = alphaForTemplatePixel(sourceRep.colorAt(x: x, y: y))
        guard alpha > 8 else { continue }
        minX = min(minX, x)
        minY = min(minY, y)
        maxX = max(maxX, x)
        maxY = max(maxY, y)
    }
}

guard minX <= maxX, minY <= maxY else {
    fputs("No logo pixels found after background removal.\n", stderr)
    exit(1)
}

let contentWidth = maxX - minX + 1
let contentHeight = maxY - minY + 1
let padding = 36
let side = max(contentWidth, contentHeight) + padding * 2
let originX = minX - (side - contentWidth) / 2
let originY = minY - (side - contentHeight) / 2
let bytesPerRow = side * 4

guard let outputRep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: side,
    pixelsHigh: side,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: bytesPerRow,
    bitsPerPixel: 32
) else {
    fputs("Could not allocate output bitmap.\n", stderr)
    exit(1)
}

guard let data = outputRep.bitmapData else {
    fputs("Could not access output bitmap data.\n", stderr)
    exit(1)
}

for y in 0..<side {
    for x in 0..<side {
        let sourceX = originX + x
        let sourceY = originY + y
        let offset = y * bytesPerRow + x * 4
        guard sourceX >= 0, sourceX < width, sourceY >= 0, sourceY < height else {
            data[offset + 0] = 0
            data[offset + 1] = 0
            data[offset + 2] = 0
            data[offset + 3] = 0
            continue
        }
        let alpha = alphaForTemplatePixel(sourceRep.colorAt(x: sourceX, y: sourceY))
        data[offset + 0] = 0
        data[offset + 1] = 0
        data[offset + 2] = 0
        data[offset + 3] = alpha
    }
}

guard let png = outputRep.representation(using: .png, properties: [:]) else {
    fputs("Could not encode template PNG.\n", stderr)
    exit(1)
}

try png.write(to: resourcesURL.appendingPathComponent("NavReadLogoTemplate.png"), options: .atomic)

let iconPixels = 1024
let iconSide = CGFloat(iconPixels)
let iconRect = NSRect(x: 0, y: 0, width: iconSide, height: iconSide)
guard let iconRep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: iconPixels,
    pixelsHigh: iconPixels,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: iconPixels * 4,
    bitsPerPixel: 32
) else {
    fputs("Could not allocate rounded app icon bitmap.\n", stderr)
    exit(1)
}
iconRep.size = NSSize(width: iconSide, height: iconSide)

NSGraphicsContext.saveGraphicsState()
let iconContext = NSGraphicsContext(bitmapImageRep: iconRep)
NSGraphicsContext.current = iconContext
iconContext?.cgContext.clear(CGRect(x: 0, y: 0, width: iconSide, height: iconSide))

let iconPath = NSBezierPath(roundedRect: iconRect, xRadius: 225, yRadius: 225)
iconPath.addClip()

image.draw(
    in: iconRect,
    from: NSRect(origin: .zero, size: image.size),
    operation: .sourceOver,
    fraction: 1
)

NSColor.black.withAlphaComponent(0.08).setStroke()
iconPath.lineWidth = 2
iconPath.stroke()
NSGraphicsContext.restoreGraphicsState()

guard let iconPng = iconRep.representation(using: .png, properties: [:]) else {
    fputs("Could not encode rounded app icon PNG.\n", stderr)
    exit(1)
}

try iconPng.write(to: resourcesURL.appendingPathComponent("AppIconBase.png"), options: .atomic)
