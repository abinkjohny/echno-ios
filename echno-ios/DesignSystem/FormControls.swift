import SwiftUI

/// A labelled field with inline validation, matching echno-web's auth inputs:
/// label, required marker, control, and a red message under the control when
/// the field is invalid.
///
/// The error is shown only once `error` is non-nil. Callers set it on blur or
/// on submit rather than on every keystroke — validating while someone is still
/// typing their email tells them it is wrong before they have finished.
struct EchnoField<Control: View>: View {
    let title: String
    var isRequired: Bool = false
    var error: String?
    @ViewBuilder var control: Control

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 2) {
                Text(title)
                if isRequired {
                    Text("*").foregroundStyle(Echno.destructive)
                }
            }
            .font(.subheadline)
            .foregroundStyle(Echno.foreground.opacity(0.85))

            control
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(Echno.background, in: RoundedRectangle(cornerRadius: Echno.Radius.lg))
                .overlay(
                    RoundedRectangle(cornerRadius: Echno.Radius.lg)
                        .stroke(error == nil ? Echno.border : Echno.destructive, lineWidth: 1)
                )

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Echno.destructive)
                    .transition(.opacity)
                    .accessibilityAddTraits(.isStaticText)
            }
        }
        .animation(.easeOut(duration: 0.15), value: error)
    }
}

/// A password field with a reveal toggle, mirroring the eye / eye-off control
/// on the web form.
struct EchnoSecureField: View {
    let placeholder: String
    @Binding var text: String
    @State private var isRevealed = false

    private var prompt: Text {
        Text(placeholder).foregroundStyle(Echno.mutedForeground)
    }

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if isRevealed {
                    TextField("", text: $text, prompt: prompt)
                } else {
                    SecureField("", text: $text, prompt: prompt)
                }
            }
            .textContentType(.password)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

            Button {
                isRevealed.toggle()
            } label: {
                Image(systemName: isRevealed ? "eye.slash" : "eye")
                    .foregroundStyle(Echno.mutedForeground)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isRevealed ? "Hide password" : "Show password")
        }
    }
}

/// The filled primary action — indigo, full width, with an in-place spinner so
/// the button does not resize while work is in flight.
struct EchnoPrimaryButton: View {
    let title: String
    var isLoading = false
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(title)
                    .opacity(isLoading ? 0 : 1)
                if isLoading {
                    ProgressView().tint(.white)
                }
            }
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Echno.primary, in: RoundedRectangle(cornerRadius: Echno.Radius.lg))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isLoading)
        .opacity(isEnabled ? 1 : 0.5)
    }
}

/// The bordered secondary action.
struct EchnoSecondaryButton: View {
    let title: String
    var systemImage: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(.body.weight(.semibold))
            .foregroundStyle(Echno.foreground)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Echno.card, in: RoundedRectangle(cornerRadius: Echno.Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: Echno.Radius.lg)
                    .stroke(Echno.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

/// The card the auth forms sit on — echno-web's `Card variant="form"`.
struct EchnoCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(20)
            .background(Echno.card, in: RoundedRectangle(cornerRadius: Echno.Radius.xl))
            .overlay(
                RoundedRectangle(cornerRadius: Echno.Radius.xl)
                    .stroke(Echno.border, lineWidth: 1)
            )
    }
}
