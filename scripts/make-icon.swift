// Rasterise Resources/AppIcon.svg into an .iconset folder (all sizes macOS expects).
// Usage: swift scripts/make-icon.swift <input.svg> <output.iconset>
// scripts/make-icon.sh wraps this and runs iconutil to produce Resources/AppIcon.icns.
import AppKit

let args = CommandLine.arguments
guard args.count == 3 else {
    FileHandle.standardError.write("usage: make-icon.swift <input.svg> <output.iconset>\n".data(using: .utf8)!)
    exit(2)
}
let input = URL(fileURLWithPath: args[1])
let output = URL(fileURLWithPath: args[2], isDirectory: true)

guard let svg = NSImage(contentsOf: input) else {
    FileHandle.standardError.write("could not load \(input.path)\n".data(using: .utf8)!)
    exit(1)
}
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

// (point size, scale) pairs required by iconutil.
let variants: [(Int, Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]

for (points, scale) in variants {
    let pixels = points * scale
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { exit(1) }
    rep.size = NSSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    svg.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()

    let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
    guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
    try png.write(to: output.appendingPathComponent(name))
}
print("wrote \(variants.count) images to \(output.path)")
