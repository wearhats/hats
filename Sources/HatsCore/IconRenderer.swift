import Foundation

#if canImport(CoreGraphics)
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers
#endif

/// Renders a macOS-style rounded-square icon with a letter or a simple
/// pictogram, in-process, with no shipped assets and no `iconutil`. The
/// pictograms are drawn here rather than taken from SF Symbols, whose licence
/// forbids their use in app icons.
public enum IconRenderer {
    public enum Glyph: Equatable, Sendable {
        case letter(String)
        case briefcase
        case person

        public init(_ profile: Profile) {
            switch profile.icon {
            case .letter: self = .letter(profile.initial)
            case .briefcase: self = .briefcase
            case .person: self = .person
            }
        }
    }
}

#if canImport(CoreGraphics)
extension IconRenderer {
    public static func png(glyph: Glyph, color: ProfileColor, size: Int) throws(HatsError) -> Data {
        guard
            let context = CGContext(
                data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { throw HatsError(.io, "cannot allocate a \(size)px bitmap") }

        // Apple's macOS icon grid: an 824/1024 body with a ~185/1024 corner radius.
        let scale = CGFloat(size) / 1024
        let body = CGRect(x: 100 * scale, y: 100 * scale, width: 824 * scale, height: 824 * scale)
        let fill = CGColor(srgbRed: CGFloat(color.red) / 255, green: CGFloat(color.green) / 255, blue: CGFloat(color.blue) / 255, alpha: 1)
        context.setShadow(offset: CGSize(width: 0, height: -10 * scale), blur: 20 * scale, color: CGColor(gray: 0, alpha: 0.3))
        context.addPath(CGPath(roundedRect: body, cornerWidth: 185 * scale, cornerHeight: 185 * scale, transform: nil))
        context.setFillColor(fill)
        context.fillPath()
        context.setShadow(offset: .zero, blur: 0)

        let glyphColor = color.prefersDarkGlyph ? CGColor(gray: 0.1, alpha: 1) : CGColor(gray: 1, alpha: 1)
        switch glyph {
        case .letter(let letter): drawLetter(letter, in: body, color: glyphColor, scale: scale, context: context)
        case .briefcase: drawBriefcase(in: body, color: glyphColor, background: fill, context: context)
        case .person: drawPerson(in: body, color: glyphColor, context: context)
        }

        guard let image = context.makeImage() else { throw HatsError(.io, "cannot render icon") }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw HatsError(.io, "cannot create a PNG encoder")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw HatsError(.io, "cannot encode icon PNG") }
        return data as Data
    }

    private static func drawLetter(_ letter: String, in body: CGRect, color glyphColor: CGColor, scale: CGFloat, context: CGContext) {
        let font =
            CTFontCreateUIFontForLanguage(.system, 520 * scale, nil)
            ?? CTFontCreateWithName("Helvetica-Bold" as CFString, 520 * scale, nil)
        let bold = CTFontCreateCopyWithSymbolicTraits(font, 0, nil, .traitBold, .traitBold) ?? font
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): bold,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): glyphColor,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: letter, attributes: attributes))
        let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        context.textPosition = CGPoint(x: body.midX - bounds.midX, y: body.midY - bounds.midY)
        CTLineDraw(line, context)
    }

    /// Coordinates are fractions of the icon body, origin bottom-left.
    private static func drawBriefcase(in body: CGRect, color: CGColor, background: CGColor, context: CGContext) {
        func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
            CGRect(x: body.minX + x * body.width, y: body.minY + y * body.height, width: width * body.width, height: height * body.height)
        }
        let unit = body.width
        context.setFillColor(color)
        context.addPath(
            CGPath(roundedRect: rect(0.18, 0.24, 0.64, 0.42), cornerWidth: 0.06 * unit, cornerHeight: 0.06 * unit, transform: nil))
        context.fillPath()
        context.setStrokeColor(color)
        context.setLineWidth(0.055 * unit)
        context.addPath(
            CGPath(roundedRect: rect(0.38, 0.62, 0.24, 0.16), cornerWidth: 0.04 * unit, cornerHeight: 0.04 * unit, transform: nil))
        context.strokePath()
        // A thin seam in the background colour keeps the case readable at 16 px.
        context.setFillColor(background)
        context.fill(rect(0.18, 0.47, 0.64, 0.025))
    }

    private static func drawPerson(in body: CGRect, color: CGColor, context: CGContext) {
        let unit = body.width
        context.setFillColor(color)
        let headDiameter = 0.30 * unit
        context.fillEllipse(
            in: CGRect(x: body.midX - headDiameter / 2, y: body.minY + 0.52 * unit, width: headDiameter, height: headDiameter))
        context.saveGState()
        context.clip(to: CGRect(x: body.minX, y: body.minY + 0.18 * unit, width: unit, height: 0.29 * unit))
        // Centred on the clip's bottom edge, so only the upper half (the shoulders) shows.
        context.fillEllipse(in: CGRect(x: body.midX - 0.3 * unit, y: body.minY - 0.1 * unit, width: 0.6 * unit, height: 0.56 * unit))
        context.restoreGState()
    }

    public static func icns(glyph: Glyph, color: ProfileColor) throws(HatsError) -> Data {
        var images: [(ICNSEncoder.ImageType, Data)] = []
        var cache: [Int: Data] = [:]
        for type in ICNSEncoder.ImageType.allCases {
            if cache[type.pixels] == nil { cache[type.pixels] = try png(glyph: glyph, color: color, size: type.pixels) }
            images.append((type, cache[type.pixels]!))
        }
        return ICNSEncoder.encode(images)
    }
}
#endif

/// Minimal ICNS writer: `'icns' | UInt32 BE total length | entries`, each entry
/// `OSType | UInt32 BE length incl. 8-byte header | PNG bytes`.
public enum ICNSEncoder {
    public enum ImageType: String, CaseIterable, Sendable {
        case icp4, icp5, ic07, ic08, ic09, ic10, ic11, ic12, ic13, ic14

        public var pixels: Int {
            switch self {
            case .icp4: 16
            case .icp5, .ic11: 32
            case .ic12: 64
            case .ic07: 128
            case .ic08, .ic13: 256
            case .ic09, .ic14: 512
            case .ic10: 1024
            }
        }
    }

    public static func encode(_ images: [(ImageType, Data)]) -> Data {
        var body = Data()
        for (type, png) in images {
            body.append(contentsOf: Array(type.rawValue.utf8))
            body.append(bigEndian: UInt32(png.count + 8))
            body.append(png)
        }
        var file = Data("icns".utf8)
        file.append(bigEndian: UInt32(body.count + 8))
        file.append(body)
        return file
    }
}

extension Data {
    mutating func append(bigEndian value: UInt32) {
        Swift.withUnsafeBytes(of: value.bigEndian) { append(contentsOf: $0) }
    }
}
