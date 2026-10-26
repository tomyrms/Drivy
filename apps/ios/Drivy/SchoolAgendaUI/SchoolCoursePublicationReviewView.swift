import SwiftUI

/// Une seule liste complète des dates au moment de publier, après l’édition compacte des séances.
struct SchoolCoursePublicationReviewView: View {
    @Bindable var model: SchoolCourseEditorWorkspace
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if let message = model.errorMessage {
                    Section { DrivyFormMessage(text: message, tone: .danger) }.drivyFormRows()
                }
                Section {
                    Text(model.form.title).font(.headline)
                    if !model.form.location.isEmpty { Label(model.form.location, systemImage: "mappin.and.ellipse") }
                    if !model.form.description.isEmpty { Text(model.form.description).fixedSize(horizontal: false, vertical: true) }
                    LabeledContent("Places", value: "\(model.form.capacity)")
                    if let minimum = model.form.minParticipants { LabeledContent("Minimum", value: "\(minimum)") }
                }.drivyFormRows()
                Section {
                    ForEach(model.form.sortedOccurrences) { occurrence in
                        VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                            Text(SchoolPlanningFormat.instant(occurrence.startsAt, zone: model.timeZone) + " – "
                                 + SchoolDateFormat.time(occurrence.endsAt, zone: model.timeZone)).monospacedDigit()
                            if let instructor = model.instructors.first(where: { $0.membershipId == occurrence.instructorID }) {
                                Text(instructor.displayName).foregroundStyle(DrivyTheme.muted)
                            }
                            if occurrence.attendanceRequired { Text("Présence requise").font(.subheadline).foregroundStyle(DrivyTheme.muted) }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityElement(children: .combine)
                    }
                    LabeledContent("Total", value: SchoolCourseFormat.duration(minutes: model.form.totalMinutes))
                } header: { Text("Séances").drivyFormSectionHeader() }
                .drivyFormRows()
                Section {
                    Text(SchoolCourseFormat.cancellationSentence(hours: model.selfCancelHours))
                    if !model.form.conditions.isEmpty { Text(model.form.conditions).fixedSize(horizontal: false, vertical: true) }
                } header: { Text("Conditions").drivyFormSectionHeader() }
                .drivyFormRows()
                Section {
                    Button("Publier le cours") { Task { await model.publish() } }
                        .buttonStyle(DrivyPrimaryButtonStyle()).disabled(!model.canPublish)
                        .accessibilityIdentifier("course-confirm-publication")
                    if model.isBusy { ProgressView().accessibilityLabel("Publication en cours") }
                }.drivyFormRows()
            }
            .scrollContentBackground(.hidden)
            .frame(maxWidth: SchoolFormLayout.maxWidth).frame(maxWidth: .infinity).background(DrivyTheme.canvas)
            .navigationTitle("Vérifier le cours").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Retour") { dismiss() }.disabled(model.isBusy) } }
            .onChange(of: model.finished) { _, value in if value != nil { dismiss() } }
        }
        .interactiveDismissDisabled(model.isBusy)
        .tint(DrivyTheme.accent)
    }
}
