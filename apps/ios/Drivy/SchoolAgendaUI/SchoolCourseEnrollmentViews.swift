import SwiftUI
import UIKit

/// Fiche d’un cours vue par l’élève : statut, séances et commandes.
struct SchoolCourseLearnerView: View {
    @Bindable var model: SchoolCourseLearnerWorkspace
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var confirmsEnroll = false
    @State private var confirmsAccept = false
    @State private var confirmsCancel = false

    private var zone: String { model.timeZone }

    var body: some View {
        NavigationStack {
            Form {
                if let message = model.errorMessage {
                    Section { DrivyFormMessage(text: message, tone: .danger) }.drivyFormRows()
                }
                if let confirmation = model.confirmation {
                    Section { DrivyFormMessage(text: confirmation, tone: .success) }.drivyFormRows()
                }
                if let series = model.series, let me = model.me {
                    content(series, me)
                } else if model.isLoading || model.errorMessage == nil {
                    Section { DrivyLoadingState(title: "Chargement…") }.drivyFormRows()
                } else {
                    Section { Button("Réessayer") { Task { await model.load() } } }.drivyFormRows()
                }
            }
            .scrollContentBackground(.hidden)
            .frame(maxWidth: SchoolFormLayout.maxWidth).frame(maxWidth: .infinity).background(DrivyTheme.canvas)
            .navigationTitle("Cours collectif").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() }.disabled(model.isBusy) } }
            .task { await model.load() }
            .refreshable { await model.load() }
            .onChange(of: model.errorMessage) { _, message in
                if let message { UIAccessibility.post(notification: .announcement, argument: message) }
            }
            .onChange(of: model.confirmation) { _, message in
                if let message { UIAccessibility.post(notification: .announcement, argument: message) }
            }
            .confirmationDialog(enrollTitle, isPresented: $confirmsEnroll, titleVisibility: .visible) {
                Button("S’inscrire") { Task { await model.perform(.enroll) } }
                Button("Annuler", role: .cancel) {}
            }
            .confirmationDialog(enrollTitle, isPresented: $confirmsAccept, titleVisibility: .visible) {
                if let offer = model.me?.offer {
                    Button("Accepter la place") { Task { await model.perform(.accept(offerID: offer.id)) } }
                }
                Button("Annuler", role: .cancel) {}
            } message: {
                if model.cancellationClosed() { Text("Le délai d’annulation est passé : tu ne pourras plus annuler toi-même.") }
            }
            .confirmationDialog("Annuler l’inscription ?", isPresented: $confirmsCancel, titleVisibility: .visible) {
                if let enrollment = model.me?.enrollment {
                    Button("Annuler l’inscription", role: .destructive) {
                        Task { await model.perform(.cancel(enrollmentID: enrollment.id, version: enrollment.version)) }
                    }
                }
                Button("Garder", role: .cancel) {}
            } message: { Text("Toutes les séances sont annulées.") }
        }
        .interactiveDismissDisabled(model.isBusy)
        .tint(DrivyTheme.accent)
    }

    /// L’inscription couvre toutes les dates : la confirmation le rappelle.
    private var enrollTitle: String {
        "L’inscription couvre \(SchoolCourseEnrollmentFormat.sessions(model.series?.occurrences.count ?? 1))."
    }

    @ViewBuilder private func content(_ series: SchoolCourseSeries, _ me: SchoolCourseLearnerState) -> some View {
        Section {
            LabeledContent("Statut") {
                Text(SchoolCourseEnrollmentFormat.status(me, zone: zone)).fontWeight(.semibold).multilineTextAlignment(.trailing)
            }
            .accessibilityIdentifier("course-learner-status")
            if !series.location.isEmpty { LabeledContent("Lieu", value: series.location) }
            if me.state == .available || me.state == .full {
                LabeledContent("Places restantes") { Text(SchoolCourseFormat.seats(series.remainingSeats)).monospacedDigit() }
            }
            LabeledContent("Paiement", value: "Sur place")
            if !series.conditions.isEmpty {
                Text(series.conditions).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            }
        } header: { Text(series.title).drivyFormSectionHeader() }
            .drivyFormRows()
        Section {
            ForEach(series.occurrences.sorted { $0.position < $1.position }) { occurrence in
                VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                    Text(SchoolPlanningFormat.interval(occurrence.startsAt, occurrence.endsAt, zone: zone)).monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                    if occurrence.attendanceRequired {
                        Text("Présence obligatoire").font(.subheadline).foregroundStyle(DrivyTheme.muted)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            LabeledContent("Total") { Text(SchoolCourseFormat.duration(minutes: series.totalMinutes)).monospacedDigit() }
            if let deadline = me.enrollment?.deadline ?? SchoolLesson.date(series.selfCancellationDeadline) {
                LabeledContent("Annulation libre jusqu’au") {
                    Text(SchoolCourseEnrollmentFormat.deadline(deadline, zone: zone)).multilineTextAlignment(.trailing)
                }
                .accessibilityIdentifier("course-cancel-deadline")
            }
        } header: { Text("Séances").drivyFormSectionHeader() }
            .drivyFormRows()
        actions(series, me)
    }

    @ViewBuilder private func actions(_ series: SchoolCourseSeries, _ me: SchoolCourseLearnerState) -> some View {
        Section {
            switch me.state {
            case .available:
                primary("S’inscrire", id: "course-enroll") { confirmsEnroll = true }
            case .full:
                if me.waitlistEnabled {
                    primary("Rejoindre la liste d’attente", id: "course-join-waitlist") { Task { await model.perform(.joinWaitlist) } }
                }
            case .waiting:
                secondary("Quitter la liste d’attente", id: "course-leave-waitlist") { Task { await model.perform(.leaveWaitlist) } }
            case .offered:
                if let offer = me.offer {
                    if model.cancellationClosed() { DrivyActionNote(text: "Le délai d’annulation est passé.") }
                    primary("Accepter la place", id: "course-accept-offer") { confirmsAccept = true }
                    secondary("Refuser", id: "course-decline-offer") { Task { await model.perform(.decline(offerID: offer.id)) } }
                }
            case .enrolled:
                if let enrollment = me.enrollment {
                    if enrollment.canSelfCancel {
                        secondary("Annuler l’inscription", id: "course-cancel", role: .destructive) { confirmsCancel = true }
                    } else {
                        DrivyActionNote(text: "Le délai d’annulation est passé.")
                        if let url = SchoolCourseEnrollmentFormat.mailURL(me.contactEmail, courseTitle: series.title) {
                            // Ouvre seulement la messagerie : rien n’est envoyé ni annulé par l’app.
                            secondary("Contacter l’école", id: "course-contact-school") { openURL(url) }
                                .accessibilityHint("Ouvre un e-mail à l’école")
                        } else {
                            DrivyActionNote(text: "Pour annuler, adresse-toi directement à l’école.")
                        }
                    }
                }
            case .completed, .cancelled, .closed:
                EmptyView()
            }
        }
        .drivyFormRows()
    }

    private func primary(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DrivySpacing.xs) {
                if model.isBusy { ProgressView().tint(DrivyTheme.disabledText).accessibilityHidden(true) }
                Text(title)
            }
        }
        .buttonStyle(DrivyPrimaryButtonStyle())
        .disabled(model.isBusy)
        .accessibilityValue(model.isBusy ? "Envoi en cours" : "")
        .accessibilityIdentifier(id)
    }
    private func secondary(_ title: String, id: String, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        Button(title, role: role, action: action)
            .buttonStyle(DrivySecondaryButtonStyle())
            .disabled(model.isBusy)
            .accessibilityIdentifier(id)
    }
}

