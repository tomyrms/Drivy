import MapKit
import SwiftUI

/// Displays the school session owned by the app. Leaving this view never starts
/// or stops location collection; every command is an explicit user action.
struct SchoolCaptureLiveView: View {
    @Bindable var controller: SchoolCaptureSessionController
    let learnerName: String
    var closeSaved: (() -> Void)? = nil
    var returnToLesson: (() -> Void)? = nil
    var openLesson: ((UUID, Bool) -> Void)? = nil
    var observationClient: SchoolObservationClient? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var resetCameraID = UUID()
    @State private var followsPosition = true
    @State private var observationMoment: ObservationMoment?
    @State private var isFinishing = false

    private struct ObservationMoment: Identifiable {
        let id = UUID()
        let instant = Date()
        let recorder: SchoolLiveObservationRecorder
    }

    private enum Command { case pause, resume, retrySaving }

    var body: some View {
        Group {
            if controller.state == .idle {
                ContentUnavailableView {
                    Label("Aucun trajet en cours", systemImage: "location.slash")
                } description: {
                    Text("Ouvre une leçon pour préparer son enregistrement GPS.")
                } actions: {
                    Button("Fermer") { close() }
                        .buttonStyle(DrivySecondaryButtonStyle())
                        .fixedSize()
                }
            } else {
                GeometryReader { geometry in
                    if dynamicTypeSize.isAccessibilitySize {
                        accessibleContent(availableHeight: geometry.size.height)
                    } else if geometry.size.width >= DrivyMapLayout.sidebarBreakpoint {
                        wideContent
                    } else {
                        compactContent
                    }
                }
            }
        }
        .background(DrivyTheme.canvas)
        .foregroundStyle(DrivyTheme.text)
        .tint(DrivyTheme.accent)
        .toolbar(.hidden, for: .navigationBar)
        .interactiveDismissDisabled(isFinishing)
        .task(id: controller.captureID) {
            if let observationClient { controller.prepareLiveObservations(client: observationClient) }
            await controller.liveObservations?.loadCompetencies()
        }
        .onChange(of: controller.captureID) { _, _ in
            observationMoment = nil
            resetCameraID = UUID()
            followsPosition = true
        }
    }

    private var compactContent: some View {
        routeMap
            .safeAreaInset(edge: .top, spacing: 0) {
                heading()
                    .frame(maxWidth: DrivyMapLayout.floatingPanelMaxWidth)
                    .padding(.horizontal, DrivySpacing.m).padding(.top, DrivySpacing.xs).padding(.bottom, DrivySpacing.xs)
                    .frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(alignment: .trailing, spacing: DrivySpacing.s) {
                    if controller.pointCount > 0 { mapControls(axis: .horizontal) }
                    commandPanel()
                }
                .frame(maxWidth: DrivyMapLayout.floatingPanelMaxWidth)
                .padding(.horizontal, DrivySpacing.m).padding(.top, DrivySpacing.xs).padding(.bottom, DrivySpacing.s)
                .frame(maxWidth: .infinity)
            }
    }

