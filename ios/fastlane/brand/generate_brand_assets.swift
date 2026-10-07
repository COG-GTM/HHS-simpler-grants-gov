import AppKit
import CoreText
import Foundation
import ImageIO

let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iosDirectory = repositoryRoot.appendingPathComponent("ios")
let assetsDirectory = iosDirectory.appendingPathComponent("App/Assets.xcassets")
let fontDirectory = iosDirectory.appendingPathComponent(
    "Packages/SGDesign/Sources/SGDesign/Resources/Fonts"
)

func font(named filename: String, size: CGFloat) throws -> CTFont {
    let url = fontDirectory.appendingPathComponent(filename)
    guard
        let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
        let descriptor = descriptors.first
    else {
        throw NSError(
            domain: "BrandAssets",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Could not load font at \(url.path)"]
        )
    }
    return CTFontCreateWithFontDescriptor(descriptor, size, nil)
}

struct Canvas {
    let width: Int
    let height: Int
    let context: CGContext

    init(width: Int, height: Int, alpha: Bool = false) {
        self.width = width
        self.height = height
        let alphaInfo = alpha
            ? CGImageAlphaInfo.premultipliedLast
            : CGImageAlphaInfo.noneSkipLast
        context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: srgb,
            bitmapInfo: alphaInfo.rawValue
        )!
    }

    var image: CGImage {
        context.makeImage()!
    }
}

func savePNG(_ image: CGImage, to url: URL) throws {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    let bitmap = NSBitmapImageRep(cgImage: image)
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(
            domain: "BrandAssets",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Could not encode PNG at \(url.path)"]
        )
    }
    try data.write(to: url)
}

func drawLine(
    _ text: String,
    font: CTFont,
    color: CGColor,
    tracking: CGFloat = 0,
    center: CGPoint,
    context: CGContext
) -> CGRect {
    var attributes: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
    ]
    if tracking != 0 {
        attributes[NSAttributedString.Key(kCTKernAttributeName as String)] = tracking
    }
    let line = CTLineCreateWithAttributedString(
        NSAttributedString(string: text, attributes: attributes)
    )
    var ascent: CGFloat = 0
    var descent: CGFloat = 0
    var leading: CGFloat = 0
    let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
    let origin = CGPoint(x: center.x - width / 2, y: center.y - (ascent - descent) / 2)
    context.textPosition = origin
    CTLineDraw(line, context)
    return CGRect(x: origin.x, y: origin.y - descent, width: width, height: ascent + descent)
}

func writeJSON(_ object: Any, to url: URL) throws {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: url)
}

func validateAppIcon(at url: URL) throws {
    guard
        let source = CGImageSourceCreateWithURL(url as CFURL, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
        throw NSError(
            domain: "BrandAssets",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: "Could not read generated AppIcon.png"]
        )
    }
    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    let hasAlphaChannel: Bool
    switch image.alphaInfo {
    case .premultipliedLast, .premultipliedFirst, .last, .first, .alphaOnly:
        hasAlphaChannel = true
    case .none, .noneSkipFirst, .noneSkipLast:
        hasAlphaChannel = false
    @unknown default:
        hasAlphaChannel = true
    }
    guard
        properties?[kCGImagePropertyHasAlpha] as? Bool != true,
        !hasAlphaChannel
    else {
        throw NSError(
            domain: "BrandAssets",
            code: 4,
            userInfo: [NSLocalizedDescriptionKey: "Generated AppIcon.png must not have an alpha channel"]
        )
    }
    guard
        let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width * 4,
            space: srgb,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ),
        let data = context.data
    else {
        throw NSError(
            domain: "BrandAssets",
            code: 5,
            userInfo: [NSLocalizedDescriptionKey: "Could not create sRGB AppIcon.png validation bitmap"]
        )
    }
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let pixels = data.assumingMemoryBound(to: UInt8.self)
    let offset = (16 * image.width + 16) * 4
    let actual = (0..<3).map { Int(pixels[offset + $0]) }
    let expected = [31, 61, 110]
    guard zip(actual, expected).allSatisfy({ abs($0.0 - $0.1) <= 1 }) else {
        throw NSError(
            domain: "BrandAssets",
            code: 6,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "Generated AppIcon.png pixel (16,16) is \(actual); expected (31,61,110) ±1"
            ]
        )
    }
    print("AppIcon sRGB self-check passed: pixel (16,16) = \(actual), no alpha.")
}

let navy = CGColor(colorSpace: srgb, components: [31 / 255, 61 / 255, 110 / 255, 1])!
let sparkColor = CGColor(colorSpace: srgb, components: [232 / 255, 237 / 255, 245 / 255, 1])!
let secondary = CGColor(colorSpace: srgb, components: [90 / 255, 96 / 255, 112 / 255, 1])!
let serif = try font(named: "SourceSerif4-Semibold.ttf", size: 1000)
let publicSansSemibold = try font(named: "PublicSans-SemiBold.ttf", size: 15)
let publicSansRegular = try font(named: "PublicSans-Regular.ttf", size: 13)

let iconSize = 1024
let icon = Canvas(width: iconSize, height: iconSize)
let iconContext = icon.context
iconContext.setFillColor(navy)
iconContext.fill(CGRect(x: 0, y: 0, width: iconSize, height: iconSize))

let targetCapHeight = CGFloat(iconSize) * 0.42
let iconFont = CTFontCreateCopyWithAttributes(
    serif,
    targetCapHeight / CTFontGetCapHeight(serif) * 1000,
    nil,
    nil
)
let wordBounds = drawLine(
    "SG",
    font: iconFont,
    color: CGColor(colorSpace: srgb, components: [1, 1, 1, 1])!,
    center: CGPoint(x: CGFloat(iconSize) / 2, y: CGFloat(iconSize) / 2),
    context: iconContext
)

