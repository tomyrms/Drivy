import SwiftUI

/// En-tête de la fiche d’une leçon : l’élève (pour l’élève qui lit sa leçon : son moniteur), puis les faits de la
/// leçon et les messages de la fiche. Le même en tête d’une leçon planifiée (formulaire) et d’un récapitulatif.
/// Un enregistrement en cours se lit dans le bouton qui l’a lancé, pas dans une ligne qui décale la fiche.
struct SchoolLessonHeaderView: View {
    let model: SchoolLessonReportWorkspace
    let learnerName: String
    var finishError: String? = nil
    /// Le prix suit le lieu sur une leçon planifiée ; le récapitulatif le range à la fin de la page.
    var showsPrices = true

    private var identity: SchoolLessonHeaderIdentity? {
        SchoolLessonHubRules.headerIdentity(learnerName: learnerName, instructorName: model.lesson?.providedInstructorName,
            isOwnLearner: model.isOwnLearner, roles: model.membership.roles)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.s) {
            if identity != nil || model.lesson != nil {
                VStack(alignment: .leading, spacing: DrivySpacing.xs) {
                    if let identity { DrivyLearnerIdentity(name: identity.name, detail: identity.role, variant: .compact) }
                    if let lesson = model.lesson { SchoolLessonFacts(model: model, lesson: lesson, showsPrices: showsPrices) }
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
    }
}

/// Faits de la leçon sous l’élève : son état s’il est inhabituel, quand, où, avec qui, à quel prix.
/// Du texte seul, sans symbole, pastille ni colonne de montants.
struct SchoolLessonFacts: View {
    let model: SchoolLessonReportWorkspace
    let lesson: SchoolLesson
    var showsPrices = true

    var body: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
            // L’inhabituel (à terminer, annulée, absence) se lit en premier, du même mot que dans les listes :
            // du texte dans la hiérarchie, sans pastille. Planifiée, en cours ou terminée : rien, l’écran le dit déjà.
            if let note = lesson.drivyState.rowNote {
                DrivyRowNoteText(note: note)
                    .accessibilityIdentifier("lesson-state")
            }
            SchoolLessonScheduleLines(lesson: lesson)
                .accessibilityElement(children: .combine)
            if let actual = SchoolLessonHubRules.actualSchedule(lesson) {
                SchoolLessonFactLine(text: actual, color: DrivyTheme.muted)
            }
            if let instructor = SchoolLessonHubRules.instructorLine(instructorName: lesson.providedInstructorName,
                isAuthor: model.isAuthor, isOwnLearner: model.isOwnLearner, roles: model.membership.roles) {
                SchoolLessonFactLine(text: instructor, color: DrivyTheme.muted)
            }
            if showsPrices { SchoolLessonPriceLines(model: model, lesson: lesson) }
        }
    }
}

/// Date, horaire et lieu. La date et l’horaire tiennent sur une ligne quand la colonne le permet, sinon l’un
/// sous l’autre : l’intervalle horaire ne se coupe jamais entre ses deux heures. Le lieu passe à la ligne seul.
private struct SchoolLessonScheduleLines: View {
    let lesson: SchoolLesson

    var body: some View {
        let schedule = SchoolLessonHubRules.schedule(lesson)?.replacingOccurrences(of: " – ", with: "\u{00A0}–\u{00A0}")
        let parts = schedule?.components(separatedBy: " · ") ?? []
        VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
            if let schedule {
                ViewThatFits(in: .horizontal) {
                    SchoolLessonFactLine(text: schedule, color: DrivyTheme.text).fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                        ForEach(parts, id: \.self) { part in SchoolLessonFactLine(text: part, color: DrivyTheme.text) }
                    }
                }
            }
            if !lesson.meetingPoint.isEmpty { SchoolLessonFactLine(text: lesson.meetingPoint, color: DrivyTheme.muted) }
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
