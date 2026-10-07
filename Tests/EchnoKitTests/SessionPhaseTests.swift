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

    @Test("No phase carries an appearance of its own")
    func noPhaseForcesAnAppearance() {
        // There was a `prefersDarkAppearance` here, and the auth screens were
        // dark in every appearance because of it. They follow the system now,
        // so the property is gone rather than returning false everywhere —
        // the phase has no opinion about appearance at all, and a property
        // that always answers the same thing is a place for one to grow back.
        //
        // What is left is the screen mapping, and it is the only thing a phase
        // decides.
        #expect(SessionPhase.Screen.allCases.count == 3)
    }

}
