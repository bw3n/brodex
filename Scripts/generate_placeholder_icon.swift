import AppKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    fputs("usage: generate_placeholder_icon.swift <logo-path> <iconset-path>\n", stderr)
    exit(1)
}

let logoURL = URL(fileURLWithPath: arguments[1])
let iconsetURL = URL(fileURLWithPath: arguments[2], isDirectory: true)
let fileManager = FileManager.default
try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let specs: [(filename: String, points: CGFloat, scale: CGFloat)] = [
    ("icon_16x16.png", 16, 1),
    ("icon_16x16@2x.png", 16, 2),
    ("icon_32x32.png", 32, 1),
    ("icon_32x32@2x.png", 32, 2),
    ("icon_128x128.png", 128, 1),
    ("icon_128x128@2x.png", 128, 2),
    ("icon_256x256.png", 256, 1),
    ("icon_256x256@2x.png", 256, 2),
    ("icon_512x512.png", 512, 1),
    ("icon_512x512@2x.png", 512, 2)
]

func loadLogo() -> NSImage? {
    if let image = NSImage(contentsOf: logoURL) {
        return image
    }

    guard
        let data = try? Data(contentsOf: logoURL),
        let rep = NSPDFImageRep(data: data)
    else {
        return nil
    }

    let image = NSImage(size: rep.size)
    image.addRepresentation(rep)
    return image
}

let logoImage = loadLogo()

func drawFallbackGlyph(in rect: NSRect, size: CGFloat) {
    let glyph = ">B_"
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let font = NSFont.monospacedSystemFont(ofSize: size * 0.24, weight: .bold)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.black,
        .paragraphStyle: paragraph
    ]
    let glyphRect = NSRect(
        x: rect.minX,
        y: rect.midY - size * 0.13,
        width: rect.width,
        height: size * 0.28
    )
    glyph.draw(in: glyphRect, withAttributes: attributes)
}

func aspectFillRect(for sourceSize: NSSize, in destinationRect: NSRect) -> NSRect {
    let safeSourceSize = NSSize(
        width: max(sourceSize.width, 1),
        height: max(sourceSize.height, 1)
    )
    let widthScale = destinationRect.width / safeSourceSize.width
    let heightScale = destinationRect.height / safeSourceSize.height
    let scale = max(widthScale, heightScale)
    let drawSize = NSSize(
        width: safeSourceSize.width * scale,
        height: safeSourceSize.height * scale
    )

    return NSRect(
        x: destinationRect.midX - drawSize.width / 2,
        y: destinationRect.midY - drawSize.height / 2,
        width: drawSize.width,
        height: drawSize.height
    )
}

func makeImage(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor.clear.setFill()
    rect.fill()

    if let logoImage {
        let drawRect = aspectFillRect(for: logoImage.size, in: rect)
        logoImage.draw(in: drawRect)
    } else {
        let fallbackPath = NSBezierPath(roundedRect: rect, xRadius: size * 0.22, yRadius: size * 0.22)
        NSColor.black.setFill()
        fallbackPath.fill()
        drawFallbackGlyph(in: rect, size: size)
    }

    return image
}

func writePNG(image: NSImage, to url: URL) throws {
    guard
        let tiff = image.tiffRepresentation,
        let rep = NSBitmapImageRep(data: tiff),
        let png = rep.representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "BrodexIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to render PNG"])
    }
    try png.write(to: url)
}

for spec in specs {
    let pixelSize = spec.points * spec.scale
    let image = makeImage(size: pixelSize)
    try writePNG(image: image, to: iconsetURL.appendingPathComponent(spec.filename))
}
