import SwiftUI
import UIKit

/// Journey being recorded (E23): full-screen map readable from the driving seat, one
/// dominant gesture (Signaler), protected stop, honest GPS state. After the stop the
/// same screen becomes the end-of-journey summary with the way to the replay and the bilan.
struct LiveSessionView: View {
    @Bindable var controller: SessionController
    /// Opens the replay of a finished journey; the caller decides where (history sheet, tab).
    var openReplay: ((UUID) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @State private var observationRequest: ObservationRequest?
    @State private var showsList = false
    @State private var confirmsStop = false
    @State private var selectedObservationID: UUID?
    @State private var resetCameraID = UUID()
    @State private var followsPosition = true
    @State private var trackedSessionID: UUID?
    @State private var recentReport: RecentReport?
    @State private var undoing = false

    private struct ObservationRequest: Identifiable {
        let id = UUID()
        let context: ObservationContext
        let startedAt: Date
    }

    /// Confirmation shown after the durable write of a report, with its undo window.
    private struct RecentReport: Equatable {
        let observation: LessonObservation
        let sessionID: UUID
        var removed = false
        let token = UUID()
    }

    private var finishedSession: DrivingSession? {
        guard let id = trackedSessionID else { return nil }
        if let selected = controller.selectedSession, selected.id == id, selected.state != .active { return selected }
        return controller.sessions.first { $0.id == id && $0.state != .active }
    }

    private var bannerTransition: AnyTransition {
        reduceMotion ? AnyTransition.opacity : AnyTransition.move(edge: .bottom).combined(with: .opacity)
    }

    var body: some View {
        Group {
            if let session = controller.activeSession {
                liveContent(session)
            } else if let finished = finishedSession {
                JourneyFinishView(controller: controller, session: finished,
                    openReplay: replayAction(for: finished.id), close: { dismiss() })
            } else {
                ProgressView("Sauvegarde du trajet…").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(DrivyTheme.canvas)
        .toolbar(.hidden, for: .navigationBar)
        .confirmationDialog("Terminer ce trajet ?", isPresented: $confirmsStop, titleVisibility: .visible) {
            Button("Terminer le trajet", role: .destructive) {
                recentReport = nil
                controller.stopSession()
            }
            .accessibilityIdentifier("stop-session-confirm")
            Button("Continuer le trajet", role: .cancel) { }
        } message: {
            Text("Le GPS s’arrête et le trajet reste sur cet appareil. Vous verrez ensuite le résumé, le replay et le bilan.")
        }
        .sheet(item: $observationRequest) { request in
            ObservationComposer(controller: controller, context: request.context, sessionStartedAt: request.startedAt,
                onSaved: { observation in reportSaved(observation, sessionID: request.context.sessionID) })
        }
        .sheet(isPresented: $showsList) {
            if let session = controller.activeSession ?? finishedSession {
                ObservationListView(session: session)
            }
        }
        .onAppear { if let id = controller.activeSession?.id { trackedSessionID = id } }
        .onChange(of: controller.activeSession?.id) { _, id in if let id { trackedSessionID = id } }
        .onChange(of: controller.isCapturing) { _, capturing in if !capturing { recentReport = nil } }
        .task(id: recentReport?.token) { await expireRecentReport() }
        // Confirmed only once the observation is durably stored on the device.
        .sensoryFeedback(.success, trigger: controller.activeSession?.observations.count ?? 0) { old, new in new > old }
    }

    // MARK: Layouts

    private func liveContent(_ session: DrivingSession) -> some View {
        GeometryReader { geometry in
            if dynamicTypeSize.isAccessibilitySize {
                accessibleSession(session)
            } else if session.usesGPS && geometry.size.width >= DrivyMapLayout.sidebarBreakpoint {
                wideSession(session)
            } else {
                compactSession(session)
            }
        }
    }

    private func compactSession(_ session: DrivingSession) -> some View {
        sessionBackground(session)
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: DrivySpacing.xs) {
                    topBar(session)
                    gpsBanner(session)
                }
                .frame(maxWidth: 640)
                .padding(.horizontal, DrivySpacing.m).padding(.top, DrivySpacing.xs).padding(.bottom, DrivySpacing.xs)
                .frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: DrivySpacing.s) {
                    undoBanner.transition(bannerTransition)
                    selectedCard(session)
                    if let error = controller.errorMessage { InlineErrorView(message: error, retry: storageRetry) }
                    if controller.isBusy && !controller.isCapturing {
                        DrivyLoadingState(title: "Sauvegarde du trajet…")
                            .padding(.horizontal, DrivySpacing.m)
                            .drivyMapPanel()
                    }
                    bottomBar(session)
                }
                .frame(maxWidth: 640)
                .padding(.horizontal, DrivySpacing.m).padding(.top, DrivySpacing.xs).padding(.bottom, DrivySpacing.s)
                .frame(maxWidth: .infinity)
                .animation(DrivyMotion.feedback(reduceMotion), value: recentReport)
            }
    }

