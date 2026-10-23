import SwiftUI
import UIKit

/// Créer ou reprendre un brouillon de cours collectif, puis le publier.
struct SchoolCourseEditorView: View {
    @Bindable var model: SchoolCourseEditorWorkspace
    var onFinished: @MainActor (SchoolCourseSeries) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var addsType = false
    private static let errorAnchor = "course-error"

    private var zone: TimeZone { TimeZone(identifier: model.timeZone) ?? .current }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scroll in
                Form {
                    if let message = model.errorMessage {
                        Section { DrivyFormMessage(text: message, tone: .danger) }
                            .drivyFormRows().id(Self.errorAnchor)
                    }
                    if model.catalogue == nil {
                        if model.isLoading { Section { DrivyLoadingState(title: "Chargement…") }.drivyFormRows() }
                    } else {
                        courseFields
                        occurrenceFields
                        summaryFields
                        if typeSize.isAccessibilitySize { Section { actions }.drivyFormRows() }
                    }
                }
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .frame(maxWidth: SchoolFormLayout.maxWidth).frame(maxWidth: .infinity).background(DrivyTheme.canvas)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if !typeSize.isAccessibilitySize && model.catalogue != nil { DrivyStickyActionBar { actions } }
                }
                .environment(\.timeZone, zone)
                .environment(\.locale, Locale(identifier: "fr_CH"))
                .navigationTitle(model.isNew ? "Cours collectif" : "Brouillon").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() }.disabled(model.isBusy) }
                    if model.catalogue != nil && model.isLoading {
                        ToolbarItem(placement: .primaryAction) { ProgressView().accessibilityLabel("Actualisation") }
                    }
                }
                .task { await model.load() }
                .onChange(of: model.errorMessage) { _, message in
                    guard let message else { return }
                    scroll.scrollTo(Self.errorAnchor, anchor: .top)
                    UIAccessibility.post(notification: .announcement, argument: message)
                }
                .onChange(of: model.finished) { _, series in
                    guard let series else { return }
                    onFinished(series)
                    dismiss()
                }
                .alert("Nouveau type", isPresented: $addsType) {
                    TextField("Nom du type", text: $model.newTypeTitle)
                    Button("Créer") { Task { await model.createType() } }
                    Button("Annuler", role: .cancel) { model.newTypeTitle = "" }
                }
            }
        }
        .interactiveDismissDisabled(model.isBusy)
        .tint(DrivyTheme.accent)
    }

    @ViewBuilder private var courseFields: some View {
        Section {
            Picker("Type", selection: $model.form.typeID) {
                ForEach(model.types) { type in Text(type.title).tag(Optional(type.id)) }
            }
            .accessibilityIdentifier("course-type")
            Button { addsType = true } label: { Label("Nouveau type", systemImage: "plus") }
                .disabled(model.isBusy)
                .accessibilityIdentifier("course-new-type")
            TextField("Titre", text: $model.form.title)
                .accessibilityIdentifier("course-title")
            TextField("Description", text: $model.form.description, axis: .vertical)
                .lineLimit(2...6)
            TextField("Lieu", text: $model.form.location, axis: .vertical)
                .lineLimit(1...3)
                .textContentType(.fullStreetAddress)
            Picker("Responsable", selection: $model.form.responsibleID) {
                if !model.instructors.contains(where: { $0.membershipId == model.form.responsibleID }), let id = model.form.responsibleID {
                    Text(responsibleName(id)).tag(Optional(id))
                }
                ForEach(model.instructors) { person in Text(person.displayName).tag(Optional(person.membershipId)) }
            }
        } header: { Text("Cours").drivyFormSectionHeader() }
            .drivyFormRows()
        Section {
            Stepper(value: $model.form.capacity, in: 1...200) {
                LabeledContent("Places") { Text("\(model.form.capacity)").monospacedDigit() }
            }
            .accessibilityValue("\(model.form.capacity) places")
            Toggle("Minimum de participants", isOn: Binding(
                get: { model.form.minParticipants != nil },
                set: { model.form.minParticipants = $0 ? min(model.form.capacity, max(1, model.form.minParticipants ?? 4)) : nil }))
                .drivyControlTint()
            if let minimum = model.form.minParticipants {
                Stepper(value: Binding(get: { minimum }, set: { model.form.minParticipants = $0 }), in: 1...max(1, model.form.capacity)) {
                    LabeledContent("Minimum") { Text("\(minimum)").monospacedDigit() }
                }
                .accessibilityValue("\(minimum) participants")
            }
            TextField("Conditions", text: $model.form.conditions, axis: .vertical)
                .lineLimit(2...6)
        } header: { Text("Inscriptions").drivyFormSectionHeader() }
            .drivyFormRows()
    }

    @ViewBuilder private var occurrenceFields: some View {
        let count = model.form.occurrences.count
        ForEach(Array(model.form.occurrences.enumerated()), id: \.element.id) { index, occurrence in
            Section {
                DatePicker("Début", selection: startBinding(occurrence.id), displayedComponents: [.date, .hourAndMinute])
                DatePicker("Fin", selection: binding(occurrence.id, \.endsAt, occurrence.endsAt), in: occurrence.startsAt...,
                           displayedComponents: [.date, .hourAndMinute])
                Picker("Moniteur", selection: binding(occurrence.id, \.instructorID, occurrence.instructorID)) {
                    if occurrence.instructorID == nil { Text("À choisir").tag(UUID?.none) }
                    ForEach(model.instructors) { person in Text(person.displayName).tag(Optional(person.membershipId)) }
                }
                Toggle("Présence obligatoire", isOn: binding(occurrence.id, \.attendanceRequired, occurrence.attendanceRequired))
                    .drivyControlTint()
                if count > 1 {
                    Button(role: .destructive) { model.removeOccurrence(occurrence.id) } label: {
                        Label("Retirer la séance", systemImage: "minus.circle")
                    }
                    .disabled(model.isBusy)
                    .accessibilityLabel("Retirer la séance \(index + 1)")
                }
            } header: { Text("Séance \(index + 1)").drivyFormSectionHeader() }
                .drivyFormRows()
        }
        .datePickerStyle(.compact)
        .drivyControlTint()
        Section {
            Button { model.addOccurrence() } label: { Label("Ajouter une séance", systemImage: "plus") }
                .disabled(model.isBusy || count >= SchoolCourseForm.maximumOccurrences)
                .accessibilityIdentifier("course-add-occurrence")
        }
        .drivyFormRows()
    }

    @ViewBuilder private var summaryFields: some View {
        let sessions = model.form.sortedOccurrences
        Section {
            ForEach(sessions) { occurrence in
                Text(SchoolPlanningFormat.instant(occurrence.startsAt, zone: model.timeZone) + " – "
                     + SchoolDateFormat.time(occurrence.endsAt, zone: model.timeZone))
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }
            LabeledContent("Total") { Text(SchoolCourseFormat.duration(minutes: model.form.totalMinutes)).monospacedDigit() }
            Text(SchoolCourseFormat.cancellationSentence(hours: model.selfCancelHours))
                .font(.subheadline)
                .foregroundStyle(DrivyTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        } header: { Text("Aperçu").drivyFormSectionHeader() }
            .drivyFormRows()
    }

    @ViewBuilder private var actions: some View {
        if let problem = model.publishProblem, !model.isBusy {
            DrivyActionNote(text: problem, isError: model.problem != nil)
        }
        Button {
            Task { await model.publish() }
        } label: {
            HStack(spacing: DrivySpacing.xs) {
                if model.isBusy { ProgressView().tint(DrivyTheme.disabledText).accessibilityHidden(true) }
                Text("Publier")
            }
        }
        .buttonStyle(DrivyPrimaryButtonStyle())
        .disabled(!model.canPublish)
        .accessibilityValue(model.isBusy ? "Envoi en cours" : "")
        .accessibilityIdentifier("course-publish")
        Button("Enregistrer le brouillon") { Task { await model.saveDraft() } }
            .buttonStyle(DrivySecondaryButtonStyle())
            .disabled(!model.canSave)
            .accessibilityIdentifier("course-save-draft")
    }

    /// Liaison par identifiant : une séance retirée ne laisse pas d’index périmé.
    private func binding<Value>(_ id: UUID, _ path: WritableKeyPath<SchoolCourseOccurrenceDraft, Value>, _ fallback: Value) -> Binding<Value> {
        Binding(
            get: { model.form.occurrences.first { $0.id == id }?[keyPath: path] ?? fallback },
            set: { value in
                guard let index = model.form.occurrences.firstIndex(where: { $0.id == id }) else { return }
                model.form.occurrences[index][keyPath: path] = value
            })
    }
    /// La fin suit le début : la durée choisie est gardée.
    private func startBinding(_ id: UUID) -> Binding<Date> {
        Binding(
            get: { model.form.occurrences.first { $0.id == id }?.startsAt ?? Date() },
            set: { value in
                guard let index = model.form.occurrences.firstIndex(where: { $0.id == id }) else { return }
                let shift = value.timeIntervalSince(model.form.occurrences[index].startsAt)
                model.form.occurrences[index].startsAt = value
                model.form.occurrences[index].endsAt = model.form.occurrences[index].endsAt.addingTimeInterval(shift)
            })
    }

    private func responsibleName(_ id: UUID) -> String {
        if let series = model.series, series.responsibleMembershipId == id, !series.responsibleDisplayName.isEmpty { return series.responsibleDisplayName }
        return "Moi"
    }
}

