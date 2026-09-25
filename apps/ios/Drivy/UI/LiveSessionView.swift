import SwiftUI
import UIKit

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
            else { ProgressView("Fermeture du trajet…").frame(maxWidth: .infinity, maxHeight: .infinity) }
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
        // Confirmed only once the observation is durably stored on the device.
        .sensoryFeedback(.success, trigger: controller.activeSession?.observations.count ?? 0) { old, new in new > old }
    }

    private func liveContent(_ session: DrivingSession) -> some View {
        GeometryReader { geometry in
            if dynamicTypeSize.isAccessibilitySize {
                accessibleSession(session)
            } else if geometry.size.width >= DrivyMapLayout.sidebarBreakpoint {
                HStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: DrivySpacing.m) {
                            sessionHeader(session, floating: false)
                            sessionDock(session, floating: false)
                        }
                        .padding(DrivySpacing.m)
                    }
                    .frame(width: DrivyMapLayout.sidebarWidth)
                    .background(DrivyTheme.canvas)
                    sessionBackground(session)
                        .overlay(alignment: .bottomTrailing) {
                            if !session.points.isEmpty { mapControls.padding(DrivySpacing.l) }
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
                    .padding(.horizontal, DrivySpacing.m).padding(.top, DrivySpacing.xs).padding(.bottom, DrivySpacing.s)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(alignment: .trailing, spacing: DrivySpacing.s) {
                    if !session.points.isEmpty { mapControls }
                    sessionDock(session)
                }
                .padding(.horizontal, DrivySpacing.m).padding(.top, DrivySpacing.xs).padding(.bottom, DrivySpacing.s)
            }
    }

    @ViewBuilder
    private func sessionBackground(_ session: DrivingSession) -> some View {
        if session.usesGPS {
            RouteMapView(session: session, selectedObservationID: $selectedObservationID,
                showsControls: false, showsEmptyState: false, resetCameraID: resetCameraID,
                followsPosition: $followsPosition)
        } else {
            DrivyMapPlaceholder(title: "Sans GPS", message: "Les observations gardent leur heure, sans position.")
        }
    }

    private func accessibleSession(_ session: DrivingSession) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DrivySpacing.l) {
                sessionHeader(session, floating: false)
                if let error = controller.errorMessage { InlineErrorView(message: error, retry: storageRetry) }
                gpsNotice(session)
                if session.usesGPS {
                    RouteMapView(session: session, selectedObservationID: $selectedObservationID,
                        showsControls: false, showsEmptyState: false, resetCameraID: resetCameraID,
                        followsPosition: $followsPosition)
                        .frame(height: DrivyMapLayout.accessibleMapHeight)
                        .clipShape(RoundedRectangle(cornerRadius: DrivyRadius.mapPanel, style: .continuous))
                    if !session.points.isEmpty { mapControls.frame(maxWidth: .infinity, alignment: .trailing) }
                }
                observationsButton(session)
                if controller.isBusy && !controller.isCapturing {
                    ProgressView("Sauvegarde du trajet…")
                }
            }
            .padding(DrivySpacing.m)
            .frame(maxWidth: DrivyMapLayout.accessibleMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            reportButton(session)
                .padding(DrivySpacing.m)
                .frame(maxWidth: DrivyMapLayout.accessibleMaxWidth)
                .frame(maxWidth: .infinity)
                .background(DrivyTheme.surface)
        }
    }

    /// Chrome floating over the map: Liquid Glass, shared with the replay and the school GPS.
    private var mapControls: some View {
        DrivyMapControls(followsPosition: $followsPosition) {
            followsPosition = false
            resetCameraID = UUID()
        }
    }

    private func sessionHeader(_ session: DrivingSession, floating: Bool = true) -> some View {
        DrivyMapHeader(
            title: controller.isCapturing ? "Trajet en cours" : controller.isBusy ? "Sauvegarde du trajet" : "Trajet arrêté",
            status: status(session),
            leading: .close(label: "Revenir à Séance",
                hint: controller.isCapturing ? "Le trajet continue" : "Revenir à l’accueil") { dismiss() },
            floating: floating
        ) {
            if controller.isCapturing {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    DrivyElapsedTime(text: timeline.date.sessionElapsed(since: session.startedAt),
                        accessibilityTitle: "Durée du trajet")
                }
            }
            DrivyMapStopButton(label: "Terminer le trajet", isEnabled: controller.isCapturing) { confirmsStop = true }
                .accessibilityIdentifier("session-stop")
        }
    }

    private func sessionDock(_ session: DrivingSession, floating: Bool = true) -> some View {
        DrivyMapDock(floating: floating) {
            if let error = controller.errorMessage { InlineErrorView(message: error, retry: storageRetry) }
            gpsNotice(session)
            if let selected = session.observations.first(where: { $0.id == selectedObservationID }) {
                HStack(alignment: .top, spacing: DrivySpacing.xs) {
                    ObservationRow(observation: selected, sessionStartedAt: session.startedAt, showsNote: false)
                    Button { selectedObservationID = nil } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.medium))
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Fermer l’observation")
                }
                Divider().overlay(DrivyTheme.border)
            }
            observationsButton(session)
            reportButton(session)
            if controller.isBusy && !controller.isCapturing {
                ProgressView("Sauvegarde du trajet…").font(.footnote).frame(maxWidth: .infinity)
            }
        }
    }

    /// GPS refused or interrupted: the journey continues without position, said once, calmly.
    @ViewBuilder
    private func gpsNotice(_ session: DrivingSession) -> some View {
        if controller.isCapturing && session.usesGPS && [.denied, .interrupted].contains(controller.gpsStatus) {
            VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                DrivyInlineMessage(
                    text: controller.gpsStatus == .denied
                        ? "Localisation non autorisée. Vous pouvez continuer à signaler, sans position."
                        : "GPS interrompu. Vous pouvez continuer à signaler, sans position.",
                    tone: .warning)
                if controller.gpsStatus == .denied, let url = URL(string: UIApplication.openSettingsURLString) {
                    Link("Ouvrir les réglages", destination: url)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DrivyTheme.accent)
                        .frame(minHeight: 44)
                }
            }
        }
    }

    private func observationsButton(_ session: DrivingSession) -> some View {
        Button { listedSession = session } label: {
            HStack(spacing: DrivySpacing.xs) {
                Image(systemName: "list.bullet").foregroundStyle(DrivyTheme.muted).accessibilityHidden(true)
                Text(DrivySeanceText.observations(session.observations.count))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DrivyTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
                Label("Privées", systemImage: "lock")
                    .labelStyle(.iconOnly)
                    .font(.caption)
                    .foregroundStyle(DrivyTheme.muted)
                Spacer(minLength: DrivySpacing.xxs)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DrivyTheme.muted)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(DrivyRowButtonStyle())
        .accessibilityHint("Afficher les observations privées de ce trajet")
        .accessibilityIdentifier("observation-list")
    }

    /// The dominant action while driving: a large target at the bottom of the dock.
    private func reportButton(_ session: DrivingSession) -> some View {
        Button {
            if let context = controller.beginObservation() {
                observationRequest = ObservationRequest(context: context, startedAt: session.startedAt)
            }
        } label: {
            Label("Signaler", systemImage: "plus.bubble.fill")
                .font(.drivySection)
                .padding(.vertical, DrivySpacing.xs)
                .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(DrivyPrimaryButtonStyle())
        .disabled(controller.isBusy || !controller.isCapturing)
        .accessibilityHint("Retient cet instant, puis propose les catégories")
        .accessibilityIdentifier("report-observation")
    }

    private func status(_ session: DrivingSession) -> DrivyMapStatus {
        if !controller.isCapturing {
            return controller.isBusy
                ? DrivyMapStatus(title: "Sauvegarde en cours", symbol: "clock")
                : DrivyMapStatus(title: "Enregistrement arrêté", symbol: "stop.circle", tone: .warning)
        }
        return session.usesGPS
            ? controller.gpsStatus.mapStatus
            : DrivyMapStatus(title: "Sans GPS · privé", symbol: "location.slash")
    }
    private var storageRetry: (() -> Void)? {
        guard !controller.isCapturing else { return nil }
        return { Task { await controller.load() } }
    }
    private func dismissWhenFinished() {
        if controller.activeSession == nil && observationRequest == nil && listedSession == nil { dismiss() }
    }
}
