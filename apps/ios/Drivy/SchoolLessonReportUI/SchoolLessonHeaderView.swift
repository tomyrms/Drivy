import SwiftUI

/// En-tête de la fiche d’une leçon : l’élève (pour l’élève qui lit sa leçon : son moniteur), puis les faits de la
/// leçon et les messages de la fiche. Le même en tête d’une leçon planifiée (formulaire) et d’un récapitulatif.
/// Un enregistrement en cours se lit dans le bouton qui l’a lancé, pas dans une ligne qui décale la fiche.
struct SchoolLessonHeaderView: View {
    let model: SchoolLessonReportWorkspace
    let learnerName: String
    var finishError: String? = nil
    @Environment(\.schoolLearnerDossier) private var dossier
    @State private var openedLearner: OpenedLearner?

    private struct OpenedLearner: Identifiable { let id: UUID }

    private var identity: SchoolLessonHeaderIdentity? {
        SchoolLessonHubRules.headerIdentity(learnerName: learnerName, instructorName: model.lesson?.providedInstructorName,
            isOwnLearner: model.isOwnLearner, roles: model.membership.roles)
    }

    /// Le nom ouvre le dossier seulement pour l’équipe, quand l’en-tête nomme bien l’élève de la leçon et de
    /// cette école. Le serveur relit les droits à l’ouverture du dossier.
    private var dossierLearnerID: UUID? {
        guard let dossier, let lesson = model.lesson, !model.isOwnLearner,
              SchoolLessonHubRules.mayManage(model.membership.roles),
              lesson.schoolId == model.membership.schoolId, dossier.schoolID == lesson.schoolId else { return nil }
        return lesson.learnerId
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.s) {
            if identity != nil || model.lesson != nil {
                VStack(alignment: .leading, spacing: DrivySpacing.xs) {
                    if let identity { identityRow(identity) }
                    if let lesson = model.lesson { SchoolLessonFacts(model: model, lesson: lesson) }
                }
            }
            if model.isLoading && model.lesson == nil {
                DrivySkeletonRows(count: 4)
                    .drivySkeleton("Chargement de la leçon…")
            }
            if let error = model.errorMessage {
                SchoolErrorNotice(message: error, retry: model.isBusy || model.isLoading || model.isInvalidated ? nil : { Task { await model.load() } })
            }
            if let finishError { DrivyInlineMessage(text: finishError, tone: .danger) }
            if let message = model.confirmation { DrivyInlineMessage(text: message) }
            if let message = model.information { DrivyInlineMessage(text: message, tone: .neutral) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Feuille par-dessus la fiche : la leçon, son brouillon et le trajet restent en place derrière.
        .sheet(item: $openedLearner) { opened in
            if let dossier { dossier.make(opened.id) }
        }
    }

    @ViewBuilder private func identityRow(_ identity: SchoolLessonHeaderIdentity) -> some View {
        if let learnerID = dossierLearnerID {
            Button { dossier?.select(learnerID); openedLearner = OpenedLearner(id: learnerID) } label: {
                DrivyLearnerIdentity(name: identity.name, detail: identity.role, variant: .compact) {
                    DrivyRowChevron()
                }
                .frame(minHeight: DrivyLayout.tapTarget)
                .contentShape(Rectangle())
            }
            // Dans la ligne de formulaire de la fiche, seul le nom réagit : « Réessayer » plus bas garde son propre geste.
            .buttonStyle(.borderless)
            .tint(DrivyTheme.text)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Ouvrir le dossier de \(identity.name)")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("lesson-open-dossier")
        } else {
            DrivyLearnerIdentity(name: identity.name, detail: identity.role, variant: .compact)
        }
    }
}

/// Ouvre le dossier existant d’un élève à partir de son identifiant, pour l’école ouverte. Fourni par l’accueil
/// de l’équipe ; absent ailleurs (élève, aperçus), et le nom reste alors du texte.
struct SchoolLearnerDossierOpener {
    let schoolID: UUID
    /// Choisit l’élève avant la présentation : le dossier ne montre jamais, même un instant, l’élève précédent.
    let select: (UUID) -> Void
    let make: (UUID) -> AnyView
}

extension EnvironmentValues {
    @Entry var schoolLearnerDossier: SchoolLearnerDossierOpener? = nil
}

/// Faits de la leçon sous l’élève : son état s’il est inhabituel, quand, à quel prix, où, avec qui.
/// Du texte seul, sans symbole, pastille ni colonne de montants.
struct SchoolLessonFacts: View {
    let model: SchoolLessonReportWorkspace
    let lesson: SchoolLesson

