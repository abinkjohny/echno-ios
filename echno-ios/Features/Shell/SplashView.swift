import SwiftUI
import EchnoKit

/// What a launch shows while the stored session is being confirmed.
///
/// Not decoration. Confirming a session means asking Keycloak for a token,
/// which is a network round trip, and before this existed the root started at
/// "signed out" and rendered the sign-in screen — so every returning user
/// watched the front door flash past on the way to their own app. The honest
/// state is *not yet known*, and this is what that looks like.
///
/// It is the brand field the auth screens use, so the hand-off is continuous:
/// the static launch image is the same near-black, this is the same field with
/// the same lockup, and the sign-in screen that follows keeps both. Nothing
/// changes colour between the tap and the first screen.
///
/// There is deliberately no progress indicator. A spinner invites the reading
/// that something is slow, and a restore that succeeds is usually too quick to
/// see; the lockup fading up says *starting* without promising a wait.
struct SplashView: View {

    /// Set once on appear so the fade runs forwards, rather than being the
    /// state the view is first drawn in.
    @State private var hasAppeared = false

    /// Someone who has asked for less movement gets the lockup, not the
    /// entrance. Honouring this is not optional — for a vestibular trigger a
    /// scaling logo is a symptom, not a flourish.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isSettled: Bool { hasAppeared || reduceMotion }

    var body: some View {
        ZStack {
            BrandBackground()

            EchnoWordmark(size: .display)
                .opacity(isSettled ? 1 : 0)
                .scaleEffect(isSettled ? 1 : 0.96)
                .animation(
                    reduceMotion ? nil : .easeOut(duration: Echno.Motion.entrance),
                    value: isSettled
                )
        }
        // The whole screen is one announcement. Without this a screen reader
        // finds a field with a logo in it and nothing to say about why.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Starting Echno")
        .onAppear { hasAppeared = true }
    }
}

#Preview {
    SplashView()
}
