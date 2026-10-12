import SwiftUI

// Shared anatomy of the guided welcome (first launch in a school): visible
// progress, one question per screen, a sentence saying why the step exists,
// labelled fields on a reading page. Built only from DrivyTheme tokens.

/// Progress of a guided flow: « Étape 2 sur 4 » above a segmented bar. The step
/// title is the heading right below, so it is not repeated here. The bar is
/// decorative; VoiceOver reads the sentence once.
struct DrivyStepProgress: View {
    let current: Int
    let total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xs) {
            Text("Étape \(current) sur \(total)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(DrivyTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: DrivySpacing.xxs) {
                ForEach(1...max(total, 1), id: \.self) { index in
                    Capsule()
                        .fill(index <= current ? DrivyTheme.accent : DrivyTheme.surfaceMuted)
                        .frame(height: 4)
                }
            }
            .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Étape \(current) sur \(total)")
    }
}

/// Labelled text field on a reading page (outside a Form): permanent label,
/// bordered field of at least 48 pt, then an optional note (why it is asked,
/// or what to fix). The placeholder is never the label.
struct DrivyGuidedTextField: View {
    let label: String
    @Binding var text: String
    var note: String? = nil
    var error: String? = nil
    var identifier: String? = nil
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DrivyRadius.field, style: .continuous)
        VStack(alignment: .leading, spacing: DrivySpacing.xs) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DrivyTheme.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)
            TextField(label, text: $text)
                .font(.body)
                .foregroundStyle(isEnabled ? DrivyTheme.text : DrivyTheme.disabledText)
                .padding(.horizontal, DrivySpacing.s)
                .frame(minHeight: 48)
                .background(isEnabled ? DrivyTheme.surfaceRaised : DrivyTheme.disabledSurface, in: shape)
                .overlay {
                    shape.strokeBorder(error == nil ? DrivyTheme.controlBorder : DrivyTheme.danger,
                                       lineWidth: error == nil && contrast != .increased ? 1 : 1.5)
                }
                .accessibilityLabel(label)
                .accessibilityHint(error == nil ? note ?? "" : "")
                .accessibilityIdentifier(identifier ?? "")
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(DrivyTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(error)
            } else if let note, !note.isEmpty {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(DrivyTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
