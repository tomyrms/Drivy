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
                heading.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 8)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(alignment: .trailing, spacing: 12) {
                    if controller.pointCount > 0 { mapControls }
                    commandPanel
                }
                .padding(.horizontal, 16).padding(.bottom, 12)
            }
    }

    private var wideContent: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    heading
                    commandPanel
                }.padding(20)
            }
            .frame(width: 360)
            routeMap.overlay(alignment: .bottomTrailing) {
                if controller.pointCount > 0 { mapControls.padding(24) }
            }
        }
    }

    private func accessibleContent(availableHeight: CGFloat) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                heading
                routeMap.frame(height: 230)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                if controller.pointCount > 0 { mapControls.frame(maxWidth: .infinity, alignment: .trailing) }
                sessionInformation
            }
            .padding(16).frame(maxWidth: 680).frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ScrollView {
                actions.padding(16).frame(maxWidth: 680).frame(maxWidth: .infinity)
            }
            .frame(maxHeight: max(160, availableHeight * 0.5))
            .background(DrivyTheme.surface)
        }
    }

    private var routeMap: some View {
        SchoolCaptureLiveMap(segments: controller.segments, resetCameraID: resetCameraID, followsPosition: $followsPosition)
    }

    private var heading: some View {
        HStack(alignment: .center, spacing: 8) {
            Button { close() } label: {
                Image(systemName: "xmark").font(.body.weight(.medium)).frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .disabled(controller.isTransferring)
            .accessibilityLabel("Revenir à la leçon")
            .accessibilityHint(controller.canStop ? "Le GPS conserve son état actuel" : "Fermer le trajet")
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                : AnyLayout(HStackLayout(spacing: 12))
            layout {
                VStack(alignment: .leading, spacing: 5) {
                    Text(learnerName).font(.headline).fixedSize(horizontal: false, vertical: true)
                    Label(statusTitle, systemImage: statusSymbol)
                        .font(.caption).foregroundStyle(statusColor)
                        .fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(elapsedLabel)
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .accessibilityLabel("Temps écoulé depuis le départ GPS")
                        .accessibilityValue(elapsedLabel)
                }
            }
        }
        .padding(.leading, 6).padding(.trailing, 16).padding(.vertical, 12)
        .background(DrivyTheme.surface, in: RoundedRectangle(cornerRadius: 24))
    }

    private var commandPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            sessionInformation
            actions
        }
        .padding(20)
        .background(DrivyTheme.surface, in: RoundedRectangle(cornerRadius: 24))
    }

    private var sessionInformation: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(controller.pointCount == 0 ? "Aucun point enregistré" : "\(controller.pointCount) position\(controller.pointCount == 1 ? "" : "s") enregistrée\(controller.pointCount == 1 ? "" : "s")")
                .font(.subheadline.weight(.semibold))
            if controller.state == .saved && controller.finalizedSyncState == nil {
                Text("Envoyez les positions, puis vérifiez le trajet complet. Il reste privé jusqu’à sa publication dans un bilan.")
                    .font(.subheadline).foregroundStyle(DrivyTheme.muted)
            } else if controller.state == .recording && controller.pointCount == 0 {
                Text("En attente d’une première position sauvegardée.")
                    .font(.subheadline).foregroundStyle(DrivyTheme.muted)
            } else if controller.state == .paused {
                Text("Aucune position n’est enregistrée pendant la pause.")
                    .font(.subheadline).foregroundStyle(DrivyTheme.muted)
            }
            if let error = controller.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.subheadline).foregroundStyle(DrivyTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let message = controller.transferMessage, controller.finalizedSyncState == nil {
                Text(message).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private var actions: some View {
        switch controller.state {
        case .recording:
            collectingActions
        case .paused:
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                VStack(alignment: .leading, spacing: 12) {
                    collectingActions
                    if !controller.canResume {
                        Text("La reprise GPS n’est plus autorisée. Vous pouvez arrêter le GPS et poursuivre la leçon.")
                            .font(.footnote).foregroundStyle(DrivyTheme.warning)
                    }
                }
            }
        case .preparing:
            ProgressView("Préparation du GPS…")
            stopButton
        case .stopping:
            ProgressView("Sauvegarde des positions…")
        case .saved:
            savedActions
        case .failed:
            if controller.canRetrySaving {
                Button { run(.retrySaving) } label: {
                    Label("Réessayer la sauvegarde", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("school-capture-retry-saving")
            }
        case .idle:
            EmptyView()
        }
    }

    private var collectingActions: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            Button {
                run(controller.canPause ? .pause : .resume)
            } label: {
                Label(controller.state == .paused ? "Reprendre" : "Pause", systemImage: controller.state == .paused ? "play.fill" : "pause.fill")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!controller.canPause && !controller.canResume)
            .accessibilityLabel(controller.state == .paused ? "Reprendre le GPS" : "Mettre le GPS en pause")
            .accessibilityIdentifier("school-capture-pause-resume")
            stopButton
        }
    }

    private var stopButton: some View {
        Button {
            if let id = controller.captureID { confirmation = .stop(id) }
        } label: {
            Label("Arrêter le GPS", systemImage: "stop.fill")
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered).tint(DrivyTheme.danger)
        .disabled(!controller.canStop)
        .accessibilityIdentifier("school-capture-stop")
    }

    private var savedActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let state = controller.finalizedSyncState {
                finalizationResult(state)
                Button("Retour à la leçon") { close() }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .buttonStyle(.bordered)
            } else {
                if controller.isTransferring { ProgressView("Échange avec l’école…") }
                Button { run(.transfer) } label: {
                    Label("Envoyer les positions", systemImage: "arrow.up")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("school-capture-transfer")
                Button { run(.finalize(allowPartial: false)) } label: {
                    Text("Vérifier le trajet complet").frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(.bordered)
                    .accessibilityIdentifier("school-capture-finalize")
                Button("Autoriser un trajet partiel…") {
                    if let id = controller.captureID { confirmation = .allowPartial(id) }
                }
                .frame(minHeight: 44)
                .accessibilityIdentifier("school-capture-allow-partial")
            }
        }
        .disabled(controller.isTransferring)
    }

    @ViewBuilder private func finalizationResult(_ state: SchoolCaptureSession.SyncState) -> some View {
        switch state {
        case .synced:
            Label("Trajet synchronisé", systemImage: "checkmark.circle").font(.headline)
            Text("Les positions ont été confirmées par l’école. Le trajet reste privé.")
                .font(.subheadline).foregroundStyle(DrivyTheme.muted)
        case .partial:
            Label("Trajet partiel", systemImage: "exclamationmark.circle").font(.headline)
                .foregroundStyle(DrivyTheme.warning)
            Text("Le trajet est conservé avec des lacunes. Il reste privé.")
                .font(.subheadline).foregroundStyle(DrivyTheme.muted)
        case .rejected:
            Label("Trajet refusé par l’école", systemImage: "exclamationmark.triangle")
                .foregroundStyle(DrivyTheme.warning)
        case .uploading:
            Label("Envoi encore en cours", systemImage: "clock")
        case .localOnly:
            Label("Trajet conservé sur cet appareil", systemImage: "iphone")
        }
    }

    private var mapControls: some View {
        HStack(spacing: 8) {
            Button { followsPosition.toggle() } label: {
                Image(systemName: followsPosition ? "location.fill" : "location")
                    .font(.title3).foregroundStyle(followsPosition ? DrivyTheme.accent : DrivyTheme.text)
                    .frame(width: 48, height: 48).background(DrivyTheme.surface, in: Circle())
            }
            .accessibilityLabel(followsPosition ? "Arrêter le suivi de position" : "Suivre la dernière position enregistrée")
            .accessibilityAddTraits(followsPosition ? [.isSelected] : [])
            Button { followsPosition = false; resetCameraID = UUID() } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.title3).frame(width: 48, height: 48)
                    .background(DrivyTheme.surface, in: Circle())
            }.accessibilityLabel("Voir tout le trajet")
        }.buttonStyle(.plain)
    }

    private var confirmsAction: Binding<Bool> {
        Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } })
    }

    private var statusTitle: String {
        switch controller.state {
        case .idle: "Aucun trajet en cours"
        case .preparing: "Préparation du GPS"
        case .recording: controller.pointCount == 0 ? "En attente de position" : "GPS en cours"
        case .paused: "GPS en pause"
        case .stopping: "Sauvegarde en cours"
        case .saved: "GPS arrêté · trajet conservé"
        case .failed: "GPS arrêté · sauvegarde à vérifier"
        }
    }

    private var statusSymbol: String {
        switch controller.state {
        case .recording: "location.fill"
        case .paused: "pause.circle"
        case .failed: "exclamationmark.triangle"
        case .preparing, .stopping: "clock"
        case .idle, .saved: "location.slash"
        }
    }

    private var statusColor: Color {
        controller.state == .recording ? DrivyTheme.accent : controller.state == .failed ? DrivyTheme.warning : DrivyTheme.muted
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
                    MapPolyline(coordinates: coordinates).stroke(DrivyTheme.surface, lineWidth: 9)
                    MapPolyline(coordinates: coordinates).stroke(DrivyTheme.accent, lineWidth: 5)
                } else if let coordinate = coordinates.first {
                    Annotation("Position enregistrée", coordinate: coordinate) {
                        Circle().fill(DrivyTheme.accent).frame(width: 8, height: 8)
                    }.annotationTitles(.hidden)
                }
            }
            if let last {
                Annotation("Dernière position enregistrée", coordinate: CLLocationCoordinate2D(latitude: last.latitude, longitude: last.longitude)) {
                    Circle().fill(DrivyTheme.accent).frame(width: 16, height: 16)
                        .overlay(Circle().stroke(DrivyTheme.surface, lineWidth: 3))
                        .padding(8)
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
