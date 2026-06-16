// Render the app icon (1024×1024 PNG) from the "cube.transparent" SF Symbol on a
// rounded-square indigo→violet gradient. Output path is argv[1].
//   swift scripts/make-icon.swift out.png
import AppKit

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
let size = 1024.0
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// rounded square (macOS-style: ~80% with margin)
let inset = size * 0.10
let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let radius = rect.width * 0.225
let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

// diagonal gradient indigo -> violet
let top = NSColor(srgbRed: 0.31, green: 0.27, blue: 0.90, alpha: 1)    // ~#4F46E5
let bottom = NSColor(srgbRed: 0.49, green: 0.23, blue: 0.93, alpha: 1) // ~#7C3AED
let grad = NSGradient(starting: top, ending: bottom)!
grad.draw(in: path, angle: -55)

// white SF Symbol "cube.transparent" centered
let cfg = NSImage.SymbolConfiguration(pointSize: 560, weight: .regular)
    .applying(NSImage.SymbolConfiguration(hierarchicalColor: .white))
if let sym = NSImage(systemSymbolName: "cube.transparent", accessibilityDescription: nil)?
    .withSymbolConfiguration(cfg) {
    let s = sym.size
    let r = NSRect(x: (size - s.width) / 2, y: (size - s.height) / 2, width: s.width, height: s.height)
    sym.draw(in: r)
}

NSGraphicsContext.restoreGraphicsState()
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
