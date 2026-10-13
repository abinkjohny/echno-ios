import SwiftUI
import EchnoKit

/// A person, as initials on a tinted disc.
///
/// echno-web's `shared/employee-avatar.tsx`, which the workforce and project
/// screens will need too. Falls back to a person glyph when there are no
/// initials to show — an empty disc reads as a rendering bug, whereas the glyph
/// reads as "no name on file", which is the truth.
struct EchnoAvatar: View {
    let initials: String
    var diameter: CGFloat = Echno.Size.avatar

    var body: some View {
        ZStack {
            Circle().fill(Echno.brand.opacity(Echno.Opacity.subtle))
            // Both the glyph and the initials sit on that tint, which lifts the
            // ground towards the ink: the plain fill measures 2.38:1 there,
            // failing even the 3:1 a glyph is held to.
            if initials.isEmpty {
                Image(systemName: "person.fill")
                    .font(.system(size: diameter * 0.42))
                    .foregroundStyle(Echno.Text.brandOnTint)
            } else {
                Text(initials)
                    .font(.system(size: diameter * 0.36, weight: .semibold))
                    .foregroundStyle(Echno.Text.brandOnTint)
                    // Three-character initials happen with Indic scripts, where
                    // a consonant and its vowel sign are one Character.
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }
}

#Preview {
    HStack(spacing: Echno.Space.lg) {
        EchnoAvatar(initials: "RK")
        EchnoAvatar(initials: "രകു")
        EchnoAvatar(initials: "")
    }
    .padding()
}