    /// iPad and wide Split View: controls in a sidebar, the map keeps its useful width.
    private func wideSession(_ session: DrivingSession) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: DrivySpacing.m) {
                topBar(session, floating: false)
                gpsBanner(session)
                ScrollView { recentObservations(session).padding(.horizontal, DrivySpacing.xs) }
                    .scrollBounceBehavior(.basedOnSize)
                Spacer(minLength: 0)
                undoBanner.transition(bannerTransition)
                if let error = controller.errorMessage { InlineErrorView(message: error, retry: storageRetry) }
                bottomBar(session, floating: false)
            }
            .padding(DrivySpacing.m)
            .frame(width: DrivyMapLayout.sidebarWidth)
            .background(DrivyTheme.canvas)
            .animation(DrivyMotion.feedback(reduceMotion), value: recentReport)
            sessionBackground(session)
                .overlay(alignment: .bottomTrailing) {
                    if !session.points.isEmpty {
                        DrivyMapControls(followsPosition: $followsPosition) {
                            followsPosition = false
                            resetCameraID = UUID()
                        }
                        .padding(DrivySpacing.l)
                    }
                }
        }
    }

    private func accessibleSession(_ session: DrivingSession) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DrivySpacing.l) {
                topBar(session, floating: false)
                gpsBanner(session)
                if let error = controller.errorMessage { InlineErrorView(message: error, retry: storageRetry) }
                if session.usesGPS {
                    if session.points.isEmpty {
                        DrivyMapStatusLabel(status: status(session), font: .headline)
                    } else {
                        RouteMapView(session: session, selectedObservationID: $selectedObservationID,
                            showsControls: false, showsEmptyState: false, resetCameraID: resetCameraID,
                            followsPosition: $followsPosition)
                            .frame(height: DrivyMapLayout.accessibleMapHeight)
                            .clipShape(RoundedRectangle(cornerRadius: DrivyRadius.mapPanel, style: .continuous))
                    }
                }
                recentObservations(session)
                if controller.isBusy && !controller.isCapturing { DrivyLoadingState(title: "Sauvegarde du trajet…") }
            }
            .padding(DrivySpacing.m)
            .frame(maxWidth: DrivyMapLayout.accessibleMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: DrivySpacing.s) {
                undoBanner
                reportButton(session)
                Button(DrivySeanceText.privateObservations(session.observations.count)) { showsList = true }
                    .buttonStyle(DrivySecondaryButtonStyle())
                    .accessibilityIdentifier("observation-list")
            }
            .padding(DrivySpacing.m)
            .frame(maxWidth: DrivyMapLayout.accessibleMaxWidth)
            .frame(maxWidth: .infinity)
            .background(DrivyTheme.surface)
        }
    }

    // MARK: Pieces

    @ViewBuilder
    private func sessionBackground(_ session: DrivingSession) -> some View {
        if !session.usesGPS {
            NoGPSJourneyFeed(session: session)
        } else if session.points.isEmpty {
            DrivyMapPlaceholder(title: waitingTitle, message: waitingMessage, symbol: "location")
        } else {
            RouteMapView(session: session, selectedObservationID: $selectedObservationID,
                showsControls: false, showsEmptyState: false, resetCameraID: resetCameraID,
                followsPosition: $followsPosition)
        }
    }

    /// No map before the first saved point: an honest wait, never a country overview.
    private var waitingTitle: String {
        guard controller.isCapturing else { return "Aucun point enregistré" }
        switch controller.gpsStatus {
        case .requestingPermission: return "Autorisation GPS demandée"
        case .denied: return "GPS non autorisé"
        case .interrupted: return "GPS interrompu"
        default: return "En attente de position"
        }
    }

    private var waitingMessage: String {
        guard controller.isCapturing else { return "Les observations enregistrées gardent leur heure." }
        switch controller.gpsStatus {
        case .requestingPermission: return "Répondez à la demande de localisation. Vous pouvez déjà signaler."
        case .denied, .interrupted: return "Le trajet continue sans position. Chaque observation garde son heure."
        default: return "Le tracé apparaît dès la première position enregistrée. Vous pouvez déjà signaler."
        }
    }

    private func topBar(_ session: DrivingSession, floating: Bool = true) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            DrivyLiveTopBar(
                elapsed: controller.isCapturing ? timeline.date.sessionElapsed(since: session.startedAt) : nil,
                status: status(session),
                leading: .close(label: "Revenir à Séance",
                    hint: controller.isCapturing ? "Le trajet continue" : "Revenir à l’accueil") { dismiss() },
                floating: floating
            ) {
                DrivyMapStopButton(label: "Terminer le trajet", isEnabled: controller.isCapturing) { confirmsStop = true }
                    .accessibilityIdentifier("session-stop")
            }
        }
    }

    /// GPS refused or interrupted: the journey continues without position, said once, calmly.
    @ViewBuilder
    private func gpsBanner(_ session: DrivingSession) -> some View {
        if controller.isCapturing && session.usesGPS && [GPSStatus.denied, .interrupted].contains(controller.gpsStatus) {
            VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                Label(controller.gpsStatus == .denied
                      ? "Localisation refusée : ce trajet continue sans position."
                      : "GPS interrompu : ce trajet continue sans position.",
                      systemImage: controller.gpsStatus == .denied ? "location.slash" : "exclamationmark.triangle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DrivyTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
                if controller.gpsStatus == .denied, let url = URL(string: UIApplication.openSettingsURLString) {
                    Link("Autoriser pour un prochain trajet", destination: url)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DrivyTheme.accent)
                        .frame(minHeight: 44)
                }
            }
            .padding(.horizontal, DrivySpacing.m).padding(.vertical, DrivySpacing.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DrivyTheme.warningSurface, in: RoundedRectangle(cornerRadius: DrivyRadius.content, style: .continuous))
            .accessibilityElement(children: .contain)
        }
    }

    /// Signaler in the middle, private observations on the left, recentrer on the right.
    private func bottomBar(_ session: DrivingSession, floating: Bool = true) -> some View {
        HStack(spacing: DrivySpacing.s) {
            DrivyBarButton(symbol: "lock.fill", text: "\(session.observations.count)") { showsList = true }
                .accessibilityLabel(DrivySeanceText.privateObservations(session.observations.count))
                .accessibilityHint("Afficher les observations de ce trajet")
                .accessibilityIdentifier("observation-list")
            reportButton(session)
            if session.usesGPS && !session.points.isEmpty {
                DrivyBarButton(symbol: followsPosition ? "arrow.up.left.and.arrow.down.right" : "location") {
                    if followsPosition {
                        followsPosition = false
                        resetCameraID = UUID()
                    } else {
                        followsPosition = true
                    }
                }
                .accessibilityLabel(followsPosition ? "Voir tout le trajet" : "Suivre la dernière position enregistrée")
            }
        }
        .padding(DrivySpacing.s)
        .drivyMapPanel(floating: floating)
    }

    private func reportButton(_ session: DrivingSession) -> some View {
        DrivyReportButton(isEnabled: controller.isCapturing && !controller.isBusy) {
            if let context = controller.beginObservation() {
                observationRequest = ObservationRequest(context: context, startedAt: session.startedAt)
            }
        }
        .accessibilityHint("Retient cet instant, puis propose les catégories")
        .accessibilityIdentifier("report-observation")
    }

    @ViewBuilder
    private func selectedCard(_ session: DrivingSession) -> some View {
        if let selected = session.observations.first(where: { $0.id == selectedObservationID }) {
            HStack(alignment: .top, spacing: DrivySpacing.xs) {
                ObservationRow(observation: selected, sessionStartedAt: session.startedAt, showsNote: false)
                Button { selectedObservationID = nil } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.medium))
                        .foregroundStyle(DrivyTheme.muted)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Fermer l’observation")
            }
            .padding(.horizontal, DrivySpacing.m).padding(.vertical, DrivySpacing.xxs)
            .drivyMapPanel()
        }
    }

    @ViewBuilder
    private func recentObservations(_ session: DrivingSession) -> some View {
        if session.observations.isEmpty {
            DrivyEmptyState(title: "Aucune observation pour l’instant",
                message: "« Signaler » retient le moment ; choisissez ensuite le thème et le statut.",
                symbol: "plus.bubble")
        } else {
            DrivyRowGroup(title: "Dernières observations") {
                ForEach(Array(session.observations.sorted { $0.observedAt > $1.observedAt }.prefix(8))) { observation in
                    ObservationRow(observation: observation, sessionStartedAt: session.startedAt)
                }
            }
        }
    }

    @ViewBuilder
    private var undoBanner: some View {
        if let report = recentReport {
            if report.removed {
                DrivyUndoBanner(title: "Observation retirée",
                    detail: "\(report.observation.theme.label) · \(report.observation.status.label)",
                    symbol: "arrow.uturn.backward", tone: .neutral, undo: nil)
            } else {
                DrivyUndoBanner(title: "\(report.observation.theme.label) · \(report.observation.status.label)",
                    detail: "Enregistrée sur cet appareil · privée",
                    symbol: report.observation.status.symbol, tone: report.observation.status.tone,
                    isUndoing: undoing, undo: undoAction(for: report))
            }
        }
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

    // MARK: Actions

    private var storageRetry: (() -> Void)? {
        guard !controller.isCapturing else { return nil }
        return { Task { await controller.load() } }
    }

    private func replayAction(for id: UUID) -> (() -> Void)? {
        guard let openReplay else { return nil }
        return {
            openReplay(id)
            dismiss()
        }
    }

    private func undoAction(for report: RecentReport) -> (() -> Void)? {
        guard controller.canUndoObservations, controller.isCapturing else { return nil }
        return { undo(report) }
    }

    private func reportSaved(_ observation: LessonObservation, sessionID: UUID) {
        recentReport = RecentReport(observation: observation, sessionID: sessionID)
        let message = "Observation enregistrée : \(observation.theme.label), \(observation.status.label)."
        AccessibilityNotification.Announcement(message).post()
    }

    private func undo(_ report: RecentReport) {
        guard !undoing else { return }
        undoing = true
        Task {
            let removed = await controller.removeObservation(report.observation.id, from: report.sessionID)
            undoing = false
            guard removed else { return }
            if selectedObservationID == report.observation.id { selectedObservationID = nil }
            recentReport = RecentReport(observation: report.observation, sessionID: report.sessionID, removed: true)
            let message = "Observation retirée."
            AccessibilityNotification.Announcement(message).post()
        }
    }

    /// The confirmation leaves after a short delay; longer with VoiceOver so « Annuler » stays reachable.
    private func expireRecentReport() async {
        guard let report = recentReport else { return }
        let seconds: Double = report.removed ? 3 : (voiceOverEnabled ? 15 : 8)
        do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
        if recentReport?.token == report.token { recentReport = nil }
    }
}

