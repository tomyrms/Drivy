import SwiftUI

struct MessagingMediaComposerPanel: View {
    @Bindable var model: MessagingMediaComposerModel
    let replyTo: UUID?
    let didConfirm: () async -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xs) {
            // Sélection (#475) : pièce, retrait, erreur de choix. Légende et envoi vivent dans la ligne du
            // composeur (MessagingThreadComposer) ; voir MessagingComposerAttachmentChip.
            MessagingComposerSelectionSection(model: model)
            if model.sending { ProgressView("Envoi…") }
            // Les intentions en attente et leurs reprises vivent dans le fil (#476), à l'emplacement de leur pièce.
            if let error = model.error, error != model.selectionError {
                Text(error).font(.footnote).foregroundStyle(DrivyTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("messaging.media.error")
            }
            if model.confirmation != nil {
                Label("Envoyé", systemImage: "checkmark").font(.footnote).foregroundStyle(DrivyTheme.success)
                if model.cleanupPending {
                    Text("Envoyé. Suivi local à actualiser.").font(.footnote).foregroundStyle(DrivyTheme.warning)
                }
            }
        }
        .padding(.horizontal, DrivySpacing.s)
        .tint(DrivyTheme.accent)
    }
}

struct MessagingMediaFileLabel: View {
    let name: String
    let mime: MessagingMediaAttachment.MIME
    let byteSize: Int

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                Text(name).font(.body).foregroundStyle(DrivyTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(ByteCountFormatter.string(fromByteCount: Int64(byteSize), countStyle: .file))
                    .font(.caption).foregroundStyle(DrivyTheme.muted)
            }
        } icon: {
            Image(systemName: mime == .pdf ? "doc.richtext" : "photo")
                .foregroundStyle(DrivyTheme.accent)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }
}

// L'aperçu plein écran (photo zoomable, lecteur PDF) vit dans MessagingMediaViewer.swift.
