import SwiftUI

struct SchoolPlanningView: View {
    @Bindable var model: SchoolPlanningWorkspace
    var cancelling = false
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsCancellation = false
    @State private var showsSetup = false

    private var title: String { cancelling ? "Annuler la leçon" : model.originalLesson == nil ? "Planifier une leçon" : "Déplacer la leçon" }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(model.school?.name ?? "Votre école").font(.subheadline).foregroundStyle(DrivyTheme.muted)
                        Text(cancelling ? "Libérer ce rendez-vous" : model.originalLesson == nil ? "Le prochain rendez-vous" : "Un nouveau créneau")
                            .font(.title2.weight(.bold))
                        Text("Heures de l’école · \(model.timeZone)").font(.caption).foregroundStyle(DrivyTheme.muted)
                    }.padding(.vertical, 8)
                }.listRowBackground(Color.clear)
                SchoolPlanningFeedback(model: model)
                if !model.isLoading && model.school != nil {
                    if cancelling { cancellationFields }
                    else { bookingFields }
                }
            }
            .scrollContentBackground(.hidden).background(DrivyTheme.canvas)
            .environment(\.timeZone, TimeZone(identifier: model.timeZone) ?? .current)
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() }.disabled(model.isBusy) }
                if !cancelling {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showsSetup = true } label: { Label("Réglages du planning", systemImage: "slider.horizontal.3") }
                            .disabled(model.isBusy || model.isLoading)
                    }
                }
            }
            .task { await model.load() }
            .sheet(isPresented: $showsSetup, onDismiss: { Task { await model.load() } }) {
                SchoolPlanningSetupView(model: model, loadsOnAppear: false)
            }
            .confirmationDialog("Annuler cette leçon ?", isPresented: $confirmsCancellation, titleVisibility: .visible) {
                Button("Annuler la leçon", role: .destructive) { Task { if await model.cancel() { dismiss() } } }
                Button("Conserver la leçon", role: .cancel) { }
            } message: { Text("L’élève et le moniteur n’auront plus ce rendez-vous dans leur planning actif.") }
        }
        .interactiveDismissDisabled(model.isBusy)
        .tint(DrivyTheme.accent)
    }

    @ViewBuilder private var bookingFields: some View {
        Section("Le dossier") {
            if model.originalLesson == nil {
                Picker("Élève", selection: Binding(get: { model.learnerID }, set: { id in
                    if let id { Task { await model.selectLearner(id) } }
                })) {
                    Text("Choisir un élève").tag(nil as UUID?)
                    ForEach(model.learners) { learner in Text(learner.displayName).tag(Optional(learner.id)) }
                }.disabled(!model.canMutate)
                if model.learners.isEmpty { Text("Aucun dossier actif n’est accessible avec votre rôle.").foregroundStyle(DrivyTheme.muted) }
                if model.learnerID != nil {
                    Picker("Formation", selection: Binding(get: { model.trainingID }, set: { id in
                        if let id { Task { await model.selectTraining(id) } }
                    })) {
                        Text("Choisir une formation").tag(nil as UUID?)
                        ForEach(model.trainings) { training in Text("\(training.categoryCode) · formation active").tag(Optional(training.id)) }
                    }.disabled(!model.canMutate)
                    if model.trainings.isEmpty { Text("L’administration doit ouvrir une formation depuis le dossier de cet élève.").foregroundStyle(DrivyTheme.muted) }
                }
            } else {
                Text(model.learners.first(where: { $0.id == model.learnerID })?.displayName ?? "Dossier de la leçon").font(.headline)
                if let training = model.selectedTraining { Text("Formation \(training.categoryCode)").foregroundStyle(DrivyTheme.muted) }
            }
        }
        if model.trainingID != nil {
            scheduleFields
            if model.originalLesson != nil {
                Section {
                    Toggle("Changer la durée ou la prestation", isOn: $model.changesCommercialTerms)
                        .disabled(!model.canMutate)
                    if !model.changesCommercialTerms, let lesson = model.originalLesson {
                        LabeledContent("Durée conservée", value: "\(lesson.durationMinutes) min")
                        LabeledContent("Prix conservé", value: SchoolCatalogFormatting.price(lesson.priceCentsSnapshot))
                    }
                } footer: { Text("Un changement de prestation demande une nouvelle lecture des conditions et un motif.") }
            }
            if model.originalLesson == nil || model.changesCommercialTerms { commercialFields }
            reviewFields
        }
    }
    private var scheduleFields: some View {
        Section {
            Picker("Moniteur", selection: $model.instructorID) {
                Text("Choisir un moniteur").tag(nil as UUID?)
                ForEach(model.assignedInstructors) { instructor in Text(instructor.displayName).tag(Optional(instructor.id)) }
            }
            .onChange(of: model.instructorID) { _, _ in model.agreementConfirmed = false; Task { await model.loadAvailability() } }
            if model.assignedInstructors.isEmpty {
                Text("Aucun moniteur affecté ne couvre ce créneau. Vérifiez les affectations depuis le dossier de l’élève.")
                    .font(.subheadline).foregroundStyle(DrivyTheme.muted)
            }
            DatePicker("Début", selection: $model.startsAt, in: Date()...)
                .onChange(of: model.startsAt) { _, _ in model.termsAccepted = false; model.agreementConfirmed = false }
            TextField("Lieu du rendez-vous", text: $model.meetingPoint, axis: .vertical).lineLimit(1...3)
                .onChange(of: model.meetingPoint) { _, _ in model.agreementConfirmed = false }
            if model.originalLesson == nil { Stepper("Temps entre deux leçons : \(model.bufferMinutes) min", value: $model.bufferMinutes, in: 0...240, step: 5) }
            if model.instructorID != nil {
                DisclosureGroup("Disponibilités du moniteur") {
                    if model.availability.isEmpty { Text("Aucune ouverture enregistrée. Ajoutez les disponibilités dans les réglages du planning.").font(.subheadline).foregroundStyle(DrivyTheme.muted) }
                    ForEach(model.availability) { rule in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(SchoolPlanningFormat.weekdays(rule.weekdays)).font(.subheadline.weight(.medium))
                            Text("\(rule.localStart) – \(rule.localEnd)").font(.subheadline)
                            Text(SchoolPlanningFormat.validity(rule.validFrom, until: rule.validUntil)).font(.caption).foregroundStyle(DrivyTheme.muted)
                        }.padding(.vertical, 5)
                    }
                    ForEach(model.closures) { closure in
                        Label(SchoolPlanningFormat.interval(closure.startsAt, closure.endsAt, zone: model.timeZone), systemImage: "calendar.badge.minus")
                            .font(.caption).foregroundStyle(DrivyTheme.warning)
                    }
                }
            }
        } header: { Text("Le rendez-vous") }
        footer: { Text("Le moniteur doit être affecté à cette formation. L’école vérifie le créneau, les fermetures et les autres rendez-vous à la confirmation.") }
        .disabled(!model.canMutate)
    }
    private var commercialFields: some View {
        Section {
            Picker("Prestation", selection: $model.productID) {
                Text("Choisir une prestation").tag(nil as UUID?)
                ForEach(model.availableProducts) { product in
                    Text("\(product.label) · \(SchoolCatalogFormatting.price(product.unitPriceCents))").tag(Optional(product.id))
                }
            }.onChange(of: model.productID) { _, _ in model.termsAccepted = false }
            if model.availableProducts.isEmpty {
                Text("Aucune prestation de cette catégorie n’est valable à cette date. L’administration peut la configurer dans les réglages du planning.")
                    .font(.subheadline).foregroundStyle(DrivyTheme.muted)
            }
            if let product = model.selectedProduct {
                Stepper("Quantité : \(model.quantity)", value: $model.quantity, in: 1...100)
                    .onChange(of: model.quantity) { _, _ in model.termsAccepted = false }
                LabeledContent("Durée", value: "\(model.duration) min")
                if let price = model.selectedPrice { LabeledContent("Prix convenu", value: SchoolCatalogFormatting.price(price)) }
                Text("\(product.unitLabel) · \(SchoolCatalogFormatting.price(product.unitPriceCents)) l’unité").font(.caption).foregroundStyle(DrivyTheme.muted)
                if let terms = model.selectedTerms {
                    DisclosureGroup("Conditions · \(terms.label)") {
                        Text(terms.termsText).font(.subheadline).textSelection(.enabled)
                        Text(SchoolPlanningFormat.validity(terms.validFrom, until: terms.validUntil)).font(.caption).foregroundStyle(DrivyTheme.muted)
                    }
                    Toggle("Prix et conditions acceptés", isOn: $model.termsAccepted)
                }
            }
            if let policy = model.selectedPolicy {
                DisclosureGroup("Procédure et annulation") {
                    Text(policy.procedureText).font(.subheadline).textSelection(.enabled)
                    Divider()
                    Text(policy.cancellationPolicyText).font(.subheadline).textSelection(.enabled)
                }
            }
        } header: { Text("La prestation") }
        footer: { Text("Le montant affiché sera rattaché à la leçon. Aucun paiement n’est effectué lors de la réservation.") }
        .disabled(!model.canMutate)
    }
    private var reviewFields: some View {
        Section {
            if model.duration > 0 {
                LabeledContent("Fin prévue", value: SchoolPlanningFormat.instant(model.endsAt, zone: model.timeZone))
            }
            if model.originalLesson != nil {
                TextField(model.changesCommercialTerms ? "Motif du changement" : "Motif facultatif", text: $model.reason, axis: .vertical).lineLimit(2...4)
                Toggle("Le nouvel horaire est convenu", isOn: $model.agreementConfirmed)
            }
            Button {
                Task { if await model.saveBooking() { dismiss() } }
            } label: {
                Label(model.originalLesson == nil ? "Confirmer la leçon" : "Confirmer le déplacement", systemImage: "calendar.badge.checkmark")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }.buttonStyle(DrivyPrimaryButtonStyle()).disabled(!model.validBooking)
                .listRowInsets(EdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0))
                .accessibilityIdentifier("planning-confirm")
        } footer: { Text("Le permis d’élève reste à vérifier avant la conduite.") }
    }
    private var cancellationFields: some View {
        Section {
            if let lesson = model.originalLesson {
                Text(SchoolPlanningFormat.interval(lesson.plannedStart, lesson.plannedEnd, zone: lesson.timeZone)).font(.headline)
                Text(lesson.meetingPoint).foregroundStyle(DrivyTheme.muted)
            }
            Picker("Motif", selection: $model.cancellationReason) {
                Text("Choisir un motif").tag("")
                Text("Demande de l’élève").tag("LEARNER_REQUEST")
                Text("Moniteur indisponible").tag("INSTRUCTOR_UNAVAILABLE")
                Text("Fermeture de l’école").tag("SCHOOL_CLOSURE")
                Text("Autre motif").tag("OTHER")
            }
            TextField("Précision facultative", text: $model.reason, axis: .vertical).lineLimit(3...6)
            Button("Annuler cette leçon", role: .destructive) { confirmsCancellation = true }
                .frame(minHeight: 48).disabled(!model.canMutate || model.cancellationReason.isEmpty || model.reason.count > 1000 || model.originalLesson?.status != "PLANNED")
        }
    }
}

