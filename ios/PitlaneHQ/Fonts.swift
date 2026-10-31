import SwiftUI

/// The Track First look's three fonts (bundled in Resources/Fonts, listed in UIAppFonts): IBM Plex Sans for every text,
/// JetBrains Mono for the numbers (times, places, iRating) and Barlow Condensed for the titles, the same as the
/// design's and the web's. The names are the fonts' PostScript names.
extension Font {
    /// text: IBM Plex Sans (its heaviest face here is Bold, so black reads Bold)
    static func ui(_ size: CGFloat, _ w: Font.Weight = .regular) -> Font {
        let n: String
        switch w {
        case .medium: n = "IBMPlexSans-Medm"
        case .semibold: n = "IBMPlexSans-SmBld"
        case .bold, .heavy, .black: n = "IBMPlexSans-Bold"
        default: n = "IBMPlexSans"
        }
        return .custom(n, size: size)
    }

    /// numbers: JetBrains Mono
    static func mono(_ size: CGFloat, _ w: Font.Weight = .regular) -> Font {
        let n: String
        switch w {
        case .medium: n = "JetBrainsMono-Medium"
        case .semibold: n = "JetBrainsMono-SemiBold"
        case .bold, .heavy, .black: n = "JetBrainsMono-Bold"
        default: n = "JetBrainsMono-Regular"
        }
        return .custom(n, size: size)
    }

    /// titles and section labels: Barlow Condensed, written in capitals by the caller
    static func display(_ size: CGFloat, _ w: Font.Weight = .bold) -> Font {
        let n: String
        switch w {
        case .heavy, .black: n = "BarlowCondensed-ExtraBold"
        case .bold: n = "BarlowCondensed-Bold"
        default: n = "BarlowCondensed-SemiBold"
        }
        return .custom(n, size: size)
    }
}
