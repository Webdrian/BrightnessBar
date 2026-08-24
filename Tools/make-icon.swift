// Generates Resources/AppIcon.icns. Run via Tools/make-icon.sh — kept in the repo so the
// icon is reproducible instead of an opaque binary nobody can edit.
import AppKit

let sizes = [16, 32, 64, 128, 256, 512, 1024]
let outputDir = URL(fileURLWithPath: CommandLine.arguments[1])

/// Rounded-square plate with a sun glyph. The glyph stays chunky on purpose: thin rays turn
/// to mush at 16 px, which is the size that actually matters in Finder lists.
func drawIcon(size: CGFloat, into context: CGContext) {
    let inset = size * 0.085
    let plate = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
    let radius = plate.width * 0.2237   // matches the macOS squircle closely enough

    let path = CGPath(roundedRect: plate, cornerWidth: radius, cornerHeight: radius, transform: nil)
    context.saveGState()
    context.addPath(path)
    context.clip()

    let colors = [
        CGColor(red: 1.00, green: 0.76, blue: 0.25, alpha: 1),
        CGColor(red: 0.98, green: 0.45, blue: 0.09, alpha: 1),
    ]
    if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                 colors: colors as CFArray, locations: [0, 1]) {
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: plate.minX, y: plate.maxY),
            end: CGPoint(x: plate.maxX, y: plate.minY),
            options: []
        )
    }
    context.restoreGState()

    let center = CGPoint(x: size / 2, y: size / 2)
    context.setFillColor(.white)

    // The glyph is staggered by size, because one drawing cannot serve 16 px and 512 px.
    // Eight thin rays read as a sun when large but collapse into a dot grid when tiny, so
    // 16 px gets the bare core, 32 px four chunky rays, and everything above the full sun.
    // Rays must also stay inside the plate: its half-width is 0.415, so 0.355 is the ceiling.
    let coreRadius: CGFloat
    let rayCount: Int
    let rayInner: CGFloat, rayOuter: CGFloat, rayWidth: CGFloat

    switch size {
    case ...16:
        coreRadius = size * 0.26
        rayCount = 0
        rayInner = 0; rayOuter = 0; rayWidth = 0
    case ...32:
        coreRadius = size * 0.185
        rayCount = 4
        rayInner = size * 0.265; rayOuter = size * 0.350; rayWidth = size * 0.105
    default:
        coreRadius = size * 0.145
        rayCount = 8
        rayInner = size * 0.225; rayOuter = size * 0.350; rayWidth = size * 0.072
    }

    context.addArc(center: center, radius: coreRadius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    context.fillPath()

    for index in 0..<rayCount {
        let angle = CGFloat(index) * (.pi * 2 / CGFloat(rayCount))
        context.saveGState()
        context.translateBy(x: center.x, y: center.y)
        context.rotate(by: angle)
        let ray = CGRect(x: rayInner, y: -rayWidth / 2, width: rayOuter - rayInner, height: rayWidth)
        context.addPath(CGPath(roundedRect: ray, cornerWidth: rayWidth / 2, cornerHeight: rayWidth / 2, transform: nil))
        context.fillPath()
        context.restoreGState()
    }
}

for size in sizes {
    guard let context = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { continue }

    context.setAllowsAntialiasing(true)
    context.interpolationQuality = .high
    drawIcon(size: CGFloat(size), into: context)

    guard let image = context.makeImage() else { continue }
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: size, height: size)
    guard let png = rep.representation(using: .png, properties: [:]) else { continue }

    // iconset naming: every size appears as @1x and, where applicable, as @2x of the half size
    var names: [String] = []
    if [16, 32, 128, 256, 512].contains(size) { names.append("icon_\(size)x\(size).png") }
    if [32, 64, 256, 512, 1024].contains(size) {
        let base = size / 2
        names.append("icon_\(base)x\(base)@2x.png")
    }
    for name in names {
        try? png.write(to: outputDir.appendingPathComponent(name))
    }
    print("  \(size)px -> \(names.joined(separator: ", "))")
}
