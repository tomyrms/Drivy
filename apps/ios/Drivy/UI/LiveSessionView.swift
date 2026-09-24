import SwiftUI

struct LiveSessionView: View {
    @Bindable var controller: SessionController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var observationRequest: ObservationRequest?
    @State private var listedSession: DrivingSession?
    @State private var confirmsStop = false
    @State private var selectedObservationID: UUID?

    private struct ObservationRequest: Identifiable {
        let id = UUID()
        let context: ObservationContext
        let startedAt: Date
    }

    var body: some View {
        Group {
            if let session = controller.activeSession {
                liveContent(session)
            } else {
                ContentUnavailableView("Séance terminée", systemImage: "checkmark.circle", description: Text("Retrouvez vos observations et votre bilan dans l’historique."))
            }
        }
        .background(DrivyTheme.canvas)
        .navigationTitle("Séance d’essai")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Fermer", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly)
                    .accessibilityHint("Revenir à l’accueil sans arrêter la séance")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Arrêter", role: .destructive) { confirmsStop = true }
                    .frame(minHeight: 48)
                    .disabled(!controller.isCapturing)
                    .accessibilityIdentifier("session-stop")
            }
        }
        .confirmationDialog("Terminer cette séance ?", isPresented: $confirmsStop, titleVisibility: .visible) {
            Button("Terminer la séance", role: .destructive) { controller.stopSession() }
                .accessibilityIdentifier("stop-session-confirm")
            Button("Continuer la séance", role: .cancel) { }
        } message: {
            Text("La capture s’arrête immédiatement. Vous pourrez ensuite relire les observations et rédiger le bilan local.")
        }
        .sheet(item: $observationRequest, onDismiss: {
            if controller.activeSession == nil { dismiss() }
        }) { request in
            ObservationComposer(controller: controller, context: request.context, sessionStartedAt: request.startedAt)
        }
        .sheet(item: $listedSession, onDismiss: {
            if controller.activeSession == nil { dismiss() }
        }) { session in
            ObservationListView(session: session)
        }
        .onChange(of: controller.activeSession?.id) { _, id in
            if id == nil && observationRequest == nil && listedSession == nil { dismiss() }
        }
    }

    @ViewBuilder
    private func liveContent(_ session: DrivingSession) -> some View {
        if !controller.isCapturing || dynamicTypeSize.isAccessibilitySize {
            ScrollView {
                VStack(spacing: 20) {
                    sessionHeader(session)
                    if session.usesGPS {
                        RouteMapView(session: session, selectedObservationID: $selectedObservationID)
                            .frame(height: 300)
                    }
                    sessionControls(session)
                    observationsPreview(session)
                        .padding(.horizontal, 20)
                }
                .padding(.bottom, 20)
            }
        } else if sizeClass == .regular {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    sessionHeader(session)
                    ScrollView {
                        observationsPreview(session)
                            .padding(20)
                    }
                    sessionControls(session)
                }
                .frame(width: 350)
                if session.usesGPS {
                    RouteMapView(session: session, selectedObservationID: $selectedObservationID)
                } else {
                    withoutGPSBackdrop
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        } else {
            VStack(spacing: 0) {
                sessionHeader(session)
                if session.usesGPS {
                    RouteMapView(session: session, selectedObservationID: $selectedObservationID)
                        .safeAreaInset(edge: .bottom, spacing: 0) { sessionControls(session) }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            withoutGPSBackdrop
                            observationsPreview(session)
                        }
                        .padding(20)
                    }
                    .safeAreaInset(edge: .bottom, spacing: 0) { sessionControls(session) }
                }
            }
        }
    }

    private func sessionHeader(_ session: DrivingSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center) {
                    gpsLabel(session)
                    Spacer(minLength: 16)
                    if controller.isCapturing { elapsedTime(session) }
                }
                VStack(alignment: .leading, spacing: 8) {
                    gpsLabel(session)
                    if controller.isCapturing { elapsedTime(session) }
                }
            }
            if controller.isCapturing && session.usesGPS && [.denied, .interrupted].contains(controller.gpsStatus) {
                Text("Vous pouvez continuer à noter vos observations sans position.")
                    .font(.footnote)
                    .foregroundStyle(DrivyTheme.muted)
            }
        }
        .padding(16)
        .background(DrivyTheme.surface)
    }

    private func gpsLabel(_ session: DrivingSession) -> some View {
        Label(controller.isCapturing ? (session.usesGPS ? controller.gpsStatus.label : "Sans GPS") : "Capture arrêtée", systemImage: session.usesGPS ? "location" : "location.slash")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(DrivyTheme.accent)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func elapsedTime(_ session: DrivingSession) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            Text(timeline.date.sessionElapsed(since: session.startedAt))
                .font(.title2.weight(.semibold).monospacedDigit())
                .foregroundStyle(DrivyTheme.text)
                .accessibilityLabel("Durée de la séance")
                .accessibilityValue(timeline.date.sessionElapsed(since: session.startedAt))
        }
    }

    private var withoutGPSBackdrop: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "text.bubble")
                .font(.largeTitle)
                .foregroundStyle(DrivyTheme.accent)
                .accessibilityHidden(true)
            Text("L’essentiel reste à portée.")
                .font(.title2.weight(.semibold))
            Text("Signalez un moment de la séance. Vous le retrouverez dans votre bilan, même sans trajet.")
                .foregroundStyle(DrivyTheme.muted)
        }
        .padding(24)
        .frame(maxWidth: 520, alignment: .leading)
    }

    private func observationsPreview(_ session: DrivingSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Observations")
                .font(.headline)
            if session.observations.isEmpty {
                Text("Aucune observation pour le moment.")
                    .foregroundStyle(DrivyTheme.muted)
                    .font(.subheadline)
            } else {
                ForEach(session.observations.suffix(3).reversed()) { observation in
                    ObservationRow(observation: observation, sessionStartedAt: session.startedAt)
                    Divider()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sessionControls(_ session: DrivingSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let error = controller.errorMessage {
                InlineErrorView(message: error, retry: controller.isCapturing ? nil : {
                    Task { await controller.load() }
                })
            }
            if let selected = session.observations.first(where: { $0.id == selectedObservationID }) {
                Button { listedSession = session } label: {
                    ObservationRow(observation: selected, sessionStartedAt: session.startedAt, showsNote: false)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Ouvrir la liste pour lire la note complète")
            }
            Button { listedSession = session } label: {
                HStack {
                    Label("Observations (\(session.observations.count))", systemImage: "list.bullet")
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .font(.subheadline.weight(.medium))
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("observation-list")
            Button {
                if let context = controller.beginObservation() {
                    observationRequest = ObservationRequest(context: context, startedAt: session.startedAt)
                }
            } label: {
                Label("Signaler", systemImage: "plus")
            }
            .buttonStyle(DrivyPrimaryButtonStyle())
            .disabled(controller.isBusy || !controller.isCapturing)
            .accessibilityIdentifier("report-observation")
            StorageCaption(message: controller.storageStatus)
        }
        .padding(16)
        .background(DrivyTheme.surface)
    }
}
