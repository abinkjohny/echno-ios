import SwiftUI

extension View {

    /// Paints a screen with Echno's background instead of the system's.
    ///
    /// Without this a `List` renders on `systemGroupedBackground` — `#F2F2F7`
    /// in light and pure black in dark — so the signed-in app looked like a
    /// default iOS app with an indigo tint rather than like Echno. The theme
    /// already carried the right values, ported from echno-web's `--background`
    /// token; nothing was asking for them.
    ///
    /// The dark value matters more than it sounds. The system's dark grouped
    /// background is `#000000` and Echno's is `#09090B`, so cards and sheets
    /// that sit on it were separating against the wrong ground.
    ///
    /// Hiding the scroll background is what lets the colour through: a `List`
    /// paints its own, and a `background` behind it is simply not visible.
    func echnoScreen() -> some View {
        scrollContentBackground(.hidden)
            .background(Echno.background)
    }
}

extension View {

    /// A row on an ``echnoScreen()``.
    ///
    /// `Echno.card` rather than the system's row colour, for the same reason —
    /// and separators take the theme's border so a row's edge is the same line
    /// everywhere, not a system hairline here and a drawn rule there.
    func echnoRow() -> some View {
        listRowBackground(Echno.card)
            .listRowSeparatorTint(Echno.border)
    }
}
