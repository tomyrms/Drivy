import SwiftUI

/// Pièce jointe locale d'un envoi en cours dans le fil (#476) : carte discrète sous la bulle, état réel de CETTE intention
/// et sa reprise ciblée. Indicateur indéterminé seulement (aucune mesure d'octets n'est raccordée), aucun succès avant
/// l'accusé durable, aucune promesse d'annulation. Aucune miniature : le runtime n'en expose pas pour une intention.
struct MessagingPendingMediaView: View {
    let thread: MessagingThreadModel
    let entry: MessagingMediaPendingEntry
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var iconSide: CGFloat = 40

    private var presentation: MessagingMediaIntentionPresentation { MessagingMediaIntentionPresentation(entry.phase) }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: DrivyRadius.content, style: .continuous) }

    var body: some View {
        let presentation = presentation
        VStack(alignment: .trailing, spacing: DrivySpacing.xxs) {
            HStack(alignment: .top, spacing: DrivySpacing.s) {
                Image(systemName: entry.snapshot.mime == .pdf ? "doc.richtext" : "photo")
                    .font(.title3)
                    .foregroundStyle(DrivyTheme.accent)
                    .frame(width: iconSide, height: iconSide)
                    .background(DrivyTheme.surface, in: RoundedRectangle(cornerRadius: DrivyRadius.field, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                    Text(entry.snapshot.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(DrivyTheme.text)
                        .lineLimit(typeSize.isAccessibilitySize ? 8 : 3)
                        .truncationMode(.middle)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(ByteCountFormatter.string(fromByteCount: Int64(entry.snapshot.byteSize), countStyle: .file))
                        .font(.caption).foregroundStyle(DrivyTheme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(DrivySpacing.s)
            .frame(maxWidth: MessagingMediaBubbleGeometry.maximumWidth, minHeight: DrivyLayout.tapTarget, alignment: .leading)
            .background(DrivyTheme.accentSoft, in: shape)
            .overlay(shape.strokeBorder(DrivyTheme.border, lineWidth: 1))
            // Un seul arrêt VoiceOver pour la pièce (nature, nom, taille) ; l'état suit dans sa propre ligne (#477).
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(MessagingComposerAttachmentText.accessibilityLabel(
                name: entry.snapshot.name, mime: entry.snapshot.mime, byteSize: entry.snapshot.byteSize))
            if presentation.showsProgress || presentation.text != nil {
                HStack(spacing: DrivySpacing.xs) {
                    // Indéterminé : jamais annoncé comme un progrès (aucune mesure d'octets).
                    if presentation.showsProgress { ProgressView().controlSize(.small).accessibilityHidden(true) }
                    if let text = presentation.text {
                        Text(text).font(.footnote).foregroundStyle(color(presentation.tone))
                            .multilineTextAlignment(.trailing)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("messaging.media.pending.state")
            }
            if let title = presentation.retryTitle {
                // Zone de toucher dans le libellé : un cadre posé après le bouton n'agrandit pas sa zone active (run 43287772177 : 16 pt).
                Button {
                    Task { await thread.retryMediaSend(entry.id) }
                } label: {
                    Text(title)
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, DrivySpacing.s)
                        .frame(minHeight: DrivyLayout.tapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(DrivyTheme.accent)
                    // Les envois passent l'un après l'autre : la reprise attend la fin de celui qui est en cours.
                    .disabled(thread.mediaComposer?.sending == true)
                    .accessibilityIdentifier("messaging.media.retry")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("messaging.media.pending")
    }

    private func color(_ tone: MessagingMediaIntentionPresentation.Tone) -> Color {
        switch tone {
        case .neutral: DrivyTheme.muted
        case .warning: DrivyTheme.warning
        case .danger: DrivyTheme.danger
        case .success: DrivyTheme.success
        }
    }
}
