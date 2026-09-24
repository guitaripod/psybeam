import AppKit
import Foundation

struct Layer: Decodable {
    var text: String
    var font: String
    var size: CGFloat
    var weight: String?
    var color: String
    var x: CGFloat
    var y: CGFloat
    var align: String?
    var maxWidthFrac: CGFloat?
    var lineSpacing: CGFloat?
    var strokeColor: String?
    var strokeWidth: CGFloat?
    var bgColor: String?
    var bgPadX: CGFloat?
    var bgPadY: CGFloat?
    var bgRadius: CGFloat?
    var shadow: Bool?
}

struct Spec: Decodable {
    var width: Int
    var height: Int
    var layers: [Layer]
}

func nsColor(_ hex: String) -> NSColor {
    var h = hex.trimmingCharacters(in: .whitespaces)
    if h.hasPrefix("#") { h.removeFirst() }
    var rgba: UInt64 = 0
    Scanner(string: h).scanHexInt64(&rgba)
    let len = h.count
    if len == 6 {
        let r = CGFloat((rgba & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((rgba & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(rgba & 0x0000FF) / 255.0
        return NSColor(srgbRed: r, green: g, blue: b, alpha: 1.0)
    } else {
        let r = CGFloat((rgba & 0xFF000000) >> 24) / 255.0
        let g = CGFloat((rgba & 0x00FF0000) >> 16) / 255.0
        let b = CGFloat((rgba & 0x0000FF00) >> 8) / 255.0
        let a = CGFloat(rgba & 0x000000FF) / 255.0
        return NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }
}

func weightedFont(_ family: String, size: CGFloat, weight: String?) -> NSFont {
    let nsWeight: NSFont.Weight
    switch weight ?? "regular" {
    case "bold": nsWeight = .bold
    case "heavy": nsWeight = .heavy
    case "black": nsWeight = .black
    case "semibold": nsWeight = .semibold
    case "medium": nsWeight = .medium
    default: nsWeight = .regular
    }
    if let manager = NSFontManager.shared as NSFontManager?,
       let base = NSFont(name: family, size: size) {
        if weight == "bold" || weight == "heavy" || weight == "black" {
            return manager.convert(base, toHaveTrait: .boldFontMask)
        }
        return base
    }
    if family == "system" {
        return NSFont.systemFont(ofSize: size, weight: nsWeight)
    }
    return NSFont(name: family, size: size) ?? NSFont.systemFont(ofSize: size, weight: nsWeight)
}

let args = CommandLine.arguments
guard args.count >= 3, args[1] == "--spec", args.count >= 5, args[3] == "--out" else {
    FileHandle.standardError.write("usage: textcard --spec spec.json --out out.png\n".data(using: .utf8)!)
    exit(1)
}
let specPath = args[2]
let outPath = args[4]

let data = try! Data(contentsOf: URL(fileURLWithPath: specPath))
let spec = try! JSONDecoder().decode(Spec.self, from: data)

let width = spec.width
let height = spec.height

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else {
    FileHandle.standardError.write("failed to create bitmap\n".data(using: .utf8)!)
    exit(1)
}
bitmap.size = NSSize(width: width, height: height)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
let ctx = NSGraphicsContext.current!.cgContext
ctx.clear(CGRect(x: 0, y: 0, width: width, height: height))

for layer in spec.layers {
    let font = weightedFont(layer.font, size: layer.size, weight: layer.weight)
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = (layer.align == "left") ? .left : (layer.align == "right" ? .right : .center)
    paragraph.lineSpacing = (layer.lineSpacing ?? 1.08 - 1.0) * layer.size
    paragraph.lineBreakMode = .byWordWrapping

    var attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: nsColor(layer.color),
        .paragraphStyle: paragraph,
        .kern: 0.1,
    ]
    if let sc = layer.strokeColor, let sw = layer.strokeWidth {
        attrs[.strokeColor] = nsColor(sc)
        attrs[.strokeWidth] = -sw
    }
    if layer.shadow == true {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.65)
        shadow.shadowOffset = NSSize(width: 0, height: -3)
        shadow.shadowBlurRadius = 10
        attrs[.shadow] = shadow
    }

    let attrString = NSAttributedString(string: layer.text, attributes: attrs)
    let maxWidth = CGFloat(width) * (layer.maxWidthFrac ?? 0.86)
    let bounding = attrString.boundingRect(
        with: NSSize(width: maxWidth, height: CGFloat(height)),
        options: [.usesLineFragmentOrigin, .usesFontLeading]
    )

    let anchorX = CGFloat(width) * layer.x
    let anchorYFromTop = CGFloat(height) * layer.y
    let anchorYFromBottom = CGFloat(height) - anchorYFromTop

    var drawRect = NSRect(
        x: anchorX - maxWidth / 2,
        y: anchorYFromBottom - bounding.height / 2,
        width: maxWidth,
        height: bounding.height + font.leading + 4
    )

    if let bgColor = layer.bgColor {
        let padX = layer.bgPadX ?? 24
        let padY = layer.bgPadY ?? 14
        let bgRect = NSRect(
            x: anchorX - bounding.width / 2 - padX,
            y: drawRect.origin.y - padY,
            width: bounding.width + padX * 2,
            height: drawRect.height + padY * 2
        )
        let radius = layer.bgRadius ?? 14
        let path = NSBezierPath(roundedRect: bgRect, xRadius: radius, yRadius: radius)
        nsColor(bgColor).setFill()
        path.fill()
    }

    drawRect.origin.x = anchorX - bounding.width / 2
    drawRect.size.width = bounding.width + 2

    attrString.draw(
        with: drawRect,
        options: [.usesLineFragmentOrigin, .usesFontLeading]
    )
}

NSGraphicsContext.current?.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("failed to encode png\n".data(using: .utf8)!)
    exit(1)
}
try! pngData.write(to: URL(fileURLWithPath: outPath))
