import SwiftUI
import UIKit
import EchnoKit

/// The registration screen.
///
/// The field set and every validation rule come from `EchnoKit`'s
/// ``RegistrationDraft``, which mirrors the backend's `UserRegistrationDto` and
/// echno-web's `lib/validators`. This file owns presentation only.
///
/// echno-web lays the fields out two-up in a single run. Here they are grouped
/// into three sections and stacked one per row on iPhone — a half-width text
/// field on a phone is a worse target and wraps its label — reverting to two-up
/// only at regular width, where there is room for it.
struct RegisterView: View {

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthSession.self) private var session
    @State private var form = RegistrationForm()
    @State private var failure: String?
    @FocusState private var focused: RegistrationField?

    private var isWide: Bool { sizeClass == .regular }

    var body: some View {
        NavigationStack {
            ZStack {
                BrandBackground()

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: Echno.Space.xl) {
                            header
                            accountSection
                            securitySection
                            profileSection
                            termsAndSubmit
                        }
                        .frame(maxWidth: 560)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, Echno.Space.xl)
                        .padding(.vertical, Echno.Space.xl)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: form.scrollTarget) { _, target in
                        guard let target else { return }
                        withAnimation(.easeOut(duration: 0.25)) {
                            proxy.scrollTo(target, anchor: .center)
                        }
                        if target.isTextEntry { focused = target }
                        form.scrollTarget = nil
                    }
                }
            }
            .navigationTitle("Create Account")
            .navigationBarTitleDisplayMode(.inline)
            .alert(
                "Registration Failed",
                isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
            ) {
                Button("OK", role: .cancel) { failure = nil }
            } message: {
                Text(failure ?? "")
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focused = nil }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Echno.Space.sm) {
            Text("Create Your Account")
                .font(.echnoScreenTitleCompact)
                .foregroundStyle(Echno.foreground)
            Text("Fill in your details to get started — it only takes a minute.")
                .font(.subheadline)
                .foregroundStyle(Echno.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Sections

    private var accountSection: some View {
        EchnoSection(title: "Account") {
            VStack(spacing: Echno.Space.lg) {
                pair {
                    field(.userName, "Username") {
                        TextField("", text: $form.userName, prompt: Self.hint("john_doe"))
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                } second: {
                    field(.name, "Full Name") {
                        TextField("", text: $form.name, prompt: Self.hint("John Doe"))
                            .textContentType(.name)
                    }
                }

                field(.email, "Email") {
                    TextField("", text: $form.email, prompt: Self.hint("john@company.com"))
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
        }
    }

    private var securitySection: some View {
        EchnoSection(
            title: "Security",
            caption: "At least 8 characters, with upper and lower case, a number and a symbol."
        ) {
            VStack(spacing: Echno.Space.lg) {
                VStack(alignment: .leading, spacing: Echno.Space.sm) {
                    field(.password, "Password") {
                        EchnoSecureField(placeholder: "At least 8 characters", text: $form.password)
                            .textContentType(.newPassword)
                    }
                    if !form.password.isEmpty {
                        PasswordStrengthMeter(score: form.passwordStrength)
                    }
                }

                field(.confirmPassword, "Confirm Password") {
                    EchnoSecureField(placeholder: "Re-enter password", text: $form.confirmPassword)
                        .textContentType(.newPassword)
                }
            }
        }
    }

    private var profileSection: some View {
        EchnoSection(title: "Profile") {
            VStack(spacing: Echno.Space.lg) {
                pair {
                    field(.phone, "Phone") {
                        TextField("", text: $form.phone, prompt: Self.hint("+911234567890"))
                            .textContentType(.telephoneNumber)
                            .keyboardType(.phonePad)
                    }
                } second: {
                    EchnoField(title: "Gender", isRequired: true) {
                        Picker("Gender", selection: $form.gender) {
                            ForEach(Gender.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.menu)
                        .tint(Echno.foreground)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .labelsHidden()
                    }
                    .id(RegistrationField.gender)
                }

                EchnoDateField(
                    title: "Date of Birth",
                    prompt: "Select Date",
                    selection: $form.dateOfBirth,
                    range: form.dateOfBirthRange,
                    error: form.error(for: .dateOfBirth)
                )
                .id(RegistrationField.dateOfBirth)
                .accessibilityHint("You must be at least \(RegistrationDraft.minimumAge) years old")

                EchnoField(title: "Role", isRequired: true, error: form.error(for: .role)) {
                    Picker("Role", selection: $form.role) {
                        Text("Select a Role").tag(UserRole?.none)
                        ForEach(UserRole.allCases) { Text($0.label).tag(UserRole?.some($0)) }
                    }
                    .pickerStyle(.menu)
                    .tint(form.role == nil ? Echno.mutedForeground : Echno.foreground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .labelsHidden()
                }
                .id(RegistrationField.role)
            }
        }
    }

    private var termsAndSubmit: some View {
        VStack(spacing: Echno.Space.xl) {
            EchnoCard {
                VStack(alignment: .leading, spacing: Echno.Space.sm) {
                    Toggle(isOn: $form.acceptTerms) {
                        Text("I accept the Terms of Service and Privacy Policy")
                            .font(.footnote)
                            .foregroundStyle(Echno.foreground)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .toggleStyle(.switch)
                    .tint(Echno.primary)

                    if let error = form.error(for: .acceptTerms) {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(Echno.destructive)
                    }
                }
            }
            .id(RegistrationField.acceptTerms)

            EchnoPrimaryButton(title: "Create Account", isLoading: form.isSubmitting) {
                submit()
            }

            HStack(spacing: Echno.Space.xs) {
                Text("Already have an account?")
                    .foregroundStyle(Echno.mutedForeground)
                Button("Sign In") { dismiss() }
                    .foregroundStyle(Echno.brand)
                    .fontWeight(.semibold)
            }
            .font(.footnote)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Behaviour

    private func submit() {
        focused = nil
        guard form.validate() else {
            // Land the user on the first problem reading down the form, not on
            // whichever key the error dictionary happened to yield first.
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            form.scrollTarget = form.firstInvalidField()
            return
        }
        register()
    }

    private func register() {
        form.isSubmitting = true
        Task {
            defer { form.isSubmitting = false }
            do {
                try await session.register(form.draft)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                // Registration creates the identity but not a session. Hand
                // straight to the hosted sign-in, as echno-web does, so a new
                // user is not left at a form wondering whether it worked.
                dismiss()
                await session.signIn()
            } catch RegistrationError.invalidDraft(let fieldErrors) {
                // The service validated too and disagreed with the form. Show
                // what it found rather than a generic failure.
                form.apply(fieldErrors)
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                form.scrollTarget = form.firstInvalidField()
            } catch {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                failure = (error as? LocalizedError)?.errorDescription
                    ?? "Registration could not be completed."
            }
        }
    }

    // MARK: Building blocks

    /// A text field wired into the keyboard chain, its error, and its scroll id.
    ///
    /// Every text field needs the same five modifiers; applying them here rather
    /// than at each call site is what keeps the Next button working when a field
    /// is added or moved.
    @ViewBuilder
    private func field<Control: View>(
        _ id: RegistrationField,
        _ title: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        EchnoField(title: title, isRequired: true, error: form.error(for: id)) {
            control()
                .focused($focused, equals: id)
                .submitLabel(id.next == nil ? .done : .next)
                .onSubmit { focused = id.next }
        }
        .id(id)
    }

    private static func hint(_ text: String) -> Text {
        Text(text).foregroundStyle(Echno.mutedForeground)
    }

    /// Two fields side by side at regular width, stacked when compact.
    @ViewBuilder
    private func pair<A: View, B: View>(
        @ViewBuilder first: () -> A,
        @ViewBuilder second: () -> B
    ) -> some View {
        if isWide {
            HStack(alignment: .top, spacing: Echno.Space.lg) { first(); second() }
        } else {
            VStack(spacing: Echno.Space.lg) { first(); second() }
        }
    }
}

/// Five segments, one per satisfied password rule.
///
/// Gives the rules a shape while the user is typing, rather than revealing them
/// one refusal at a time after each submit.
private struct PasswordStrengthMeter: View {
    let score: Int

    private var colour: Color {
        switch score {
        case 0...2: Echno.destructive
        case 3...4: Echno.warning
        default: Echno.success
        }
    }

    private var label: String {
        switch score {
        case 0...2: "Weak"
        case 3...4: "Getting There"
        default: "Strong"
        }
    }

    var body: some View {
        HStack(spacing: Echno.Space.sm) {
            HStack(spacing: Echno.Space.xs) {
                ForEach(0..<5, id: \.self) { index in
                    Capsule()
                        .fill(index < score ? colour : Echno.border)
                        .frame(height: 4)
                }
            }
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(colour)
                .frame(width: 84, alignment: .leading)
        }
        .animation(.easeOut(duration: 0.2), value: score)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Password strength: \(label), \(score) of 5 rules met")
    }
}

#Preview("iPhone") {
    RegisterView()
        .environment(AuthSession())
        .preferredColorScheme(.dark)
}

// Forces the regular-width layout so the two-up rows are reviewable without an
// iPad in the canvas. For a true iPad rendering, pick one in the device picker.
#Preview("Regular width") {
    RegisterView()
        .environment(AuthSession())
        .environment(\.horizontalSizeClass, .regular)
        .preferredColorScheme(.dark)
}
