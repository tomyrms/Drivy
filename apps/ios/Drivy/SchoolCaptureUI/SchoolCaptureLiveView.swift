import MapKit
import SwiftUI

/// Displays the school session owned by the app. Leaving this view never starts
/// or stops location collection; every command is an explicit user action.
struct SchoolCaptureLiveView: View {
    @Bindable var controller: SchoolCaptureSessionController
    let learnerName: String
    var closeSaved: (() -> Void)? = nil
    var returnToLesson: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var resetCameraID = UUID()
    @State private var followsPosition = true
    @State private var confirmation: Confirmation?

    private enum Command {
        case pause, resume, stop, retrySaving, transfer, finalize(allowPartial: Bool)
    }

    private enum Confirmation {
        case stop(UUID), allowPartial(UUID)
        var captureID: UUID {
            switch self { case .stop(let id), .allowPartial(let id): id }
        }
        var title: String {
            switch self {
            case .stop: "Arrêter le GPS ?"
            case .allowPartial: "Autoriser un trajet partiel ?"
            }
        }
    }

    var body: some View {
        Group {
            if controller.state == .idle {
                ContentUnavailableView {
                    Label("Aucun trajet en cours", systemImage: "location.slash")
                } description: {
                    Text("Ouvrez une leçon pour préparer son enregistrement GPS.")
                } actions: {
                    Button("Fermer") { close() }.buttonStyle(.bordered)
                }
            } else {
                GeometryReader { geometry in
                    if dynamicTypeSize.isAccessibilitySize {
                        accessibleContent(availableHeight: geometry.size.height)
                    } else if geometry.size.width >= 760 {
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
        .interactiveDismissDisabled(controller.isTransferring)
        .confirmationDialog(confirmation?.title ?? "Confirmer", isPresented: confirmsAction, titleVisibility: .visible, presenting: confirmation) { request in
            switch request {
            case .stop:
                Button("Arrêter le GPS", role: .destructive) {
                    run(.stop, captureID: request.captureID)
                }
                .accessibilityIdentifier("school-capture-stop-confirm")
            case .allowPartial:
                Button("Autoriser la clôture partielle") {
                    run(.finalize(allowPartial: true), captureID: request.captureID)
                }
                .accessibilityIdentifier("school-capture-partial-confirm")
            }
            Button("Annuler", role: .cancel) { }
        } message: { request in
            switch request {
            case .stop:
                Text("Les positions déjà enregistrées seront conservées. La leçon continue sans GPS.")
            case .allowPartial:
                Text("Le trajet pourra être clôturé avec les seules positions confirmées par l’école. Les lacunes resteront visibles. Il ne sera pas publié dans un bilan.")
            }
        }
        .onChange(of: controller.captureID) { _, _ in
            confirmation = nil
            resetCameraID = UUID()
            followsPosition = true
        }
    }

    private var compactContent: some View {
        routeMap
            .safeAreaInset(edge: .top, spacing: 0) {
                heading()
                    .padding(.horizontal, DrivySpacing.m).padding(.top, DrivySpacing.xs).padding(.bottom, DrivySpacing.s)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(alignment: .trailing, spacing: DrivySpacing.s) {
                    if controller.pointCount > 0 { mapControls }
                    commandPanel()
                }
                .padding(.horizontal, DrivySpacing.m).padding(.top, DrivySpacing.xs).padding(.bottom, DrivySpacing.s)
            }
    }

    private var wideContent: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: DrivySpacing.m) {
                    heading(floating: false)
                    commandPanel(floating: false)
                }
                .padding(DrivySpacing.m)
            }
            .frame(width: DrivyMapLayout.sidebarWidth)
            .background(DrivyTheme.canvas)
            routeMap.overlay(alignment: .bottomTrailing) {
                if controller.pointCount > 0 { mapControls.padding(DrivySpacing.l) }
            }
        }
    }

