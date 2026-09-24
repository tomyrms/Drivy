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
    @State private var resetCameraID = UUID()

    private struct ObservationRequest: Identifiable {
        let id = UUID()
        let context: ObservationContext
        let startedAt: Date
    }
    var body: some View {
        Group {
            if let session = controller.activeSession { liveContent(session) }
            else { ProgressView("Ouverture du bilan…").frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        .background(DrivyTheme.canvas)
        .toolbar(.hidden, for: .navigationBar)
        .confirmationDialog("Terminer ce trajet ?", isPresented: $confirmsStop, titleVisibility: .visible) {
            Button("Terminer la séance", role: .destructive) { controller.stopSession() }
                .accessibilityIdentifier("stop-session-confirm")
            Button("Continuer", role: .cancel) { }
        } message: { Text("Vous retrouverez le trajet, les observations et le bilan sur cet appareil.") }
        .sheet(item: $observationRequest, onDismiss: dismissWhenFinished) { request in
            ObservationComposer(controller: controller, context: request.context, sessionStartedAt: request.startedAt)
        }
        .sheet(item: $listedSession, onDismiss: dismissWhenFinished) { session in ObservationListView(session: session) }
        .onChange(of: controller.activeSession?.id) { _, id in if id == nil { dismissWhenFinished() } }
    }

    @ViewBuilder
    private func liveContent(_ session: DrivingSession) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            accessibleSession(session)
        } else {
            sessionBackground(session)
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack {
                    sessionHeader(session).frame(maxWidth: 620)
                    if sizeClass == .regular { Spacer(minLength: 0) }
                }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 12)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .trailing, spacing: 12) {
                        if !session.points.isEmpty {
                            Button { selectedObservationID = nil; resetCameraID = UUID() } label: {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.title3.weight(.medium)).frame(width: 48, height: 48)
                                    .background(DrivyTheme.surface, in: Circle())
                            }.buttonStyle(.plain).accessibilityLabel("Voir tout le trajet")
                        }
                        sessionDock(session)
                    }.frame(maxWidth: 460)
                    if sizeClass == .regular { Spacer(minLength: 0) }
                }.padding(.horizontal, 16).padding(.bottom, 10).padding(.top, 8)
            }
        }
    }

    @ViewBuilder
    private func sessionBackground(_ session: DrivingSession) -> some View {
        if session.usesGPS {
            RouteMapView(session: session, selectedObservationID: $selectedObservationID,
                showsControls: false, showsEmptyState: false, resetCameraID: resetCameraID,
                framingInsets: EdgeInsets(top: 100, leading: 0, bottom: 190, trailing: 0))
                .ignoresSafeArea()
        } else {
            VStack(spacing: 16) {
                Image(systemName: "text.bubble")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(DrivyTheme.accent)
                    .frame(width: 88, height: 88)
                    .background(DrivyTheme.accentSoft, in: Circle())
                    .accessibilityHidden(true)
                Text("Les moments comptent")
                    .font(.title2.weight(.semibold))
                Text("Une observation suffit pour\nretrouver un passage au bilan.")
                    .font(.body)
                    .foregroundStyle(DrivyTheme.muted)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DrivyTheme.canvas)
        }
    }

    private func accessibleSession(_ session: DrivingSession) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                sessionHeader(session)
                if let error = controller.errorMessage { InlineErrorView(message: error, retry: storageRetry) }
                if session.usesGPS {
                    RouteMapView(session: session, selectedObservationID: $selectedObservationID, showsEmptyState: false)
                        .frame(height: 230)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                }
                observationsButton(session)
                if session.usesGPS && [.denied, .interrupted].contains(controller.gpsStatus) {
                    Text("Le GPS est indisponible. Vos observations restent enregistrées.")
                        .font(.body).foregroundStyle(DrivyTheme.muted)
                }
            }
            .padding(16)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            reportButton(session)
                .padding(16)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
                .background(DrivyTheme.surface)
        }
    }

    private func sessionHeader(_ session: DrivingSession) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.body.weight(.medium)).frame(width: 44, height: 44)
            }.buttonStyle(.plain).accessibilityLabel("Revenir à Séance")
                .accessibilityHint("Le trajet continue")
            let contentLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                : AnyLayout(HStackLayout(spacing: 8))
            contentLayout {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Trajet en cours").font(.subheadline.weight(.semibold))
                    HStack(alignment: .center, spacing: 5) {
                        Circle().fill(controller.isCapturing ? DrivyTheme.accent : DrivyTheme.warning).frame(width: 5, height: 5)
                        Text(status(session)).font(.caption).foregroundStyle(DrivyTheme.muted)
                    }
                }.fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                if controller.isCapturing {
                    TimelineView(.periodic(from: .now, by: 1)) { timeline in
                        Text(timeline.date.sessionElapsed(since: session.startedAt))
                            .font(.title3.weight(.semibold).monospacedDigit())
                            .accessibilityLabel("Durée du trajet")
                            .accessibilityValue(timeline.date.sessionElapsed(since: session.startedAt))
                    }
                }
            }
            Button { confirmsStop = true } label: {
                Image(systemName: "stop.fill").font(.body.weight(.medium))
                    .foregroundStyle(DrivyTheme.danger).frame(width: 44, height: 44)
            }.buttonStyle(.plain).accessibilityLabel("Terminer le trajet")
                .disabled(!controller.isCapturing).accessibilityIdentifier("session-stop")
        }
        .padding(.horizontal, 8).padding(.vertical, 12)
        .foregroundStyle(DrivyTheme.text)
        .background(DrivyTheme.surface, in: RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.08), radius: 18, y: 5)
    }

    private func sessionDock(_ session: DrivingSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let error = controller.errorMessage { InlineErrorView(message: error, retry: storageRetry) }
            if let selected = session.observations.first(where: { $0.id == selectedObservationID }) {
                HStack(alignment: .top) {
                    ObservationRow(observation: selected, sessionStartedAt: session.startedAt, showsNote: false)
                    Button { selectedObservationID = nil } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                        .buttonStyle(.plain).accessibilityLabel("Fermer l’observation")
                }
                Divider()
            }
            observationsButton(session)
            reportButton(session)
            if controller.isBusy && !controller.isCapturing {
                ProgressView("Sauvegarde du trajet…").font(.footnote).frame(maxWidth: .infinity)
            } else if session.usesGPS && [.denied, .interrupted].contains(controller.gpsStatus) {
                Text("Le GPS est indisponible. Vos observations restent enregistrées.")
                    .font(.caption).foregroundStyle(DrivyTheme.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 16)
        .foregroundStyle(DrivyTheme.text)
        .background(DrivyTheme.surface, in: RoundedRectangle(cornerRadius: 26))
        .shadow(color: .black.opacity(0.08), radius: 20, y: 5)
    }

    private func observationsButton(_ session: DrivingSession) -> some View {
        Button { listedSession = session } label: {
            HStack(spacing: 10) {
                Image(systemName: "list.bullet").foregroundStyle(DrivyTheme.muted)
                Text("\(session.observations.count) observation\(session.observations.count == 1 ? "" : "s")")
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Image(systemName: "lock").font(.caption).foregroundStyle(DrivyTheme.muted)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(DrivyTheme.muted)
            }.frame(minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("observation-list")
    }

    private func reportButton(_ session: DrivingSession) -> some View {
        Button {
            if let context = controller.beginObservation() {
                observationRequest = ObservationRequest(context: context, startedAt: session.startedAt)
            }
        } label: {
            Label("Signaler", systemImage: "plus")
                .padding(.vertical, 4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(DrivyPrimaryButtonStyle())
        .disabled(controller.isBusy || !controller.isCapturing)
        .accessibilityIdentifier("report-observation")
    }
    private func status(_ session: DrivingSession) -> String {
        if !controller.isCapturing { return "Capture arrêtée" }
        return session.usesGPS ? controller.gpsStatus.label : "Sans GPS · privé"
    }
    private var storageRetry: (() -> Void)? {
        guard !controller.isCapturing else { return nil }
        return { Task { await controller.load() } }
    }
    private func dismissWhenFinished() {
        if controller.activeSession == nil && observationRequest == nil && listedSession == nil { dismiss() }
    }
}
