import SwiftUI

/// The Echno lockup: the amber mark, then the wordmark.
///
/// One definition, two users — the auth panel and the splash. They have to be
/// the same drawing at two sizes, because the splash hands straight over to the
/// sign-in screen and a lockup that moved or changed weight between them reads
/// as a flicker rather than as a transition.
///
/// Sizes are fixed rather than semantic, which is the opposite of the rule the
/// rest of the type follows. A logo is artwork: it keeps its proportions, and a
/// mark that grew with Dynamic Type while the glyph beside it did not would
/// come apart. Nothing here is prose, so nothing here is read at a text size.
struct EchnoWordmark: View {

    enum Size {
        /// Beside a form — the auth panel's header.
        case standard
        /// Alone on a launch screen, where it is the only thing on the field.
        case display

        var glyph: CGFloat {
            switch self {
            case .standard: 22
            case .display: 40
            }
        }

        var text: CGFloat {
            switch self {
            case .standard: 20
            case .display: 34
            }
        }

        var kerning: CGFloat {
            switch self {
            case .standard: 2
            case .display: 4
            }
        }
    }

    var size: Size = .standard

    var body: some View {
        HStack(spacing: size == .display ? Echno.Space.md : Echno.Space.sm) {
            Image(systemName: "cube.transparent.fill")
                .font(.system(size: size.glyph, weight: .bold))
                .foregroundStyle(Echno.brand)
            Text("ECHNO")
                .font(.system(size: size.text, weight: .black))
                .kerning(size.kerning)
                .foregroundStyle(.white)
        }
        // One element, not two: a screen reader should say the product name
        // once, not announce a decorative cube and then spell out five capitals.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Echno")
        .accessibilityAddTraits(.isImage)
    }
}

#Preview {
    ZStack {
        Echno.panel
        VStack(spacing: Echno.Space.section) {
            EchnoWordmark(size: .standard)
            EchnoWordmark(size: .display)
        }
    }
    .ignoresSafeArea()
}
