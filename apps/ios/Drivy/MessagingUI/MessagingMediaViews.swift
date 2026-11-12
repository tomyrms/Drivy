import SwiftUI

struct MessagingMediaComposerPanel: View {
    @Bindable var model: MessagingMediaComposerModel
    let replyTo: UUID?
    let didConfirm: () async -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xs) {
            if model.preparing {
                ProgressView("Préparation…").accessibilityIdentifier("messaging.media.preparing")
                Button("Retirer") { model.removeSelection() }.frame(minHeight: DrivyLayout.tapTarget)
            }
            if let media = model.selection {
                let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading)) : AnyLayout(HStackLayout())
                layout {
                    Button { model.showSelection() } label: {
                        MessagingMediaFileLabel(name: media.name, mime: media.mime, byteSize: media.data.count)
                    }
                    .frame(minHeight: DrivyLayout.tapTarget)
                    .accessibilityIdentifier("messaging.media.selection.open")
                    Button("Retirer", systemImage: "xmark") { model.removeSelection() }
                        .frame(minHeight: DrivyLayout.tapTarget).disabled(model.sending)
                        .accessibilityIdentifier("messaging.media.selection.remove")
                }
                TextField("Légende facultative", text: $model.caption, axis: .vertical)
                    .lineLimit(1...6).font(.body).foregroundStyle(DrivyTheme.text)
                    .frame(minHeight: DrivyLayout.tapTarget)
                    .disabled(model.sending)
                    .accessibilityIdentifier("messaging.media.caption")
                Button("Envoyer la pièce") {
                    Task { await model.sendSelected(replyTo: replyTo); if model.confirmation != nil { await didConfirm() } }
                }
                .frame(minHeight: DrivyLayout.tapTarget).disabled(!model.canSend)
                .accessibilityIdentifier("messaging.media.send")
            }
            if model.sending { ProgressView("Envoi…") }
            // Les intentions en attente et leurs reprises vivent dans le fil (#476), à l'emplacement de leur pièce.
            if let error = model.error {
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
