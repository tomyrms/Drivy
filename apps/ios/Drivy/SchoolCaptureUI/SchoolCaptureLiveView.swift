import MapKit
import SwiftUI
import UIKit

/// Displays the school session owned by the app. Leaving this view never starts
/// or stops location collection; every command is an explicit user action.
struct SchoolCaptureLiveView: View {
    @Bindable var controller: SchoolCaptureSessionController
    let learnerName: String
    var closeSaved: (() -> Void)? = nil
    var returnToLesson: (() -> Void)? = nil
    var openLesson: ((UUID, Bool) -> Void)? = nil
    var observationClient: SchoolObservationClient? = nil
    var isTabRoot: Bool = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var resetCameraID = UUID()
    @State private var followMode: DrivyMapFollowMode = .free
    @State private var observationMoment: ObservationMoment?
    @State private var observationNotice: ObservationNotice?
    @State private var isFinishing = false
    @State private var confirmsFinish = false
    @State private var cancellationModel: SchoolPlanningWorkspace?
    @State private var cancellationError: String?
    @State private var isOpeningCancellation = false
    /// Passage (pause, reprise) qui dure assez pour être nommé sur sa commande ; un passage bref ne montre rien.
    @State private var slowTransition: SchoolCaptureSessionController.Transition?

    /// Délai avant de nommer un passage en cours. Il retarde un indicateur, jamais un résultat.
    private static let slowTransitionDelay = Duration.milliseconds(400)

    private struct ObservationMoment: Identifiable {
        let id = UUID()
        let instant: Date
        let recorder: SchoolLiveObservationRecorder
        let anchor: SchoolLiveObservationAnchor?
    }

    private struct ObservationNotice: Identifiable {
        let receipt: SchoolLiveObservationReceipt
        let recorder: SchoolLiveObservationRecorder
        var id: UUID { receipt.id }
    }

    private enum Command { case pause, resume, retrySaving }

    private var usesInlineObservation: Bool {
        horizontalSizeClass != .regular && !dynamicTypeSize.isAccessibilitySize
    }

    private var observationPopover: Binding<ObservationMoment?> {
        Binding(get: { usesInlineObservation ? nil : observationMoment }, set: { observationMoment = $0 })
    }

