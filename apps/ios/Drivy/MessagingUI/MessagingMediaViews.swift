import PDFKit
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
            if model.opening { ProgressView("Ouverture…") }
            if let error = model.error {
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

/// Only validated, memory-backed values enter this surface. No decrypted file URL.
struct MessagingMediaPreview: View {
    let media: MessagingPreparedMedia
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if media.mime == .pdf {
                    MessagingMemoryPDF(data: media.data)
                } else if let image = UIImage(data: media.data) {
                    ScrollView([.horizontal, .vertical]) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .containerRelativeFrame(.horizontal)
                            .accessibilityLabel(media.name)
                    }
                } else {
                    ContentUnavailableView("Aperçu indisponible", systemImage: "doc")
                }
            }
            .background(DrivyTheme.surface)
            .navigationTitle(media.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
        .tint(DrivyTheme.accent)
        .accessibilityIdentifier("messaging.media.preview")
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

/// PDFKit reads bytes in memory and lazily renders pages in the available viewport.
/// The action override and delegate both suppress document-supplied external actions.
private struct MessagingMemoryPDF: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> MessagingReadOnlyPDFView {
        let view = MessagingReadOnlyPDFView()
        view.delegate = context.coordinator
        view.autoScales = true
        view.maxScaleFactor = 4
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = UIColor(DrivyTheme.surface)
        view.document = PDFDocument(data: data)
        return view
    }

    func updateUIView(_ view: MessagingReadOnlyPDFView, context: Context) {}

    static func dismantleUIView(_ view: MessagingReadOnlyPDFView, coordinator: Coordinator) {
        view.document = nil
        view.delegate = nil
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, PDFViewDelegate {
        func pdfViewWillClick(onLink sender: PDFView, with url: URL) {}
        func pdfViewOpenPDF(_ sender: PDFView, forRemoteGoToAction action: PDFActionRemoteGoTo) {}
        func pdfViewPerformPrint(_ sender: PDFView) {}
    }
}

private final class MessagingReadOnlyPDFView: PDFView {
    override func perform(_ action: PDFAction) {
        // No implicit links, remote documents, launches, scripts or form actions.
    }
}
