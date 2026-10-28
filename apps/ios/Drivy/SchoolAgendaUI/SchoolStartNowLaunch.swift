import Foundation
import Observation
import SwiftUI
import UIKit

/// Accord GPS de l’élève et état de cet appareil, lus dans le récapitulatif du démarrage immédiat.
/// La réponse donnée ici reste locale jusqu’à « Démarrer maintenant » : un oui effleuré n’est jamais enregistré.
/// Deux questions distinctes : l’accord de l’élève (l’enregistrement de son trajet) et l’autorisation de
/// localisation d’iOS (cet appareil). Aucune n’est jamais déduite de l’autre.
@MainActor @Observable final class SchoolStartNowGPS {
    enum Device: Equatable { case ready, needsPermission, denied, approximate }

    /// Ce que le récapitulatif doit montrer de l’accord GPS. Seul `.known` allège la présentation : la lecture en
    /// cours et la panne de lecture ne passent jamais pour une absence de choix ni pour un accord acquis.
    enum Display: Equatable {
        case reading, unavailable, needsReview, question
        case known(SchoolRecordingChoice.Status)

        static func resolve(hasNotice: Bool, isLoading: Bool, hasError: Bool, accessRevoked: Bool,
                            hasPendingOrOldScope: Bool, answer: SchoolRecordingChoice.Status?, isChanging: Bool) -> Display {
            if !hasNotice { return isLoading || !hasError ? .reading : .unavailable }
            if accessRevoked { return .unavailable }
            if hasPendingOrOldScope { return .needsReview }
            guard let answer, !isChanging else { return .question }
            return .known(answer)
        }
    }

    let learnerID: UUID
    let consent: SchoolRecordingChoiceWorkspace
    /// Réponse donnée dans le récapitulatif quand elle diffère du choix enregistré.
    private(set) var selection: SchoolRecordingChoice.Status?
    /// « Modifier le choix GPS » a été touché : la question se montre à nouveau, sans rien enregistrer.
    private(set) var isChanging = false
    private(set) var device: Device
    @ObservationIgnored let source: any SchoolCaptureLocationProviding
    @ObservationIgnored private var released = false

    init(learnerID: UUID, consent: SchoolRecordingChoiceWorkspace, source: any SchoolCaptureLocationProviding,
         scope: SchoolCommandScope) {
        self.learnerID = learnerID
        self.consent = consent
        self.source = source
        device = Self.device(of: source)
        source.updateScope(scope)
        source.onEvent = { [weak self] event in
            guard let self, case .diagnosticChanged = event else { return }
            // Retour des Réglages, réponse à l’alerte d’iOS : l’état de l’appareil se relit.
            self.device = Self.device(of: self.source)
            self.warmIfWanted()
        }
    }

    private static func device(of source: any SchoolCaptureLocationProviding) -> Device {
        switch source.permission {
        case .notDetermined: .needsPermission
        case .denied, .restricted: .denied
        case .foreground, .background: source.preciseLocation ? .ready : .approximate
        }
    }

    /// Choix enregistré qui vaut pour l’information actuelle de l’école ; `nil` : la question reste à poser.
    var recorded: SchoolRecordingChoice.Status? { consent.validAnswer }
    /// Ce qui vaudra au départ : la réponse donnée ici, sinon le choix enregistré.
    var answer: SchoolRecordingChoice.Status? { selection ?? recorded }
    /// Aucune demande d’accord en suspens ni droit retiré : sinon aucun trajet ne part d’ici.
    var consentIsClear: Bool {
        consent.notice != nil && !consent.needsReload && consent.relatedPending.isEmpty && !consent.hasOldScope
            && !consent.accessRevoked
    }
    /// L’accord se lit encore (ni réponse ni erreur), ou se relit : le départ attend, pour ne pas partir sans GPS
    /// par mégarde ni sur la foi d’un choix lu avant une relecture qui n’a pas abouti.
    var isReading: Bool {
        !consent.accessRevoked && consent.errorMessage == nil && (consent.notice == nil || consent.needsReload)
    }
    /// Un choix déjà lu ne vaut que tant que la dernière lecture a abouti. Pendant une relecture il reste affiché (pas de
    /// saut de mise en page), mais le départ attend ; une relecture échouée ne laisse plus rien d’acquis.
    var display: Display {
        .resolve(hasNotice: consent.notice != nil && (!consent.needsReload || consent.isLoading), isLoading: consent.isLoading,
            hasError: consent.errorMessage != nil,
            accessRevoked: consent.accessRevoked, hasPendingOrOldScope: !consent.relatedPending.isEmpty || consent.hasOldScope,
            answer: answer, isChanging: isChanging)
    }
    /// Le trajet est voulu et cet appareil peut l’enregistrer (l’autorisation d’iOS peut encore être demandée).
    var wantsTrip: Bool { answer == .allowed && consentIsClear && (device == .ready || device == .needsPermission) }