/// Fiche d’un cours publié : dates, places restantes et changement de capacité.
struct SchoolCourseDetailView: View {
    @Bindable var model: SchoolCourseDetailWorkspace
    let timeZone: String
    @Environment(\.dismiss) private var dismiss

    private var series: SchoolCourseSeries { model.series }

    var body: some View {
        NavigationStack {
            Form {
                if let message = model.errorMessage {
                    Section { DrivyFormMessage(text: message, tone: .danger) }.drivyFormRows()
                }
                Section {
                    LabeledContent("Type", value: series.typeTitle)
                    if !series.location.isEmpty { LabeledContent("Lieu", value: series.location) }
                    if !series.responsibleDisplayName.isEmpty { LabeledContent("Responsable", value: series.responsibleDisplayName) }
                    if series.status != .published { LabeledContent("État", value: statusTitle) }
                } header: { Text(series.title).drivyFormSectionHeader() }
                    .drivyFormRows()
                Section {
                    ForEach(series.occurrences.sorted { $0.position < $1.position }) { occurrence in
                        VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                            Text(SchoolPlanningFormat.interval(occurrence.startsAt, occurrence.endsAt, zone: timeZone)).monospacedDigit()
                            if !occurrence.instructorDisplayName.isEmpty {
                                Text(occurrence.instructorDisplayName).font(.subheadline).foregroundStyle(DrivyTheme.muted)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                    LabeledContent("Total") { Text(SchoolCourseFormat.duration(minutes: series.totalMinutes)).monospacedDigit() }
                    Text(SchoolCourseFormat.cancellationSentence(hours: series.selfCancelHours))
                        .font(.subheadline).foregroundStyle(DrivyTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                } header: { Text("Séances").drivyFormSectionHeader() }
                    .drivyFormRows()
                Section {
                    LabeledContent("Places restantes") { Text(SchoolCourseFormat.seats(series.remainingSeats)).monospacedDigit() }
                    if series.canManage && series.status == .published {
                        Stepper(value: $model.capacity, in: model.minimumCapacity...200) {
                            LabeledContent("Capacité") { Text("\(model.capacity)").monospacedDigit() }
                        }
                        .accessibilityValue("\(model.capacity) places")
                        .disabled(model.isBusy)
                        Button {
                            Task { await model.changeCapacity() }
                        } label: {
                            HStack(spacing: DrivySpacing.xs) {
                                if model.isBusy { ProgressView().accessibilityHidden(true) }
                                Text("Changer la capacité")
                            }
                        }
                        .disabled(!model.canChangeCapacity)
                        .accessibilityIdentifier("course-change-capacity")
                    } else {
                        LabeledContent("Capacité") { Text("\(series.capacity)").monospacedDigit() }
                    }
                } header: { Text("Inscriptions").drivyFormSectionHeader() }
                    .drivyFormRows()
                if let roster = model.roster { SchoolCourseRosterSection(model: roster) }
            }
            .scrollContentBackground(.hidden)
            .frame(maxWidth: SchoolFormLayout.maxWidth).frame(maxWidth: .infinity).background(DrivyTheme.canvas)
            .navigationTitle("Cours collectif").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() }.disabled(model.isBusy) } }
            .task { await model.refresh() }
            .onChange(of: model.errorMessage) { _, message in
                if let message { UIAccessibility.post(notification: .announcement, argument: message) }
            }
        }
        .interactiveDismissDisabled(model.isBusy)
        .tint(DrivyTheme.accent)
    }

    private var statusTitle: String {
        switch series.status {
        case .draft: "Brouillon"
        case .published: "Publié"
        case .cancelled: "Annulé"
        case .closed: "Clos"
        }
    }
}
