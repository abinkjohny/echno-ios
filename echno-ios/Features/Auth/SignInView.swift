import SwiftUI

/// The auth flow: sign-in, with registration presented over it.
///
/// Both screens sit on the dark brand field and run in dark appearance
/// regardless of the system setting. That is deliberate — this is the brand
/// moment, the same one echno-web builds with its near-black register panel,
/// and committing to it also keeps the status bar legible over the artwork.
/// Everything past sign-in follows the system appearance.
struct AuthFlowView: View {
    var body: some View {
        SignInView()
            .preferredColorScheme(.dark)
            .tint(Echno.primary)
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
    @State private var isAuthenticating = false
    @State private var showRegister = false

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
                .preferredColorScheme(.dark)
                .tint(Echno.primary)
        }
    }

    // MARK: Layouts

    /// iPad and iPhone landscape: brand column beside the card, as on the web.
    private var wideLayout: some View {
        HStack(alignment: .center, spacing: 0) {
            BrandPanel(layout: .full)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 0) {
                signInBlock
            }
            .frame(maxWidth: .infinity)
            .padding(40)
        }
    }

    /// iPhone: a short brand header, then the card, then the legal line.
    private var compactLayout: some View {
        VStack(spacing: 0) {
            BrandPanel(layout: .header)
            // Capped so the card sits in the upper-middle on a tall phone
            // instead of drifting to the centre of a mostly empty field.
            Spacer(minLength: 16).frame(maxHeight: 96)
            signInBlock
                .padding(.horizontal, 24)
            Spacer(minLength: 20)
        }
        .padding(.bottom, 12)
    }

    // MARK: Content

    private var signInBlock: some View {
        VStack(spacing: 22) {
            VStack(spacing: 8) {
                Text("Welcome back")
                    .font(.system(size: 27, weight: .black))
                    .foregroundStyle(Echno.foreground)
                Text("Sign in to your Echno account to continue.")
                    .font(.subheadline)
                    .foregroundStyle(Echno.mutedForeground)
                    .multilineTextAlignment(.center)
            }

            EchnoCard {
                VStack(spacing: 16) {
                    EchnoPrimaryButton(title: "Sign in", isLoading: isAuthenticating) {
                        signIn()
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Image(systemName: "lock.shield")
                        Text("Opens a secure Echno sign-in page. Your password is never entered in this app.")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.caption)
                    .foregroundStyle(Echno.mutedForeground)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 10) {
                        rule
                        Text("New to Echno?")
                            .font(.caption)
                            .foregroundStyle(Echno.mutedForeground)
                            .fixedSize()
                        rule
                    }

                    EchnoSecondaryButton(
                        title: "Create an account",
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

    /// Phase 1 replaces this with `ASWebAuthenticationSession` + PKCE.
    private func signIn() {
        isAuthenticating = true
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            isAuthenticating = false
        }
    }
}

#Preview("iPhone") { AuthFlowView() }

#Preview("iPad", traits: .landscapeLeft) { AuthFlowView() }
