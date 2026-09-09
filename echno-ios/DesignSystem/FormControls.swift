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
        VStack(alignment: .leading, spacing: Echno.Space.sm) {
            HStack(spacing: Echno.Space.hairline) {
                Text(title)
                if isRequired {
                    Text("*").foregroundStyle(Echno.destructive)
                }
            }
            .font(.subheadline)
            .foregroundStyle(Echno.foreground.opacity(Echno.Opacity.primary))

            control
                .padding(.horizontal, Echno.Space.md)
                .frame(minHeight: Echno.Size.field)
                .background(Echno.background, in: RoundedRectangle(cornerRadius: Echno.Radius.lg))
                .overlay(
                    RoundedRectangle(cornerRadius: Echno.Radius.lg)
                        .stroke(error == nil ? Echno.border : Echno.destructive, lineWidth: Echno.Size.hairline)
                )

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Echno.destructive)
                    .transition(.opacity)
                    .accessibilityAddTraits(.isStaticText)
            }
        }
        .animation(.easeOut(duration: Echno.Motion.quick), value: error)
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
        HStack(spacing: Echno.Space.sm) {
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
            .frame(maxWidth: .infinity, minHeight: Echno.Size.control)
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
            HStack(spacing: Echno.Space.sm) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(.body.weight(.semibold))
            .foregroundStyle(Echno.foreground)
            .frame(maxWidth: .infinity, minHeight: Echno.Size.control)
            .background(Echno.card, in: RoundedRectangle(cornerRadius: Echno.Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: Echno.Radius.lg)
                    .stroke(Echno.border, lineWidth: Echno.Size.hairline)
            )
        }
        .buttonStyle(.plain)
    }
}

/// A date field that shows nothing until a date is actually chosen.
///
/// A bare `DatePicker` has no empty state: bound through a fallback it renders
/// today-minus-eighteen-years and reads as already answered, so a required field
/// the user never touched looks complete. This shows a prompt until they pick,
/// which is also what makes the validation message make sense when they do not.
struct EchnoDateField: View {
    let title: String
    let prompt: String
    @Binding var selection: Date?
    let range: ClosedRange<Date>
    var error: String?

    @State private var isPresented = false

    private var formatted: String? {
        selection.map { $0.formatted(.dateTime.day().month(.abbreviated).year()) }
    }

    var body: some View {
        EchnoField(title: title, isRequired: true, error: error) {
            Button {
                isPresented = true
            } label: {
                HStack {
                    Text(formatted ?? prompt)
                        .foregroundStyle(selection == nil ? Echno.mutedForeground : Echno.foreground)
                    Spacer()
                    Image(systemName: "calendar")
                        .foregroundStyle(Echno.mutedForeground)
                }
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(formatted ?? "Not set")
        .sheet(isPresented: $isPresented) {
            DateChoiceSheet(
                title: title,
                selection: $selection,
                range: range,
                isPresented: $isPresented
            )
        }
    }
}

private struct DateChoiceSheet: View {
    let title: String
    @Binding var selection: Date?
    let range: ClosedRange<Date>
    @Binding var isPresented: Bool

    /// Opens on the newest allowed date — the youngest eligible person — because
    /// scrolling back from there is shorter than scrolling forward from 1906.
    @State private var draft: Date

    init(title: String, selection: Binding<Date?>, range: ClosedRange<Date>, isPresented: Binding<Bool>) {
        self.title = title
        self._selection = selection
        self.range = range
        self._isPresented = isPresented
        self._draft = State(initialValue: selection.wrappedValue ?? range.upperBound)
    }

    var body: some View {
        NavigationStack {
            DatePicker(title, selection: $draft, in: range, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding()
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { isPresented = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            selection = draft
                            isPresented = false
                        }
                        .fontWeight(.semibold)
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }
}

/// A titled group of fields.
///
/// echno-web lays registration out as one two-column grid. Ten fields in a
/// single run reads as a wall on a phone, so they are grouped instead: the
/// headers give the form a shape and a sense of how much is left.
struct EchnoSection<Content: View>: View {
    let title: String
    var caption: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Echno.Space.md) {
            VStack(alignment: .leading, spacing: Echno.Space.hairline) {
                Text(title)
                    .font(.echnoSectionTitle)
                    .foregroundStyle(Echno.foreground)
                if let caption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(Echno.mutedForeground)
                }
            }
            .accessibilityAddTraits(.isHeader)
            .padding(.horizontal, Echno.Space.xs)

            EchnoCard { content }
        }
    }
}

/// The card the auth forms sit on — echno-web's `Card variant="form"`.
struct EchnoCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(Echno.Space.xl)
            .background(Echno.card, in: RoundedRectangle(cornerRadius: Echno.Radius.xl))
            .overlay(
                RoundedRectangle(cornerRadius: Echno.Radius.xl)
                    .stroke(Echno.border, lineWidth: Echno.Size.hairline)
            )
    }
}
