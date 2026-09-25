import SwiftUI

// Shared anatomy of the guided welcome (first launch in a school): visible
// progress, one question per screen, a sentence saying why the step exists,
// labelled fields on a reading page. Built only from DrivyTheme tokens.

/// Progress of a guided flow: « Étape 2 sur 4 · Votre formation » above a
/// segmented bar. The bar is decorative; VoiceOver reads the sentence once.
struct DrivyStepProgress: View {
    let current: Int
    let total: Int
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xs) {
            Text("Étape \(current) sur \(total) · \(title)")
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
        .accessibilityLabel("Étape \(current) sur \(total), \(title)")
    }
}

/// Head of a guided screen: symbol, the question or subject as title, then the
/// one sentence that says why this step exists. The symbol disappears at
/// accessibility text sizes so the title keeps the width.
struct DrivyGuidedStepHeader: View {
    let symbol: String
    let title: String
    let reason: String
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.s) {
            if !typeSize.isAccessibilitySize {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(DrivyTheme.accent)
                    .frame(width: 56, height: 56)
                    .background(DrivyTheme.accentSoft, in: Circle())
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(.drivyTitle)
                .foregroundStyle(DrivyTheme.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(reason)
                .font(.body)
                .foregroundStyle(DrivyTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One explanatory point of a guided screen: a muted symbol and a sentence.
struct DrivyGuidedFact: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DrivySpacing.s) {
            Image(systemName: symbol)
                .font(.body)
                .foregroundStyle(DrivyTheme.muted)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(text)
                .font(.body)
                .foregroundStyle(DrivyTheme.text)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
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
                .background(isEnabled ? DrivyTheme.surface : DrivyTheme.disabledSurface, in: shape)
                .overlay {
                    shape.strokeBorder(error == nil ? DrivyTheme.controlBorder : DrivyTheme.danger,
                                       lineWidth: error == nil && contrast != .increased ? 1 : 1.5)
                }
                .accessibilityLabel(label)
                .accessibilityHint(error ?? note ?? "")
                .accessibilityIdentifier(identifier ?? "")
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(DrivyTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
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
