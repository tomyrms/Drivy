import SwiftUI

struct SchoolPlanningView: View {
    @Bindable var model: SchoolPlanningWorkspace
    var cancelling = false
    var beforeCancellation: (@MainActor () async -> Bool)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var confirmsCancellation = false
    @State private var document: SchoolPlanningDocument?

    private var title: String { cancelling ? "Annuler la leçon" : model.originalLesson == nil ? "Planifier une leçon" : "Déplacer la leçon" }
    var body: some View {
        NavigationStack {
            Form {
                SchoolPlanningFeedback(model: model)
                if model.school != nil {
                    if cancelling { cancellationFields }
                    else {
                        bookingFields
                        if typeSize.isAccessibilitySize {
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
                if !typeSize.isAccessibilitySize && !cancelling && model.school != nil { bookingActionBar }
            }
            .environment(\.timeZone, TimeZone(identifier: model.timeZone) ?? .current)
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() }.disabled(model.isBusy) }
            }
            .task { if model.school == nil { await model.load() } }
            .sheet(item: $document) { SchoolPlanningDocumentView(document: $0) }
            .confirmationDialog("Annuler cette leçon ?", isPresented: $confirmsCancellation, titleVisibility: .visible) {
                Button("Annuler la leçon", role: .destructive) {
                    Task {
                        guard await beforeCancellation?() ?? true else { return }
                        if await model.cancel() { dismiss() }
                    }
                }
                Button("Conserver la leçon", role: .cancel) { }
            } message: { Text("L’élève et le moniteur n’auront plus ce rendez-vous dans leur planning actif.") }
        }
        .interactiveDismissDisabled(model.isBusy)
        .tint(DrivyTheme.accent)
    }