    private func accessibleContent(availableHeight: CGFloat) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DrivySpacing.l) {
                heading(floating: false)
                routeMap.frame(height: DrivyMapLayout.accessibleMapHeight)
                    .clipShape(RoundedRectangle(cornerRadius: DrivyRadius.mapPanel, style: .continuous))
                if controller.pointCount > 0 { mapControls.frame(maxWidth: .infinity, alignment: .trailing) }
                sessionInformation
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

    private var routeMap: some View {
        SchoolCaptureLiveMap(segments: controller.segments, resetCameraID: resetCameraID, followsPosition: $followsPosition)
    }

    /// Same header as the personal journey: close, learner, GPS state, elapsed time.
    private func heading(floating: Bool = true) -> some View {
        DrivyMapHeader(
            title: learnerName,
            status: status,
            leading: .close(label: "Revenir à la leçon",
                hint: controller.canStop ? "Le GPS conserve son état actuel" : "Fermer le trajet",
                isDisabled: controller.isTransferring) { close() },
            floating: floating
        ) {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                DrivyElapsedTime(text: elapsedLabel, accessibilityTitle: "Temps écoulé depuis le départ GPS")
            }
        }
    }

    private func commandPanel(floating: Bool = true) -> some View {
        DrivyMapDock(floating: floating) {
            sessionInformation
            actions
        }
    }

    private var sessionInformation: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xs) {
            Label(controller.pointCount == 0 ? "Aucune position enregistrée" : "\(controller.pointCount) position\(controller.pointCount == 1 ? "" : "s") enregistrée\(controller.pointCount == 1 ? "" : "s")",
                  systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(DrivyTheme.text)
                .fixedSize(horizontal: false, vertical: true)
            if controller.state == .saved && controller.finalizedSyncState == nil {
                Text("Envoyez les positions, puis vérifiez le trajet complet. Il reste privé jusqu’à sa publication dans un bilan.")
                    .font(.subheadline).foregroundStyle(DrivyTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            } else if controller.state == .recording && controller.pointCount == 0 {
                Text("En attente d’une première position sauvegardée.")
                    .font(.subheadline).foregroundStyle(DrivyTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            } else if controller.state == .paused {
                Text("Aucune position n’est enregistrée pendant la pause.")
                    .font(.subheadline).foregroundStyle(DrivyTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let error = controller.errorMessage {
                DrivyInlineMessage(text: error, tone: .warning)
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
                        DrivyInlineMessage(text: "La reprise du GPS n’est plus autorisée. Vous pouvez arrêter le GPS et poursuivre la leçon.",
                            tone: .warning)
                    }
                }
            }
        case .preparing:
            ProgressView("Préparation du GPS…").frame(maxWidth: .infinity)
            stopButton
        case .stopping:
            ProgressView("Sauvegarde des positions…").frame(maxWidth: .infinity, minHeight: 52)
        case .saved:
            savedActions
        case .failed:
            if controller.canRetrySaving {
                Button { run(.retrySaving) } label: {
                    Label("Réessayer la sauvegarde", systemImage: "arrow.clockwise")
                }
                .buttonStyle(DrivyPrimaryButtonStyle())
                .accessibilityIdentifier("school-capture-retry-saving")
            }
        case .idle:
            EmptyView()
        }
    }

    /// Pause and stop side by side, each 52 pt tall; stacked in large text sizes.
    private var collectingActions: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: DrivySpacing.s))
            : AnyLayout(HStackLayout(spacing: DrivySpacing.s))
        return layout {
            pauseResumeButton
            stopButton
        }
    }

    @ViewBuilder private var pauseResumeButton: some View {
        let paused = controller.state == .paused
        let button = Button {
            run(controller.canPause ? .pause : .resume)
        } label: {
            Label(paused ? "Reprendre" : "Pause", systemImage: paused ? "play.fill" : "pause.fill")
                .fixedSize(horizontal: false, vertical: true)
        }
        // Resuming is the next gesture of a paused journey; pausing stays secondary.
        if paused {
            button.buttonStyle(DrivyPrimaryButtonStyle())
                .disabled(!controller.canPause && !controller.canResume)
                .accessibilityLabel("Reprendre le GPS")
                .accessibilityIdentifier("school-capture-pause-resume")
        } else {
            button.buttonStyle(DrivySecondaryButtonStyle())
                .disabled(!controller.canPause && !controller.canResume)
                .accessibilityLabel("Mettre le GPS en pause")
                .accessibilityIdentifier("school-capture-pause-resume")
        }
    }

    private var stopButton: some View {
        Button {
            if let id = controller.captureID { confirmation = .stop(id) }
        } label: {
            Label("Arrêter le GPS", systemImage: "stop.fill")
                .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(DrivyDangerButtonStyle())
        .disabled(!controller.canStop)
        .accessibilityIdentifier("school-capture-stop")
    }

    private var savedActions: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.s) {
            if let state = controller.finalizedSyncState {
                finalizationResult(state)
                Button("Retour à la leçon") { close() }
                    .buttonStyle(DrivyPrimaryButtonStyle())
            } else {
                if controller.isTransferring {
                    ProgressView("Échange avec l’école…").frame(maxWidth: .infinity)
                }
                Button { run(.transfer) } label: {
                    Label("Envoyer les positions", systemImage: "arrow.up")
                }
                .buttonStyle(DrivyPrimaryButtonStyle())
                .accessibilityIdentifier("school-capture-transfer")
                Button { run(.finalize(allowPartial: false)) } label: {
                    Label("Vérifier le trajet complet", systemImage: "checkmark.circle")
                }
                .buttonStyle(DrivySecondaryButtonStyle())
                .accessibilityIdentifier("school-capture-finalize")
                Button("Autoriser un trajet partiel…") {
                    if let id = controller.captureID { confirmation = .allowPartial(id) }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DrivyTheme.accent)
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityIdentifier("school-capture-allow-partial")
            }
        }
        .disabled(controller.isTransferring)
    }

    @ViewBuilder private func finalizationResult(_ state: SchoolCaptureSession.SyncState) -> some View {
        switch state {
        case .synced:
            resultLabel("Trajet synchronisé", symbol: "checkmark.circle.fill", tone: .success,
                message: "Les positions ont été confirmées par l’école. Le trajet reste privé.")
        case .partial:
            resultLabel("Trajet partiel", symbol: "exclamationmark.circle.fill", tone: .warning,
                message: "Le trajet est conservé avec des lacunes. Il reste privé.")
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

    private var mapControls: some View {
        DrivyMapControls(followsPosition: $followsPosition) {
            followsPosition = false
            resetCameraID = UUID()
        }
    }

    private var confirmsAction: Binding<Bool> {
        Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } })
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
        guard !controller.isTransferring else { return }
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
            case .stop: await controller.stop()
            case .retrySaving: await controller.retrySaving()
            case .transfer: await controller.transfer()
            case .finalize(let allowPartial): await controller.finalize(allowPartial: allowPartial)
            }
        }
    }
}