    /// État dont l’écran garde la disposition : pendant une mise en pause, une reprise ou une perte de signal
    /// récupérée, celui que l’on quitte, jusqu’au résultat durable. La carte, le panneau et les commandes restent en place.
    private var shownState: SchoolCaptureSessionController.State { controller.presentedState }

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
                    ZStack(alignment: .bottom) {
                        Group {
                            if dynamicTypeSize.isAccessibilitySize {
                                accessibleContent(availableHeight: geometry.size.height)
                            } else if geometry.size.width >= DrivyMapLayout.sidebarBreakpoint {
                                wideContent
                            } else {
                                compactContent
                            }
                        }
                        .allowsHitTesting(!(usesInlineObservation && observationMoment != nil))
                        .accessibilityHidden(usesInlineObservation && observationMoment != nil)
                        // Pause et reprise : seuls les éléments qui en dépendent changent, par une transition courte.
                        .animation(DrivyMotion.context(reduceMotion), value: shownState == .paused)
                        if usesInlineObservation, let moment = observationMoment {
                            DrivyTheme.shadow.opacity(0.16)
                                .ignoresSafeArea(edges: .top)
                                .onTapGesture { closeObservation() }
                                .accessibilityHidden(true)
                            SchoolLiveObservationPalette(recorder: moment.recorder, observedAt: moment.instant,
                                anchor: moment.anchor, onRecorded: { showObservationNotice(moment.recorder) }, onClose: closeObservation)
                                .frame(maxWidth: DrivyMapLayout.floatingPanelMaxWidth)
                                .frame(height: min(DrivyMapLayout.reportPaletteHeight, max(0, geometry.size.height - DrivySpacing.xl)))
                                .background(DrivyTheme.surface, in: RoundedRectangle(cornerRadius: DrivyRadius.mapPanel, style: .continuous))
                                .clipShape(RoundedRectangle(cornerRadius: DrivyRadius.mapPanel, style: .continuous))
                                .drivyShadow(radius: 18, y: 8)
                                .padding(DrivySpacing.m)
                                .accessibilityAddTraits(.isModal)
                                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                }
            }
        }
        .background(DrivyTheme.canvas)
        .foregroundStyle(DrivyTheme.text)
        .tint(DrivyTheme.accent)
        .toolbar(.hidden, for: .navigationBar)
        .interactiveDismissDisabled(isFinishing)
        .sensoryFeedback(.success, trigger: observationNotice?.id) { _, newValue in newValue != nil }
        .alert("Terminer la leçon ?", isPresented: $confirmsFinish) {
            Button("Terminer") { finishLesson() }
                .accessibilityIdentifier("capture-confirm-finish")
            Button("Continuer", role: .cancel) { }
        }
        .task(id: controller.captureID) {
            if let observationClient { controller.prepareLiveObservations(client: observationClient) }
            await controller.liveObservations?.loadCompetencies()
        }
        .task(id: controller.transition) {
            slowTransition = nil
            guard let transition = controller.transition else { return }
            do { try await Task.sleep(for: Self.slowTransitionDelay) } catch { return }
            slowTransition = transition
        }
        .onChange(of: shownState == .paused) { _, _ in
            // La commande activée vient d’être remplacée : VoiceOver entend le résultat de la pause ou de la reprise.
            UIAccessibility.post(notification: .announcement, argument: status.title)
        }
        .onChange(of: controller.captureID) { _, _ in
            observationMoment = nil
            observationNotice = nil
            confirmsFinish = false
            resetCameraID = UUID()
            followMode = .free
        }
        .onDisappear { observationMoment = nil; observationNotice = nil }
        .sheet(item: $cancellationModel) { model in
            SchoolPlanningView(model: model, cancelling: true, beforeCancellation: {
                await controller.stopAndSynchronize()
            })
            .onChange(of: model.confirmedCancellationLessonID) { _, id in
                guard let id, id == model.originalLesson?.id, id == controller.lessonID else { return }
                controller.closeSaved()
                openLesson?(id, false)
            }
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
                commandDock()
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
                    wideCommands
                    ScrollView { wideCommands }
                        .scrollBounceBehavior(.basedOnSize)
                }
            }
            .padding(DrivySpacing.m)
            .frame(width: DrivyMapLayout.sidebarWidth)
            .background(DrivyTheme.canvas)
            routeMap.overlay(alignment: .bottomTrailing) {
                if controller.displayedPointCount > 0 { mapControls(axis: .vertical).padding(DrivySpacing.l) }
            }
        }
    }

    private func accessibleContent(availableHeight: CGFloat) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DrivySpacing.l) {
                heading(floating: false)
                if controller.displayedPointCount > 0 {
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
                VStack(alignment: .leading, spacing: DrivySpacing.s) {
                    observationNoticeView
                    actions
                }
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
        if controller.displayedPointCount > 0 {
            SchoolCaptureLiveMap(segments: controller.segments,
                observations: controller.liveObservations?.mapObservations ?? [],
                resetCameraID: resetCameraID, isRecording: shownState == .recording,
                followMode: $followMode)
        } else {
            DrivyMapPlaceholder(title: placeholderTitle, message: placeholderMessage, symbol: "location",
                isSearching: shownState == .preparing || shownState == .recording)
        }
    }

    private var placeholderTitle: String {
        switch shownState {
        case .preparing: "Préparation du GPS"
        case .recording: "En attente de position"
        case .paused: "GPS en pause"
        default: "Aucune position enregistrée"
        }
    }

    private var placeholderMessage: String {
        if let message = controller.locationMessage { return message }
        return switch shownState {
        case .preparing, .recording: "Recherche du signal GPS…"
        case .paused: "Aucune position n’est enregistrée pendant la pause."
        default: "Le GPS n’a enregistré aucune position pendant cette leçon."
        }
    }

    /// Identité et état GPS ; les actions secondaires de leçon sont dans le menu.
    private func heading(floating: Bool = true) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            DrivyLiveTopBar(
                context: learnerName,
                elapsed: showsElapsed ? elapsedLabel : nil,
                elapsedLabel: "Temps écoulé depuis le départ GPS",
                status: status,
                leading: isTabRoot ? nil : .back(label: "Revenir à la leçon",
                    hint: controller.presentsStopEnabled ? "Le GPS conserve son état actuel" : "Fermer le trajet",
                    isDisabled: isFinishing) { close() },
                floating: floating
            ) { lessonMenu }
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
        controller.errorMessage != nil || cancellationError != nil
            || (controller.displayedPointCount > 0 && controller.locationMessage != nil)
            || (controller.transferMessage != nil && controller.finalizedSyncState == nil)
    }

    private var sessionInformation: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xs) {
            if let cancellationError { DrivyInlineMessage(text: cancellationError, tone: .warning) }
            if let error = controller.errorMessage {
                DrivyInlineMessage(text: error, tone: .warning)
            }
            if controller.displayedPointCount > 0, let message = controller.locationMessage {
                DrivyInlineMessage(text: message, tone: .warning)
            }
            if let message = controller.transferMessage, controller.finalizedSyncState == nil {
                DrivyInlineMessage(text: message, tone: .neutral)
            }
        }
    }

    @ViewBuilder private var actions: some View {
        if isFinishing {
            DrivyLoadingState(title: "Préparation du bilan…")
        } else {
            switch shownState {
            case .recording, .paused:
                // Un seul bloc en route et en pause : ses commandes changent, le panneau reste en place.
                collectingActions
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
    }

    private var collectingActions: some View {
        let paused = shownState == .paused
        return VStack(spacing: DrivySpacing.s) {
            // Une seule action principale, en grand format terrain : « Signaler » en route,
            // « Reprendre » en pause. L’autre geste garde sa place en second rang.
            // L’aplat bleu ne se fond pas : seul son libellé change d’un état à l’autre.
            if paused { resumeControls.transition(.identity) }
            else if let recorder = controller.liveObservations { signalButton(recorder, isDominant: true).transition(.identity) }
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
            let instant = Date()
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.24, extraBounce: 0)) {
                observationMoment = ObservationMoment(instant: instant, recorder: recorder, anchor: controller.observationAnchor(at: instant))
            }
        } label: {
            Label {
                Text("Signaler")
            } icon: {
                Image("Brand-marker").resizable().scaledToFit()
                    .frame(width: 28, height: 28)
                    .accessibilityHidden(true)
            }
        }
        Group {
            if isDominant {
                signal.buttonStyle(DrivyPrimaryButtonStyle(size: .field))
            } else {
                signal.buttonStyle(DrivySecondaryButtonStyle())
            }
        }
        // L’envoi qui suit un signalement est bref : il ne grise pas la commande. La palette s’ouvre, l’écriture
        // suivante attend la fin de cet envoi et le double envoi reste refusé par l’enregistreur.
        .disabled(!recorder.acceptsSignal || isFinishing)
        .sensoryFeedback(.impact(weight: .medium), trigger: observationMoment?.id)
        .accessibilityIdentifier("capture-signal-observation")
        .popover(item: observationPopover, attachmentAnchor: .rect(.bounds)) { moment in
            SchoolLiveObservationSheet(recorder: moment.recorder, observedAt: moment.instant, anchor: moment.anchor,
                onRecorded: { showObservationNotice(moment.recorder) })
                .frame(width: horizontalSizeClass == .regular ? DrivyMapLayout.reportPopoverSize.width : nil,
                       height: horizontalSizeClass == .regular ? DrivyMapLayout.reportPopoverSize.height : nil)
                .presentationCompactAdaptation(.sheet)
        }
    }

    private func closeObservation() {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.24, extraBounce: 0)) { observationMoment = nil }
    }

    private func showObservationNotice(_ recorder: SchoolLiveObservationRecorder) {
        guard let receipt = recorder.lastAdded else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
            observationNotice = ObservationNotice(receipt: receipt, recorder: recorder)
        }
    }

    @ViewBuilder private var observationNoticeView: some View {
        if let notice = observationNotice {
            SchoolObservationUndoBanner(recorder: notice.recorder, receipt: notice.receipt) {
                guard observationNotice?.id == notice.id else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { observationNotice = nil }
            }
        }
    }

    private func commandDock(floating: Bool = true) -> some View {
        let noticeSpacing = observationNotice == nil ? DrivySpacing.s : DrivySpacing.xl
        return commandPanel(floating: floating)
            .overlay(alignment: .top) {
                VStack(alignment: .trailing, spacing: DrivySpacing.s) {
                    if controller.displayedPointCount > 0 { mapControls(axis: .horizontal) }
                    observationNoticeView
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                // Le bandeau laisse aussi la ligne des mentions Apple Plans visible au bas de la carte.
                .alignmentGuide(.top) { $0[.bottom] + noticeSpacing }
            }
    }

    private var wideCommands: some View {
        VStack(spacing: DrivySpacing.s) {
            observationNoticeView
            commandPanel(floating: false)
        }
    }

    @ViewBuilder private func observationFeedback(_ recorder: SchoolLiveObservationRecorder) -> some View {
        if recorder.isSending {
            // L’envoi qui suit le geste est bref : seul un nouvel essai demandé nomme son attente dans le panneau.
            if observationNotice == nil, !recorder.isSettlingGesture { DrivyLoadingState(title: "Envoi de l’observation…") }
        }
        else if recorder.pending != nil {
            DrivyInlineMessage(text: recorder.errorMessage
                ?? (recorder.pendingIsForeign
                    ? "Une autre demande de l’école attend d’être vérifiée. Elle empêche de signaler pour l’instant."
                    : "Une observation attend son envoi."), tone: .warning)
            if recorder.canRetry {
                Button("Réessayer l’envoi", systemImage: "arrow.clockwise") { Task { await recorder.retry() } }
                    .buttonStyle(DrivySecondaryButtonStyle())
            } else {
                Button("Actualiser", systemImage: "arrow.clockwise") { recorder.refreshPending() }
                    .buttonStyle(DrivySecondaryButtonStyle())
            }
        } else if let error = recorder.errorMessage, !(observationNotice != nil && recorder.undoState == .refused) {
            // Un refus de l’école se lit déjà dans le bandeau du signalement : pas deux fois le même texte.
            DrivyInlineMessage(text: error, tone: .warning)
        }
    }

    /// Second rang : le geste qui n’est pas dominant (Pause en route, Signaler en pause) et « Terminer la leçon ».
    @ViewBuilder private func secondaryCommands(hugsFirst: Bool) -> some View {
        if shownState == .paused {
            if let recorder = controller.liveObservations {
                signalButton(recorder, isDominant: false)
                    .fixedSize(horizontal: hugsFirst, vertical: false)
            }
        } else {
            pauseButton
                .fixedSize(horizontal: hugsFirst, vertical: false)
        }
        Button {
            confirmsFinish = true
        } label: {
            Text("Terminer la leçon")
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
        }
        .buttonStyle(DrivySecondaryButtonStyle())
        .disabled(isFinishing || !controller.presentsStopEnabled)
        .accessibilityIdentifier("capture-finish-lesson")
    }

    /// L’apparence ne change pas pendant l’écriture de la pause ; un second appui reste sans effet,
    /// parce que `pause()` relit l’état réel.
    private var pauseButton: some View {
        let isSlow = controller.transition == .pausing && slowTransition == .pausing
        return Button {
            run(.pause)
        } label: {
            Label { Text("Pause") } icon: { commandIcon("pause.fill", isBusy: isSlow, tint: DrivyTheme.accent) }
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
        }
        .buttonStyle(DrivySecondaryButtonStyle())
        .disabled(!controller.presentsPauseEnabled)
        .accessibilityLabel("Mettre le GPS en pause")
        .accessibilityValue(isSlow ? "Mise en pause en cours" : "")
        .accessibilityIdentifier("school-capture-pause-resume")
    }

    /// La reprise est le prochain geste d’un trajet en pause : seule action principale. Elle garde son
    /// apparence pendant la relecture de l’école ; un second appui reste sans effet (`resume()` relit l’état).
    private var resumeButton: some View {
        let isSlow = controller.transition == .resuming && slowTransition == .resuming
        return Button {
            run(.resume)
        } label: {
            Label { Text("Reprendre") } icon: { commandIcon("play.fill", isBusy: isSlow, tint: DrivyTheme.onAccent) }
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
        }
        .buttonStyle(DrivyPrimaryButtonStyle(size: .field))
        .disabled(!controller.presentsResumeEnabled)
        .accessibilityLabel("Reprendre le GPS")
        .accessibilityValue(isSlow ? "Reprise en cours" : "")
        .accessibilityIdentifier("school-capture-pause-resume")
    }

    /// La reprise dépend d’une autorisation qui expire : elle seule est relue chaque seconde.
    private var resumeControls: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            VStack(alignment: .leading, spacing: DrivySpacing.s) {
                resumeButton
                if !controller.presentsResumeEnabled {
                    DrivyInlineMessage(text: "La reprise du GPS n’est plus autorisée. Tu peux arrêter le GPS et poursuivre la leçon.",
                        tone: .warning)
                }
            }
        }
    }

    /// L’icône d’une commande ne devient un indicateur que si son passage dure.
    @ViewBuilder private func commandIcon(_ symbol: String, isBusy: Bool, tint: Color) -> some View {
        if isBusy { ProgressView().tint(tint) } else { Image(systemName: symbol) }
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
            Button("Terminer la leçon") { confirmsFinish = true }
                .buttonStyle(DrivyPrimaryButtonStyle(size: .field)).disabled(isFinishing)
        }
    }

    private var lessonMenu: some View {
        Menu {
            Button("Voir la leçon", systemImage: "doc.text") { close() }
            if observationClient != nil {
                Button("Annuler la leçon", systemImage: "xmark.circle", role: .destructive) { openCancellation() }
                    .disabled(!controller.presentsStopEnabled && controller.state != .saved)
                    .accessibilityIdentifier("capture-cancel-lesson")
            }
        } label: {
            // La lecture de la leçon à annuler se signale là où le geste a eu lieu : le panneau reste en place.
            Group {
                if isOpeningCancellation {
                    ProgressView()
                } else {
                    Image(systemName: "ellipsis")
                        .font(DrivyMapGlyph.control)
                        .foregroundStyle(DrivyTheme.text)
                }
            }
            .frame(width: 48, height: 48)
            .background(DrivyTheme.surfaceMuted, in: Circle())
            .contentShape(Circle())
        }
        .disabled(isFinishing)
        .accessibilityLabel("Plus d’actions")
        .accessibilityValue(isOpeningCancellation ? "Ouverture de l’annulation" : "")
        .accessibilityIdentifier("capture-more")
    }

    private func openCancellation() {
        guard !isFinishing, !isOpeningCancellation, let client = observationClient?.agenda.planningClient else { return }
        isOpeningCancellation = true; cancellationError = nil
        Task { @MainActor in
            defer { isOpeningCancellation = false }
            do {
                let model = try await controller.cancellationWorkspace(client: client)
                // Un geste engagé pendant la lecture (fin de leçon, signalement) garde la main :
                // l’annulation ne s’ouvre pas par-dessus.
                guard !isFinishing, !confirmsFinish, observationMoment == nil else { return }
                cancellationModel = model
            }
            catch { cancellationError = (error as? LocalizedError)?.errorDescription ?? "Impossible d’ouvrir l’annulation. Vérifie la connexion et réessaie." }
        }
    }

    private func finishLesson() {
        guard !isFinishing, let lessonID = controller.lessonID, let captureID = controller.captureID,
              controller.presentsStopEnabled || controller.state == .saved else { return }
        isFinishing = true
        Task { @MainActor in
            let saved = await controller.stopAndSynchronize()
            isFinishing = false
            guard saved, controller.captureID == captureID, controller.lessonID == lessonID else { return }
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
        DrivyMapControls(followMode: $followMode, axis: axis) {
            followMode = .free
            resetCameraID = UUID()
        }
    }

    /// Same state vocabulary as the personal journey (« GPS actif », « En attente de position »).
    private var status: DrivyMapStatus {
        switch shownState {
        case .idle: DrivyMapStatus(title: "Aucun trajet en cours", symbol: "location.slash")
        case .preparing: DrivyMapStatus(title: "Préparation du GPS", symbol: "clock")
        case .recording:
            controller.displayedPointCount == 0
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
