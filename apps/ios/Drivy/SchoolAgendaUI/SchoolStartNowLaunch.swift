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

    let learnerID: UUID
    let consent: SchoolRecordingChoiceWorkspace
    /// Réponse donnée dans le récapitulatif quand elle diffère du choix enregistré.
    private(set) var selection: SchoolRecordingChoice.Status?
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
    var recorded: SchoolRecordingChoice.Status? {
        guard let choice = consent.choice, let notice = consent.notice,
              choice.noticeVersionId == notice.noticeVersionId, choice.status != .unknown else { return nil }
        return choice.status
    }
    /// Ce qui vaudra au départ : la réponse donnée ici, sinon le choix enregistré.
    var answer: SchoolRecordingChoice.Status? { selection ?? recorded }
    /// Aucune demande d’accord en suspens ni droit retiré : sinon aucun trajet ne part d’ici.
    var consentIsClear: Bool {
        consent.notice != nil && consent.relatedPending.isEmpty && !consent.hasOldScope && !consent.accessRevoked
    }
    /// L’accord se lit encore (ni réponse ni erreur) : le départ attend, pour ne pas partir sans GPS par mégarde.
    var isReading: Bool { consent.notice == nil && consent.errorMessage == nil && !consent.accessRevoked }
    /// Le trajet est voulu et cet appareil peut l’enregistrer (l’autorisation d’iOS peut encore être demandée).
    var wantsTrip: Bool { answer == .allowed && consentIsClear && (device == .ready || device == .needsPermission) }

    func load() async {
        await consent.load()
        warmIfWanted()
    }

    func select(_ status: SchoolRecordingChoice.Status) {
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

    @ObservationIgnored let agenda: SchoolAgendaClient
    @ObservationIgnored let workspace: SchoolWorkspace
    @ObservationIgnored let controller: SchoolCaptureSessionController?
    /// Fin du geste, une seule fois : l’écran d’origine se relit.
    @ObservationIgnored var onFinished: @MainActor () -> Void = {}
    @ObservationIgnored private var preparation: SchoolCapturePreparationWorkspace?
    @ObservationIgnored private var invalidated = false
    @ObservationIgnored private var completed = false

    init(form: SchoolStartNowWorkspace, agenda: SchoolAgendaClient, workspace: SchoolWorkspace,
         controller: SchoolCaptureSessionController?) {
        self.form = form
        self.agenda = agenda
        self.workspace = workspace
        self.controller = controller
        // Élève imposé par sa fiche : le récapitulatif d’emblée, sans liste.
        step = form.presetLearnerID == nil ? .learner : .summary
    }

    /// Une étape du départ est en cours : la feuille ne se ferme pas et rien ne se modifie.
    var isBusy: Bool { (phase != .editing && phase != .done) || form.isBusy }
    /// Le départ du trajet est en cours ou abouti : la chaîne se termine elle-même, l’écran d’origine ayant
    /// laissé place à la carte.
    var finishesItself: Bool { phase == .startingTrip || phase == .waitingForPosition || (phase == .done && closesSheet) }

    private static var stepMotion: Animation { DrivyMotion.step(UIAccessibility.isReduceMotionEnabled) }

    func open() async {
        guard !invalidated, form.learners.isEmpty else { return }
        await reload()
        guard !invalidated else { return }
        // Élève unique ou demande à résoudre : le récapitulatif, qui les montre.
        if step == .learner, form.learnerID != nil || form.pending != nil {
            withAnimation(Self.stepMotion) { step = .summary }
        }
    }

    /// Lecture (ou nouvel essai) de la feuille : l’accord GPS suit l’élève retenu, même choisi d’emblée.
    func reload() async {
        // Élève imposé par sa fiche : son accord se lit pendant que la feuille se charge.
        if let preset = form.presetLearnerID { prepareGPS(for: preset) }
        await form.load()
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
        guard phase == .editing, !invalidated, form.canStart else { return }
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
        form.invalidate()
        gps?.close()
        if phase == .startingTrip { preparation?.invalidate() }
        if phase != .editing && phase != .done { Task { await DrivyLaunchCurtain.shared.hide() } }
        phase = .done
    }

    // MARK: - Chaîne de départ

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
        if tripPlanned {
            gps?.warmIfWanted()
            curtain.show()
        }
        // L’accord et la leçon s’enregistrent en même temps : aucun des deux n’attend l’autre.
        let consentSaved: Task<Bool, Never>? = gps.map { value in Task { @MainActor in await value.commit() } }
        let lesson = await form.start()
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
                tripIssue = consentReady ? "Le trajet ne peut pas démarrer pour cette leçon. Elle continue sans GPS."
                    : "L’accord GPS n’a pas pu être enregistré. La leçon continue sans GPS."
            } else if tripWanted {
                // Localisation refusée à l’instant dans l’alerte d’iOS : l’accord de l’élève reste enregistré.
                tripIssue = "La localisation n’est pas autorisée pour Drivy. La leçon continue sans GPS."
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
        // Le récepteur réveillé depuis le récapitulatif passe tel quel à la préparation : pas de second démarrage.
        let prep = agenda.capturePreparation(scope: form.scope, lessonID: lesson.id, controller: controller, source: source)
        preparation = prep
        prep.onQuickStep = { step in
            curtain.step = step
            if step != nil { curtain.advanceStep() }
        }
        await waitUntilActive()
        let started = await prep.begin(reload: true)
        prep.onQuickStep = nil
        guard !invalidated else { return }
        if started {
            phase = .waitingForPosition
            closesSheet = true
            // La carte du trajet est déjà à l’écran, sous le rideau. Il se lève à la première position
            // enregistrée, sept secondes au plus ; au-delà, la carte montre sa recherche, discrètement.
            await curtain.hide(afterSequence: true, waitingFor: { controller.pointCount > 0 }, atMost: 7)
            phase = .done
            complete()
        } else {
            // La leçon existe : elle s’ouvre dans la feuille, avec la raison. Aucune position n’est inventée.
            tripIssue = Self.issue(of: prep)
            // Plus de départ depuis cette préparation : le récepteur reçu réveillé s’arrête avec elle.
            prep.invalidate()
            showLesson(lesson)
            await curtain.hide(afterSequence: true)
        }
    }

    private static func issue(of prep: SchoolCapturePreparationWorkspace) -> String {
        switch prep.quickBlock {
        case .failed(let message): message
        case .choice: "L’accord GPS de l’élève est à confirmer. La leçon continue sans GPS."
        case .refused: "L’élève a refusé l’enregistrement du trajet."
        case .permission: "Autorise la localisation pour enregistrer le trajet."
        case nil: prep.errorMessage ?? "Le trajet n’a pas démarré. La leçon continue sans GPS."
        }
    }

    private func showLesson(_ lesson: SchoolLesson) {
        phase = .done
        withAnimation(Self.stepMotion) { step = .lesson(lesson) }
    }

    /// Le trajet ne démarre qu’au premier plan : un départ lancé puis interrompu par un appel attend le retour.
    private func waitUntilActive() async {
        for _ in 0..<3000 where UIApplication.shared.applicationState != .active {
            do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
        }
    }

    private var tripAvailable: Bool {
        guard let controller, controller.canPrepareCapture, let school = workspace.school,
              school.status == "ACTIVE", school.modules.gpsEnabled,
              workspace.membership?.roles.contains("INSTRUCTOR") == true else { return false }
        return true
    }

    private func prepareGPS(for learnerID: UUID) {
        guard gps?.learnerID != learnerID else { return }
        gps?.close(); gps = nil
        guard tripAvailable, let controller else { return }
        let consent = SchoolRecordingChoiceWorkspace(scope: form.scope, lessonID: nil, learnerID: learnerID,
            client: agenda.captureClient, reader: agenda.reader, agenda: agenda,
            onRefusalConfirmed: { learner, lesson in controller.learnerRefused(learnerID: learner, lessonID: lesson) },
            journalProvider: { try await controller.journal() })
        let value = SchoolStartNowGPS(learnerID: learnerID, consent: consent, source: SchoolCaptureLocationSource(), scope: form.scope)
        gps = value
        Task { await value.load() }
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