/// Cours ouverts à l’élève ; les propositions actives en tête, lues à chaque ouverture et au retour dans l’app.
struct SchoolLearnerCoursesView: View {
    @Bindable var model: SchoolLearnerCoursesWorkspace
    @Environment(\.dismiss) private var dismiss
    @State private var opened: SchoolCourseLearnerWorkspace?

    var body: some View {
        NavigationStack {
            List {
                if let message = model.errorMessage {
                    SchoolErrorNotice(message: message, retry: { Task { await model.load() } })
                }
                if !model.offers.isEmpty {
                    Section {
                        ForEach(model.offers) { offer in
                            Button { open(offer.seriesId) } label: {
                                SchoolCourseOfferBanner(offer: offer, title: model.title(for: offer.seriesId), zone: model.timeZone)
                            }
                            .accessibilityHint("Ouvre le cours")
                        }
                    }
                }
                if let progress = model.progress, !progress.completions.isEmpty || !model.tracked.isEmpty {
                    Section {
                        ForEach(model.tracked) { enrollment in
                            VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                                Text(model.title(for: enrollment.seriesId) ?? "Cours collectif").font(.body.weight(.semibold))
                                Text(SchoolCourseSheetFormat.progress(enrollment.requirements))
                                    .font(.subheadline).foregroundStyle(DrivyTheme.muted).monospacedDigit()
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("learner-course-progress")
                        }
                        ForEach(progress.completions) { completion in
                            HStack(alignment: .firstTextBaseline, spacing: DrivySpacing.s) {
                                Image(systemName: "checkmark.seal.fill").foregroundStyle(DrivyTheme.accent).accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                                    Text(completion.typeTitle).font(.body.weight(.semibold))
                                    if let date = SchoolLesson.date(completion.validatedAt) {
                                        Text("Validé le \(SchoolCourseEnrollmentFormat.day(date, zone: model.timeZone))")
                                            .font(.subheadline).foregroundStyle(DrivyTheme.muted)
                                    }
                                }
                                .fixedSize(horizontal: false, vertical: true)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("learner-course-completion")
                        }
                    } header: { Text("Mes cours") }
                }
                if !model.hasLoaded && model.errorMessage == nil {
                    DrivyLoadingState(title: "Chargement…")
                } else if model.hasLoaded && model.courses.isEmpty {
                    Text("Aucun cours à venir").foregroundStyle(DrivyTheme.muted)
                } else {
                    Section {
                        ForEach(model.courses) { course in
                            Button { open(course.id) } label: { row(course) }
                                .accessibilityHint("Ouvre le cours")
                                .accessibilityIdentifier("learner-course-row")
                        }
                    }
                }
            }
            .navigationTitle("Cours collectifs").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } } }
            .task { await model.load() }
            .refreshable { await model.load() }
            .sheet(item: $opened, onDismiss: { Task { await model.load() } }) { course in
                SchoolCourseLearnerView(model: course)
            }
        }
        .tint(DrivyTheme.accent)
    }

    private func row(_ course: SchoolCourseSeries) -> some View {
        let first = SchoolLesson.date(course.firstStartsAt)
        let note: String? = model.offer(for: course.id) != nil ? "Place proposée"
            : model.isEnrolled(course.id) ? "Inscrit" : course.remainingSeats == 0 ? "Complet" : nil
        return VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
            Text(course.title).font(.body.weight(.semibold)).foregroundStyle(DrivyTheme.text)
            if let first {
                Text(SchoolPlanningFormat.instant(first, zone: model.timeZone) + " · " + SchoolCourseEnrollmentFormat.sessions(course.occurrences.count).capitalizedFirst)
                    .font(.subheadline).foregroundStyle(DrivyTheme.muted).monospacedDigit()
            }
            if let note { Text(note).font(.subheadline.weight(.semibold)).foregroundStyle(DrivyTheme.text) }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func open(_ seriesID: UUID) {
        let course = SchoolCourseLearnerWorkspace(schoolID: model.schoolID, seriesID: seriesID, timeZone: model.timeZone, client: model.client)
        opened = course
    }
}