struct SchoolPlanningFeedback: View {
    @Bindable var model: SchoolPlanningWorkspace
    var body: some View {
        if model.isLoading { Section { ProgressView("Ouverture du planning…") } }
        if let error = model.errorMessage {
            Section {
                Text(error).font(.subheadline).foregroundStyle(DrivyTheme.danger)
                if !model.accessRevoked { Button("Actualiser les informations") { Task { await model.load() } }.disabled(model.isBusy || model.isLoading) }
            }
        }
        if let success = model.successMessage { Section { Label(success, systemImage: "checkmark.circle").foregroundStyle(DrivyTheme.success) } }
        if let command = model.pending {
            Section {
                Label("Confirmation en attente", systemImage: "clock.arrow.circlepath").font(.headline)
                Text("La demande est conservée. Vérifiez son résultat avant d’en envoyer une nouvelle.").font(.subheadline)
                DisclosureGroup("Référence de la demande") {
                    Text(command.id.uuidString).font(.caption.monospaced()).textSelection(.enabled)
                }
                Button("Vérifier auprès de l’école") { Task { await model.verify() } }.disabled(model.isBusy || model.isLoading)
                if model.canRetry { Button("Renvoyer la même demande") { Task { _ = await model.retry() } } }
                else if command.scope != model.scope { Text("Vos accès ont changé. La demande initiale reste conservée.").font(.caption).foregroundStyle(DrivyTheme.muted) }
            }
        }
        if model.isBusy { Section { ProgressView("Confirmation par l’école…") } }
    }
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