/// Journey without GPS, first-class: no empty map, the last observations with their time.
private struct NoGPSJourneyFeed: View {
    let session: DrivingSession

    private var recent: [LessonObservation] {
        Array(session.observations.sorted { $0.observedAt > $1.observedAt }.prefix(5))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DrivySpacing.l) {
                VStack(alignment: .leading, spacing: DrivySpacing.xs) {
                    Label("Trajet sans GPS", systemImage: "clock")
                        .font(.drivyTitle)
                        .foregroundStyle(DrivyTheme.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Aucune position n’est enregistrée. Chaque observation garde l’heure de votre signalement.")
                        .font(.body)
                        .foregroundStyle(DrivyTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if recent.isEmpty {
                    DrivyEmptyState(title: "Aucune observation pour l’instant",
                        message: "« Signaler » retient le moment ; choisissez ensuite le thème et le statut.",
                        symbol: "plus.bubble")
                } else {
                    DrivyRowGroup(title: "Dernières observations") {
                        ForEach(recent) { observation in
                            ObservationRow(observation: observation, sessionStartedAt: session.startedAt)
                        }
                    }
                }
            }
            .padding(.horizontal, DrivySpacing.l).padding(.vertical, DrivySpacing.m)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(DrivyTheme.canvas)
    }
}

/// End of journey: what was recorded, then the way to the replay and the bilan.
/// Counts only, no score; « Terminé » is shown only after the store sealed the journey.
struct JourneyFinishView: View {
    @Bindable var controller: SessionController
    let session: DrivingSession
    let openReplay: (() -> Void)?
    let close: () -> Void
    @State private var editsSummary = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var stats: JourneyStats { JourneyStats(session: session) }
    private var interrupted: Bool { session.state == .interrupted }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DrivySpacing.l) {
                heading
                if interrupted {
                    DrivyInlineMessage(text: "L’enregistrement s’est arrêté avant votre confirmation. Les données déjà sauvegardées sont conservées.",
                        tone: .warning)
                }
                if let error = controller.errorMessage { InlineErrorView(message: error) }
                if !session.points.isEmpty {
                    RouteMapView(session: session, selectedObservationID: .constant(nil), showsControls: false,
                        showsEmptyState: false, showsOriginBadge: false, fitMargin: 1.5)
                        .allowsHitTesting(false)
                        .frame(height: DrivyMapLayout.previewHeight)
                        .clipShape(RoundedRectangle(cornerRadius: DrivyRadius.content, style: .continuous))
                        .accessibilityHidden(true)
                }
                figures
                if stats.observationCount > 0 { ObservationStatusSummary(count: stats.count) }
                summaryPanel
                actions
                Label("Privé sur cet appareil · aucun partage automatique", systemImage: "lock")
                    .font(.footnote)
                    .foregroundStyle(DrivyTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .drivyPageContent(maxWidth: 620)
        }
        .background(DrivyTheme.surface)
        .sheet(isPresented: $editsSummary) {
            SummaryEditorView(controller: controller, sessionID: session.id, initialText: session.summary,
                isExample: session.isExample, observations: JourneyReplay.ordered(session.observations),
                sessionStartedAt: session.startedAt)
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xs) {
            DrivyStatusBadge(title: interrupted ? "Interrompu" : "Enregistré sur cet appareil",
                symbol: interrupted ? "exclamationmark.triangle" : "checkmark.circle",
                tone: interrupted ? .warning : .success)
            Text(interrupted ? "Trajet interrompu" : "Trajet terminé")
                .font(.drivyScreenTitle)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(timeRange)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(DrivyTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var timeRange: String {
        let locale = Locale(identifier: "fr_CH")
        let day = session.startedAt.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(locale)).capitalizedFirst
        let start = session.startedAt.formatted(.dateTime.hour().minute().locale(locale))
        guard let end = session.endedAt else { return "\(day) · \(start)" }
        return "\(day) · \(start) – \(end.formatted(.dateTime.hour().minute().locale(locale)))"
    }

    private var figures: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DrivySpacing.s))
            : AnyLayout(HStackLayout(alignment: .top, spacing: DrivySpacing.s))
        return layout {
            figure(title: "Durée", value: DrivySeanceText.duration(stats.duration), symbol: "clock")
            figure(title: "Observations", value: "\(stats.observationCount)", symbol: "text.bubble")
            figure(title: "Position", value: positionSummary, symbol: session.points.isEmpty ? "location.slash" : "point.topleft.down.to.point.bottomright.curvepath")
        }
    }