    func load() async {
        await consent.load()
        warmIfWanted()
    }

    /// Lecture interrompue (ni réponse ni panne) : à reprendre, jamais à prendre pour une absence de choix.
    var readWasInterrupted: Bool {
        !consent.isLoading && consent.errorMessage == nil && !consent.accessRevoked && consent.needsReload
    }

    /// Retour au premier plan : le choix a pu changer ailleurs (compte de l’élève, autre appareil). Il se relit, et
    /// ne vaut plus tant que la relecture n’a pas abouti. Aucune écriture, aucune collecte.
    func refresh() async {
        guard !released, !consent.isBusy, !consent.isLoading else { return }
        await load()
    }

    /// Rouvre la question pour changer d’avis ; rien n’est envoyé avant une réponse et « Démarrer ».
    func beginChanging() { isChanging = true }

    func select(_ status: SchoolRecordingChoice.Status) {
        isChanging = false
        selection = status == recorded ? nil : status
        warmIfWanted()
    }

    /// Le récepteur se réveille dès que le trajet est voulu et permis, pendant que le moniteur relit le
    /// récapitulatif : sa première position arrive plus tôt. Aucune coordonnée n’en est conservée.
    func warmIfWanted() {
        guard !released else { return }
        if answer == .allowed && device == .ready { source.warmUp() } else { source.coolDown() }
    }

    /// Demande l’autorisation d’iOS et attend la réponse de la personne (une minute au plus).
    func requestPermission() async {
        guard !released, source.permission == .notDetermined else { return }
        source.requestPermission()
        for _ in 0..<600 where source.permission == .notDetermined {
            do { try await Task.sleep(for: .milliseconds(100)) } catch { break }
        }
        device = Self.device(of: source)
        warmIfWanted()
    }

    /// Enregistre la réponse donnée ici quand elle change le choix de l’élève. Vrai quand l’école connaît le
    /// choix qui vaut au départ.
    func commit() async -> Bool {
        guard let selection, selection != recorded else { return recorded != nil }
        guard await consent.choose(selection) else { return false }
        let saved = recorded == selection
        if saved { self.selection = nil }
        return saved
    }

    /// Le récepteur passe, réveillé, à la préparation du trajet ; ce modèle ne le pilote plus.
    func handOver() -> any SchoolCaptureLocationProviding {
        released = true
        source.onEvent = nil
        return source
    }

    /// Récapitulatif quitté sans trajet : le récepteur s’arrête.
    func close() {
        guard !released else { return }
        released = true
        consent.invalidate()
        source.onEvent = nil
        source.updateScope(nil)
        source.stop()
    }
}

/// « Démarrer maintenant » de bout en bout, comme une seule interface : élève, récapitulatif et accord dans une
/// même feuille ; puis, avec GPS, le rideau de marque couvre l’enregistrement de l’accord et de la leçon, le
/// départ du trajet et sa première position ; sans GPS, la leçon s’ouvre à sa place dans la feuille.
/// Une seule exécution à la fois. Elle survit à l’écran d’où elle part : la carte du trajet remplace
/// « Aujourd’hui » dès que le départ est confirmé.
@MainActor @Observable final class SchoolStartNowLaunch: Identifiable {
    enum StartPolicy: String { case legacy = "LEGACY", gpsRequired = "GPS_REQUIRED" }
    enum Step: Equatable { case learner, summary, lesson(SchoolLesson) }
    enum Phase: Equatable { case editing, requestingPermission, creating, startingTrip, waitingForPosition, done }

    let id = UUID()
    let form: SchoolStartNowWorkspace
    private(set) var gps: SchoolStartNowGPS?
    private(set) var step: Step
    private(set) var phase: Phase = .editing
    /// Le trajet n’a pas démarré alors que la leçon existe : sa raison, au-dessus de la leçon.
    private(set) var tripIssue: String?
    /// Le trajet est à l’écran sous le rideau : la feuille se retire.
    private(set) var closesSheet = false
    /// Départs demandés : le retour haptique suit ce compteur.
    private(set) var launches = 0
    /// Lue même sans contrôleur ou module GPS : leur absence ne prouve jamais la politique LEGACY.
    private(set) var startPolicy: StartPolicy?
    private(set) var isReadingPolicy = false
    private(set) var policyError: String?

