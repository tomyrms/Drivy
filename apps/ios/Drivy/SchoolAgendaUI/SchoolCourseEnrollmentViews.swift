import SwiftUI
import UIKit

/// Fiche d’un cours vue par l’élève : statut, séances et commandes.
struct SchoolCourseLearnerView: View {
    @Bindable var model: SchoolCourseLearnerWorkspace
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var review: SchoolCourseEnrollmentReview?
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
            .navigationTitle(model.series?.title ?? "Cours collectif").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() }.disabled(model.isBusy) } }
            .task { await model.load() }
            .refreshable { await model.load() }
            .onChange(of: model.errorMessage) { _, message in
                if let message { UIAccessibility.post(notification: .announcement, argument: message) }
            }
            .onChange(of: model.confirmation) { _, message in
                if let message { UIAccessibility.post(notification: .announcement, argument: message) }
            }
            .sheet(item: $review) { review in
                SchoolCourseEnrollmentReviewView(model: model, review: review)
            }
            .confirmationDialog("Annuler l’inscription ?", isPresented: $confirmsCancel, titleVisibility: .visible) {
                if let enrollment = model.me?.enrollment {
                    Button("Annuler l’inscription", role: .destructive) {
                        Task { await model.perform(.cancel(enrollmentID: enrollment.id, version: enrollment.version)) }
                    }
                }
                Button("Garder", role: .cancel) {}
            } message: { Text(SchoolCourseEnrollmentFormat.cancellationMessage(model.series?.occurrences.count ?? 1)) }
        }
        .interactiveDismissDisabled(model.isBusy)
        .tint(DrivyTheme.accent)
    }

    @ViewBuilder private func content(_ series: SchoolCourseSeries, _ me: SchoolCourseLearnerState) -> some View {
        Section {
            Text(SchoolCourseEnrollmentFormat.status(me, zone: zone)).font(.headline)
            .accessibilityIdentifier("course-learner-status")
            if let next = SchoolCoursePresentation.nextOccurrence(series, now: Date()) {
                Label(SchoolPlanningFormat.interval(next.startsAt, next.endsAt, zone: zone), systemImage: "calendar")
                    .monospacedDigit().fixedSize(horizontal: false, vertical: true)
            }
            if !series.location.isEmpty { Label(series.location, systemImage: "mappin.and.ellipse") }
            Text("\(series.occurrences.count) \(series.occurrences.count == 1 ? "séance" : "séances") · \(SchoolCourseFormat.duration(minutes: series.totalMinutes))")
                .foregroundStyle(DrivyTheme.muted)
            if me.state == .available || me.state == .full {
                Text(SchoolCourseFormat.seats(series.remainingSeats)).monospacedDigit()
            }
        }
            .drivyFormRows()
        actions(series, me)
        if !series.description.isEmpty {
            Section {
                Text(series.description).fixedSize(horizontal: false, vertical: true)
            } header: { Text("À propos").drivyFormSectionHeader() }
            .drivyFormRows()
        }
        Section {
            DisclosureGroup("Toutes les séances") {
                SchoolCourseDatesContent(series: series, timeZone: zone)
            }
            if let deadline = me.enrollment?.deadline ?? SchoolLesson.date(series.selfCancellationDeadline) {
                LabeledContent("Annulable jusqu’au") {
                    Text(SchoolCourseEnrollmentFormat.deadline(deadline, zone: zone)).multilineTextAlignment(.trailing)
                }
                .accessibilityIdentifier("course-cancel-deadline")
            }
            DisclosureGroup("Conditions d’inscription") {
                Text("Inscription pour \(SchoolCourseEnrollmentFormat.sessions(series.occurrences.count)).")
                Text("Paiement sur place")
                if !series.conditions.isEmpty { Text(series.conditions).fixedSize(horizontal: false, vertical: true) }
            }
        } header: { Text("Détails").drivyFormSectionHeader() }
            .drivyFormRows()
    }

    @ViewBuilder private func actions(_ series: SchoolCourseSeries, _ me: SchoolCourseLearnerState) -> some View {
        Section {
            switch me.state {
            case .available:
                primary("S’inscrire", id: "course-enroll") { review = SchoolCourseEnrollmentReview(action: .enroll) }
            case .full:
                if me.waitlistEnabled {
                    primary("Rejoindre la liste d’attente", id: "course-join-waitlist") { Task { await model.perform(.joinWaitlist) } }
                }
            case .waiting:
                secondary("Quitter la liste d’attente", id: "course-leave-waitlist") { Task { await model.perform(.leaveWaitlist) } }
            case .offered:
                if let offer = me.offer {
                    if model.cancellationClosed() { DrivyActionNote(text: "Le délai d’annulation est passé.") }
                    primary("Accepter la place", id: "course-accept-offer") { review = SchoolCourseEnrollmentReview(action: .accept(offerID: offer.id)) }
                    secondary("Refuser", id: "course-decline-offer") { Task { await model.perform(.decline(offerID: offer.id)) } }
                }
            case .enrolled:
                if let enrollment = me.enrollment {
                    if enrollment.canSelfCancel {
                        secondary("Annuler l’inscription", id: "course-cancel", role: .destructive) { confirmsCancel = true }
                    } else {
                        DrivyActionNote(text: "Le délai d’annulation est passé.")
                        // L’entrée existante ne propose que les contacts autorisés et n’envoie rien à l’ouverture.
                        SchoolMessagingEntryButton()
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
            if let following = model.following {
                Button(following ? "Ne plus prévenir" : "Prévenir des prochaines sessions",
                       systemImage: following ? "bell.slash" : "bell") {
                    Task { await model.setFollow(!following) }
                }
                .disabled(model.isBusy || model.isUpdatingFollow)
                .accessibilityValue(model.isUpdatingFollow ? "Envoi en cours" : "")
                .accessibilityIdentifier("course-follow")
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
                if !model.activeEnrollments.isEmpty {
                    Section {
                        ForEach(model.activeEnrollments) { enrollment in
                            Button { open(enrollment.seriesId) } label: {
                                VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                                    Text(model.title(for: enrollment.seriesId) ?? "Cours collectif").font(.body.weight(.semibold))
                                    if let next = model.nextOccurrence(for: enrollment.seriesId) {
                                        Text(SchoolPlanningFormat.interval(next.startsAt, next.endsAt, zone: model.timeZone))
                                            .font(.subheadline).foregroundStyle(DrivyTheme.muted).monospacedDigit()
                                    }
                                    if let tracked = model.tracked.first(where: { $0.seriesId == enrollment.seriesId }) {
                                        Text(SchoolCourseSheetFormat.progress(tracked.requirements))
                                            .font(.subheadline).foregroundStyle(DrivyTheme.muted).monospacedDigit()
                                    }
                                }
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityHint("Ouvre ton inscription")
                            .accessibilityIdentifier("learner-course-progress")
                        }
                    } header: { Text("Mes inscriptions") }
                }
                if let progress = model.progress, !progress.completions.isEmpty {
                    Section {
                        ForEach(progress.completions) { completion in
                            if let seriesID = completion.seriesId {
                                Button { open(seriesID) } label: { completionRow(completion) }
                                    .accessibilityHint("Ouvre le cours effectué")
                            } else {
                                completionRow(completion)
                            }
                        }
                    } header: { Text("Cours effectués") }
                }
                if !model.hasLoaded && model.errorMessage == nil {
                    DrivyLoadingState(title: "Chargement…")
                } else if model.hasLoaded && model.availableCourses.isEmpty {
                    Section { Text("Aucun autre cours disponible").foregroundStyle(DrivyTheme.muted) } header: { Text("Disponibles") }
                } else {
                    Section {
                        ForEach(model.availableCourses) { course in
                            Button { open(course.id) } label: { row(course) }
                                .accessibilityHint("Ouvre le cours")
                                .accessibilityIdentifier("learner-course-row")
                        }
                    } header: { Text("Disponibles") }
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

    private func completionRow(_ completion: SchoolCourseProgress.Completion) -> some View {
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
                        Menu {
                            Button("Annuler l’inscription", role: .destructive) { cancelling = row }
                        } label: {
                            Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 44)
                        }
                            .disabled(model.isBusy)
                            .accessibilityLabel("Actions pour \(row.learnerDisplayName)")
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
            .sheet(isPresented: $choosesLearner) { SchoolCourseParticipantPicker(model: model) }
            .sheet(item: $cancelling) { row in SchoolCourseCancelEnrollmentSheet(model: model, row: row) }
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
                if let model {
                  if let offer = model.offers.first {
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
                  } else if let enrollment = model.nextEnrollment(), let next = model.nextOccurrence(for: enrollment.seriesId) {
                    Button {
                        offered = SchoolCourseLearnerWorkspace(schoolID: model.schoolID, seriesID: enrollment.seriesId,
                            timeZone: model.timeZone, client: model.client)
                    } label: {
                        DrivyEntityRow(title: model.title(for: enrollment.seriesId) ?? "Cours collectif",
                            meta: SchoolPlanningFormat.interval(next.startsAt, next.endsAt, zone: model.timeZone),
                            leading: .symbol("person.3"), showsChevron: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Prochain cours, \(model.title(for: enrollment.seriesId) ?? "Cours collectif"), \(SchoolPlanningFormat.interval(next.startsAt, next.endsAt, zone: model.timeZone))")
                    .accessibilityIdentifier("learner-next-course")
                    .padding(.horizontal, DrivySpacing.m).padding(.vertical, DrivySpacing.xs)
                  }
                }
            }
            .toolbar {
                if model != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button { presented = model } label: { Label("Cours collectifs", systemImage: "person.3") }
                            .labelStyle(.titleAndIcon)
                            .accessibilityIdentifier("learner-courses")
                    }
                }
            }
            .task(id: schoolID) { await prepare(); openPendingSeries() }
            // Toucher une notification de cours : sa fiche s’ouvre, relue auprès de l’école (aucun droit déduit de la charge utile).
            .onChange(of: SchoolPushCenter.shared.pendingSeriesID) { _, _ in openPendingSeries() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active, let model { Task { await model.load() } }
            }
            .sheet(item: $presented, onDismiss: { Task { await model?.load() } }) { courses in
                SchoolLearnerCoursesView(model: courses)
            }
            .sheet(item: $offered, onDismiss: { Task { await model?.load() } }) { course in
                SchoolCourseLearnerView(model: course)
            }
    }

    private func openPendingSeries() {
        guard let model, SchoolPushCenter.shared.pendingSeriesID != nil, presented == nil,
              let seriesID = SchoolPushCenter.shared.consumePendingSeries() else { return }
        offered = SchoolCourseLearnerWorkspace(schoolID: model.schoolID, seriesID: seriesID, timeZone: model.timeZone, client: model.client)
    }

    private func prepare() async {
        guard let client, let schoolID else { model = nil; presented = nil; offered = nil; return }
        if model?.schoolID != schoolID {
            presented = nil; offered = nil
            model = SchoolLearnerCoursesWorkspace(schoolID: schoolID, timeZone: timeZone, client: client)
        }
        await model?.load()
    }
}

extension View {
    func schoolLearnerCourses(client: SchoolCourseClient?, schoolID: UUID?, timeZone: String) -> some View {
        modifier(SchoolLearnerCourseEntry(client: client, schoolID: schoolID, timeZone: timeZone))
    }
}