let sparkCenter = CGPoint(x: wordBounds.maxX - wordBounds.width * 0.12, y: wordBounds.maxY - wordBounds.height * 0.2)
let sparkRadius = CGFloat(iconSize) * 0.045
let sparkPath = CGMutablePath()
sparkPath.move(to: CGPoint(x: sparkCenter.x, y: sparkCenter.y + sparkRadius))
sparkPath.addLine(to: CGPoint(x: sparkCenter.x + sparkRadius * 0.2, y: sparkCenter.y + sparkRadius * 0.2))
sparkPath.addLine(to: CGPoint(x: sparkCenter.x + sparkRadius, y: sparkCenter.y))
sparkPath.addLine(to: CGPoint(x: sparkCenter.x + sparkRadius * 0.2, y: sparkCenter.y - sparkRadius * 0.2))
sparkPath.addLine(to: CGPoint(x: sparkCenter.x, y: sparkCenter.y - sparkRadius))
sparkPath.addLine(to: CGPoint(x: sparkCenter.x - sparkRadius * 0.2, y: sparkCenter.y - sparkRadius * 0.2))
sparkPath.addLine(to: CGPoint(x: sparkCenter.x - sparkRadius, y: sparkCenter.y))
sparkPath.addLine(to: CGPoint(x: sparkCenter.x - sparkRadius * 0.2, y: sparkCenter.y + sparkRadius * 0.2))
sparkPath.closeSubpath()
iconContext.addPath(sparkPath)
iconContext.setFillColor(sparkColor)
iconContext.fillPath()

let iconSet = assetsDirectory.appendingPathComponent("AppIcon.appiconset")
try savePNG(icon.image, to: iconSet.appendingPathComponent("AppIcon.png"))
try writeJSON(
    [
        "images": [
            [
                "filename": "AppIcon.png",
                "idiom": "universal",
                "platform": "ios",
                "size": "1024x1024",
            ],
        ],
        "info": ["author": "xcode", "version": 1],
    ],
    to: iconSet.appendingPathComponent("Contents.json")
)

let preview = Canvas(width: iconSize, height: iconSize)
let previewContext = preview.context
previewContext.setFillColor(CGColor(colorSpace: srgb, components: [0.9, 0.9, 0.9, 1])!)
previewContext.fill(CGRect(x: 0, y: 0, width: iconSize, height: iconSize))
let roundedRect = CGPath(
    roundedRect: CGRect(x: 0, y: 0, width: iconSize, height: iconSize),
    cornerWidth: CGFloat(iconSize) * 0.225,
    cornerHeight: CGFloat(iconSize) * 0.225,
    transform: nil
)
previewContext.addPath(roundedRect)
previewContext.clip()
previewContext.draw(icon.image, in: CGRect(x: 0, y: 0, width: iconSize, height: iconSize))
try savePNG(
    preview.image,
    to: iosDirectory.appendingPathComponent("fastlane/output/icon-preview.png")
)

let colorSet = assetsDirectory.appendingPathComponent("LaunchBackground.colorset")
try writeJSON(
    [
        "colors": [
            [
                "color": [
                    "color-space": "srgb",
                    "components": [
                        "alpha": "1.000",
                        "blue": "0xF3",
                        "green": "0xF6",
                        "red": "0xF6",
                    ],
                ],
                "idiom": "universal",
            ],
        ],
        "info": ["author": "xcode", "version": 1],
    ],
    to: colorSet.appendingPathComponent("Contents.json")
)

let wordmarkSet = assetsDirectory.appendingPathComponent("LaunchBackgroundWordmark.imageset")
for scale in 1...3 {
    let width = 260 * scale
    let height = 60 * scale
    let wordmark = Canvas(width: width, height: height, alpha: true)
    let context = wordmark.context
    context.clear(CGRect(x: 0, y: 0, width: width, height: height))
    let multiplier = CGFloat(scale)
    let mainFont = CTFontCreateCopyWithAttributes(
        publicSansSemibold,
        15 * multiplier,
        nil,
        nil
    )
    let subtitleFont = CTFontCreateCopyWithAttributes(
        publicSansRegular,
        13 * multiplier,
        nil,
        nil
    )
    _ = drawLine(
        "SIMPLER.GRANTS.GOV",
        font: mainFont,
        color: navy,
        tracking: 1.2 * multiplier,
        center: CGPoint(x: CGFloat(width) / 2, y: CGFloat(height) * 0.68),
        context: context
    )
    _ = drawLine(
        "Demo · sample data",
        font: subtitleFont,
        color: secondary,
        center: CGPoint(x: CGFloat(width) / 2, y: CGFloat(height) * 0.28),
        context: context
    )
    try savePNG(
        wordmark.image,
        to: wordmarkSet.appendingPathComponent("LaunchBackgroundWordmark@\(scale)x.png")
    )
}
try writeJSON(
    [
        "images": [
            ["filename": "LaunchBackgroundWordmark@3x.png", "idiom": "universal", "scale": "3x"],
            ["filename": "LaunchBackgroundWordmark@2x.png", "idiom": "universal", "scale": "2x"],
            ["filename": "LaunchBackgroundWordmark@1x.png", "idiom": "universal", "scale": "1x"],
        ],
        "info": ["author": "xcode", "version": 1],
    ],
    to: wordmarkSet.appendingPathComponent("Contents.json")
)
try validateAppIcon(at: iconSet.appendingPathComponent("AppIcon.png"))
