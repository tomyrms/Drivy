import SwiftUI

struct LiveSessionView: View {
    @Bindable var controller: SessionController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var observationRequest: ObservationRequest?
    @State private var listedSession: DrivingSession?
    @State private var confirmsStop = false
    @State private var selectedObservationID: UUID?
    @State private var resetCameraID = UUID()
    @State private var followsPosition = true

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
            Button("Terminer le trajet", role: .destructive) { controller.stopSession() }
                .accessibilityIdentifier("stop-session-confirm")
            Button("Continuer", role: .cancel) { }
        } message: { Text("Vous retrouverez le trajet, les observations et le bilan sur cet appareil.") }
        .sheet(item: $observationRequest, onDismiss: dismissWhenFinished) { request in
            ObservationComposer(controller: controller, context: request.context, sessionStartedAt: request.startedAt)
        }
        .sheet(item: $listedSession, onDismiss: dismissWhenFinished) { session in ObservationListView(session: session) }
        .onChange(of: controller.activeSession?.id) { _, id in if id == nil { dismissWhenFinished() } }
    }

    private func liveContent(_ session: DrivingSession) -> some View {
        GeometryReader { geometry in
            if dynamicTypeSize.isAccessibilitySize {
                accessibleSession(session)
            } else if geometry.size.width >= 760 {
                HStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            sessionHeader(session)
                            sessionDock(session)
                        }.padding(20)
                    }.frame(width: 360)
                    sessionBackground(session)
                        .safeAreaInset(edge: .bottom, alignment: .trailing, spacing: 0) {
                            if !session.points.isEmpty { mapControls.padding(24) }
                        }
                }
            } else {
                compactSession(session)
            }
        }
    }

    private func compactSession(_ session: DrivingSession) -> some View {
        sessionBackground(session)
            .safeAreaInset(edge: .top, spacing: 0) {
                sessionHeader(session)
                    .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 12)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(alignment: .trailing, spacing: 12) {
                    if !session.points.isEmpty { mapControls }
                    sessionDock(session)
                }.padding(.horizontal, 16).padding(.bottom, 10).padding(.top, 8)
            }
    }

    @ViewBuilder
    private func sessionBackground(_ session: DrivingSession) -> some View {
        if session.usesGPS {
            RouteMapView(session: session, selectedObservationID: $selectedObservationID,
                showsControls: false, showsEmptyState: false, resetCameraID: resetCameraID,
                followsPosition: $followsPosition)
        } else {
            VStack(spacing: DrivySpacing.s) {
                Image(systemName: "location.slash")
                    .font(.title)
                    .foregroundStyle(DrivyTheme.muted)
                    .frame(width: 72, height: 72)
                    .background(DrivyTheme.surfaceMuted, in: Circle())
                    .accessibilityHidden(true)
                Text("Sans GPS")
                    .font(.title2.weight(.semibold))
                Text("Les observations conservent leur heure, sans position.")
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
                    RouteMapView(session: session, selectedObservationID: $selectedObservationID,
                        showsControls: false, showsEmptyState: false, resetCameraID: resetCameraID,
                        followsPosition: $followsPosition)
                        .frame(height: 230)
                        .clipShape(RoundedRectangle(cornerRadius: DrivyRadius.mapPanel, style: .continuous))
                    if !session.points.isEmpty { mapControls.frame(maxWidth: .infinity, alignment: .trailing) }
                }
                observationsButton(session)
                if controller.isBusy && !controller.isCapturing {
                    ProgressView("Sauvegarde du trajet…")
                } else if controller.isCapturing && session.usesGPS && [.denied, .interrupted].contains(controller.gpsStatus) {
                    Text("GPS indisponible. Vous pouvez continuer à signaler sans position.")
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

    /// Chrome floating over the map: Liquid Glass, grouped so the two buttons blend.
    private var mapControls: some View {
        GlassEffectContainer(spacing: DrivySpacing.xs) {
            HStack(spacing: DrivySpacing.xs) {
                Button { followsPosition.toggle() } label: {
                    Image(systemName: followsPosition ? "location.fill" : "location")
                        .font(.title3).foregroundStyle(followsPosition ? DrivyTheme.accent : DrivyTheme.text)
                        .frame(width: 48, height: 48)
                        .drivyMapControl(in: Circle())
                }
                .accessibilityLabel(followsPosition ? "Arrêter le suivi de position" : "Suivre la dernière position enregistrée")
                .accessibilityAddTraits(followsPosition ? [.isSelected] : [])
                Button { followsPosition = false; resetCameraID = UUID() } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.title3).foregroundStyle(DrivyTheme.text)
                        .frame(width: 48, height: 48)
                        .drivyMapControl(in: Circle())
                }.accessibilityLabel("Voir tout le trajet")
            }
        }
        .buttonStyle(.plain)
    }

    private func sessionHeader(_ session: DrivingSession) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.body.weight(.medium)).frame(width: 44, height: 44)
            }.buttonStyle(.plain).accessibilityLabel("Revenir à Séance")
                .accessibilityHint(controller.isCapturing ? "Le trajet continue" : "Revenir à l’accueil")
            let contentLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                : AnyLayout(HStackLayout(spacing: 8))
            contentLayout {
                VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                    Text(controller.isCapturing ? "Trajet en cours" : controller.isBusy ? "Sauvegarde du trajet" : "Trajet arrêté")
                        .font(.headline)
                    DrivyStatusDot(title: status(session), tone: controller.isCapturing ? .accent : .warning)
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
                Image(systemName: "stop.fill").font(.body.weight(.semibold))
                    .foregroundStyle(controller.isCapturing ? DrivyTheme.danger : DrivyTheme.disabledText)
                    .frame(width: 44, height: 44)
                    .background(controller.isCapturing ? DrivyTheme.dangerSurface : DrivyTheme.disabledSurface, in: Circle())
            }.buttonStyle(.plain).accessibilityLabel("Terminer le trajet")
                .disabled(!controller.isCapturing).accessibilityIdentifier("session-stop")
        }
        .padding(.horizontal, DrivySpacing.xs).padding(.vertical, DrivySpacing.s)
        .foregroundStyle(DrivyTheme.text)
        .background(DrivyTheme.surface, in: RoundedRectangle(cornerRadius: DrivyRadius.mapPanel, style: .continuous))
        .shadow(color: .black.opacity(0.10), radius: 16, y: 4)
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
            } else if controller.isCapturing && session.usesGPS && [.denied, .interrupted].contains(controller.gpsStatus) {
                Text("GPS indisponible. Vous pouvez continuer à signaler sans position.")
                    .font(.caption).foregroundStyle(DrivyTheme.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, DrivySpacing.m).padding(.top, DrivySpacing.xs).padding(.bottom, DrivySpacing.m)
        .foregroundStyle(DrivyTheme.text)
        .background(DrivyTheme.surface, in: RoundedRectangle(cornerRadius: DrivyRadius.mapPanel, style: .continuous))
        .shadow(color: .black.opacity(0.10), radius: 16, y: 4)
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
            Label("Signaler", systemImage: "plus.bubble.fill")
                .font(.title3.weight(.semibold))
                .padding(.vertical, DrivySpacing.xs)
                .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(DrivyPrimaryButtonStyle())
        .disabled(controller.isBusy || !controller.isCapturing)
        .accessibilityIdentifier("report-observation")
    }
    private func status(_ session: DrivingSession) -> String {
        if !controller.isCapturing { return "Enregistrement arrêté" }
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
