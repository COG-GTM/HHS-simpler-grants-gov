import CoreText
import Foundation

public enum SGFonts {
    private static let requiredFonts: [(postScriptName: String, familyName: String)] = [
        ("SourceSerif4-Regular", "Source Serif 4"),
        ("SourceSerif4-SemiBold", "Source Serif 4"),
        ("PublicSans-Regular", "Public Sans"),
        ("PublicSans-Medium", "Public Sans"),
        ("PublicSans-SemiBold", "Public Sans"),
        ("PublicSans-Bold", "Public Sans")
    ]

    public static func registerAll() {
        let resourceNames = [
            "SourceSerif4-Regular",
            "SourceSerif4-Semibold",
            "PublicSans-Regular",
            "PublicSans-Medium",
            "PublicSans-SemiBold",
            "PublicSans-Bold"
        ]

        for resourceName in resourceNames {
            guard let url = Bundle.module.url(
                forResource: resourceName,
                withExtension: "ttf",
                subdirectory: "Fonts"
            ) else {
                preconditionFailure("Missing bundled font \(resourceName).ttf")
            }
            _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }

        let availableNames = CTFontManagerCopyAvailablePostScriptNames() as? [String] ?? []
        for requiredFont in requiredFonts {
            guard let registeredName = availableNames.first(where: {
                $0.caseInsensitiveCompare(requiredFont.postScriptName) == .orderedSame
            }) else {
                preconditionFailure("Font \(requiredFont.postScriptName) was not registered")
            }
            let font = CTFontCreateWithName(registeredName as CFString, 12, nil)
            let familyName = CTFontCopyFamilyName(font) as String
            precondition(
                familyName == requiredFont.familyName,
                "Font \(requiredFont.postScriptName) resolved to \(familyName)"
            )
        }
    }
}