    /// L’élève ne termine pas de leçon : dans sa fiche comme dans sa liste, une leçon restée sans résultat se lit
    /// « En attente », sans encre d’alerte.
    private var stateNote: DrivyRowNote? {
        let state = lesson.drivyState
        if model.isOwnLearner, state == .waiting || state == .toFinish {
            return DrivyRowNote(text: DrivyLessonState.waiting.title, tone: .neutral)
        }
        return state.rowNote
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
            // L’inhabituel (à terminer, annulée, absence) se lit en premier, du même mot que dans les listes :
            // du texte dans la hiérarchie, sans pastille. Planifiée, en cours ou terminée : rien, l’écran le dit déjà.
            if let note = stateNote {
                DrivyRowNoteText(note: note)
                    .accessibilityIdentifier("lesson-state")
            }
            SchoolLessonScheduleLines(lesson: lesson)
                .accessibilityElement(children: .combine)
            if let actual = SchoolLessonHubRules.actualSchedule(lesson) {
                SchoolLessonFactLine(text: actual, color: DrivyTheme.muted)
            }
            // Le prix suit l’horaire, réel s’il est affiché, prévu sinon : sa place ne dépend pas de l’état de la leçon.
            SchoolLessonPriceLines(model: model, lesson: lesson)
            if !lesson.meetingPoint.isEmpty {
                SchoolLessonFactLine(text: lesson.meetingPoint, color: DrivyTheme.muted)
            }
            if let instructor = SchoolLessonHubRules.instructorLine(instructorName: lesson.providedInstructorName,
                isAuthor: model.isAuthor, isOwnLearner: model.isOwnLearner, roles: model.membership.roles) {
                SchoolLessonFactLine(text: instructor, color: DrivyTheme.muted)
            }
        }
    }
}

/// Date et horaire. Ils tiennent sur une ligne quand la colonne le permet, sinon l’un sous l’autre :
/// l’intervalle horaire ne se coupe jamais entre ses deux heures.
private struct SchoolLessonScheduleLines: View {
    let lesson: SchoolLesson

    var body: some View {
        let schedule = SchoolLessonHubRules.schedule(lesson)?.replacingOccurrences(of: " – ", with: "\u{00A0}–\u{00A0}")
        let parts = schedule?.components(separatedBy: " · ") ?? []
        if let schedule {
            ViewThatFits(in: .horizontal) {
                SchoolLessonFactLine(text: schedule, color: DrivyTheme.text).fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                    ForEach(parts, id: \.self) { part in SchoolLessonFactLine(text: part, color: DrivyTheme.text) }
                }
            }
        }
    }
}

/// Une ligne de l’en-tête : l’horaire en encre pleine, le lieu et le prix en retrait.
struct SchoolLessonFactLine: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.subheadline)
            .monospacedDigit()
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Le prix se lit sous son intitulé ; il n’ouvre rien et ne promet aucun suivi.
struct SchoolLessonPriceLines: View {
    let model: SchoolLessonReportWorkspace
    let lesson: SchoolLesson

    var body: some View {
        ForEach(SchoolLessonHubRules.priceLines(lesson: lesson, account: model.account)) { line in
            let amount = SchoolCatalogFormatting.price(line.cents)
            SchoolLessonFactLine(text: "\(line.title)\u{00A0}: \(amount)", color: DrivyTheme.muted)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(line.title)
                .accessibilityValue(amount)
                .accessibilityIdentifier(line.kind == .agreed ? "lesson-tariff" : "lesson-balance")
        }
    }
}