/// Bandeau d’une place proposée : visible sans notification, jusqu’à son échéance.
struct SchoolCourseOfferBanner: View {
    let offer: SchoolCourseOffer
    let title: String?
    let zone: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DrivySpacing.s) {
            Image(systemName: "person.3.fill").foregroundStyle(DrivyTheme.accent).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                Text(title.map { "Place proposée : \($0)" } ?? "Place proposée dans un cours")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(DrivyTheme.text)
                if let expiry = offer.expiry {
                    Text("Jusqu’à \(SchoolCourseEnrollmentFormat.moment(expiry, zone: zone))")
                        .font(.subheadline).foregroundStyle(DrivyTheme.muted).monospacedDigit()
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("course-offer-banner")
    }
}

/// Inscrits et file d’un cours publié, pour le personnel habilité.
struct SchoolCourseRosterSection: View {
    @Bindable var model: SchoolCourseRosterWorkspace
    @State private var choosesLearner = false
    @State private var cancelling: SchoolCourseRosterEnrollment?
    @State private var reason = ""

    var body: some View {
        Section {
            if let message = model.errorMessage { DrivyFormMessage(text: message, tone: .danger) }
            if let confirmation = model.confirmation { DrivyFormMessage(text: confirmation, tone: .success) }
            if let roster = model.roster {
                if roster.active.isEmpty { Text("Aucun inscrit").foregroundStyle(DrivyTheme.muted) }
                ForEach(roster.active) { row in
                    HStack {
                        Text(row.learnerDisplayName.isEmpty ? "Élève" : row.learnerDisplayName)
                        Spacer(minLength: DrivySpacing.xs)
                        Button("Annuler l’inscription", role: .destructive) { reason = ""; cancelling = row }
                            .buttonStyle(.borderless)
                            .disabled(model.isBusy)
                            .accessibilityLabel("Annuler l’inscription de \(row.learnerDisplayName)")
                    }
                }
                Button { choosesLearner = true } label: { Label("Inscrire un élève", systemImage: "person.badge.plus") }
                    .disabled(model.isBusy || model.candidates.isEmpty)
                    .accessibilityIdentifier("course-staff-enroll")
            } else if model.isLoading {
                DrivyLoadingState(title: "Chargement…")
            }
        } header: { Text("Inscrits").drivyFormSectionHeader() }
            .drivyFormRows()
            .task { await model.load() }
            .confirmationDialog("Inscrire un élève", isPresented: $choosesLearner, titleVisibility: .visible) {
                ForEach(model.candidates.prefix(20)) { learner in
                    Button(learner.displayName) { Task { await model.enroll(learner) } }
                }
                Button("Annuler", role: .cancel) {}
            } message: { Text("L’inscription couvre toutes les séances.") }
            .alert("Annuler l’inscription", isPresented: Binding(get: { cancelling != nil }, set: { if !$0 { cancelling = nil } })) {
                TextField("Motif", text: $reason)
                Button("Annuler l’inscription", role: .destructive) {
                    if let row = cancelling { Task { await model.cancel(row, reason: reason) } }
                    cancelling = nil
                }
                .disabled(reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Garder", role: .cancel) { cancelling = nil }
            } message: { Text("Le motif est obligatoire.") }
        if let waitlist = model.roster?.waitlist, !waitlist.isEmpty {
            Section {
                ForEach(waitlist) { entry in
                    LabeledContent("\(entry.position). \(entry.learnerDisplayName.isEmpty ? "Élève" : entry.learnerDisplayName)") {
                        if entry.status == "OFFERED" { Text("Place proposée").font(.subheadline.weight(.semibold)) }
                    }
                }
            } header: { Text("Liste d’attente").drivyFormSectionHeader() }
                .drivyFormRows()
        }
    }
}

/// Entrée de l’élève vers les cours : un bouton de barre et, sans push, le bandeau des places proposées.
struct SchoolLearnerCourseEntry: ViewModifier {
    let client: SchoolCourseClient?
    let schoolID: UUID?
    let timeZone: String
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: SchoolLearnerCoursesWorkspace?
    @State private var presented: SchoolLearnerCoursesWorkspace?
    @State private var offered: SchoolCourseLearnerWorkspace?

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                if let model, let offer = model.offers.first {
                    Button {
                        offered = SchoolCourseLearnerWorkspace(schoolID: model.schoolID, seriesID: offer.seriesId,
                            timeZone: model.timeZone, client: model.client)
                    } label: {
                        SchoolCourseOfferBanner(offer: offer, title: model.title(for: offer.seriesId), zone: model.timeZone)
                            .padding(DrivySpacing.s)
                            .background(DrivyTheme.accentSoft, in: RoundedRectangle(cornerRadius: DrivyRadius.content, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Ouvre le cours")
                    .padding(.horizontal, DrivySpacing.m).padding(.vertical, DrivySpacing.xs)
                }
            }
            .toolbar {
                if model != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button { presented = model } label: { Label("Cours collectifs", systemImage: "person.3") }
                            .accessibilityIdentifier("learner-courses")
                    }
                }
            }
            .task(id: schoolID) { await prepare() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active, let model { Task { await model.refreshOffers() } }
            }
            .sheet(item: $presented, onDismiss: { Task { await model?.load() } }) { courses in
                SchoolLearnerCoursesView(model: courses)
            }
            .sheet(item: $offered, onDismiss: { Task { await model?.load() } }) { course in
                SchoolCourseLearnerView(model: course)
            }
    }

    private func prepare() async {
        guard let client, let schoolID else { model = nil; return }
        if model?.schoolID != schoolID { model = SchoolLearnerCoursesWorkspace(schoolID: schoolID, timeZone: timeZone, client: client) }
        await model?.load()
    }
}

extension View {
    func schoolLearnerCourses(client: SchoolCourseClient?, schoolID: UUID?, timeZone: String) -> some View {
        modifier(SchoolLearnerCourseEntry(client: client, schoolID: schoolID, timeZone: timeZone))
    }
}
