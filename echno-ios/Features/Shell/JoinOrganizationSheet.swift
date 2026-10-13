import SwiftUI
import EchnoKit

/// Redeems an invite code.
///
/// Everything a user needs to join is five digits, because the employment
/// details — department, designation, status — are set by whoever issued the
/// code and travel on it. There is nothing else to collect, so this is one
/// field rather than a form.
struct JoinOrganizationSheet: View {

    @Environment(AuthSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    /// What the field holds. Not an ``InviteCode``, because a code only exists
    /// once it is valid and a field has to be able to hold three digits on the
    /// way there.
    @State private var typed = ""
    @State private var isJoining = false
    @State private var failure: String?
    @FocusState private var isFocused: Bool

    /// The code, or `nil` while it is incomplete. Also what enables the button,
    /// so it cannot be pressed on something the server would reject.
    private var code: InviteCode? { InviteCode(typed) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Echno.Space.lg) {
                Text("Enter the \(InviteCode.length)-digit code from your organization's administrator.")
                    .font(.subheadline)
                    .foregroundStyle(Echno.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)

                EchnoField(title: "Invite Code", isRequired: true, error: failure) {
                    TextField("", text: $typed)
                        .font(.title2.weight(.semibold).monospacedDigit())
                        // Tracked so five digits read as a code rather than a
                        // number, the way the web console presents one.
                        .kerning(Echno.Space.sm)
                        .multilineTextAlignment(.center)
                        .keyboardType(.numberPad)
                        .textContentType(nil)
                        .autocorrectionDisabled()
                        .focused($isFocused)
                        .accessibilityLabel("Invite code")
                        .accessibilityHint("\(InviteCode.length) digits, from your organization's administrator")
                        .onChange(of: typed) { _, new in
                            // The field cannot come to hold something
                            // unsendable: a paste with spaces or letters in it
                            // is reduced as it arrives. Also clears a stale
                            // failure, so the previous attempt's message does
                            // not sit under a code being retyped.
                            let sanitized = InviteCode.sanitize(new)
                            if sanitized != new { typed = sanitized }
                            failure = nil
                        }
                }

                EchnoPrimaryButton(
                    title: "Join",
                    isLoading: isJoining,
                    isEnabled: code != nil
                ) {
                    Task { await join() }
                }

                Spacer(minLength: 0)
            }
            .padding(Echno.Space.lg)
            .echnoScreen()
            .navigationTitle("Join an Organization")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // Dismissing is a decision, not a failure, so nothing is
                    // reported when it happens.
                    Button("Cancel") { dismiss() }
                        .disabled(isJoining)
                }
            }
            .task { isFocused = true }
        }
    }

    /// Redeems, and leaves the sheet open on failure so the code is still
    /// there to correct.
    ///
    /// `isJoining` is what stops a second attempt while one is in flight. Not
    /// only to avoid a double request: redeeming twice means the second one
    /// finds an existing membership, which the backend answers with a 500 that
    /// cannot be told apart from a real fault (ask #22).
    private func join() async {
        guard let code, !isJoining else { return }
        isJoining = true
        failure = nil
        defer { isJoining = false }

        do {
            _ = try await session.join(using: code)
            dismiss()
        } catch {
            failure = (error as? APIError)?.message
                ?? (error as? LocalizedError)?.errorDescription
                ?? "The code could not be used. Try again shortly."
        }
    }
}

#Preview {
    JoinOrganizationSheet()
        .environment(AuthSession())
}
