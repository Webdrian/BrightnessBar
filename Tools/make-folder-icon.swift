// Builds a Finder folder icon carrying the app's sun glyph, and optionally applies it to a
// folder. Lives next to make-icon.swift so both marks come from the same drawing instead of
// one being traced from a screenshot of the other.
import AppKit
import UniformTypeIdentifiers

let canvas = 1024

/// The app icon's glyph, drawn white so it reads as part of the folder rather than as a
/// sticker on top of it.
func drawSun(in context: CGContext, center: CGPoint, size: CGFloat) {
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -size * 0.02),
                      blur: size * 0.06,
                      color: NSColor.black.withAlphaComponent(0.33).cgColor)
    context.setFillColor(NSColor.white.cgColor)

    let core = size * 0.145
    context.addArc(center: center, radius: core, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    context.fillPath()

    let inner = size * 0.225, outer = size * 0.350, thickness = size * 0.072
    for index in 0..<8 {
        context.saveGState()
        context.translateBy(x: center.x, y: center.y)
        context.rotate(by: CGFloat(index) * .pi / 4)
        let ray = CGRect(x: inner, y: -thickness / 2, width: outer - inner, height: thickness)
        context.addPath(CGPath(roundedRect: ray, cornerWidth: thickness / 2,
                               cornerHeight: thickness / 2, transform: nil))
        context.fillPath()
        context.restoreGState()
    }
    context.restoreGState()
}

func folderIcon(glyphScale: CGFloat, glyphY: CGFloat) -> NSImage? {
    let base = NSWorkspace.shared.icon(for: .folder)
    guard let context = CGContext(data: nil, width: canvas, height: canvas,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }

    let graphics = NSGraphicsContext(cgContext: context, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    base.draw(in: NSRect(x: 0, y: 0, width: canvas, height: canvas),
              from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()

    drawSun(in: context,
            center: CGPoint(x: CGFloat(canvas) / 2, y: CGFloat(canvas) * glyphY),
            size: CGFloat(canvas) * glyphScale)

    guard let cgImage = context.makeImage() else { return nil }
    return NSImage(cgImage: cgImage, size: NSSize(width: canvas, height: canvas))
}

let scale = CommandLine.arguments.count > 3 ? CGFloat(Double(CommandLine.arguments[3]) ?? 0.46) : 0.46
let yPos  = CommandLine.arguments.count > 4 ? CGFloat(Double(CommandLine.arguments[4]) ?? 0.43) : 0.43

guard let icon = folderIcon(glyphScale: scale, glyphY: yPos) else {
    fputs("Icon konnte nicht gezeichnet werden\n", stderr); exit(1)
}

// Argument 1: PNG-Ziel. Argument 2 (optional): Ordner, auf den es gesetzt wird.
if CommandLine.arguments.count > 1, CommandLine.arguments[1] != "-" {
    let out = URL(fileURLWithPath: CommandLine.arguments[1])
    if let tiff = icon.tiffRepresentation,
       let rep = NSBitmapImageRep(data: tiff),
       let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: out)
        print("  geschrieben: \(out.lastPathComponent)")
    }
}
if CommandLine.arguments.count > 2, CommandLine.arguments[2] != "-" {
    let folder = CommandLine.arguments[2]
    print(NSWorkspace.shared.setIcon(icon, forFile: folder, options: [])
          ? "  gesetzt auf: \(folder)" : "  FEHLER beim Setzen auf \(folder)")
}
