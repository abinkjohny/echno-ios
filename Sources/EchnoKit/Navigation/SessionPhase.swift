import Foundation

/// How far the app has got in working out who, if anyone, is signed in.
///
/// The phase exists as its own type, rather than as a flag on the session,
/// because what the root of the app shows is a decision with four inputs and
/// one right answer each — and the app target has no test bundle, so a decision
/// made there cannot be checked. ``screen`` and ``prefersDarkAppearance`` are
/// the whole of that decision, and `SessionPhaseTests` pins both.
public enum SessionPhase: String, CaseIterable, Equatable, Sendable {

    /// Launched, with a stored session not yet confirmed either way.
    case restoring

    /// No session. The front door.
    case signedOut

    /// A hosted sign-in is open.
    case signingIn

    /// Confirmed. The app proper.
    case signedIn

    /// Where a launch starts.
    ///
    /// `restoring`, not `signedOut`. Restoring a stored session means asking
    /// Keycloak for a token, which is asynchronous, so a launch that started at
    /// `signedOut` rendered the sign-in screen and then replaced it — every
    /// returning user watched the front door flash past before their own app
    /// appeared. The honest initial state is *not yet known*, which is a third
    /// thing and not a shade of signed out.
    public static let initial: SessionPhase = .restoring

    /// What the root of the app shows.
    public enum Screen: String, CaseIterable, Equatable, Sendable {
        case splash
        case signIn
        case app
    }

    public var screen: Screen {
        switch self {
        case .restoring: .splash
        case .signedOut, .signingIn: .signIn
        case .signedIn: .app
        }
    }

    /// Whether the brand's dark treatment applies.
    ///
    /// Auth is a brand moment and is dark; the app itself follows whatever the
    /// user set. The splash has to match the screen that follows it, or a launch
    /// flashes between appearances before anything is tapped — the same defect
    /// as the screen flash ``initial`` removes, one layer down.
    public var prefersDarkAppearance: Bool {
        switch self {
        case .restoring, .signedOut, .signingIn: true
        case .signedIn: false
        }
    }
}
