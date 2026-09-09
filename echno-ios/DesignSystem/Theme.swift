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

    // MARK: Status
    //
    // Almost every module in this product is status-shaped: attendance is
    // pending, approved or rejected; so are leave requests, indents, purchase
    // orders and site transfers. Without a named set each screen picks its own
    // green, and "approved" stops looking the same from one screen to the next —
    // which is exactly how a design system comes apart.
    //
    // Paired with an icon or a label wherever they carry meaning. Colour alone
    // fails for the ~8% of men with a colour vision deficiency, and a
    // construction workforce is not an exception to that.

    /// Approved, complete, in good standing.
    static let success = Color(light: 0x16A34A, dark: 0x4ADE80)

    /// Pending, expiring, needs attention but is not yet wrong.
    static let warning = Color(light: 0xD97706, dark: 0xFBBF24)

    /// Neutral information — draft, submitted, awaiting someone else.
    static let info = Color(light: 0x0284C7, dark: 0x38BDF8)

    // MARK: Surfaces

    static let background = Color(light: 0xFFFFFF, dark: 0x09090B)
    static let card = Color(light: 0xFFFFFF, dark: 0x18181B)
    static let border = Color(light: 0xE4E4E7, dark: 0x27272A)

    /// The dark panel behind the brand artwork. Fixed in both appearances —
    /// it is artwork, not a surface, and it reads as Echno in either theme.
    static let panel = Color(rgb: 0x09090B)

    /// Text on ``panel``.
    ///
    /// Fixed, not adaptive, and that is the point: the panel is always dark, so
    /// the adaptive `foreground` and `mutedForeground` would turn near-black on
    /// it in light appearance and disappear. These were inline hex literals in
    /// `BrandPanel` for exactly that reason — naming them records the reason
    /// with them.
    enum OnPanel {
        /// Headings and highlight titles.
        static let primary = Color(rgb: 0xF4F4F5)
        /// Supporting copy under a heading.
        static let secondary = Color(rgb: 0xA1A1AA)
        /// Detail lines beneath a highlight.
        static let tertiary = Color(rgb: 0x71717B)
        /// The quietest thing on the panel — legal and trust lines.
        static let faint = Color(rgb: 0x52525C)
    }

    /// The amber sweep on the brand headline, warm end first.
    static let brandGradient = [Color(rgb: 0xF59E0B), Color(rgb: 0xEA580C)]

    /// The deeper amber behind the panel's lower glow.
    static let brandGlow = Color(rgb: 0xEA580C)

    // MARK: Text

    static let foreground = Color(light: 0x09090B, dark: 0xFAFAFA)
    static let mutedForeground = Color(light: 0x71717B, dark: 0x9F9FA9)

    // MARK: Geometry

    /// The spacing scale.
    ///
    /// Before this existed the view layer used 21 distinct spacing values across
    /// 65 sites — 7, 14, 18, 22, 28 among them. Nobody chose 7 over 8; they were
    /// whatever looked right while typing. With 26 module screens still to come,
    /// that spread only widens and screens drift out of rhythm in ways nobody
    /// can point at.
    ///
    /// A 4-point grid, because that is what iOS lays out on. Reach for the
    /// nearest step rather than adding one — a scale with an exception for every
    /// case is just the literals again with longer names.
    enum Space {
        /// 2 — between a label and the value it describes.
        static let hairline: CGFloat = 2
        /// 4 — inside a tightly grouped pair.
        static let xs: CGFloat = 4
        /// 8 — between elements of one control.
        static let sm: CGFloat = 8
        /// 12 — between related controls.
        static let md: CGFloat = 12
        /// 16 — between controls in a form.
        static let lg: CGFloat = 16
        /// 20 — between a group and its neighbour.
        static let xl: CGFloat = 20
        /// 24 — screen margins when compact; between sections.
        static let xxl: CGFloat = 24
        /// 32 — around a major block.
        static let section: CGFloat = 32
        /// 40 — screen margins at regular width.
        static let screen: CGFloat = 40
    }

    /// Fixed dimensions that are not spacing.
    enum Size {
        /// Borders and rules. One point, not one pixel — SwiftUI works in
        /// points and the display scale handles the rest.
        static let hairline: CGFloat = 1
        /// Text fields and list rows: the HIG minimum touch target.
        static let field: CGFloat = 44
        /// Primary buttons — taller than the minimum, because the main action
        /// on a screen should be the easiest thing on it to hit.
        static let control: CGFloat = 50
        /// The avatar disc. Matches ``field`` so a row with one keeps its rhythm.
        static let avatar: CGFloat = 44
        /// The brand panel's glow blur.
        static let glowBlur: CGFloat = 40
    }

    /// The opacity ladder.
    ///
    /// There were ten distinct values before this, six of them used once —
    /// 0.16, 0.20, 0.22, 0.25, 0.28, 0.30. Tinted fills and borders that differ
    /// by two percent do not read as different, they read as unconsidered.
    enum Opacity {
        /// A tinted fill behind an icon or a badge.
        static let faint = 0.10
        /// A hairline border on a tinted fill.
        static let subtle = 0.15
        /// A border that should be seen without being read.
        static let soft = 0.20
        /// Artwork that must register.
        static let medium = 0.25
        /// The panel's glows.
        static let strong = 0.30
        /// De-emphasised text that still has to be legible.
        static let secondary = 0.70
        /// Text one step below full strength.
        static let primary = 0.85
    }

    /// Animation timings.
    ///
    /// Inconsistent timing is felt even when it is not noticed: two controls
    /// that should feel like siblings stop doing so.
    enum Motion {
        /// A state toggle — a message appearing, a meter filling.
        static let quick = 0.15
        /// The default for anything that changes in place.
        static let standard = 0.20
        /// Movement the eye has to follow, like scrolling to an error.
        static let deliberate = 0.25
    }

    /// echno-web's `--radius: 0.625rem`.
    enum Radius {
        static let sm: CGFloat = 6
        static let md: CGFloat = 8
        static let lg: CGFloat = 10
        static let xl: CGFloat = 14
    }
}

/// The few typographic mannerisms that are Echno's rather than the system's.
///
/// Deliberately built on semantic styles, never point sizes. A scale expressed
/// in points would reintroduce a bug this codebase already had: headings at
/// fixed sizes while body text scaled, so at accessibility sizes the subtitle
/// rendered larger than the heading it sat under. Everything here scales with
/// Dynamic Type because `.title` and `.subheadline` do.
///
/// The system styles are used directly everywhere else — `.caption`,
/// `.subheadline`, `.headline` say what they mean, and wrapping them would add
/// a layer of indirection over names SwiftUI already chose well.
extension Font {
    /// The heading at the top of a screen. Heavier than the system's title,
    /// which is the whole mannerism.
    static let echnoScreenTitle = Font.title.weight(.black)

    /// A screen heading where a full title would crowd the content.
    static let echnoScreenTitleCompact = Font.title2.weight(.black)

    /// A group heading inside a form.
    static let echnoSectionTitle = Font.subheadline.weight(.semibold)
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