    @ObservationIgnored let agenda: SchoolAgendaClient
    @ObservationIgnored let workspace: SchoolWorkspace
    @ObservationIgnored let controller: SchoolCaptureSessionController?
    @ObservationIgnored private let makeLocationSource: @MainActor () -> any SchoolCaptureLocationProviding
    /// Fin du geste, une seule fois : l’écran d’origine se relit.
    @ObservationIgnored var onFinished: @MainActor () -> Void = {}
    @ObservationIgnored private var preparation: SchoolCapturePreparationWorkspace?
    @ObservationIgnored private var invalidated = false
    @ObservationIgnored private var completed = false
    @ObservationIgnored private var policyRequest = UUID()

    init(form: SchoolStartNowWorkspace, agenda: SchoolAgendaClient, workspace: SchoolWorkspace,
         controller: SchoolCaptureSessionController?,
         makeLocationSource: @escaping @MainActor () -> any SchoolCaptureLocationProviding = { SchoolCaptureLocationSource() }) {
        self.form = form
        self.agenda = agenda
        self.workspace = workspace
        self.controller = controller
        self.makeLocationSource = makeLocationSource
        // Élève imposé par sa fiche : le récapitulatif d’emblée, sans liste.
        step = form.presetLearnerID == nil ? .learner : .summary
    }

    /// Une étape du départ est en cours : la feuille ne se ferme pas et rien ne se modifie.
    var isBusy: Bool { (phase != .editing && phase != .done) || form.isBusy }
    /// Le libellé annonce le parcours qui partira : une question sans réponse ou un GPS indisponible
    /// ne doivent jamais se cacher derrière « Démarrer maintenant ».
    var startTitle: String { "Démarrer la leçon" }
    var requiresGPS: Bool { startPolicy == .gpsRequired || gps?.consent.notice?.requiresGPS == true }
    var canLaunch: Bool {
        phase == .editing && !invalidated && form.canStart && gps?.isReading != true && gpsMatchesLearner
            && startPolicy != nil && !isReadingPolicy && policyError == nil
            && (!requiresGPS || (tripAvailable && gps?.wantsTrip == true
                && gps?.consent.notice?.requiresGPS == true && gps?.consent.choice?.source == .own))
    }
    /// Le choix lu appartient bien à l’élève retenu : pendant un changement d’élève, rien du précédent ne vaut.
    var gpsMatchesLearner: Bool { gps.map { $0.learnerID == form.learnerID } ?? true }
    var gpsUnavailableReason: SchoolGPSUnavailableReason? {
        SchoolLessonHubRules.capturePreparationUnavailableReason(school: workspace.school,
            hasController: controller != nil, controllerCanPrepare: controller?.canPrepareCapture == true)
    }
    /// Le départ du trajet est en cours ou abouti : la chaîne se termine elle-même, l’écran d’origine ayant
    /// laissé place à la carte.
    var finishesItself: Bool { phase == .startingTrip || phase == .waitingForPosition || (phase == .done && closesSheet) }

    private static var stepMotion: Animation { DrivyMotion.step(UIAccessibility.isReduceMotionEnabled) }

    func open() async {
        guard !invalidated else { return }
        if form.learners.isEmpty { await reload() }
        else {
            await loadStartPolicy()
            if let learnerID = form.learnerID { prepareGPS(for: learnerID) }
        }
        guard !invalidated else { return }
        // Élève unique ou demande à résoudre : le récapitulatif, qui les montre.
        if step == .learner, form.learnerID != nil || form.pending != nil {
            withAnimation(Self.stepMotion) { step = .summary }
        }
    }

    /// Lecture (ou nouvel essai) de la feuille : l’accord GPS suit l’élève retenu, même choisi d’emblée.
    func reload() async {
        let policyRead = Task { await loadStartPolicy() }
        defer { policyRead.cancel() }
        // Élève imposé par sa fiche : son accord se lit pendant que la feuille se charge.
        if let preset = form.presetLearnerID { prepareGPS(for: preset) }
        await form.load()
        await policyRead.value
        guard !invalidated, let learnerID = form.learnerID else { return }
        prepareGPS(for: learnerID)
    }

    func choose(_ learnerID: UUID) {
        guard phase == .editing, !invalidated else { return }
        prepareGPS(for: learnerID)
        step = .summary
        Task { await form.select(learnerID) }
    }

