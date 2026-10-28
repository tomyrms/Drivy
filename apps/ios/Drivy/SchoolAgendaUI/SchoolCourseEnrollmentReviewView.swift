import SwiftUI

enum SchoolCoursePresentation {
    static func nextOccurrence(_ series: SchoolCourseSeries, now: Date) -> SchoolCourseOccurrence? {
        series.occurrences.filter { ($0.end ?? .distantPast) > now }
            .min { ($0.start ?? .distantFuture) < ($1.start ?? .distantFuture) }
    }

    static func allAttendanceRequired(_ series: SchoolCourseSeries) -> Bool {
        !series.occurrences.isEmpty && series.occurrences.allSatisfy(\.attendanceRequired)
    }
}

/// Même présentation des dates dans la fiche et dans la confirmation, sans résumer les conditions acceptées.
struct SchoolCourseDatesContent: View {
    let series: SchoolCourseSeries
    let timeZone: String

    var body: some View {
        let allRequired = SchoolCoursePresentation.allAttendanceRequired(series)
        ForEach(series.occurrences.sorted { $0.position < $1.position }) { occurrence in
            VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                Text(SchoolPlanningFormat.interval(occurrence.startsAt, occurrence.endsAt, zone: timeZone))
                    .monospacedDigit().fixedSize(horizontal: false, vertical: true)
                if !allRequired && occurrence.attendanceRequired {
                    Text("Présence requise").font(.subheadline).foregroundStyle(DrivyTheme.muted)
                }
            }
            .accessibilityElement(children: .combine)
        }
        if allRequired {
            Text("Présence requise à chaque séance").font(.subheadline).foregroundStyle(DrivyTheme.muted)
        }
    }
}

struct SchoolCourseEnrollmentReview: Identifiable {
    let id = UUID()
    let action: SchoolCourseLearnerAction
    var title: String {
        if case .accept = action { return "Accepter la place" }
        return "Confirmer l’inscription"
    }

    func isAvailable(in me: SchoolCourseLearnerState?, now: Date = Date()) -> Bool {
        guard let me else { return false }
        switch action {
        case .enroll: return me.state == .available
        case .accept(let offerID): return me.state == .offered && me.offer?.id == offerID && (me.offer?.expiry ?? .distantPast) > now
        default: return false
        }
    }
}

/// L’action terminale suit toutes les dates et les conditions de la série réellement choisie.
struct SchoolCourseEnrollmentReviewView: View {
    @Bindable var model: SchoolCourseLearnerWorkspace
    let review: SchoolCourseEnrollmentReview
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if let error = model.errorMessage {
                    Section { DrivyFormMessage(text: error, tone: .danger) }.drivyFormRows()
                }
                if let series = model.series {
                    Section {
                        Text(series.title).font(.headline)
                        if !series.location.isEmpty { Text(series.location) }
                        if let language = SchoolCourseLanguage.phrase(for: series.teachingLanguage) { Text(language) }
                        Text("Inscription pour \(SchoolCourseEnrollmentFormat.sessions(series.occurrences.count)).")
                    }.drivyFormRows()
                    Section {
                        SchoolCourseDatesContent(series: series, timeZone: model.timeZone)
                        LabeledContent("Total", value: SchoolCourseFormat.duration(minutes: series.totalMinutes))
                    } header: { Text("Séances").drivyFormSectionHeader() }
                    .drivyFormRows()
                    Section {
                        Text("Paiement sur place")
                        if !series.conditions.isEmpty { Text(series.conditions).fixedSize(horizontal: false, vertical: true) }
                        if let deadline = SchoolLesson.date(series.selfCancellationDeadline) {
                            LabeledContent("Annulable jusqu’au") {
                                Text(SchoolCourseEnrollmentFormat.deadline(deadline, zone: model.timeZone)).multilineTextAlignment(.trailing)
                            }
                        }
                        if model.cancellationClosed() {
                            DrivyFormMessage(text: "Le délai d’annulation est passé : pour annuler, tu devras contacter l’école.", tone: .warning)
                        }
                        if case .accept = review.action, let expiry = model.me?.offer?.expiry {
                            LabeledContent("Place proposée jusqu’au") {
                                Text(SchoolCourseEnrollmentFormat.deadline(expiry, zone: model.timeZone)).multilineTextAlignment(.trailing)
                            }
                        }
                    } header: { Text("Conditions").drivyFormSectionHeader() }
                    .drivyFormRows()
                    Section {
                        // La demande part et la fiche du cours la suit : retour immédiat, sans faux « Inscrit ».
                        Button(review.title) {
                            model.submit(review.action)
                            dismiss()
                        }
                        .buttonStyle(DrivyPrimaryButtonStyle())
                        .disabled(model.isBusy || !review.isAvailable(in: model.me, now: model.serverNow))
                        .accessibilityIdentifier("course-confirm-enrollment")
                    }.drivyFormRows()
                }
            }
            .scrollContentBackground(.hidden)
            .frame(maxWidth: SchoolFormLayout.maxWidth).frame(maxWidth: .infinity).background(DrivyTheme.canvas)
            .navigationTitle("Vérifier l’inscription").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Retour") { dismiss() } } }
        }
        .tint(DrivyTheme.accent)
    }
}
