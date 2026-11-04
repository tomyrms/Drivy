import PDFKit
import SwiftUI

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