    func changeLearner() {
        guard phase == .editing, !invalidated, form.presetLearnerID == nil else { return }
        step = .learner
    }

    func dismissTripIssue() { tripIssue = nil }

    /// Demande en file abandonnée, ou confirmée sans leçon à ouvrir ici : sans élève choisi, retour à la liste.
    func pendingCleared() {
        guard phase == .editing, !invalidated, form.pending == nil, form.learnerID == nil, !form.learners.isEmpty else { return }
        withAnimation(Self.stepMotion) { step = .learner }
    }

    /// Une demande restée en file est confirmée par l’école : la leçon s’ouvre, sans départ automatique.
    func resolved(_ lesson: SchoolLesson) {
        guard !invalidated else { return }
        gps?.close()
        showLesson(lesson)
    }

    func launch() {
        // Garde synchrone : un second appui, même avant le prochain rendu, ne lance rien.
        guard canLaunch else { return }
        phase = .creating
        launches += 1
        tripIssue = nil
        Task { await run() }
    }

    func complete() {
        guard !completed else { return }
        completed = true
        onFinished()
    }

    /// Feuille fermée : sans départ en cours, le récepteur réveillé pour le récapitulatif s’arrête.
    func sheetClosed() {
        if phase == .editing || phase == .done { gps?.close() }
    }

    func invalidate() {
        guard !invalidated else { return }
        invalidated = true
        policyRequest = UUID(); startPolicy = nil; isReadingPolicy = false
        form.invalidate()
        gps?.close()
        if phase == .startingTrip { preparation?.invalidate() }
        if phase != .editing && phase != .done { Task { await DrivyLaunchCurtain.shared.hide() } }
        phase = .done
    }

    // MARK: - Chaîne de départ

    /// Une lecture réussie de l’ancien contrat sans ce champ conserve LEGACY. Une panne ou une valeur
    /// inconnue bloque seulement ce nouveau départ ; les demandes déjà journalisées gardent leur reprise.
    func loadStartPolicy() async {
        guard !invalidated, phase == .editing else { return }
        let request = UUID(); policyRequest = request
        startPolicy = nil; policyError = nil; isReadingPolicy = true
        do {
            let notice = try await agenda.captureClient.recordingNotice(schoolID: form.scope.schoolID)
            guard !invalidated, request == policyRequest else { return }
            guard let value = StartPolicy(rawValue: notice.practicalStartPolicy ?? "LEGACY") else {
                throw SchoolCaptureFailure.invalidResponse
            }
            if let gps, let knownNotice = gps.consent.notice, knownNotice.requiresGPS != (value == .gpsRequired) {
                await gps.refresh()
                guard !invalidated, request == policyRequest else { return }
            }
            startPolicy = value
            isReadingPolicy = false
        } catch {
            guard !invalidated, request == policyRequest else { return }
            isReadingPolicy = false
            if let failure = error as? SchoolCaptureFailure, case .rejected(let message) = failure { policyError = message }
            else { policyError = "Les conditions de départ n’ont pas pu être vérifiées. Réessaie." }
        }
    }

    private func run() async {
        let curtain = DrivyLaunchCurtain.shared
        let tripWanted = gps?.wantsTrip == true
        var tripPlanned = tripWanted
        if tripPlanned, let gps, gps.device == .needsPermission {
            // L’alerte d’iOS passe avant le rideau, sur la feuille : elle ne coupe aucune animation.
            phase = .requestingPermission
            await gps.requestPermission()
            tripPlanned = gps.wantsTrip && gps.device == .ready
            phase = .creating
        }
        guard !invalidated else { return }
        if requiresGPS && !tripPlanned {
            tripIssue = "La localisation doit être autorisée pour démarrer la leçon dans Drivy."
            phase = .editing
            return
        }
        if tripPlanned {
            gps?.warmIfWanted()
            curtain.show()
        }
        // L’accord et la leçon s’enregistrent en même temps : aucun des deux n’attend l’autre.
        let consentSaved: Task<Bool, Never>? = gps.map { value in Task { @MainActor in await value.commit() } }
        let lesson = await form.start(prepareForGPS: requiresGPS)
        let consentReady = await consentSaved?.value ?? false
        guard !invalidated else { return }
        guard let lesson else {
            // Refus, conflit de planning ou réponse incertaine : la feuille les montre, rien n’est parti.
            phase = .editing
            if tripPlanned { await curtain.hide() }
            return
        }
        guard tripPlanned, consentReady, gps?.recorded == .allowed, mayStart(lesson), let gps else {
            gps?.close()
            if tripPlanned {
                tripIssue = consentReady ? "Le trajet n’a pas démarré. Vérifie la fiche de la leçon avant de réessayer."
                    : "L’accord GPS n’a pas pu être confirmé. Vérifie la fiche de la leçon."
            } else if tripWanted {
                // Localisation refusée à l’instant dans l’alerte d’iOS : l’accord de l’élève reste enregistré.
                tripIssue = "La localisation n’est pas autorisée pour Drivy. Vérifie la fiche de la leçon."
            }
            showLesson(lesson)
            if tripPlanned { await curtain.hide(afterSequence: true) }
            return
        }
        await startTrip(lesson, source: gps.handOver())
    }

