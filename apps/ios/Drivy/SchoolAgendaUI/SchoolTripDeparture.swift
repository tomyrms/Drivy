import Foundation
import SwiftUI
import UIKit

/// Départ du trajet d’une leçon déjà démarrée, sous le rideau de marque déjà montré : la préparation tourne sans
/// écran, ses étapes s’annoncent sur le rideau, puis le rideau se lève à la première position enregistrée (sept
/// secondes au plus). Un échec rend sa raison et laisse le rideau à l’appelant, qui ouvre la leçon dessous.
@MainActor enum SchoolTripDeparture {
    enum Result: Equatable { case started, failed(String) }

    /// `prepared` reçoit la préparation (pour l’invalider si la portée change) ; `started` est appelé dès que le
    /// trajet est confirmé, avant l’attente de la première position (la feuille d’origine peut alors se retirer).
    static func run(lessonID: UUID, scope: SchoolCommandScope, agenda: SchoolAgendaClient,
                    controller: SchoolCaptureSessionController, source: any SchoolCaptureLocationProviding,
                    prepared: (SchoolCapturePreparationWorkspace) -> Void = { _ in },
                    started: () -> Void = {}) async -> Result {
        let curtain = DrivyLaunchCurtain.shared
        // Le récepteur déjà réveillé passe tel quel à la préparation : pas de second démarrage.
        let prep = agenda.capturePreparation(scope: scope, lessonID: lessonID, controller: controller, source: source)
        prepared(prep)
        prep.onQuickStep = { step in
            curtain.step = step
            if step != nil { curtain.advanceStep() }
        }
        await waitUntilActive()
        let didStart = await prep.begin(reload: true)
        prep.onQuickStep = nil
        guard didStart else {
            let reason = issue(of: prep)
            // Plus de départ depuis cette préparation : le récepteur reçu réveillé s’arrête avec elle.
            prep.invalidate()
            return .failed(reason)
        }
        started()
        // La carte du trajet est déjà à l’écran, sous le rideau ; au-delà de sept secondes, elle montre sa recherche.
        await curtain.hide(afterSequence: true, waitingFor: { controller.pointCount > 0 }, atMost: 7)
        return .started
    }

    static func issue(of prep: SchoolCapturePreparationWorkspace) -> String {
        switch prep.quickBlock {
        case .failed(let message): message
        case .choice: "L’accord GPS de l’élève est à confirmer. La leçon continue sans GPS."
        case .refused: "L’élève a refusé l’enregistrement du trajet."
        case .permission: "Autorise la localisation pour enregistrer le trajet."
        case nil: prep.errorMessage ?? "Le trajet n’a pas démarré. La leçon continue sans GPS."
        }
    }

    /// Le trajet ne démarre qu’au premier plan : un départ interrompu par un appel attend le retour dans l’app.
    static func waitUntilActive() async {
        for _ in 0..<3000 where UIApplication.shared.applicationState != .active {
            do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
        }
    }
}

/// « Commencer la leçon » d’une leçon planifiée, quand rien n’est à demander : accord de l’élève déjà valable,
/// localisation et position exacte accordées. Le rideau couvre le début de la leçon (écriture durable), le départ
/// du trajet et sa première position, sans ouvrir la fiche entre-temps. Sinon, la fiche s’ouvre comme avant.
@MainActor enum SchoolPlannedStart {
    enum Outcome: Equatable { case trip, lesson(issue: String?) }

    /// Lecture seule : l’accord qui vaut pour cette leçon et l’information actuelle de l’école. Rien n’est écrit.
    static func consentAllows(_ lesson: SchoolLesson, scope: SchoolCommandScope, client: SchoolCaptureClient) async -> Bool {
        let notice = Task { @MainActor in try await client.recordingNotice(schoolID: scope.schoolID) }
        let choice = try? await client.recordingChoice(schoolID: scope.schoolID, learnerID: lesson.learnerId, lessonID: lesson.id)
        guard let current = try? await notice.value, let choice else { return false }
        return choice.status == .allowed && choice.noticeVersionId == current.noticeVersionId
    }

    static func run(lesson: SchoolLesson, membership: SchoolMembership, scope: SchoolCommandScope,
                    agenda: SchoolAgendaClient, controller: SchoolCaptureSessionController) async -> Outcome {
        let curtain = DrivyLaunchCurtain.shared
        // Le récepteur se réveille dès le geste : sa première position arrive pendant l’écriture du début de leçon.
        let source = SchoolCaptureLocationSource()
        source.updateScope(scope)
        source.warmUp()
        curtain.show()
        // Même file durable et même preuve d’opération que le bouton de la fiche ; aucun brouillon n’est touché.
        let report = SchoolLessonReportWorkspace(scope: scope, membership: membership, lessonID: lesson.id, client: agenda.reportClient)
        await report.load()
        let lessonStarted = await report.start()
        let reason = report.errorMessage
        report.invalidate()
        guard lessonStarted else {
            source.onEvent = nil
            source.updateScope(nil)
            source.stop()
            return .lesson(issue: reason ?? "La leçon n’a pas pu commencer. Réessaie depuis sa fiche.")
        }
        switch await SchoolTripDeparture.run(lessonID: lesson.id, scope: scope, agenda: agenda, controller: controller, source: source) {
        case .started: return .trip
        case .failed(let message): return .lesson(issue: message)
        }
    }
}

/// Raison d’un trajet qui n’a pas démarré, posée au-dessus de la leçon ouverte : la leçon continue, le message se masque.
struct SchoolTripIssueBanner: View {
    let text: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: DrivySpacing.xs) {
            DrivyInlineMessage(text: text, tone: .warning)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DrivyTheme.muted)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Masquer ce message")
        }
        .padding(.horizontal, DrivySpacing.m)
        .padding(.vertical, DrivySpacing.xs)
        .background(DrivyTheme.canvas)
        .accessibilityIdentifier("trip-issue")
    }
}
