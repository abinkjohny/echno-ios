import SwiftUI

/// The Echno colour palette.
///
/// These are echno-web's design tokens, converted from OKLCH to sRGB so the two
/// products read as one. The source of truth is `app/globals.css` in echno-web —
/// when a token changes there, change it here.
///
/// Each colour resolves per appearance, so views never branch on colour scheme.
enum Echno {

    // MARK: Brand

    /// Amber. The Echno accent — highlights, marks, the logo lockup.
    static let brand = Color(light: 0xE68300, dark: 0xFE9A00)

    /// Indigo. Primary actions and the app tint.
    static let primary = Color(light: 0x686FFF, dark: 0x8693FF)

    /// Red. Destructive actions and validation failures.
    static let destructive = Color(light: 0xE7000B, dark: 0xFF6467)

    // MARK: Surfaces

    static let background = Color(light: 0xFFFFFF, dark: 0x09090B)
    static let card = Color(light: 0xFFFFFF, dark: 0x18181B)
    static let border = Color(light: 0xE4E4E7, dark: 0x27272A)

    /// The dark panel behind the brand artwork. Fixed in both appearances —
    /// it is artwork, not a surface, and it reads as Echno in either theme.
    static let panel = Color(rgb: 0x09090B)

    // MARK: Text

    static let foreground = Color(light: 0x09090B, dark: 0xFAFAFA)
    static let mutedForeground = Color(light: 0x71717B, dark: 0x9F9FA9)

    // MARK: Geometry

    /// echno-web's `--radius: 0.625rem`.
    enum Radius {
        static let sm: CGFloat = 6
        static let md: CGFloat = 8
        static let lg: CGFloat = 10
        static let xl: CGFloat = 14
    }
}

// MARK: - Hex helpers

extension Color {

    /// A colour that resolves differently in light and dark appearance.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    init(rgb: UInt32) {
        self.init(uiColor: UIColor(rgb: rgb))
    }
}

extension UIColor {
    fileprivate convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension Bundle {
    /// `1.0 (1)` — the marketing version and build, for the sign-in footer and
    /// anything support needs quoted back.
    var displayVersion: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }
}
