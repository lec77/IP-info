import AppKit

// Generates a 1024x1024 PNG app-icon master: a white globe on a blue gradient
// rounded-rect ("squircle"-ish). Usage: swift make-icon.swift <output.png>

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon-1024.png"
let size = CGFloat(1024)

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { fputs("no rep\n", stderr); exit(1) }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Gradient rounded-rect background
let inset = CGFloat(88)
let bg = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let radius = bg.width * 0.2237
NSGraphicsContext.current!.saveGraphicsState()
NSBezierPath(roundedRect: bg, xRadius: radius, yRadius: radius).addClip()
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.22, green: 0.64, blue: 1.00, alpha: 1.0),
    NSColor(calibratedRed: 0.00, green: 0.34, blue: 0.86, alpha: 1.0),
])!
gradient.draw(in: bg, angle: -90)
NSGraphicsContext.current!.restoreGraphicsState()

// White globe (SF Symbol), tinted white, centered
let glyphSide = CGFloat(600)
let symConfig = NSImage.SymbolConfiguration(pointSize: 600, weight: .semibold)
if let base = NSImage(systemSymbolName: "globe", accessibilityDescription: nil)?
    .withSymbolConfiguration(symConfig) {
    let s = base.size
    let tinted = NSImage(size: s)
    tinted.lockFocus()
    base.draw(in: NSRect(origin: .zero, size: s))
    NSColor.white.set()
    NSRect(origin: .zero, size: s).fill(using: .sourceAtop)
    tinted.unlockFocus()
    let target = NSRect(x: (size - glyphSide) / 2, y: (size - glyphSide) / 2, width: glyphSide, height: glyphSide)
    tinted.draw(in: target)
}

NSGraphicsContext.restoreGraphicsState()

guard let data = rep.representation(using: .png, properties: [:]) else {
    fputs("failed to encode png\n", stderr); exit(1)
}
try! data.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
