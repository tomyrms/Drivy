import SwiftUI
import UIKit

struct SchoolPlanningView: View {
    @Bindable var model: SchoolPlanningWorkspace
    var cancelling = false
    var beforeCancellation: (@MainActor () async -> Bool)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var confirmsCancellation = false
    @State private var isPreparingCancellation = false
    @State private var cancellationPreparationError: String?
    @State private var document: SchoolPlanningDocument?

    private var title: String { cancelling ? "Annuler la leçon" : model.originalLesson == nil ? "Planifier une leçon" : "Déplacer la leçon" }
    var body: some View {
        NavigationStack {
            ScrollViewReader { scroll in
            Form {
                SchoolPlanningFeedback(model: model)
                if let cancellationPreparationError {
                    Section { DrivyFormMessage(text: cancellationPreparationError, tone: .danger) }.drivyFormRows()
                } else if isPreparingCancellation {
                    Section { ProgressView("Arrêt du trajet…") }.drivyFormRows()
                }
                if model.school != nil {
                    if cancelling { cancellationFields }
                    else {
                        bookingFields
                        if typeSize.isAccessibilitySize && model.showsSlotDetails {
                            Section {
                                VStack(alignment: .leading, spacing: DrivySpacing.xs) { bookingActionContent }
                            }
                            .drivyFormRows()
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .frame(maxWidth: SchoolFormLayout.maxWidth).frame(maxWidth: .infinity).background(DrivyTheme.canvas)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !typeSize.isAccessibilitySize && !cancelling && model.showsSlotDetails { bookingActionBar }
            }
            .environment(\.timeZone, TimeZone(identifier: model.timeZone) ?? .current)
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() }.disabled(model.isBusy || isPreparingCancellation) }
                // Relecture du planning, nouvel élève ou nouvelle formation : l’attente se lit dans la barre,
                // le formulaire ne reçoit pas de ligne et ne se décale pas. Le premier chargement garde son squelette.
                if model.school != nil && model.isLoading {
                    ToolbarItem(placement: .primaryAction) {
                        ProgressView().accessibilityLabel("Actualisation du planning")
                    }
                }
            }
            .task { if model.school == nil { await model.load() } }
            .task(id: model.slotValidationRequest) {
                if !cancelling, model.slotValidationRequest != nil { await model.validateSlot(debounced: true) }
            }
            .sheet(item: $document) { SchoolPlanningDocumentView(document: $0) }
            .alert("Annuler cette leçon ?", isPresented: $confirmsCancellation) {
                Button("Annuler la leçon", role: .destructive) {
                    Task {
                        guard !isPreparingCancellation, model.canMutate else { return }
                        cancellationPreparationError = nil; isPreparingCancellation = true
                        defer { isPreparingCancellation = false }
                        guard await beforeCancellation?() ?? true else {
                            cancellationPreparationError = "Le trajet n’a pas pu être arrêté. Réessaie avant d’annuler la leçon."
                            return
                        }
                        isPreparingCancellation = false
                        if await model.cancel() { dismiss() }
                    }
                }
                Button("Conserver", role: .cancel) { }
            } message: { Text("Ce rendez-vous sera retiré du planning.") }
            // Le bouton est en bas, le refus de l’école s’affiche en tête : il est ramené à l’écran et annoncé,
            // sans quoi « Planifier » ou « Annuler la leçon » semblait rester sans effet.
            .onChange(of: model.errorMessage) { _, message in
                guard let message else { return }
                scroll.scrollTo(SchoolPlanningFeedback.errorAnchor, anchor: .top)
                UIAccessibility.post(notification: .announcement, argument: message)
            }
            }
        }
        .interactiveDismissDisabled(model.isBusy || isPreparingCancellation)
        .tint(DrivyTheme.accent)
    }