    private var positionSummary: String {
        if !session.usesGPS { return "Sans GPS" }
        if session.points.isEmpty { return "Aucun point enregistré" }
        return stats.unlocatedCount > 0 ? "Tracé · \(stats.unlocatedCount) sans position" : "Tracé enregistré"
    }

    private func figure(title: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(DrivyTheme.muted)
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(DrivyTheme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DrivySpacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DrivyTheme.canvas, in: RoundedRectangle(cornerRadius: DrivyRadius.field, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var summaryPanel: some View {
        DrivyPanel {
            VStack(alignment: .leading, spacing: DrivySpacing.xs) {
                Text("Bilan personnel")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                if stats.hasSummary {
                    Text(session.summary)
                        .font(.body)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 4)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(stats.observationCount > 0
                         ? "Les observations sont prêtes à être reprises : ce qui a été travaillé, le constat, la prochaine étape."
                         : "Notez ce qui a été travaillé et la prochaine étape.")
                        .font(.subheadline)
                        .foregroundStyle(DrivyTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: DrivySpacing.s) {
            if let openReplay {
                Button(action: openReplay) {
                    Label("Revoir le trajet", systemImage: "play.fill")
                }
                .buttonStyle(DrivyPrimaryButtonStyle())
                .accessibilityIdentifier("finish-open-replay")
                Button { editsSummary = true } label: {
                    Label(stats.hasSummary ? "Modifier le bilan" : "Écrire le bilan", systemImage: "square.and.pencil")
                }
                .buttonStyle(DrivySecondaryButtonStyle())
                .accessibilityIdentifier("finish-write-summary")
                Button("Retour à Séance", action: close)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DrivyTheme.accent)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .accessibilityIdentifier("finish-close")
            } else {
                Button { editsSummary = true } label: {
                    Label(stats.hasSummary ? "Modifier le bilan" : "Écrire le bilan", systemImage: "square.and.pencil")
                }
                .buttonStyle(DrivySecondaryButtonStyle())
                .accessibilityIdentifier("finish-write-summary")
                Button("Retour à Séance", action: close)
                    .buttonStyle(DrivyPrimaryButtonStyle())
                    .accessibilityIdentifier("finish-close")
            }
        }
    }
}