private struct SchoolCaptureLiveMap: View {
    let segments: [SchoolCaptureMapSegment]
    let resetCameraID: UUID
    @Binding var followsPosition: Bool
    @State private var camera: MapCameraPosition = .region(JourneyMapRegion.overview)

    private var count: Int { segments.reduce(0) { $0 + $1.measurements.count } }
    private var last: SchoolCaptureMeasurement? { segments.last(where: { !$0.measurements.isEmpty })?.measurements.last }

    var body: some View {
        Map(position: $camera) {
            ForEach(segments) { segment in
                let coordinates = segment.measurements.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
                if coordinates.count > 1 {
                    MapPolyline(coordinates: coordinates).stroke(DrivyTheme.routeHalo, lineWidth: 9)
                    MapPolyline(coordinates: coordinates).stroke(DrivyTheme.route, lineWidth: 5)
                } else if let coordinate = coordinates.first {
                    Annotation("Position enregistrée", coordinate: coordinate) {
                        Circle().fill(DrivyTheme.route).frame(width: 8, height: 8)
                    }.annotationTitles(.hidden)
                }
            }
            if let last {
                Annotation("Dernière position enregistrée", coordinate: CLLocationCoordinate2D(latitude: last.latitude, longitude: last.longitude)) {
                    Circle().fill(DrivyTheme.route).frame(width: 16, height: 16)
                        .overlay(Circle().stroke(DrivyTheme.routeHalo, lineWidth: 3))
                        .padding(DrivySpacing.xs)
                        .background(DrivyTheme.route.opacity(0.18), in: Circle())
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
            else { camera = count > 0 ? .automatic : .region(JourneyMapRegion.overview) }
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