    @ViewBuilder private var bookingFields: some View {
        Section {
            if model.originalLesson == nil {
                NavigationLink {
                    SchoolLearnerSearchList(learners: model.learners, selectedID: model.learnerID) { id in
                        Task { await model.selectLearner(id) }
                    }
                } label: {
                    LabeledContent("Élève") {
                        Text(model.learners.first(where: { $0.id == model.learnerID })?.displayName ?? "Choisir un élève")
                    }
                }
                .disabled(!model.canMutate)
                .accessibilityIdentifier("planning-learner")
                if model.learners.isEmpty && !model.isLoading { formNote("Aucun dossier d’élève actif n’est accessible avec ton rôle.") }
                if model.learnerID != nil {
                    trainingChoice
                    if model.isLoading && model.trainings.isEmpty {
                        DrivySkeletonRow().drivySkeleton("Chargement de la formation…")
                    } else if model.trainings.isEmpty {
                        formNote("Aucune formation active. L’administration peut en ouvrir une depuis le dossier de cet élève.")
                    }
                }
            } else {
                LabeledContent("Élève") {
                    Text(model.learners.first(where: { $0.id == model.learnerID })?.displayName ?? "Dossier de la leçon")
                        .foregroundStyle(DrivyTheme.muted)
                }
                if let training = model.selectedTraining {
                    LabeledContent("Formation") { Text("Permis \(training.categoryCode)").foregroundStyle(DrivyTheme.muted) }
                }
            }
        } header: { Text("Élève et formation").drivyFormSectionHeader() }
            .drivyFormRows()
        if model.trainingID != nil {
            scheduleFields
            if model.originalLesson != nil { keptTermsFields }
            if model.showsSlotDetails {
                reviewFields
                documentLinks
            }
        }
    }
    /// Une seule formation en cours : il n’y a rien à choisir, une ligne suffit (comme pour un déplacement).
    @ViewBuilder private var trainingChoice: some View {
        if model.trainings.count == 1, let training = model.trainings.first, training.id == model.trainingID {
            LabeledContent("Formation") { Text("Permis \(training.categoryCode)").foregroundStyle(DrivyTheme.muted) }
        } else {
            Picker("Formation", selection: Binding(get: { model.trainingID }, set: { id in
                if let id { Task { await model.selectTraining(id) } }
            })) {
                Text("Choisir une formation").tag(nil as UUID?)
                ForEach(model.trainings) { training in Text("Permis \(training.categoryCode)").tag(Optional(training.id)) }
            }.disabled(!model.canMutate)
        }
    }
    /// Déplacement : la durée et le prix restent ceux de la leçon, sauf si le moniteur les change.
    private var keptTermsFields: some View {
        Section {
            Toggle("Changer la durée ou le tarif", isOn: $model.changesCommercialTerms)
                .disabled(!model.canMutate)
            if !model.changesCommercialTerms, let lesson = model.originalLesson {
                LabeledContent("Durée et prix conservés") {
                    Text("\(lesson.durationMinutes) min · \(SchoolCatalogFormatting.price(lesson.priceCentsSnapshot))")
                        .monospacedDigit().foregroundStyle(DrivyTheme.muted)
                }
            }
        }
        .drivyFormRows()
    }
    private var scheduleFields: some View {
        Section {
            Picker("Moniteur", selection: $model.instructorID) {
                Text("Choisir un moniteur").tag(nil as UUID?)
                ForEach(model.assignedInstructors) { instructor in Text(instructor.displayName).tag(Optional(instructor.id)) }
                if let selected = model.instructors.first(where: { $0.id == model.instructorID }),
                   !model.assignedInstructors.contains(where: { $0.id == selected.id }) {
                    Text(selected.displayName).tag(Optional(selected.id)).disabled(true)
                }
            }
            .onChange(of: model.instructorID) { _, _ in model.agreementConfirmed = false }
            if model.assignedInstructors.isEmpty && !model.isLoading {
                formNote("Aucun moniteur affecté ne couvre ce créneau.")
            }
            // Rendez-vous resté en attente après son horaire : la borne ne masque pas sa date réelle. Sans cela le
            // sélecteur affichait aujourd’hui pendant que le formulaire refusait encore l’horaire passé.
            DatePicker("Date", selection: $model.startsAt, in: min(model.startsAt, Date())..., displayedComponents: .date)
            DatePicker("Heure", selection: $model.startsAt, displayedComponents: .hourAndMinute)
            if model.originalLesson == nil || model.changesCommercialTerms {
                Picker("Durée", selection: Binding(get: { model.duration }, set: { model.selectDuration($0) })) {
                    ForEach(model.durationChoices, id: \.self) { minutes in Text("\(minutes) min").tag(minutes) }
                }
                .accessibilityIdentifier("planning-duration")
            }
            if model.duration > 0 {
                LabeledContent("Fin prévue") { Text(SchoolPlanningFormat.instant(model.endsAt, zone: model.timeZone)).monospacedDigit().foregroundStyle(DrivyTheme.muted) }
            }
            slotStatus
            DisclosureGroup("Détails du rendez-vous") {
                SchoolMeetingPointField(text: $model.meetingPoint)
                .onChange(of: model.meetingPoint) { _, _ in model.agreementConfirmed = false }
                if model.meetingPointTooLong {
                    DrivyFormMessage(text: "Raccourcis le lieu à 500 caractères.", tone: .danger)
                }
                if model.originalLesson == nil {
                    Stepper("Temps entre deux leçons : \(model.bufferMinutes) min", value: $model.bufferMinutes, in: 0...240, step: 5)
                        .accessibilityLabel("Temps entre deux leçons")
                        .accessibilityValue("\(model.bufferMinutes) minutes")
                }
            }
            if model.instructorID != nil {
                DisclosureGroup {
                    if !model.availabilityLoaded && model.availabilityError == nil {
                        DrivySkeletonRows(count: 2).drivySkeleton("Chargement des disponibilités…")
                    }
                    if let error = model.availabilityError {
                        SchoolErrorNotice(message: error, retry: { Task { await model.loadAvailability() } })
                    }
                    if model.availabilityLoaded && model.availability.isEmpty {
                        formNote("Aucune disponibilité : ajoute-la sur le web.")
                    }
                    ForEach(model.availability) { rule in
                        VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                            Text(SchoolPlanningFormat.weekdays(rule.weekdays)).font(.subheadline.weight(.semibold))
                            Text("\(rule.localStart) – \(rule.localEnd)").font(.subheadline.monospacedDigit())
                            Text(SchoolPlanningFormat.validity(rule.validFrom, until: rule.validUntil)).font(.caption).foregroundStyle(DrivyTheme.muted)
                        }.padding(.vertical, DrivySpacing.xxs)
                    }
                    ForEach(model.closures) { closure in
                        Text("Indisponible : \(SchoolPlanningFormat.interval(closure.startsAt, closure.endsAt, zone: model.timeZone))")
                            .font(.caption).foregroundStyle(DrivyTheme.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } label: {
                    // La relecture se lit sur la ligne du titre : aucune ligne n’est insérée dans la liste ouverte.
                    HStack(spacing: DrivySpacing.xs) {
                        Text("Disponibilités du moniteur")
                        if model.availabilityLoaded && model.isLoadingAvailability {
                            ProgressView().accessibilityLabel("Actualisation des disponibilités")
                        }
                    }
                }
                .task(id: model.instructorID) { await model.loadAvailability() }
            }
        } header: { Text("Le rendez-vous").drivyFormSectionHeader() }
            .drivyFormRows()
        .disabled(!model.canMutate)
    }
    @ViewBuilder private var slotFeedback: some View {
        if let message = model.slotInputMessage {
            DrivyFormMessage(text: message, tone: .danger)
        } else if model.checkedSlotRequest == model.slotRequest, model.slotRequest != nil {
            if model.isCheckingSlot {
                // Après un créneau libre, l’attente se lit dans le bouton : aucune ligne ne s’insère.
                if !model.showsSlotDetails {
                    ProgressView("Vérification du créneau…")
                        .accessibilityIdentifier("planning-slot-checking")
                }
            } else if let error = model.slotError {
                SchoolErrorNotice(message: error, retry: { Task { await model.validateSlot() } })
                    .accessibilityIdentifier("planning-slot-error")
            } else if let message = model.slotAvailability?.refusalMessage {
                DrivyFormMessage(text: message, tone: .danger)
                    .accessibilityIdentifier("planning-slot-unavailable")
            }
        }
    }
    /// Le créneau puis, au même endroit, le tarif : la ligne remplace l’indicateur de vérification.
    @ViewBuilder private var slotStatus: some View {
        slotFeedback
        tariffRow
    }
    /// Le prix convenu est celui de la barre d’action. Ici, seulement la prestation : une ligne quand il n’y a
    /// rien à choisir, un sélecteur quand plusieurs tarifs correspondent. Le motif d’un tarif manquant est dans la barre.
    @ViewBuilder private var tariffRow: some View {
        if model.showsSlotDetails && (model.originalLesson == nil || model.changesCommercialTerms) {
            if let product = model.automaticTariff {
                LabeledContent("Tarif") {
                    Text(model.quantity > 1 ? SchoolPlanningFormat.tariff(product, quantity: model.quantity) : product.label)
                        .monospacedDigit().foregroundStyle(DrivyTheme.muted)
                }
                .accessibilityIdentifier("planning-tariff")
            } else if model.needsTariffChoice {
                Picker("Tarif", selection: $model.productID) {
                    Text("Choisir un tarif").tag(nil as UUID?)
                    ForEach(model.compatibleProducts) { product in
                        Text(SchoolPlanningFormat.tariff(product, quantity: model.quantityCovered(by: product))).tag(Optional(product.id))
                    }
                }
                .accessibilityIdentifier("planning-tariff")
            }
        }
    }
    private var documentLinks: some View {
        Section {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: DrivySpacing.m) { documentButtons }.fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 0) { documentButtons }
            }
            .font(.footnote)
            .buttonStyle(.plain)
            .foregroundStyle(DrivyTheme.accent)
        }
        .listRowBackground(Color.clear)
    }
    @ViewBuilder private var documentButtons: some View {
        if let terms = model.selectedTerms {
            Button {
                document = SchoolPlanningDocument(title: "Conditions tarifaires", text: "\(terms.label)\n\n\(terms.termsText)\n\n\(SchoolPlanningFormat.validity(terms.validFrom, until: terms.validUntil))")
            } label: { Text("Conditions tarifaires").frame(minHeight: 44).contentShape(Rectangle()) }
        }
        if let policy = model.selectedPolicy {
            Button { document = SchoolPlanningDocument(title: "Procédure", text: policy.procedureText) }
                label: { Text("Procédure").frame(minHeight: 44).contentShape(Rectangle()) }
            Button { document = SchoolPlanningDocument(title: "Annulation", text: policy.cancellationPolicyText) }
                label: { Text("Annulation").frame(minHeight: 44).contentShape(Rectangle()) }
        }
    }
    @ViewBuilder private var reviewFields: some View {
        if model.originalLesson != nil {
            Section {
                TextField(model.changesCommercialTerms ? "Motif du changement" : "Motif facultatif", text: $model.reason, axis: .vertical).lineLimit(2...4)
                Toggle("Le nouvel horaire est convenu", isOn: $model.agreementConfirmed)
            } header: { Text("Motif et accord").drivyFormSectionHeader() }
            .drivyFormRows()
            .disabled(!model.canMutate)
        }
    }

    private var bookingActionBar: some View {
        DrivyStickyActionBar { bookingActionContent }
    }

    @ViewBuilder private var bookingActionContent: some View {
        if model.duration > 0 {
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text("\(model.duration) min · \(SchoolPlanningFormat.instant(model.startsAt, zone: model.timeZone))").fixedSize()
                    Spacer(minLength: DrivySpacing.s)
                    if let price = bookingPrice { bookingPriceText(price).fixedSize() }
                }
                VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                    Text("\(model.duration) min · \(SchoolPlanningFormat.instant(model.startsAt, zone: model.timeZone))")
                        .fixedSize(horizontal: false, vertical: true)
                    if let price = bookingPrice { bookingPriceText(price) }
                }
            }
            .font(.subheadline.monospacedDigit())
            .foregroundStyle(DrivyTheme.muted)
            .accessibilityElement(children: .combine)
        }
        if model.meetingPointTooLong {
            DrivyActionNote(text: "Raccourcis le lieu à 500 caractères.", isError: true)
        } else if model.reasonTooLong {
            DrivyActionNote(text: "Raccourcis le motif à 1 000 caractères.", isError: true)
        } else if model.startsAt <= Date() {
            DrivyActionNote(text: "Choisis un horaire à venir.", isError: true)
        } else if let message = model.tariffMessage {
            DrivyActionNote(text: message, isError: true)
        } else if model.originalLesson != nil && model.changesCommercialTerms
            && model.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            DrivyActionNote(text: "Indique le motif du changement.", isError: true)
        }
        Button {
            Task { if await model.saveBooking() { dismiss() } }
        } label: {
            HStack(spacing: DrivySpacing.xs) {
                if model.isBusy || model.isCheckingSlot { ProgressView().tint(DrivyTheme.disabledText).accessibilityHidden(true) }
                Text(model.originalLesson == nil ? "Planifier" : "Confirmer le déplacement")
            }
        }
        .buttonStyle(DrivyPrimaryButtonStyle())
        .disabled(!model.validBooking)
        .accessibilityIdentifier("planning-confirm")
    }

    /// Le prix est le point focal de la barre : plus grand que la durée et l’horaire qui l’accompagnent.
    private func bookingPriceText(_ price: Int64) -> some View {
        Text(SchoolCatalogFormatting.price(price)).font(.headline.monospacedDigit()).foregroundStyle(DrivyTheme.text)
    }

    private var bookingPrice: Int64? {
        if let lesson = model.originalLesson, !model.changesCommercialTerms { return lesson.priceCentsSnapshot }
        return model.selectedPrice
    }

    @ViewBuilder private var cancellationFields: some View {
        if let lesson = model.originalLesson {
            Section {
                VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                    Text(SchoolPlanningFormat.interval(lesson.plannedStart, lesson.plannedEnd, zone: lesson.timeZone))
                        .font(.headline.monospacedDigit())
                    if !lesson.meetingPoint.isEmpty { Text(lesson.meetingPoint).font(.subheadline).foregroundStyle(DrivyTheme.muted) }
                    // Un mot de texte seulement pour l’inhabituel : une leçon planifiée à venir n’en porte pas.
                    if let note = lesson.drivyState.rowNote { DrivyRowNoteText(note: note) }
                }
                .padding(.vertical, DrivySpacing.xxs)
                .accessibilityElement(children: .combine)
            } header: { Text("Leçon concernée").drivyFormSectionHeader() }
                .drivyFormRows()
        }
        Section {
            Picker("Motif", selection: $model.cancellationReason) {
                Text("Choisir un motif").tag("")
                Text("Demande de l’élève").tag("LEARNER_REQUEST")
                Text("Moniteur indisponible").tag("INSTRUCTOR_UNAVAILABLE")
                Text("Fermeture de l’école").tag("SCHOOL_CLOSURE")
                Text("Autre motif").tag("OTHER")
            }
            TextField("Précision facultative", text: $model.reason, axis: .vertical).lineLimit(3...6)
            // Explication seulement en cas d’erreur : la limite n’apparaît qu’une fois dépassée.
            if model.reasonTooLong {
                DrivyFormMessage(text: "Raccourcis la précision à 1 000 caractères.", tone: .danger)
            }
        } header: { Text("Motif d’annulation").drivyFormSectionHeader() }
            .drivyFormRows()
            .disabled(!model.canMutate || isPreparingCancellation)
        Section {
            Button(role: .destructive) { confirmsCancellation = true } label: {
                Text("Annuler la leçon")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .disabled(isPreparingCancellation || !model.canMutate || model.cancellationReason.isEmpty || model.reasonTooLong || model.originalLesson?.status != "PLANNED")
        }
            .drivyFormRows()
    }
    private func formNote(_ text: String) -> some View {
        Text(text).font(.subheadline).foregroundStyle(DrivyTheme.muted).fixedSize(horizontal: false, vertical: true)
    }
}

