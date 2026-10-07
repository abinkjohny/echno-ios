import Foundation
import Testing
@testable import EchnoKit

@Suite("Session phase")
struct SessionPhaseTests {

    @Test("A launch begins by restoring, so the sign-in screen is never the first thing shown")
    func launchBeginsByRestoring() {
        // The bug this exists to stop: starting at .signedOut renders the
        // sign-in screen, and restoring a stored session is asynchronous, so a
        // returning user watched the front door flash past on every launch.
        #expect(SessionPhase.initial == .restoring)
        #expect(SessionPhase.initial.screen == .splash)
    }

    @Test(
        "A phase that has not resolved yet shows the splash, not a decision",
        arguments: [SessionPhase.restoring]
    )
    func unresolvedShowsSplash(phase: SessionPhase) {
        #expect(phase.screen == .splash)
    }

    @Test(
        "Both signed-out phases show the front door",
        arguments: [SessionPhase.signedOut, .signingIn]
    )
    func signedOutShowsSignIn(phase: SessionPhase) {
        #expect(phase.screen == .signIn)
    }

    @Test("A signed-in phase shows the app")
    func signedInShowsApp() {
        #expect(SessionPhase.signedIn.screen == .app)
    }

    @Test("Every phase maps to a screen")
    func everyPhaseIsMapped() {
        // Derived from CaseIterable rather than listed, so a phase added later
        // cannot quietly fall through to whatever the last case happened to be.
        for phase in SessionPhase.allCases {
            #expect(SessionPhase.Screen.allCases.contains(phase.screen))
        }
        #expect(SessionPhase.allCases.count == 4)
    }

    @Test("The splash carries the same dark treatment as the sign-in screen")
    func splashMatchesSignIn() {
        // Auth is a brand moment and is dark; the app follows the user's own
        // setting. If the splash did not match the screen that follows it, a
        // launch would flash between appearances before anything was tapped —
        // which is the same defect as the flash this phase exists to remove,
        // one layer down.
        #expect(SessionPhase.restoring.prefersDarkAppearance)
        #expect(SessionPhase.signedOut.prefersDarkAppearance)
        #expect(SessionPhase.signingIn.prefersDarkAppearance)
        #expect(!SessionPhase.signedIn.prefersDarkAppearance)
    }
}