    private var wideContent: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: DrivySpacing.m) {
                heading(floating: false)
                // Les commandes descendent au bas de la colonne, à portée du pouce, et non collées
                // au titre ; elles défilent seulement si la colonne est trop basse.
                Spacer(minLength: 0)
                ViewThatFits(in: .vertical) {
                    commandPanel(floating: false)
                    ScrollView { commandPanel(floating: false) }
                        .scrollBounceBehavior(.basedOnSize)
                }
            }
            .padding(DrivySpacing.m)
            .frame(width: DrivyMapLayout.sidebarWidth)
            .background(DrivyTheme.canvas)
            routeMap.overlay(alignment: .bottomTrailing) {
                if controller.pointCount > 0 { mapControls(axis: .vertical).padding(DrivySpacing.l) }
            }
        }
    }

    private func accessibleContent(availableHeight: CGFloat) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DrivySpacing.l) {
                heading(floating: false)
                if controller.pointCount > 0 {
                    routeMap.frame(height: DrivyMapLayout.accessibleMapHeight)
                        .clipShape(RoundedRectangle(cornerRadius: DrivyRadius.mapPanel, style: .continuous))
                    mapControls(axis: .horizontal).frame(maxWidth: .infinity, alignment: .trailing)
                }
                if hasSessionInformation { sessionInformation }
            }
            .padding(DrivySpacing.m)
            .frame(maxWidth: DrivyMapLayout.accessibleMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: DrivySpacing.s) { actions }
                    .padding(DrivySpacing.m)
                    .frame(maxWidth: DrivyMapLayout.accessibleMaxWidth)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxHeight: max(160, availableHeight * 0.5))
            .background(DrivyTheme.surface)
        }
    }

    /// No position yet: an honest wait instead of a country overview.
    @ViewBuilder private var routeMap: some View {
        if controller.pointCount > 0 {
            SchoolCaptureLiveMap(segments: controller.segments, resetCameraID: resetCameraID, followsPosition: $followsPosition)
        } else {
            DrivyMapPlaceholder(title: placeholderTitle, message: placeholderMessage, symbol: "location",
                isSearching: controller.state == .preparing || controller.state == .recording)
        }
    }

    private var placeholderTitle: String {
        switch controller.state {
        case .preparing: "Préparation du GPS"
        case .recording: "En attente de position"
        case .paused: "GPS en pause"
        default: "Aucune position enregistrée"
        }
    }

    private var placeholderMessage: String {
        if let message = controller.locationMessage { return message }
        return switch controller.state {
        case .preparing, .recording: "Recherche du signal GPS…"
        case .paused: "Aucune position n’est enregistrée pendant la pause."
        default: "Le GPS n’a enregistré aucune position pendant cette leçon."
        }
    }

    /// Identité et état GPS ; les commandes de leçon restent dans le panneau inférieur.
    private func heading(floating: Bool = true) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            DrivyLiveTopBar(
                context: learnerName,
                elapsed: showsElapsed ? elapsedLabel : nil,
                elapsedLabel: "Temps écoulé depuis le départ GPS",
                status: status,
                leading: .close(label: "Revenir à la leçon",
                    hint: controller.canStop ? "Le GPS conserve son état actuel" : "Fermer le trajet",
                    isDisabled: isFinishing) { close() },
                floating: floating
            ) { EmptyView() }
        }
    }

    private var showsElapsed: Bool {
        [SchoolCaptureSessionController.State.recording, .paused, .preparing, .stopping].contains(controller.state)
    }

    private func commandPanel(floating: Bool = true) -> some View {
        DrivyMapDock(floating: floating) {
            // Pas de bloc vide : sans information, le dock commence directement par l’action.
            if hasSessionInformation { sessionInformation }
            actions
        }
    }

    private var hasSessionInformation: Bool {
        controller.pointCount > 0
            || [SchoolCaptureSessionController.State.saved, .failed].contains(controller.state)
            || controller.errorMessage != nil
            || (controller.transferMessage != nil && controller.finalizedSyncState == nil)
    }

    private var sessionInformation: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xs) {
            // Before the first point the map placeholder already says it; no duplicate line here.
            if controller.pointCount > 0 || [SchoolCaptureSessionController.State.saved, .failed].contains(controller.state) {
                Label(controller.pointCount == 0 ? "Aucune position enregistrée" : "\(controller.pointCount) position\(controller.pointCount == 1 ? "" : "s") enregistrée\(controller.pointCount == 1 ? "" : "s")",
                      systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(DrivyTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let error = controller.errorMessage {
                DrivyInlineMessage(text: error, tone: .warning)
            }
            if controller.pointCount > 0, let message = controller.locationMessage {
                DrivyInlineMessage(text: message, tone: .warning)
            }
            if let message = controller.transferMessage, controller.finalizedSyncState == nil {
                DrivyInlineMessage(text: message, tone: .neutral)
            }
        }
    }

    @ViewBuilder private var actions: some View {
        switch controller.state {
        case .recording:
            collectingActions
        case .paused:
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                VStack(alignment: .leading, spacing: DrivySpacing.s) {
                    collectingActions
                    if !controller.canResume {
                        DrivyInlineMessage(text: "La reprise du GPS n’est plus autorisée. Tu peux arrêter le GPS et poursuivre la leçon.",
                            tone: .warning)
                    }
                }
            }
        case .preparing:
            DrivyLoadingState(title: "Préparation du GPS…")
        case .stopping:
            DrivyLoadingState(title: "Sauvegarde des positions…")
        case .saved:
            savedActions
        case .failed:
            if controller.canRetrySaving {
                Button { run(.retrySaving) } label: {
                    Label("Réessayer la sauvegarde", systemImage: "arrow.clockwise")
                }
                .buttonStyle(DrivyPrimaryButtonStyle(size: .field))
                .accessibilityIdentifier("school-capture-retry-saving")
            }
        case .idle:
            EmptyView()
        }
    }

    private var collectingActions: some View {
        let paused = controller.state == .paused
        return VStack(spacing: DrivySpacing.s) {
            // Une seule action principale, en grand format terrain : « Signaler » en route,
            // « Reprendre » en pause. L’autre geste garde sa place en second rang.
            if paused { resumeButton }
            else if let recorder = controller.liveObservations { signalButton(recorder, isDominant: true) }
            if let recorder = controller.liveObservations { observationFeedback(recorder) }
            // Côte à côte quand les deux libellés tiennent sur une ligne ; sinon empilés
            // (colonne iPad de 380 pt, grand texte) plutôt qu’un « Terminer / la leçon » coupé.
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: DrivySpacing.s) { secondaryCommands(hugsFirst: false) }
            } else {
                // En ligne, le premier geste prend sa largeur naturelle et « Terminer la leçon » le reste :
                // un partage à 50/50 coupait ce libellé même sur un grand iPhone.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: DrivySpacing.s) { secondaryCommands(hugsFirst: true) }
                    VStack(spacing: DrivySpacing.s) { secondaryCommands(hugsFirst: false) }
                }
            }
        }
    }

    /// « Signaler » : dominant en route, secondaire en pause (où « Reprendre » prend l’aplat).
    @ViewBuilder private func signalButton(_ recorder: SchoolLiveObservationRecorder, isDominant: Bool) -> some View {
        let signal = Button {
            observationMoment = ObservationMoment(recorder: recorder)
        } label: {
            Label("Signaler", systemImage: "text.bubble.fill")
        }
        Group {
            if isDominant {
                signal.buttonStyle(DrivyPrimaryButtonStyle(size: .field))
            } else {
                signal.buttonStyle(DrivySecondaryButtonStyle())
            }
        }
        .disabled(!recorder.canRecord || isFinishing)
        .sensoryFeedback(.impact(weight: .medium), trigger: observationMoment?.id)
        .accessibilityIdentifier("capture-signal-observation")
        .popover(item: $observationMoment, attachmentAnchor: .rect(.bounds)) { moment in
            SchoolLiveObservationSheet(recorder: moment.recorder, observedAt: moment.instant)
                .frame(width: horizontalSizeClass == .regular ? DrivyMapLayout.reportPopoverSize.width : nil,
                       height: horizontalSizeClass == .regular ? DrivyMapLayout.reportPopoverSize.height : nil)
                .presentationCompactAdaptation(.sheet)
        }
    }

    @ViewBuilder private func observationFeedback(_ recorder: SchoolLiveObservationRecorder) -> some View {
        if recorder.isSending { DrivyLoadingState(title: "Envoi de l’observation…") }
        else if recorder.pending != nil {
            DrivyInlineMessage(text: recorder.errorMessage ?? "Une observation attend son envoi.", tone: .warning)
            if recorder.canRetry {
                Button("Réessayer l’envoi", systemImage: "arrow.clockwise") { Task { await recorder.retry() } }
                    .buttonStyle(DrivySecondaryButtonStyle())
            } else {
                Button("Actualiser", systemImage: "arrow.clockwise") { recorder.refreshPending() }
                    .buttonStyle(DrivySecondaryButtonStyle())
            }
        } else if let error = recorder.errorMessage {
            DrivyInlineMessage(text: error, tone: .warning)
        }
    }

    /// Second rang : le geste qui n’est pas dominant (Pause en route, Signaler en pause) et « Terminer la leçon ».
    @ViewBuilder private func secondaryCommands(hugsFirst: Bool) -> some View {
        if controller.state == .paused {
            if let recorder = controller.liveObservations {
                signalButton(recorder, isDominant: false)
                    .fixedSize(horizontal: hugsFirst, vertical: false)
            }
        } else {
            pauseButton
                .fixedSize(horizontal: hugsFirst, vertical: false)
        }
        Button {
            finishLesson()
        } label: {
            Label("Terminer la leçon", systemImage: "checkmark.circle")
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
        }
        .buttonStyle(DrivySecondaryButtonStyle())
        .disabled(isFinishing || !controller.canStop)
        .accessibilityIdentifier("capture-finish-lesson")
    }

    private var pauseButton: some View {
        Button {
            run(.pause)
        } label: {
            Label("Pause", systemImage: "pause.fill")
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
        }
        .buttonStyle(DrivySecondaryButtonStyle())
        .disabled(!controller.canPause)
        .accessibilityLabel("Mettre le GPS en pause")
        .accessibilityIdentifier("school-capture-pause-resume")
    }

    /// La reprise est le prochain geste d’un trajet en pause : seule action principale.
    private var resumeButton: some View {
        Button {
            run(.resume)
        } label: {
            Label("Reprendre", systemImage: "play.fill")
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
        }
        .buttonStyle(DrivyPrimaryButtonStyle(size: .field))
        .disabled(!controller.canResume)
        .accessibilityLabel("Reprendre le GPS")
        .accessibilityIdentifier("school-capture-pause-resume")
    }

    private var savedActions: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.s) {
            if controller.isTransferring { DrivyLoadingState(title: "Enregistrement du trajet…") }
            if controller.synchronizationNeedsRetry {
                Button("Réessayer l’envoi du trajet", systemImage: "arrow.clockwise") {
                    Task { await controller.retrySynchronization() }
                }.buttonStyle(DrivySecondaryButtonStyle())
            }
            if let state = controller.finalizedSyncState { finalizationResult(state) }
            Button("Terminer la leçon", systemImage: "checkmark.circle") { finishLesson() }
                .buttonStyle(DrivyPrimaryButtonStyle(size: .field)).disabled(isFinishing)
        }
    }

    private func finishLesson() {
        guard !isFinishing, let lessonID = controller.lessonID else { return }
        isFinishing = true
        Task { @MainActor in
            let saved = await controller.stopAndSynchronize()
            isFinishing = false
            guard saved else { return }
            if let openLesson { openLesson(lessonID, true) }
            else { close() }
        }
    }

    @ViewBuilder private func finalizationResult(_ state: SchoolCaptureSession.SyncState) -> some View {
        switch state {
        case .synced:
            resultLabel("Trajet synchronisé", symbol: "checkmark.circle.fill", tone: .success,
                message: nil)
        case .partial:
            resultLabel("Trajet partiel", symbol: "exclamationmark.circle.fill", tone: .warning,
                message: "Le trajet est conservé avec des lacunes.")
        case .rejected:
            resultLabel("Trajet refusé par l’école", symbol: "exclamationmark.triangle.fill", tone: .warning, message: nil)
        case .uploading:
            resultLabel("Envoi encore en cours", symbol: "clock", tone: .accent,
                message: "Les positions restent conservées sur cet appareil jusqu’à la confirmation de l’école.")
        case .localOnly:
            resultLabel("Trajet conservé sur cet appareil", symbol: "iphone", tone: .neutral, message: nil)
        }
    }

    private func resultLabel(_ title: String, symbol: String, tone: DrivyTone, message: String?) -> some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .foregroundStyle(tone == .neutral ? DrivyTheme.text : tone.foreground)
            if let message {
                Text(message).font(.subheadline).foregroundStyle(DrivyTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func mapControls(axis: Axis) -> some View {
        DrivyMapControls(followsPosition: $followsPosition, axis: axis) {
            followsPosition = false
            resetCameraID = UUID()
        }
    }

    /// Same state vocabulary as the personal journey (« GPS actif », « En attente de position »).
    private var status: DrivyMapStatus {
        switch controller.state {
        case .idle: DrivyMapStatus(title: "Aucun trajet en cours", symbol: "location.slash")
        case .preparing: DrivyMapStatus(title: "Préparation du GPS", symbol: "clock")
        case .recording:
            controller.pointCount == 0
                ? DrivyMapStatus(title: "En attente de position", symbol: "location")
                : DrivyMapStatus(title: "GPS actif", symbol: "location.fill", tone: .accent)
        case .paused: DrivyMapStatus(title: "GPS en pause", symbol: "pause.circle")
        case .stopping: DrivyMapStatus(title: "Sauvegarde en cours", symbol: "clock")
        case .saved: DrivyMapStatus(title: "GPS arrêté · trajet conservé", symbol: "location.slash")
        case .failed: DrivyMapStatus(title: "GPS arrêté · sauvegarde à vérifier", symbol: "exclamationmark.triangle", tone: .warning)
        }
    }

    private var elapsedLabel: String {
        let seconds = max(0, Int(controller.elapsedSeconds))
        return seconds >= 3_600
            ? String(format: "%d:%02d:%02d", seconds / 3_600, (seconds % 3_600) / 60, seconds % 60)
            : String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func close() {
        guard !isFinishing else { return }
        if let lessonID = controller.lessonID, let openLesson { openLesson(lessonID, false); return }
        if controller.state == .saved { closeSaved?() }
        if let returnToLesson { returnToLesson() }
        else { dismiss() }
    }

    private func run(_ command: Command, captureID: UUID? = nil) {
        guard let id = captureID ?? controller.captureID else { return }
        Task { @MainActor in
            guard controller.captureID == id else { return }
            switch command {
            case .pause: await controller.pause()
            case .resume: await controller.resume()
            case .retrySaving: await controller.retrySaving()
            }
        }
    }
}

private struct SchoolCaptureLiveMap: View {
    let segments: [SchoolCaptureMapSegment]
    let resetCameraID: UUID
    @Binding var followsPosition: Bool
    @State private var camera: MapCameraPosition = .automatic

    private var count: Int { segments.reduce(0) { $0 + $1.measurements.count } }
    private var last: SchoolCaptureMeasurement? { segments.last(where: { !$0.measurements.isEmpty })?.measurements.last }

    var body: some View {
        Map(position: $camera) {
            ForEach(segments) { segment in
                let coordinates = segment.measurements.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
                if coordinates.count > 1 {
                    // Trait épais : lisible d’un regard, en plein soleil comme de nuit.
                    MapPolyline(coordinates: coordinates).stroke(DrivyTheme.routeHalo, lineWidth: 11)
                    MapPolyline(coordinates: coordinates).stroke(DrivyTheme.route, lineWidth: 6)
                } else if let coordinate = coordinates.first {
                    Annotation("Position enregistrée", coordinate: coordinate) {
                        Circle().fill(DrivyTheme.route).frame(width: 8, height: 8)
                    }.annotationTitles(.hidden)
                }
            }
            if let last {
                Annotation("Dernière position enregistrée", coordinate: CLLocationCoordinate2D(latitude: last.latitude, longitude: last.longitude)) {
                    Circle().fill(DrivyTheme.route).frame(width: 20, height: 20)
                        .overlay(Circle().stroke(DrivyTheme.routeHalo, lineWidth: 4))
                        .shadow(color: DrivyTheme.shadow.opacity(0.3), radius: 3, y: 1)
                        .padding(DrivySpacing.s)
                        .background(DrivyTheme.route.opacity(0.2), in: Circle())
                        .accessibilityLabel("Dernière position enregistrée")
                }.annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .mapControls { }
        .onAppear { if followsPosition { followPoint() } else if count > 0 { camera = .automatic } }
        .onChange(of: camera.positionedByUser) { _, byUser in if byUser { followsPosition = false } }
        .onChange(of: followsPosition) { _, follows in if follows { followPoint() } }
        .onChange(of: count) { before, after in
            if followsPosition && !camera.positionedByUser { followPoint() }
            else if before == 0 && after > 0 { camera = .automatic }
        }
        .onChange(of: resetCameraID) { _, _ in
            if followsPosition { followPoint() }
            else { camera = .automatic }
        }
        .accessibilityLabel("Carte du trajet enregistré")
        .accessibilityValue("\(count) positions enregistrées")
    }

    private func followPoint() {
        guard let last else { return }
        camera = .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: last.latitude, longitude: last.longitude),
            span: MKCoordinateSpan(latitudeDelta: 0.006, longitudeDelta: 0.006)))
    }
}
