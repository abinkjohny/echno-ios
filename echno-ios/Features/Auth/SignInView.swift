import SwiftUI

/// The auth flow: sign-in, with registration presented over it.
///
/// The sign-in and registration screens sit on the dark brand field and run in
/// dark appearance regardless of the system setting — the brand moment, the same
/// one echno-web builds with its near-black register panel, and what keeps the
/// status bar legible over the artwork.
///
/// The app shell does **not**. `preferredColorScheme` is applied to the
/// signed-out branch alone, so it lifts the moment the shell replaces it and the
/// app follows whatever the user set. Applied to the whole `Group` it would
/// force the entire signed-in app dark, which is a different product decision
/// and not one anybody made.
struct AuthFlowView: View {
    @State private var session = AuthSession()

    var body: some View {
        Group {
            switch session.state {
            case .signedOut, .signingIn:
                // Dark only while signed out. The preference travels with the
                // view, so it lifts as soon as the shell replaces this — which
                // is the intent: auth is a brand moment, the app itself follows
                // whatever the user set.
                SignInView().preferredColorScheme(.dark)
            case .signedIn:
                AppShell()
            }
        }
        .environment(session)
        .tint(Echno.primary)
        .task { await session.restore() }
    }
}

/// The sign-in screen.
///
/// There is no password field here on purpose. Echno authenticates against
/// Keycloak, and echno-web's real sign-in is `signIn('keycloak')` — a redirect
/// to Keycloak's hosted login. (Its email/password provider is a dev-only mock
/// gated behind `DEV_MOCK_EMAIL`.) The iOS equivalent is
/// `ASWebAuthenticationSession` opening that same page, which keeps SSO, MFA
/// and password policy in one place and the user's password out of this app.
///
/// So this screen's job is to be a confident front door and hand off cleanly.
struct SignInView: View {

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(AuthSession.self) private var session
    @State private var showRegister = false

    private var isAuthenticating: Bool { session.state == .signingIn }

    private var isWide: Bool { sizeClass == .regular }

    var body: some View {
        ZStack {
            BrandBackground()

            GeometryReader { proxy in
                ScrollView {
                    Group {
                        if isWide { wideLayout } else { compactLayout }
                    }
                    .frame(minHeight: proxy.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .sheet(isPresented: $showRegister) {
            RegisterView()
                .environment(session)
                .preferredColorScheme(.dark)
                .tint(Echno.primary)
                // A default sheet on iPad is a form sheet: ~540pt wide, which
                // carries the *compact* size class. The registration form would
                // render single-column on a 13-inch iPad, with most of it below
                // the fold, and the two-up layout would never appear. A page
                // sheet is wide enough to be regular width, so the form gets the
                // room the device actually has. No effect on iPhone, where a
                // sheet is full width either way.
                .presentationSizing(.page)
        }
        .alert(
            "Sign-In Failed",
            isPresented: Binding(
                get: { session.error != nil },
                set: { if !$0 { session.error = nil } }
            )
        ) {
            Button("OK", role: .cancel) { session.error = nil }
        } message: {
            Text(session.error ?? "")
        }
    }

    // MARK: Layouts

    /// iPad and iPhone landscape: brand column beside the card, as on the web.
    private var wideLayout: some View {
        HStack(alignment: .center, spacing: 0) {
            BrandPanel(layout: .full)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: Echno.Space.section) {
                signInBlock
                footer
            }
            .frame(maxWidth: .infinity)
            .padding(Echno.Space.screen)
        }
    }

    /// iPhone: a short brand header, then the card, then the legal line.
    private var compactLayout: some View {
        VStack(spacing: 0) {
            BrandPanel(layout: .header)
            // Capped so the card sits in the upper-middle on a tall phone
            // instead of drifting to the centre of a mostly empty field.
            Spacer(minLength: Echno.Space.lg).frame(maxHeight: 88)
            signInBlock
                .padding(.horizontal, Echno.Space.xxl)
            Spacer(minLength: Echno.Space.xxl)
            footer
        }
        .padding(.bottom, Echno.Space.sm)
    }

    // MARK: Content

    private var signInBlock: some View {
        VStack(spacing: Echno.Space.xxl) {
            VStack(spacing: Echno.Space.sm) {
                Text("Welcome Back")
                    .font(.echnoScreenTitle)
                    .foregroundStyle(Echno.foreground)
                Text("Sign in to your Echno account to continue.")
                    .font(.subheadline)
                    .foregroundStyle(Echno.mutedForeground)
                    .multilineTextAlignment(.center)
            }

            EchnoCard {
                VStack(spacing: Echno.Space.lg) {
                    EchnoPrimaryButton(title: "Sign In", isLoading: isAuthenticating) {
                        signIn()
                    }
                    .accessibilityHint("Opens the Echno sign-in page in a secure browser")

                    HStack(alignment: .firstTextBaseline, spacing: Echno.Space.sm) {
                        Image(systemName: "lock.shield")
                        Text("Opens a secure Echno sign-in page. Your password is never entered in this app.")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.caption)
                    .foregroundStyle(Echno.mutedForeground)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: Echno.Space.md) {
                        rule
                        Text("New to Echno?")
                            .font(.caption)
                            .foregroundStyle(Echno.mutedForeground)
                            .fixedSize()
                        rule
                    }

                    EchnoSecondaryButton(
                        title: "Create an Account",
                        systemImage: "person.badge.plus"
                    ) {
                        showRegister = true
                    }
                }
            }

            Text("By continuing you agree to Echno's Terms of Service and Privacy Policy.")
                .font(.caption2)
                .foregroundStyle(Echno.mutedForeground)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 400)
    }

    private var rule: some View {
        Rectangle().fill(Echno.border).frame(height: 1)
    }

    /// Anchors the bottom of the screen and gives support something to quote.
    private var footer: some View {
        VStack(spacing: Echno.Space.xs) {
            Text("Echno for iOS")
                .font(.caption2.weight(.medium))
            Text(Bundle.main.displayVersion)
                .font(.caption2)
                .monospacedDigit()
        }
        .foregroundStyle(Echno.mutedForeground.opacity(Echno.Opacity.secondary))
        .accessibilityElement(children: .combine)
    }

    private func signIn() {
        Task { await session.signIn() }
    }
}

#Preview("iPhone") { AuthFlowView() }

// `traits: .landscapeLeft` only rotates whichever device the canvas has
// selected, and an iPhone stays horizontally compact in landscape — so it
// rendered the phone layout, not the iPad one. Overriding the size class shows
// the two-column layout on any device. For a true iPad rendering, pick an iPad
// in the canvas device picker.
#Preview("Regular width — two column") {
    AuthFlowView()
        .environment(\.horizontalSizeClass, .regular)
}

#Preview("Accessibility XXL") {
    AuthFlowView()
        .environment(\.dynamicTypeSize, .accessibility2)
}
