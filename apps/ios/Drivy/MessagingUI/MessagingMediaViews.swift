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
            if model.opening { ProgressView("Ouverture…") }
            if let error = model.error, error != model.selectionError {
                Text(error).font(.footnote).foregroundStyle(DrivyTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("messaging.media.error")
                if model.selection == nil {
                    Button("Actualiser les envois") { Task { await model.load() } }.frame(minHeight: DrivyLayout.tapTarget)
                }
            }
            ForEach(model.pendingItems) { item in
                VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                    MessagingMediaFileLabel(name: item.name, mime: item.mime, byteSize: item.byteSize)
                    if let failure = model.failures[item.id] {
                        Text(MessagingMediaComposerModel.label(failure)).font(.footnote).foregroundStyle(DrivyTheme.warning)
                    } else if !model.sending {
                        Text("Envoi à vérifier").font(.footnote).foregroundStyle(DrivyTheme.warning)
                    }
                    if !model.sending {
                        Button(model.failures[item.id] == .membersChanged ? "Vérifier et renvoyer aux participants" : "Vérifier et renvoyer") {
                            Task { await model.retry(item.id); if model.confirmation != nil { await didConfirm() } }
                        }
                        .frame(minHeight: DrivyLayout.tapTarget)
                        .accessibilityIdentifier("messaging.media.retry")
                    }
                }
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
