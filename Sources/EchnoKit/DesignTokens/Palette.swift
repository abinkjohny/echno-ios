import Foundation

/// The raw colour values the app's theme is built from.
///
/// ## Why these live in `EchnoKit` rather than beside the `Color`s
///
/// A colour used for text has to meet WCAG's 4.5:1 contrast against its
/// backdrop, and one used for a bar or an icon has to meet 3:1. Those are
/// arithmetic facts about the values, so they can be *tested* — but only where
/// `swift test` can reach them, and the app target has no test bundle.
///
/// So the numbers live here and `Theme.swift` binds them to SwiftUI colours.
/// `Theme.swift` remains the one file to read to understand the theme; this is
/// the data underneath it, kept honest by ``contrastRatio(_:_:)``.
public enum Palette {

    // MARK: Surfaces

    public static let white: UInt32 = 0xFFFFFF
    public static let near_black: UInt32 = 0x09090B
    public static let cardDark: UInt32 = 0x18181B

    // MARK: Fills
    //
    // Vivid. Used for bars, icons and tinted backgrounds, which WCAG holds to
    // 3:1 as graphical objects rather than the 4.5:1 it asks of text.

    public static let brandLight: UInt32 = 0xE68300
    public static let brandDark: UInt32 = 0xFE9A00
    public static let successLight: UInt32 = 0x16A34A
    public static let successDark: UInt32 = 0x4ADE80
    public static let warningLight: UInt32 = 0xD97706
    public static let warningDark: UInt32 = 0xFBBF24
    public static let infoLight: UInt32 = 0x0284C7
    public static let infoDark: UInt32 = 0x38BDF8

    // MARK: Text
    //
    // Darker in light appearance, because the fill values above sit between
    // 2.7:1 and 4.1:1 on white — fine behind a bar, unreadable as a caption.
    // The dark-appearance values are the fills again: on near-black they are
    // already well past 4.5:1.

    public static let brandTextLight: UInt32 = 0xB45309
    public static let brandTextDark: UInt32 = 0xFE9A00
    public static let successTextLight: UInt32 = 0x15803D
    public static let successTextDark: UInt32 = 0x4ADE80
    public static let warningTextLight: UInt32 = 0xB45309
    public static let warningTextDark: UInt32 = 0xFBBF24
    public static let infoTextLight: UInt32 = 0x0369A1
    public static let infoTextDark: UInt32 = 0x38BDF8
    public static let destructiveLight: UInt32 = 0xE7000B
    public static let destructiveDark: UInt32 = 0xFF6467

    // MARK: On the always-dark brand panel

    public static let onPanelPrimary: UInt32 = 0xF4F4F5
    public static let onPanelSecondary: UInt32 = 0xA1A1AA
    public static let onPanelTertiary: UInt32 = 0x8E8E96
    public static let onPanelFaint: UInt32 = 0x82828A

    // MARK: Contrast

    /// WCAG 2.1 relative luminance.
    public static func relativeLuminance(_ colour: UInt32) -> Double {
        let channels = [16, 8, 0].map { Double((colour >> UInt32($0)) & 0xFF) / 255 }
        let linear = channels.map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
    }

    /// The WCAG contrast ratio between two colours, from 1:1 to 21:1.
    ///
    /// Normal text needs 4.5, large text and graphical objects 3.
    public static func contrastRatio(_ a: UInt32, _ b: UInt32) -> Double {
        let (first, second) = (relativeLuminance(a), relativeLuminance(b))
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }
}
