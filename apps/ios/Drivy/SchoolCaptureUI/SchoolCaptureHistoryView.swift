import SwiftUI

/// « À envoyer » : trips stopped on this device whose data or final confirmation has not
/// reached the school. A List section; the list itself belongs to the Trajets tab.
/// Sending never restarts the GPS.
struct SchoolCaptureUploadsSection: View {
    @Bindable var model: SchoolCaptureHistoryWorkspace
    let learnerName: (UUID) -> String
    var onChange: () -> Void = {}

    var body: some View {
        Section {
            ForEach(model.pendingUploads) { capture in
                SchoolCaptureUploadRow(model: model, capture: capture,
                    learnerName: learnerName(capture.serverCapture.learnerId), onChange: onChange)
            }
            if let error = model.errorMessage {
                SchoolErrorNotice(message: error,
                    retry: model.accessRevoked || model.isBusy ? nil : { Task { await model.load() } })
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
        } header: {
            Text("À envoyer")
        }
    }
}

private struct SchoolCaptureUploadRow: View {
    @Bindable var model: SchoolCaptureHistoryWorkspace
    let capture: SchoolCaptureStoredSession
    let learnerName: String
    let onChange: () -> Void
    @State private var confirmsPartial = false

    var body: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.s) {
            HStack(alignment: .center, spacing: DrivySpacing.s) {
                VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                    Text(learnerName)
                        .font(.headline).foregroundStyle(DrivyTheme.text)
                    if let date = SchoolLesson.date(capture.serverCapture.authorizedAt) {
                        Text(date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
                            .font(.subheadline).foregroundStyle(DrivyTheme.muted)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                Button {
                    Task { await model.upload(capture); onChange() }
                } label: {
                    DrivyBusyLabel(title: "Envoyer", busyTitle: "Envoi…", isBusy: model.busyCaptureID == capture.id)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, DrivySpacing.s)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .disabled(model.isBusy)
                .accessibilityLabel("Envoyer le trajet de \(learnerName)")
                .accessibilityIdentifier("school-upload-\(capture.id.uuidString)")
            }
            if model.incomplete.contains(capture.id) && model.pendingFinalization[capture.id] == nil {
                Button("Garder en partiel…") { confirmsPartial = true }
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
                    .buttonStyle(.borderless)
                    .disabled(model.isBusy)
                    .confirmationDialog("Garder un trajet partiel ?", isPresented: $confirmsPartial, titleVisibility: .visible) {
                        Button("Garder en partiel") { Task { await model.finalize(capture, allowPartial: true); onChange() } }
                        Button("Annuler", role: .cancel) { }
                    } message: {
                        Text("Seules les positions reçues par l’école seront gardées.")
                    }
            }
        }
        .padding(.vertical, DrivySpacing.xxs)
    }
}