    @ViewBuilder private var bookingFields: some View {
        Section {
            if model.originalLesson == nil {
                Picker("Élève", selection: Binding(get: { model.learnerID }, set: { id in
                    if let id { Task { await model.selectLearner(id) } }
                })) {
                    Text("Choisir un élève").tag(nil as UUID?)
                    ForEach(model.learners) { learner in Text(learner.displayName).tag(Optional(learner.id)) }
                }.disabled(!model.canMutate)
                if model.learners.isEmpty && !model.isLoading { formNote("Aucun dossier d’élève actif n’est accessible avec ton rôle.") }
                if model.learnerID != nil {
                    Picker("Formation", selection: Binding(get: { model.trainingID }, set: { id in
                        if let id { Task { await model.selectTraining(id) } }
                    })) {
                        Text("Choisir une formation").tag(nil as UUID?)
                        ForEach(model.trainings) { training in Text("Permis \(training.categoryCode)").tag(Optional(training.id)) }
                    }.disabled(!model.canMutate)
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
            if model.originalLesson != nil {
                Section {
                    Toggle("Changer la durée ou le tarif", isOn: $model.changesCommercialTerms)
                        .disabled(!model.canMutate)
                    if !model.changesCommercialTerms, let lesson = model.originalLesson {
                        LabeledContent("Durée conservée") { Text("\(lesson.durationMinutes) min").monospacedDigit().foregroundStyle(DrivyTheme.muted) }
                        LabeledContent("Prix conservé") { Text(SchoolCatalogFormatting.price(lesson.priceCentsSnapshot)).monospacedDigit().foregroundStyle(DrivyTheme.muted) }
                    }
                } header: { Text("Durée et prix").drivyFormSectionHeader() }
                    .drivyFormRows()
            }
            if model.originalLesson == nil || model.changesCommercialTerms { commercialFields }
            reviewFields
            documentLinks
        }
    }
    private var scheduleFields: some View {
        Section {
            Picker("Moniteur", selection: $model.instructorID) {
                Text("Choisir un moniteur").tag(nil as UUID?)
                ForEach(model.assignedInstructors) { instructor in Text(instructor.displayName).tag(Optional(instructor.id)) }
            }
            .onChange(of: model.instructorID) { _, _ in model.agreementConfirmed = false }
            if model.assignedInstructors.isEmpty && !model.isLoading {
                formNote("Aucun moniteur affecté à cet élève.")
            }
            DatePicker("Date", selection: $model.startsAt, in: Date()..., displayedComponents: .date)
                .onChange(of: model.startsAt) { _, _ in model.termsAccepted = false; model.agreementConfirmed = false }
            DatePicker("Heure", selection: $model.startsAt, displayedComponents: .hourAndMinute)
                .onChange(of: model.startsAt) { _, _ in model.termsAccepted = false; model.agreementConfirmed = false }
            if model.duration > 0 {
                LabeledContent("Fin prévue") { Text(SchoolPlanningFormat.instant(model.endsAt, zone: model.timeZone)).monospacedDigit().foregroundStyle(DrivyTheme.muted) }
            }
            DisclosureGroup("Détails du rendez-vous") {
                SchoolMeetingPointField(text: $model.meetingPoint)
                .onChange(of: model.meetingPoint) { _, _ in model.agreementConfirmed = false }
                if model.meetingPointTooLong {
                    DrivyFormMessage(text: "Raccourcis le lieu à 500 caractères.", tone: .danger)
                }
                if model.originalLesson == nil {
                    Stepper("Intervalle : \(model.bufferMinutes) min", value: $model.bufferMinutes, in: 0...240, step: 5)
                        .accessibilityLabel("Temps entre deux leçons")
                        .accessibilityValue("\(model.bufferMinutes) minutes")
                }
            }
            if model.instructorID != nil {
                DisclosureGroup("Disponibilités du moniteur") {
                    if !model.availabilityLoaded && model.availabilityError == nil {
                        DrivySkeletonRows(count: 2).drivySkeleton("Chargement des disponibilités…")
                    } else if model.isLoadingAvailability {
                        ProgressView().accessibilityLabel("Actualisation des disponibilités")
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
                        Label(SchoolPlanningFormat.interval(closure.startsAt, closure.endsAt, zone: model.timeZone), systemImage: "calendar.badge.minus")
                            .font(.caption).foregroundStyle(DrivyTheme.warning)
                    }
                }
                .task(id: model.instructorID) { await model.loadAvailability() }
            }
        } header: { Text("Le rendez-vous").drivyFormSectionHeader() }
            .drivyFormRows()
        .disabled(!model.canMutate)
    }
    private var commercialFields: some View {
        Section {
            Picker("Tarif", selection: $model.productID) {
                Text("Choisir un tarif").tag(nil as UUID?)
                ForEach(model.availableProducts) { product in
                    Text("\(product.label) · \(SchoolCatalogFormatting.price(product.unitPriceCents))").tag(Optional(product.id))
                }
            }.onChange(of: model.productID) { _, _ in model.termsAccepted = false }
            if model.availableProducts.isEmpty && !model.isLoading {
                formNote("Aucun tarif valable à cette date.")
            }
            if let product = model.selectedProduct {
                Stepper(value: $model.quantity, in: 1...100) {
                    VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                        Text("Quantité : \(model.quantity)").monospacedDigit()
                        Text("Durée : \(model.duration) min").font(.subheadline.monospacedDigit()).foregroundStyle(DrivyTheme.muted)
                    }
                }
                .onChange(of: model.quantity) { _, _ in model.termsAccepted = false }
                // Le prix unitaire n’apporte rien quand il est déjà le prix convenu.
                if model.quantity > 1 {
                    LabeledContent("Prix par \(product.unitLabel)") {
                        Text(SchoolCatalogFormatting.price(product.unitPriceCents)).monospacedDigit().foregroundStyle(DrivyTheme.muted)
                    }
                }
                if model.selectedTerms != nil {
                    Toggle("Prix et conditions acceptés", isOn: $model.termsAccepted)
                }
            }
        } header: { Text("Le tarif").drivyFormSectionHeader() }
            .drivyFormRows()
        .disabled(!model.canMutate)
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
            } header: { Text("Vérification").drivyFormSectionHeader() }
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
        } else if model.originalLesson != nil && model.changesCommercialTerms
            && model.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            DrivyActionNote(text: "Indique le motif du changement.", isError: true)
        }
        Button {
            Task { if await model.saveBooking() { dismiss() } }
        } label: {
            HStack(spacing: DrivySpacing.xs) {
                if model.isBusy { ProgressView().tint(DrivyTheme.disabledText).accessibilityHidden(true) }
                Label(model.originalLesson == nil ? "Confirmer la leçon" : "Confirmer le déplacement", systemImage: "calendar.badge.checkmark")
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
                }
                .padding(.vertical, DrivySpacing.xxs)
                .accessibilityElement(children: .combine)
                lesson.drivyState.badge
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
            .disabled(!model.canMutate)
        Section {
            Button(role: .destructive) { confirmsCancellation = true } label: {
                Label("Annuler la leçon", systemImage: "calendar.badge.minus")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .disabled(!model.canMutate || model.cancellationReason.isEmpty || model.reasonTooLong || model.originalLesson?.status != "PLANNED")
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
    @Bindable var model: SchoolPlanningWorkspace
    var body: some View {
        if model.school == nil && (model.isLoading || model.errorMessage == nil) { Section { DrivySkeletonRows(count: 4).drivySkeleton("Ouverture du planning…") }
            .drivyFormRows() }
        if let error = model.errorMessage {
            // Même présentation d’erreur que les pages : notice, puis « Réessayer ».
            Section {
                SchoolErrorNotice(message: error, retry: model.accessRevoked ? nil : { Task { await model.load() } })
                    .disabled(model.isBusy || model.isLoading)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
        if let success = model.successMessage {
            Section { DrivyFormMessage(text: success, tone: .success) }
                .drivyFormRows()
        }
        if let command = model.pending {
            Section {
                DrivyPendingRequest(message: "La demande est conservée. Vérifie son résultat avant d’en envoyer une nouvelle.",
                    notes: !model.canRetry && command.scope != model.scope ? ["Tes accès ont changé. La demande initiale reste conservée."] : [],
                    reference: command.id,
                    verify: { Task { await model.verify() } }, canVerify: !(model.isBusy || model.isLoading),
                    retry: model.canRetry ? { Task { _ = await model.retry() } } : nil)
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
    static func instant(_ date: Date, zone: String) -> String {
        let format = DateFormatter(); format.locale = Locale(identifier: "fr_CH"); format.timeZone = TimeZone(identifier: zone)
        format.dateFormat = "EEE d MMM · HH:mm"; return format.string(from: date)
    }
    static func interval(_ start: String, _ end: String, zone: String) -> String {
        guard let start = SchoolLesson.date(start), let end = SchoolLesson.date(end) else { return "Horaire indisponible" }
        return instant(start, zone: zone) + " – " + instant(end, zone: zone)
    }
}
