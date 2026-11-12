import SwiftUI

/// Accès au brouillon texte du composeur, fourni par la vue (#475). La légende d'une pièce choisie
/// EST ce brouillon : une seule valeur, visible dans le champ principal.
struct MessagingCaptionChannel {
    let read: @MainActor () -> String
    let write: @MainActor (String) -> Void
}

/// Libellés VoiceOver et texte de taille de la pièce choisie (#475). Fonctions pures, testées.
enum MessagingComposerAttachmentText {
    static func size(_ byteSize: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(byteSize), countStyle: .file)
    }

    /// « Photo, nom » ou « Document PDF, nom, taille ».
    static func accessibilityLabel(name: String, mime: MessagingMediaAttachment.MIME, byteSize: Int) -> String {
        mime == .pdf ? "Document PDF, \(name), \(size(byteSize))" : "Photo, \(name)"
    }
}

/// Partie « sélection » du panneau média : préparation en cours, pièce choisie, erreur de choix.
struct MessagingComposerSelectionSection: View {
    @Bindable var model: MessagingMediaComposerModel

    var body: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xs) {
            if model.preparing {
                HStack(spacing: DrivySpacing.s) {
                    ProgressView().accessibilityHidden(true)
                    Text("Préparation…").font(.subheadline).foregroundStyle(DrivyTheme.text)
                    Spacer(minLength: 0)
                    Button("Retirer") { model.removeSelection() }
                        .frame(minHeight: DrivyLayout.tapTarget)
                        .accessibilityLabel("Retirer la pièce jointe")
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("messaging.media.preparing")
            } else if let media = model.selection {
                MessagingComposerAttachmentChip(media: media, revision: model.selectionRevision,
                                                removeDisabled: model.sending,
                                                open: { model.showSelection() },
                                                remove: { model.removeSelection() })
            }
            if let message = model.selectionError {
                Text(message).font(.footnote).foregroundStyle(DrivyTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("messaging.media.error")
            }
        }
    }
}

/// Pièce choisie, présentée dans le composeur : vraie miniature (photo) ou carte compacte (PDF), à
/// espace réservé de taille fixe (aucun saut de mise en page à l'arrivée de la miniature), retrait
/// ciblé. Le toucher ouvre l'aperçu de la sélection ; la légende s'écrit dans le champ principal.
struct MessagingComposerAttachmentChip: View {
    let media: MessagingPreparedMedia
    let revision: UUID
    let removeDisabled: Bool
    let open: () -> Void
    let remove: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    nonisolated static let tile: CGFloat = 56

    var body: some View {
        HStack(spacing: DrivySpacing.xs) {
            Button(action: open) {
                HStack(spacing: DrivySpacing.s) {
                    tileView
                    VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                        Text(media.name)
                            .font(.subheadline.weight(.semibold)).foregroundStyle(DrivyTheme.text)
                            .lineLimit(typeSize.isAccessibilitySize ? 4 : 2).truncationMode(.middle)
                            .fixedSize(horizontal: false, vertical: true)
                        if media.mime == .pdf {
                            Text("PDF · \(MessagingComposerAttachmentText.size(media.data.count))")
                                .font(.caption).foregroundStyle(DrivyTheme.muted)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: DrivyLayout.tapTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(MessagingComposerAttachmentText.accessibilityLabel(
                name: media.name, mime: media.mime, byteSize: media.data.count))
            .accessibilityHint("Ouvre l’aperçu")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("messaging.media.selection.open")
            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(DrivyTheme.text)
                    .frame(width: 28, height: 28)
                    .background(DrivyTheme.surfaceMuted, in: Circle())
                    .frame(width: DrivyLayout.tapTarget, height: DrivyLayout.tapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(removeDisabled)
            .accessibilityLabel("Retirer la pièce jointe")
            .accessibilityIdentifier("messaging.media.selection.remove")
        }
        .padding(DrivySpacing.xs)
        .background(DrivyTheme.surfaceCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(DrivyTheme.border, lineWidth: 1))
    }

    @ViewBuilder private var tileView: some View {
        if media.mime == .pdf {
            Image(systemName: "doc.richtext")
                .font(.title2).foregroundStyle(DrivyTheme.accent)
                .frame(width: Self.tile, height: Self.tile)
                .background(DrivyTheme.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)
        } else {
            MessagingComposerThumbnail(data: media.thumbnail ?? media.data, revision: revision)
                .accessibilityHidden(true)
        }
    }
}

/// Miniature carrée décodée hors du MainActor par ImageIO, sous-échantillonnée (jamais l'image entière).
struct MessagingComposerThumbnail: View {
    let data: Data
    let revision: UUID
    @State private var image: CGImage?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        ZStack {
            DrivyTheme.surfaceMuted
            if let image {
                Image(decorative: image, scale: 1).resizable().scaledToFill()
            } else {
                Image(systemName: "photo").font(.title3).foregroundStyle(DrivyTheme.muted)
            }
        }
        .frame(width: MessagingComposerAttachmentChip.tile, height: MessagingComposerAttachmentChip.tile)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .task(id: revision) {
            image = nil
            // Valeurs copiées avant de quitter le MainActor : la tâche détachée ne touche à aucun membre isolé.
            let bytes = data, scale = displayScale, side = MessagingComposerAttachmentChip.tile
            let decoded = await Task.detached(priority: .userInitiated) {
                MessagingImageDecoder.decode(bytes, viewportLongestSide: side, displayScale: scale)
            }.value
            guard !Task.isCancelled else { return }
            image = decoded?.cgImage
        }
    }
}