/// A permanent label; large text keeps the field on its own line instead of squeezing its value.
struct SchoolMeetingPointField: View {
    @Binding var text: String
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: DrivySpacing.xs) {
                    Text("Lieu (facultatif)").accessibilityHidden(true)
                    field
                }
            } else {
                LabeledContent("Lieu (facultatif)") { field.multilineTextAlignment(.trailing) }
            }
        }
    }
    private var field: some View {
        TextField("Lieu du rendez-vous", text: $text, axis: .vertical)
            .lineLimit(1...3)
            .accessibilityLabel("Lieu du rendez-vous, facultatif")
    }
}

struct SchoolPlanningFeedback: View {
    /// Repère de la notice d’erreur, pour la ramener à l’écran depuis le bas du formulaire.
    static let errorAnchor = "planning-error"
    @Bindable var model: SchoolPlanningWorkspace
    /// Une demande renvoyée avec succès ferme la feuille, comme un premier envoi.
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        if model.school == nil && (model.isLoading || model.errorMessage == nil) { Section { DrivySkeletonRows(count: 4).drivySkeleton("Ouverture du planning…") }
            .drivyFormRows() }
        if let error = model.errorMessage {
            // Même présentation d’erreur que les pages : notice, puis « Réessayer ».
            Section {
                SchoolErrorNotice(message: error, retry: model.accessRevoked ? nil : { Task { await model.load() } })
                    .disabled(model.isBusy || model.isLoading)
                    .id(Self.errorAnchor)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
        // Une écriture confirmée ferme la feuille : son bandeau ne s’insère pas pendant la descente.
        if let success = model.successMessage, !model.writeConfirmed {
            Section { DrivyFormMessage(text: success, tone: .success) }
                .drivyFormRows()
        }
        if let command = model.pending {
            Section {
                DrivyPendingRequest(message: command.waitingMessage(absent: model.pendingAbsent),
                    notes: !model.canRetry && command.scope != model.scope ? ["Tes accès ont changé. La demande initiale reste conservée."] : [],
                    reference: command.id,
                    verify: model.pendingAbsent ? nil : { Task { await model.verify() } }, canVerify: !(model.isBusy || model.isLoading),
                    retry: model.canRetry ? { Task { if await model.retry() { dismiss() } } } : nil,
                    abandon: model.pendingAbsent ? { Task { await model.abandonPending() } } : nil,
                    canAbandon: !(model.isBusy || model.isLoading))
            }
                .drivyFormRows()
        }
        if model.isBusy { Section { DrivyLoadingState(title: "Confirmation par l’école…") }
            .drivyFormRows() }
    }
}

/// Colonne bornée des formulaires de planification (planifier, déplacer, annuler, démarrer maintenant) sur iPad.
enum SchoolFormLayout {
    static let maxWidth = DrivyLayout.formColumn
}

enum SchoolPlanningFormat {
    static func weekdays(_ days: [Int]) -> String {
        let labels = ["Lundi", "Mardi", "Mercredi", "Jeudi", "Vendredi", "Samedi", "Dimanche"]
        return days.sorted().compactMap { (1...7).contains($0) ? labels[$0 - 1] : nil }.joined(separator: ", ")
    }
    static func civil(_ value: String) -> String {
        let parts = value.split(separator: "-")
        guard parts.count == 3 else { return value }
        return "\(parts[2]).\(parts[1]).\(parts[0])"
    }
    static func validity(_ from: String, until: String?) -> String {
        if let until { return "Du \(civil(from)) au \(civil(until))" }
        return "Dès le \(civil(from))"
    }
    /// La prestation et son prix unitaire ; une durée multiple précise la quantité (« 2 × CHF 95.00 »).
    static func tariff(_ product: SchoolServiceProduct, quantity: Int) -> String {
        let price = SchoolCatalogFormatting.price(product.unitPriceCents)
        return quantity > 1 ? "\(product.label) · \(quantity) × \(price)" : "\(product.label) · \(price)"
    }
    static func instant(_ date: Date, zone: String) -> String {
        let format = DateFormatter(); format.locale = Locale(identifier: "fr_CH"); format.timeZone = TimeZone(identifier: zone)
        format.dateFormat = "EEE d MMM · HH:mm"; return format.string(from: date)
    }
    static func interval(_ start: String, _ end: String, zone: String) -> String {
        guard let start = SchoolLesson.date(start), let end = SchoolLesson.date(end) else { return "Horaire indisponible" }
        return instant(start, zone: zone) + " – " + instant(end, zone: zone)
    }
}