    private func startTrip(_ lesson: SchoolLesson, source: any SchoolCaptureLocationProviding) async {
        let curtain = DrivyLaunchCurtain.shared
        guard let controller else {
            showLesson(lesson)
            await curtain.hide(afterSequence: true)
            return
        }
        phase = .startingTrip
        let result = await SchoolTripDeparture.run(lessonID: lesson.id, scope: form.scope, agenda: agenda,
            controller: controller, source: source, prepared: { preparation = $0 }, started: {
                // Trajet confirmé : la feuille se retire sous le rideau pendant l’attente de la première position.
                phase = .waitingForPosition
                closesSheet = true
            })
        guard !invalidated else { return }
        switch result {
        case .started:
            phase = .done
            complete()
        case .failed(let reason):
            // La leçon existe : elle s’ouvre dans la feuille, avec la raison. Aucune position n’est inventée.
            tripIssue = reason
            showLesson(lesson)
            await curtain.hide(afterSequence: true)
        }
    }

    private func showLesson(_ lesson: SchoolLesson) {
        phase = .done
        withAnimation(Self.stepMotion) { step = .lesson(lesson) }
    }

    private var tripAvailable: Bool {
        guard let controller, controller.canPrepareCapture, let school = workspace.school,
              school.status == "ACTIVE", school.modules.gpsEnabled,
              workspace.membership?.roles.contains("INSTRUCTOR") == true else { return false }
        return true
    }

    private func prepareGPS(for learnerID: UUID) {
        // Après activation du module sur le web, la même feuille peut préparer le GPS. Une désactivation
        // retire aussi le choix local avant le départ ; aucun collecteur n'est lancé par une relecture.
        guard tripAvailable else { gps?.close(); gps = nil; return }
        guard gps?.learnerID != learnerID else { return }
        gps?.close(); gps = nil
        guard tripAvailable, let controller else { return }
        let consent = SchoolRecordingChoiceWorkspace(scope: form.scope, lessonID: nil, learnerID: learnerID,
            client: agenda.captureClient, reader: agenda.reader, agenda: agenda,
            onRefusalConfirmed: { learner, lesson in controller.learnerRefused(learnerID: learner, lessonID: lesson) },
            journalProvider: { try await controller.journal() })
        let value = SchoolStartNowGPS(learnerID: learnerID, consent: consent, source: makeLocationSource(), scope: form.scope)
        gps = value
        Task { await value.load() }
    }

    /// De retour dans l’app, le choix GPS se relit sans rien écrire.
    func refreshConsent() {
        guard phase == .editing, !invalidated else { return }
        startPolicy = nil
        Task {
            await loadStartPolicy()
            await gps?.refresh()
        }
    }

    func refreshGPSAvailability() {
        guard phase == .editing, !invalidated, let learnerID = form.learnerID else { return }
        startPolicy = nil
        prepareGPS(for: learnerID)
        Task { await loadStartPolicy() }
    }

    private func mayStart(_ lesson: SchoolLesson) -> Bool {
        guard let controller else { return false }
        return SchoolLessonHubRules.mayStartCapture(lesson: lesson,
            isAuthor: lesson.instructorMembershipId == workspace.membership?.membershipId, school: workspace.school,
            capture: SchoolLessonCaptureStatus(controller: controller, lessonID: lesson.id),
            controllerCanPrepare: controller.canPrepareCapture, now: Date())
    }

    func learnerName(_ lesson: SchoolLesson) -> String {
        lesson.providedLearnerName
            ?? form.learners.first { $0.id == lesson.learnerId }?.displayName
            ?? workspace.learners.first { $0.id == lesson.learnerId }?.displayName
            ?? (workspace.learner?.id == lesson.learnerId ? workspace.learner?.displayName : nil) ?? "Leçon de conduite"
    }
}
