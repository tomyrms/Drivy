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
                    VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                        Text(model.school?.name ?? "Votre école").font(.subheadline.weight(.semibold)).foregroundStyle(DrivyTheme.muted)
                        Text(cancelling ? "Libérer ce rendez-vous" : model.originalLesson == nil ? "Choisir, puis confirmer" : "Choisir un nouveau créneau")
                            .font(.drivyTitle).foregroundStyle(DrivyTheme.text)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Horaires à l’heure de l’école · \(model.timeZone)").font(.footnote).foregroundStyle(DrivyTheme.muted)
                    }
                    .padding(.vertical, DrivySpacing.xs)
                    .accessibilityElement(children: .combine)
                }.listRowBackground(Color.clear)
                SchoolPlanningFeedback(model: model)
                if !model.isLoading && model.school != nil {
                    if cancelling { cancellationFields }
                    else { bookingFields }
                }
            }
            .scrollContentBackground(.hidden).background(DrivyTheme.canvas)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !cancelling && !model.isLoading && model.school != nil { bookingActionBar }
            }
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
        Section("Élève et formation") {
            if model.originalLesson == nil {
                Picker("Élève", selection: Binding(get: { model.learnerID }, set: { id in
                    if let id { Task { await model.selectLearner(id) } }
                })) {
                    Text("Choisir un élève").tag(nil as UUID?)
                    ForEach(model.learners) { learner in Text(learner.displayName).tag(Optional(learner.id)) }
                }.disabled(!model.canMutate)
                if model.learners.isEmpty { formNote("Aucun dossier d’élève actif n’est accessible avec votre rôle.") }
                if model.learnerID != nil {
                    Picker("Formation", selection: Binding(get: { model.trainingID }, set: { id in
                        if let id { Task { await model.selectTraining(id) } }
                    })) {
                        Text("Choisir une formation").tag(nil as UUID?)
                        ForEach(model.trainings) { training in Text("\(training.categoryCode) · formation active").tag(Optional(training.id)) }
                    }.disabled(!model.canMutate)
                    if model.trainings.isEmpty { formNote("Aucune formation active. L’administration peut en ouvrir une depuis le dossier de cet élève.") }
                }
            } else {
                LabeledContent("Élève", value: model.learners.first(where: { $0.id == model.learnerID })?.displayName ?? "Dossier de la leçon")
                if let training = model.selectedTraining { LabeledContent("Formation", value: "Permis \(training.categoryCode)") }
            }
        }
        if model.trainingID != nil {
            scheduleFields
            if model.originalLesson != nil {
                Section {
                    Toggle("Changer la durée ou la prestation", isOn: $model.changesCommercialTerms)
                        .disabled(!model.canMutate)
                    if !model.changesCommercialTerms, let lesson = model.originalLesson {
                        LabeledContent("Durée conservée") { Text("\(lesson.durationMinutes) min").monospacedDigit() }
                        LabeledContent("Prix conservé") { Text(SchoolCatalogFormatting.price(lesson.priceCentsSnapshot)).monospacedDigit() }
                    }
                } header: { Text("Durée et prix") }
                footer: { Text("Un changement de prestation demande une nouvelle lecture des conditions et un motif.") }
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
                formNote("Aucun moniteur affecté ne couvre ce créneau. Vérifiez les affectations depuis le dossier de l’élève.")
            }
            DatePicker("Date", selection: $model.startsAt, in: Date()..., displayedComponents: .date)
                .onChange(of: model.startsAt) { _, _ in model.termsAccepted = false; model.agreementConfirmed = false }
            DatePicker("Heure", selection: $model.startsAt, displayedComponents: .hourAndMinute)
                .onChange(of: model.startsAt) { _, _ in model.termsAccepted = false; model.agreementConfirmed = false }
            TextField("Lieu du rendez-vous", text: $model.meetingPoint, axis: .vertical).lineLimit(1...3)
                .onChange(of: model.meetingPoint) { _, _ in model.agreementConfirmed = false }
            if model.originalLesson == nil {
                DisclosureGroup("Temps entre deux leçons") {
                    Stepper("\(model.bufferMinutes) min", value: $model.bufferMinutes, in: 0...240, step: 5)
                }
            }
            if model.instructorID != nil {
                DisclosureGroup("Disponibilités du moniteur") {
                    if model.availability.isEmpty { formNote("Aucune disponibilité enregistrée. Ajoutez-la dans les réglages du planning.") }
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
                formNote("Aucune prestation de cette catégorie n’est valable à cette date. L’administration peut la configurer dans les réglages du planning.")
            }
            if let product = model.selectedProduct {
                Stepper("Quantité : \(model.quantity)", value: $model.quantity, in: 1...100)
                    .onChange(of: model.quantity) { _, _ in model.termsAccepted = false }
                LabeledContent("Durée") { Text("\(model.duration) min").monospacedDigit() }
                if let price = model.selectedPrice { LabeledContent("Prix convenu") { Text(SchoolCatalogFormatting.price(price)).monospacedDigit() } }
                Text("\(product.unitLabel) · \(SchoolCatalogFormatting.price(product.unitPriceCents)) l’unité").font(.footnote.monospacedDigit()).foregroundStyle(DrivyTheme.muted)
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
                LabeledContent("Fin prévue") { Text(SchoolPlanningFormat.instant(model.endsAt, zone: model.timeZone)).monospacedDigit() }
            }
            if model.originalLesson != nil {
                TextField(model.changesCommercialTerms ? "Motif du changement" : "Motif facultatif", text: $model.reason, axis: .vertical).lineLimit(2...4)
                Toggle("Le nouvel horaire est convenu", isOn: $model.agreementConfirmed)
            }
        } header: { Text("Vérification") }
        footer: { Text("Le permis d’élève reste à vérifier avant la conduite.") }
    }

    private var bookingActionBar: some View {
        DrivyStickyActionBar {
            if model.duration > 0 {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        Text("\(model.duration) min · \(SchoolPlanningFormat.instant(model.startsAt, zone: model.timeZone))")
                        Spacer(minLength: DrivySpacing.s)
                        if let price = bookingPrice { Text(SchoolCatalogFormatting.price(price)).fontWeight(.semibold).foregroundStyle(DrivyTheme.text) }
                    }
                    VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                        Text("\(model.duration) min · \(SchoolPlanningFormat.instant(model.startsAt, zone: model.timeZone))")
                        if let price = bookingPrice { Text(SchoolCatalogFormatting.price(price)).fontWeight(.semibold).foregroundStyle(DrivyTheme.text) }
                    }
                }
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(DrivyTheme.muted)
                .accessibilityElement(children: .combine)
            }
            if !model.validBooking {
                DrivyActionNote(text: bookingHint)
            }
            Button {
                Task { if await model.saveBooking() { dismiss() } }
            } label: {
                HStack(spacing: DrivySpacing.xs) {
                    if model.isBusy { ProgressView().tint(DrivyTheme.disabledText) }
                    Label(model.originalLesson == nil ? "Confirmer la leçon" : "Confirmer le déplacement", systemImage: "calendar.badge.checkmark")
                }
            }
            .buttonStyle(DrivyPrimaryButtonStyle())
            .disabled(!model.validBooking)
            .accessibilityIdentifier("planning-confirm")
        }
    }

    private var bookingPrice: Int64? {
        if let lesson = model.originalLesson, !model.changesCommercialTerms { return lesson.priceCentsSnapshot }
        return model.selectedPrice
    }

    /// Helpful next-step copy only. The workspace remains the sole source of
    /// client validation and the server still decides whether to book.
    private var bookingHint: String {
        if model.isBusy { return "Confirmation par l’école…" }
        if model.pending != nil { return "Vérifiez d’abord la confirmation en attente." }
        if model.learnerID == nil { return "Commencez par choisir l’élève." }
        if model.trainingID == nil { return "Choisissez sa formation." }
        if model.instructorID == nil { return "Choisissez le moniteur pour cette leçon." }
        if model.startsAt <= Date() { return "Choisissez un horaire à venir." }
        if model.meetingPoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Indiquez le lieu de rendez-vous." }
        if model.originalLesson != nil && !model.agreementConfirmed { return "Confirmez que le nouvel horaire est convenu." }
        if (model.originalLesson == nil || model.changesCommercialTerms) && model.productID == nil { return "Choisissez une prestation pour fixer la durée et le prix." }
        if (model.originalLesson == nil || model.changesCommercialTerms) && !model.termsAccepted { return "Relisez puis acceptez le prix et les conditions." }
        return "Vérifiez les informations du rendez-vous avant de confirmer."
    }
    @ViewBuilder private var cancellationFields: some View {
        if let lesson = model.originalLesson {
            Section("Leçon concernée") {
                VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                    Text(SchoolPlanningFormat.interval(lesson.plannedStart, lesson.plannedEnd, zone: lesson.timeZone))
                        .font(.headline.monospacedDigit())
                    Text(lesson.meetingPoint).font(.subheadline).foregroundStyle(DrivyTheme.muted)
                }
                .padding(.vertical, DrivySpacing.xxs)
                .accessibilityElement(children: .combine)
                lesson.drivyState.badge
            }
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
        } header: { Text("Motif d’annulation") }
        footer: { Text("Précision limitée à 1 000 caractères.") }
        Section {
            Button(role: .destructive) { confirmsCancellation = true } label: {
                Label("Annuler cette leçon", systemImage: "calendar.badge.minus")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .disabled(!model.canMutate || model.cancellationReason.isEmpty || model.reason.count > 1000 || model.originalLesson?.status != "PLANNED")
        } footer: {
            Text(model.cancellationReason.isEmpty ? "Choisissez un motif pour pouvoir annuler." : "Une confirmation vous est demandée avant l’annulation.")
        }
    }
    private func formNote(_ text: String) -> some View {
        Text(text).font(.subheadline).foregroundStyle(DrivyTheme.muted).fixedSize(horizontal: false, vertical: true)
    }
}

struct SchoolPlanningFeedback: View {
    @Bindable var model: SchoolPlanningWorkspace
    var body: some View {
        if model.isLoading { Section { ProgressView("Ouverture du planning…").frame(maxWidth: .infinity, alignment: .leading) } }
        if let error = model.errorMessage {
            Section {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline).foregroundStyle(DrivyTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
                if !model.accessRevoked {
                    Button { Task { await model.load() } } label: { Label("Actualiser les informations", systemImage: "arrow.clockwise") }
                        .disabled(model.isBusy || model.isLoading)
                }
            }
        }
        if let success = model.successMessage {
            Section {
                Label(success, systemImage: "checkmark.circle.fill").font(.subheadline).foregroundStyle(DrivyTheme.success)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        if let command = model.pending {
            Section {
                Label("Confirmation en attente", systemImage: "clock.arrow.circlepath").font(.headline).foregroundStyle(DrivyTheme.warning)
                Text("La demande est conservée. Vérifiez son résultat avant d’en envoyer une nouvelle.").font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
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
