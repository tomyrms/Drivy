import SwiftUI

/// Terminer la leçon : horaires réels proposés (trajet de la leçon, sinon horaire prévu), arrêt du trajet encore
/// ouvert, permis vu en un geste ou situation écrite. Rien n’est affiché comme terminé avant la preuve de l’école.
struct SchoolLessonCompletionSheet: View {
    @Bindable var model: SchoolLessonReportWorkspace
    @Environment(SchoolCaptureSessionController.self) private var capture: SchoolCaptureSessionController?
    @Environment(\.dismiss) private var dismiss
    @State private var start: Date
    @State private var end: Date
    @State private var timesEdited = false
    @State private var reason = ""
    @State private var recordingPermit = false

    init(model: SchoolLessonReportWorkspace) {
        self.model = model
        let times = model.completionTimes()
        _start = State(initialValue: times.start); _end = State(initialValue: times.end)
    }

    private var captureStatus: SchoolLessonCaptureStatus { SchoolLessonCaptureStatus(controller: capture, lessonID: model.lessonID) }
    /// Sans contrôleur de séance, aucun trajet de cet appareil ne peut être ouvert pour cette leçon.
    private var captureStopped: Bool { captureStatus.permitsCompletion }
    private var trimmedReason: String { reason.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var zone: TimeZone { model.lesson.flatMap { TimeZone(identifier: $0.timeZone) } ?? .current }
    private var valid: Bool {
        model.canMutate && captureStopped && end > start && end <= Date().addingTimeInterval(300)
            && (!model.completionNeedsReason || !trimmedReason.isEmpty) && reason.unicodeScalars.count <= 1_000
    }
    private var hint: String? {
        if !captureStopped { return "Arrêtez d’abord le trajet." }
        if end <= start { return "La fin doit suivre le début." }
        if end > Date().addingTimeInterval(300) { return "La fin ne peut pas être à venir." }
        if model.completionNeedsReason && trimmedReason.isEmpty {
            return model.mayRecordPermit ? "Confirmez le permis ou précisez sa situation." : "Précisez la situation du permis."
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                if captureStatus == .collecting { captureSection }
                Section {
                    DatePicker("Début", selection: edited($start))
                    DatePicker("Fin", selection: edited($end))
                }
                .environment(\.timeZone, zone)
                permitSection
            }
            .scrollContentBackground(.hidden).background(DrivyTheme.canvas)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                DrivyStickyActionBar {
                    if let message = model.errorMessage { DrivyActionNote(text: message, isError: true) }
                    else if let hint { DrivyActionNote(text: hint) }
                    Button {
                        Task { if await model.complete(start: start, end: end, reason: reason, localCaptureStopped: captureStopped) { dismiss() } }
                    } label: {
                        HStack(spacing: DrivySpacing.xs) {
                            if model.isBusy && !recordingPermit { ProgressView() }
                            Label("Terminer la leçon", systemImage: "checkmark.circle")
                        }
                    }
                    .buttonStyle(DrivyPrimaryButtonStyle())
                    .disabled(!valid)
                    .accessibilityIdentifier("lesson-complete-confirm")
                }
            }
            .navigationTitle("Terminer").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() }.disabled(model.isBusy) } }
            .interactiveDismissDisabled(model.isBusy)
            .task { await model.refreshCaptures(); prefill() }
            .onChange(of: captureStatus) { _, status in if status == .stopped { prefill() } }
        }
        .tint(DrivyTheme.accent)
    }

    /// Le trajet de cette leçon tourne encore : l’arrêter ici, en un geste. Les positions déjà écrites restent conservées.
    @ViewBuilder private var captureSection: some View {
        Section {
            if capture?.state == .stopping {
                HStack(spacing: DrivySpacing.s) {
                    ProgressView()
                    Text("Sauvegarde du trajet…")
                }
            } else {
                Button(role: .destructive) { Task { await capture?.stop() } } label: {
                    Label("Arrêter le trajet", systemImage: "stop.circle.fill")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .disabled(capture?.canStop != true)
                .accessibilityIdentifier("lesson-stop-capture")
            }
        }
    }

    @ViewBuilder private var permitSection: some View {
        if model.completionNeedsReason {
            Section {
                if model.mayRecordPermit {
                    Button {
                        recordingPermit = true
                        Task { _ = await model.recordPermitSeen(); recordingPermit = false }
                    } label: {
                        HStack(spacing: DrivySpacing.s) {
                            Label("J’ai vu le permis d’élève", systemImage: "checkmark.seal")
                                .font(.body.weight(.semibold))
                            Spacer(minLength: 0)
                            if recordingPermit { ProgressView() }
                        }
                        .frame(minHeight: 44)
                    }
                    .disabled(!model.canMutate)
                    .accessibilityIdentifier("lesson-permit-seen")
                }
                TextField("Permis non présenté : précisez", text: $reason, axis: .vertical).lineLimit(2...6)
            } header: { Text("Permis") }
        } else if model.permitRecorded {
            Section {
                Label("Permis d’élève vu", systemImage: "checkmark.seal.fill").foregroundStyle(DrivyTheme.success)
            }
        }
    }

    /// Les horaires suivent le trajet tant que la personne ne les a pas modifiés.
    private func prefill() {
        guard !timesEdited else { return }
        let times = model.completionTimes()
        start = times.start; end = times.end
    }
    private func edited(_ value: Binding<Date>) -> Binding<Date> {
        Binding(get: { value.wrappedValue }, set: { value.wrappedValue = $0; timesEdited = true })
    }
}
