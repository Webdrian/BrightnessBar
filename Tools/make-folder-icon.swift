// Draws the folder mark for this project and can apply it to a folder in Finder.
//
// Three styles, because what fits depends on the company the icon keeps:
//   dark    — near-black squircle with an amber sun, matching the other project folders
//   app     — the app icon itself, amber plate with a white sun
//   folder  — the macOS folder with a white sun, for people who want it to read as a folder
//
// The geometry comes from make-icon.swift rather than from a traced screenshot, so all marks
// stay in step when one of them changes.
import AppKit
import UniformTypeIdentifiers

let canvas = 1024

func drawSun(in context: CGContext, center: CGPoint, size: CGFloat, color: NSColor, shadow: Bool) {
    context.saveGState()
    if shadow {
        context.setShadow(offset: CGSize(width: 0, height: -size * 0.02),
                          blur: size * 0.06,
                          color: NSColor.black.withAlphaComponent(0.33).cgColor)
    }
    context.setFillColor(color.cgColor)

    context.addArc(center: center, radius: size * 0.145, startAngle: 0, endAngle: .pi * 2, clockwise: false)
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

/// The rounded square macOS app icons use, with the usual breathing room around it.
func squirclePath(in size: CGFloat) -> (CGPath, CGRect) {
    let inset = size * 0.085
    let plate = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
    let radius = plate.width * 0.2237
    return (CGPath(roundedRect: plate, cornerWidth: radius, cornerHeight: radius, transform: nil), plate)
}

func makeContext() -> CGContext? {
    CGContext(data: nil, width: canvas, height: canvas, bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpaceCreateDeviceRGB(),
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
}

func icon(style: String) -> NSImage? {
    guard let context = makeContext() else { return nil }
    let size = CGFloat(canvas)
    let center = CGPoint(x: size / 2, y: size / 2)

    switch style {
    case "folder":
        let graphics = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        NSWorkspace.shared.icon(for: .folder)
            .draw(in: NSRect(x: 0, y: 0, width: size, height: size), from: .zero,
                  operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        drawSun(in: context, center: CGPoint(x: size / 2, y: size * 0.43),
                size: size * 0.46, color: .white, shadow: true)

    case "app":
        let (path, plate) = squirclePath(in: size)
        context.saveGState(); context.addPath(path); context.clip()
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: [CGColor(red: 1.00, green: 0.76, blue: 0.25, alpha: 1),
                                              CGColor(red: 0.98, green: 0.45, blue: 0.09, alpha: 1)] as CFArray,
                                     locations: [0, 1]) {
            context.drawLinearGradient(gradient,
                                       start: CGPoint(x: plate.minX, y: plate.maxY),
                                       end: CGPoint(x: plate.maxX, y: plate.minY), options: [])
        }
        context.restoreGState()
        drawSun(in: context, center: center, size: size, color: .white, shadow: false)

    default: // "dark"
        let (path, _) = squirclePath(in: size)
        context.saveGState(); context.addPath(path); context.clip()
        context.setFillColor(CGColor(red: 0.086, green: 0.090, blue: 0.110, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        context.restoreGState()
        drawSun(in: context, center: center, size: size,
                color: NSColor(red: 0.98, green: 0.68, blue: 0.13, alpha: 1), shadow: false)
    }

    guard let image = context.makeImage() else { return nil }
    return NSImage(cgImage: image, size: NSSize(width: canvas, height: canvas))
}

// Argumente: <stil> <png-ziel|-> [ordner]
let style = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "dark"
guard let mark = icon(style: style) else { fputs("Zeichnen fehlgeschlagen\n", stderr); exit(1) }

if CommandLine.arguments.count > 2, CommandLine.arguments[2] != "-" {
    let out = URL(fileURLWithPath: CommandLine.arguments[2])
    if let tiff = mark.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
       let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: out)
        print("  \(style): \(out.lastPathComponent)")
    }
}
if CommandLine.arguments.count > 3 {
    let folder = CommandLine.arguments[3]
    print(NSWorkspace.shared.setIcon(mark, forFile: folder, options: [])
          ? "  gesetzt auf: \(folder)" : "  FEHLER beim Setzen")
}
