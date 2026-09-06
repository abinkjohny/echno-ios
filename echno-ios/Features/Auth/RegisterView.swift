import SwiftUI
import EchnoCore

/// The registration screen.
///
/// Field set and validation come from the backend's `UserRegistrationDto`
/// (`POST /api/v1/auth/register`) and echno-web's `RegistrationForm`. echno-web
/// lays the fields out two-up; here they are one per row on iPhone and two-up
/// on iPad, because a half-width text field on a phone is a worse target and
/// wraps its label.
struct RegisterView: View {

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dismiss) private var dismiss
    @State private var form = RegistrationForm()
    @FocusState private var focused: RegistrationField?

    private var isWide: Bool { sizeClass == .regular }

    var body: some View {
        NavigationStack {
            ZStack {
                BrandBackground()
                ScrollView {
                    VStack(spacing: 24) {
                        header
                        EchnoCard { fields }
                        submit
                    }
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 20)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Create account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Create your account")
                .font(.system(size: 26, weight: .black))
                .foregroundStyle(Echno.foreground)
            Text("Fill in your details to get started — it only takes a minute.")
                .font(.subheadline)
                .foregroundStyle(Echno.mutedForeground)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Fields

    @ViewBuilder
    private var fields: some View {
        VStack(spacing: 16) {
            pair {
                EchnoField(title: "Username", isRequired: true, error: form.error(for: .userName)) {
                    TextField("", text: $form.userName, prompt: Self.hint("john_doe"))
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focused, equals: .userName)
                }
            } second: {
                EchnoField(title: "Full name", isRequired: true, error: form.error(for: .name)) {
                    TextField("", text: $form.name, prompt: Self.hint("John Doe"))
                        .textContentType(.name)
                        .focused($focused, equals: .name)
                }
            }

            EchnoField(title: "Email", isRequired: true, error: form.error(for: .email)) {
                TextField("", text: $form.email, prompt: Self.hint("john@company.com"))
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused, equals: .email)
            }

            VStack(alignment: .leading, spacing: 8) {
                EchnoField(title: "Password", isRequired: true, error: form.error(for: .password)) {
                    EchnoSecureField(placeholder: "At least 8 characters", text: $form.password)
                        .focused($focused, equals: .password)
                }
                if !form.password.isEmpty {
                    PasswordStrengthMeter(score: form.passwordStrength)
                }
            }

            EchnoField(
                title: "Confirm password",
                isRequired: true,
                error: form.error(for: .confirmPassword)
            ) {
                EchnoSecureField(placeholder: "Re-enter password", text: $form.confirmPassword)
                    .focused($focused, equals: .confirmPassword)
            }

            pair {
                EchnoField(title: "Phone", isRequired: true, error: form.error(for: .phone)) {
                    TextField("", text: $form.phone, prompt: Self.hint("+911234567890"))
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                        .focused($focused, equals: .phone)
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
            }

            EchnoField(
                title: "Date of birth",
                isRequired: true,
                error: form.error(for: .dateOfBirth)
            ) {
                DatePicker(
                    "Date of birth",
                    selection: Binding(
                        get: { form.dateOfBirth ?? form.dateOfBirthRange.upperBound },
                        set: { form.dateOfBirth = $0 }
                    ),
                    in: form.dateOfBirthRange,
                    displayedComponents: .date
                )
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            EchnoField(title: "Role", isRequired: true, error: form.error(for: .role)) {
                Picker("Role", selection: $form.role) {
                    Text("Select a role").tag(UserRole?.none)
                    ForEach(UserRole.allCases) { Text($0.label).tag(UserRole?.some($0)) }
                }
                .pickerStyle(.menu)
                .tint(form.role == nil ? Echno.mutedForeground : Echno.foreground)
                .frame(maxWidth: .infinity, alignment: .leading)
                .labelsHidden()
            }

            terms
        }
    }

    private var terms: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $form.acceptTerms) {
                Text("I accept the Terms of Service and Privacy Policy")
                    .font(.footnote)
                    .foregroundStyle(Echno.foreground)
            }
            .toggleStyle(.switch)
            .tint(Echno.primary)
            .onChange(of: form.acceptTerms) { form.clearError(.acceptTerms) }

            if let error = form.error(for: .acceptTerms) {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Echno.destructive)
            }
        }
    }

    private var submit: some View {
        VStack(spacing: 14) {
            EchnoPrimaryButton(title: "Create account", isLoading: form.isSubmitting) {
                focused = nil
                if form.validate() { register() }
            }

            HStack(spacing: 4) {
                Text("Already have an account?")
                    .foregroundStyle(Echno.mutedForeground)
                Button("Sign in") { dismiss() }
                    .foregroundStyle(Echno.brand)
                    .fontWeight(.semibold)
            }
            .font(.footnote)
            .frame(maxWidth: .infinity)
        }
    }

    /// Phase 1 replaces this with `POST /api/v1/auth/register` followed by the
    /// hosted sign-in, which is the sequence echno-web uses.
    private func register() {
        form.isSubmitting = true
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            form.isSubmitting = false
        }
    }

    /// A placeholder in the muted foreground colour.
    private static func hint(_ text: String) -> Text {
        Text(text).foregroundStyle(Echno.mutedForeground)
    }

    /// Two fields side by side on iPad, stacked on iPhone.
    @ViewBuilder
    private func pair<A: View, B: View>(
        @ViewBuilder first: () -> A,
        @ViewBuilder second: () -> B
    ) -> some View {
        if isWide {
            HStack(alignment: .top, spacing: 14) { first(); second() }
        } else {
            VStack(spacing: 16) { first(); second() }
        }
    }
}

/// Five segments, one per satisfied password rule, coloured by how far along
/// the password is. Gives the rules a shape before the user hits submit.
private struct PasswordStrengthMeter: View {
    let score: Int

    private var colour: Color {
        switch score {
        case 0...2: Echno.destructive
        case 3...4: Echno.brand
        default: Color(light: 0x16A34A, dark: 0x4ADE80)
        }
    }

    private var label: String {
        switch score {
        case 0...2: "Weak"
        case 3...4: "Getting there"
        default: "Strong"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
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
        .accessibilityLabel("Password strength: \(label)")
    }
}

#Preview {
    RegisterView().preferredColorScheme(.dark)
}
