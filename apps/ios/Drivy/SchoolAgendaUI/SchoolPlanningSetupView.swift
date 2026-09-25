import SwiftUI

struct SchoolPlanningSetupView: View {
    @Bindable var model: SchoolPlanningWorkspace
    var loadsOnAppear = true
    @Environment(\.dismiss) private var dismiss
    @State private var editor: PlanningSetupEditorRequest?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                        Text(model.school?.name ?? "Votre école").font(.drivyTitle).foregroundStyle(DrivyTheme.text)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Horaires à l’heure de l’école · \(model.timeZone)")
                            .font(.footnote).foregroundStyle(DrivyTheme.muted)
                    }
                    .padding(.vertical, DrivySpacing.xs)
                    .accessibilityElement(children: .combine)
                }.listRowBackground(Color.clear)
                SchoolPlanningFeedback(model: model)
                if !model.isLoading && model.school != nil {
                    availabilitySection
                    closureSection
                    if model.canConfigureCatalog { commercialSection }
                }
            }
            .scrollContentBackground(.hidden).background(DrivyTheme.canvas)
            .navigationTitle("Réglages du planning").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fermer") { dismiss() }.disabled(model.isBusy) } }
            .task {
                if loadsOnAppear { await model.load() }
                if model.instructorID == nil && !model.roles.contains("ADMIN") { model.instructorID = model.scope.membershipID }
                await model.loadAvailability()
            }
            .sheet(item: $editor, onDismiss: { Task { await model.loadAvailability() } }) { request in SchoolPlanningSetupEditor(model: model, request: request) }
        }
        .interactiveDismissDisabled(model.isBusy)
        .tint(DrivyTheme.accent)
    }
    private var commercialSection: some View {
        Group {
          Section {
            Button { editor = .init(kind: .terms) } label: { Label("Créer des conditions", systemImage: "plus") }
                .disabled(!model.canMutate).frame(minHeight: 44)
            ForEach(model.terms.sorted { $0.version > $1.version }) { terms in
                DisclosureGroup {
                    Text(terms.termsText).font(.subheadline).textSelection(.enabled)
                    Text(SchoolPlanningFormat.validity(terms.validFrom, until: terms.validUntil)).font(.caption).foregroundStyle(DrivyTheme.muted)
                    Button("Préparer une nouvelle version") { editor = .init(kind: .terms, terms: terms) }
                        .disabled(!model.canMutate)
                } label: {
                    VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                        Text(terms.label).font(.headline)
                        HStack(spacing: DrivySpacing.xs) {
                            Text("Version \(terms.version)").font(.caption.monospacedDigit()).foregroundStyle(DrivyTheme.muted)
                            DrivyStatusBadge(title: terms.approved ? "Approuvées" : "Brouillon",
                                symbol: terms.approved ? "checkmark" : "pencil", tone: terms.approved ? .success : .neutral)
                        }
                    }
                    .padding(.vertical, DrivySpacing.xxs)
                }
            }
          } header: { Text("Conditions commerciales") }
          footer: { Text("Une nouvelle version conserve les conditions des rendez-vous déjà pris.") }
          Section {
            Button { editor = .init(kind: .product) } label: { Label("Créer une prestation", systemImage: "plus") }
                .disabled(!model.canMutate || model.terms.isEmpty).frame(minHeight: 44)
            if model.terms.isEmpty { formNote("Créez d’abord des conditions commerciales : chaque prestation s’y rattache.") }
            ForEach(model.products.sorted { ($0.label, $0.version) < ($1.label, $1.version) }) { product in
                DisclosureGroup {
                    LabeledContent("Référence", value: product.productKey)
                    LabeledContent("Catégorie", value: product.categoryCode ?? "—")
                    LabeledContent("Prix unitaire", value: SchoolCatalogFormatting.price(product.unitPriceCents))
                    if let duration = product.durationMinutes { LabeledContent("Durée", value: "\(duration) min") }
                    Text(SchoolPlanningFormat.validity(product.validFrom, until: product.validUntil)).font(.caption).foregroundStyle(DrivyTheme.muted)
                    Button("Préparer une nouvelle version") { editor = .init(kind: .product, product: product) }.disabled(!model.canMutate)
                } label: {
                    VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                        Text(product.label).font(.headline)
                        HStack(spacing: DrivySpacing.xs) {
                            Text("\(SchoolCatalogFormatting.price(product.unitPriceCents)) · version \(product.version)")
                                .font(.caption.monospacedDigit()).foregroundStyle(DrivyTheme.muted)
                            DrivyStatusBadge(title: product.enabled ? "Active" : "Inactive",
                                symbol: product.enabled ? "checkmark" : "pause", tone: product.enabled ? .success : .neutral)
                        }
                    }
                    .padding(.vertical, DrivySpacing.xxs)
                }
            }
          } header: { Text("Prestations de conduite") }
        }
    }
    private var availabilitySection: some View {
        Section {
            Picker("Moniteur", selection: $model.instructorID) {
                Text("Choisir un moniteur").tag(nil as UUID?)
                ForEach(model.instructors) { value in Text(value.displayName).tag(Optional(value.id)) }
            }.disabled(model.isBusy || model.isLoading)
                .onChange(of: model.instructorID) { _, _ in Task { await model.loadAvailability() } }
            if model.instructorID != nil {
                if model.isLoadingAvailability { ProgressView("Lecture des disponibilités…") }
                if let error = model.availabilityError {
                    SchoolErrorNotice(message: error, retry: { Task { await model.loadAvailability() } })
                }
                ForEach(model.availability) { rule in
                    VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                        Text(SchoolPlanningFormat.weekdays(rule.weekdays)).font(.headline)
                        Text("\(rule.localStart) – \(rule.localEnd)").monospacedDigit()
                        Text(SchoolPlanningFormat.validity(rule.validFrom, until: rule.validUntil)).font(.caption).foregroundStyle(DrivyTheme.muted)
                        HStack(spacing: DrivySpacing.l) {
                            Button("Modifier") { editor = .init(kind: .availability, rule: rule) }.frame(minHeight: 44)
                            Button("Retirer", role: .destructive) { editor = .init(kind: .removeAvailability, rule: rule) }.frame(minHeight: 44)
                        }.font(.subheadline.weight(.semibold)).buttonStyle(.borderless).disabled(!model.canMutate)
                    }.padding(.vertical, DrivySpacing.xxs)
                }
                if model.availabilityLoaded && model.availability.isEmpty { formNote("Aucune disponibilité pour ce moniteur. Ajoutez sa première plage horaire.") }
                if !model.availabilityLoaded && !model.isLoadingAvailability && model.availabilityError == nil {
                    Button("Charger les disponibilités") { Task { await model.loadAvailability() } }.frame(minHeight: 44)
                }
                Button { editor = .init(kind: .availability) } label: { Label("Ajouter une disponibilité", systemImage: "calendar.badge.plus") }
                    .frame(minHeight: 44).disabled(!model.canMutate || !model.availabilityLoaded)
            }
        } header: { Text("Disponibilités") }
        footer: { Text("Les jours et horaires sont exprimés dans le fuseau de l’école. Les rendez-vous existants sont protégés.") }
    }
    private var closureSection: some View {
        Section {
            if model.instructorID != nil {
                if model.isLoadingAvailability { ProgressView("Lecture des fermetures…") }
                else if model.availabilityError != nil { formNote("Les fermetures n’ont pas pu être lues. Réessayez depuis la section Disponibilités.") }
                ForEach(model.closures) { closure in
                    VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                        Text(SchoolPlanningFormat.interval(closure.startsAt, closure.endsAt, zone: model.timeZone)).font(.headline.monospacedDigit())
                        if let reason = closure.reason, !reason.isEmpty { Text(reason).font(.subheadline).foregroundStyle(DrivyTheme.muted) }
                        Button("Retirer cette fermeture", role: .destructive) { editor = .init(kind: .removeClosure, closure: closure) }
                            .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                            .buttonStyle(.borderless).disabled(!model.canMutate)
                    }.padding(.vertical, DrivySpacing.xxs)
                }
                if model.availabilityLoaded && model.closures.isEmpty { formNote("Aucune fermeture enregistrée.") }
                Button { editor = .init(kind: .closure) } label: { Label("Ajouter une fermeture", systemImage: "calendar.badge.minus") }
                    .frame(minHeight: 44).disabled(!model.canMutate || !model.availabilityLoaded)
            } else { formNote("Choisissez un moniteur pour consulter ses fermetures.") }
        } header: { Text("Fermetures et absences") }
    }
    private func formNote(_ text: String) -> some View {
        Text(text).font(.subheadline).foregroundStyle(DrivyTheme.muted).fixedSize(horizontal: false, vertical: true)
    }
}

private enum PlanningSetupEditorKind { case terms, product, availability, closure, removeAvailability, removeClosure }
private struct PlanningSetupEditorRequest: Identifiable {
    let id = UUID()
    let kind: PlanningSetupEditorKind
    var terms: SchoolCommercialTerms? = nil
    var product: SchoolServiceProduct? = nil
    var rule: SchoolAvailabilityRule? = nil
    var closure: SchoolClosure? = nil
}

private struct SchoolPlanningSetupEditor: View {
    @Bindable var model: SchoolPlanningWorkspace
    let request: PlanningSetupEditorRequest
    @Environment(\.dismiss) private var dismiss
    @State private var label = ""
    @State private var reference = ""
    @State private var category = ""
    @State private var termsText = ""
    @State private var reason = ""
    @State private var price = ""
    @State private var duration = ""
    @State private var unit = ""
    @State private var termsID: UUID?
    @State private var validFrom = Date()
    @State private var validUntil = Date()
    @State private var starts = Date()
    @State private var ends = Date().addingTimeInterval(3600)
    @State private var hasEnd = false
    @State private var approved = false
    @State private var enabled = false
    @State private var confirmed = false
    @State private var days = Set<Int>()
    @State private var localStart = ""
    @State private var localEnd = ""
    @State private var awaitingCommandID: UUID?

    private var title: String {
        switch request.kind {
        case .terms: "Conditions commerciales"
        case .product: "Prestation de conduite"
        case .availability: request.rule == nil ? "Ajouter une disponibilité" : "Modifier la disponibilité"
        case .closure: "Ajouter une fermeture"
        case .removeAvailability: "Retirer la disponibilité"
        case .removeClosure: "Retirer la fermeture"
        }
    }
    var body: some View {
        NavigationStack {
            Form {
                SchoolPlanningFeedback(model: model)
                fields.disabled(!model.canMutate)
                Section {
                    Toggle(confirmationText, isOn: $confirmed)
                        .disabled(!model.canMutate)
                } footer: { Text("La modification est appliquée uniquement après confirmation par l’école.") }
            }
            .scrollContentBackground(.hidden).background(DrivyTheme.canvas)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) { saveBar }
            .environment(\.timeZone, TimeZone(identifier: model.timeZone) ?? .current)
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() }.disabled(model.isBusy) } }
            .onAppear(perform: populate)
            .onChange(of: formValues) { _, _ in confirmed = false }
            .onChange(of: model.isLoading) { _, loading in
                if awaitingCommandID != nil && !loading && !model.needsReload && model.pending == nil && model.successMessage != nil {
                    dismiss()
                }
            }
        }
        .interactiveDismissDisabled(model.isBusy)
        .tint(DrivyTheme.accent)
    }
    @ViewBuilder private var fields: some View {
        switch request.kind {
        case .terms: termsFields
        case .product: productFields
        case .availability: availabilityFields
        case .closure:
            Section { instructorLabel }
            Section("Début de la fermeture") {
                DatePicker("Date", selection: $starts, displayedComponents: .date)
                DatePicker("Heure", selection: $starts, displayedComponents: .hourAndMinute)
            }
            Section("Fin de la fermeture") {
                DatePicker("Date", selection: $ends, in: starts..., displayedComponents: .date)
                DatePicker("Heure", selection: $ends, displayedComponents: .hourAndMinute)
            }
            Section {
                multilineField("Motif · facultatif", text: $reason)
            } footer: { Text("Les leçons concernées doivent être déplacées ou annulées avant d’ajouter une fermeture.") }
        case .removeAvailability, .removeClosure:
            Section {
                if let rule = request.rule {
                    Text(SchoolPlanningFormat.weekdays(rule.weekdays)).font(.headline)
                    Text("\(rule.localStart) – \(rule.localEnd)")
                }
                if let closure = request.closure { Text(SchoolPlanningFormat.interval(closure.startsAt, closure.endsAt, zone: model.timeZone)).font(.headline) }
                multilineField("Motif du retrait", text: $reason)
            }
        }
    }
    private var termsFields: some View {
        Group {
            Section("Les textes") {
                field("Nom des conditions", text: $label)
                multilineField("Conditions commerciales de l’école", text: $termsText, lines: 5...12)
            }
            validityFields
            Section {
                Toggle("Approuver les textes affichés", isOn: $approved)
                multilineField("Motif de cette version", text: $reason)
            } footer: { Text("L’approbation porte sur le texte affiché. Aucune approbation n’est préremplie.") }
        }
    }
    private var productFields: some View {
        Group {
            Section("La prestation") {
                field("Nom de la prestation", text: $label)
                field("Référence", text: $reference).textInputAutocapitalization(.never).autocorrectionDisabled()
                field("Catégorie de permis", text: $category).textInputAutocapitalization(.characters)
                field("Durée en minutes", text: $duration).keyboardType(.numberPad)
                field("Unité facturée", text: $unit)
                field("Prix unitaire en CHF", text: $price).keyboardType(.decimalPad)
            }
            validityFields
            Section {
                Picker("Conditions commerciales", selection: $termsID) {
                    Text("Choisir les conditions").tag(nil as UUID?)
                    ForEach(model.terms) { terms in Text("\(terms.label) · v\(terms.version)").tag(Optional(terms.id)) }
                }
                if let selected = model.terms.first(where: { $0.id == termsID }) {
                    DisclosureGroup("Relire les conditions") { Text(selected.termsText).font(.subheadline).textSelection(.enabled) }
                    if !selected.approved {
                        Label("Ces conditions ne sont pas approuvées. La prestation doit rester inactive.", systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote).foregroundStyle(DrivyTheme.warning).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Toggle("Activer cette prestation", isOn: $enabled)
            } footer: { Text("Cette version concerne une leçon individuelle. Le tarif doit être explicitement convenu à chaque réservation.") }
        }
    }
    private var availabilityFields: some View {
        Group {
            Section {
                instructorLabel
                ForEach(1...7, id: \.self) { day in
                    Toggle(SchoolPlanningFormat.weekdays([day]), isOn: Binding(get: { days.contains(day) }, set: { selected in
                        if selected { days.insert(day) } else { days.remove(day) }
                    }))
                }
            } header: { Text("Les jours") }
            Section {
                field("Heure de début", text: $localStart, placeholder: "HH:mm").keyboardType(.numbersAndPunctuation)
                field("Heure de fin", text: $localEnd, placeholder: "HH:mm").keyboardType(.numbersAndPunctuation)
            } header: { Text("Heures locales · \(model.timeZone)") }
            validityFields
        }
    }
    private var instructorLabel: some View {
        LabeledContent("Moniteur", value: model.instructors.first(where: { $0.id == (request.rule?.instructorMembershipId ?? model.instructorID) })?.displayName ?? "Moniteur choisi")
    }
    private func field(_ title: String, text: Binding<String>, placeholder: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
            Text(title).font(.subheadline).foregroundStyle(DrivyTheme.muted).accessibilityHidden(true)
            TextField(placeholder ?? title, text: text).accessibilityLabel(title)
        }.padding(.vertical, DrivySpacing.xxs)
    }
    private func multilineField(_ title: String, text: Binding<String>, lines: ClosedRange<Int> = 2...6) -> some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
            Text(title).font(.subheadline).foregroundStyle(DrivyTheme.muted).accessibilityHidden(true)
            TextField(title, text: text, axis: .vertical).lineLimit(lines).accessibilityLabel(title)
        }.padding(.vertical, DrivySpacing.xxs)
    }
    private var saveBar: some View {
        DrivyStickyActionBar {
            if let error = model.errorMessage {
                DrivyActionNote(text: error, isError: true)
            } else if let hint = validationHint {
                DrivyActionNote(text: hint)
            } else if !confirmed {
                DrivyActionNote(text: "Confirmez la relecture des informations avant d’enregistrer.")
            }
            if request.kind == .removeAvailability || request.kind == .removeClosure {
                Button(role: .destructive, action: save) {
                    HStack(spacing: DrivySpacing.xs) {
                        if model.isBusy { ProgressView() }
                        Text(model.isBusy ? "Retrait en cours…" : actionTitle)
                    }
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered).controlSize(.large)
                .disabled(!valid || !confirmed || !model.canMutate)
            } else {
                Button(action: save) {
                    HStack(spacing: DrivySpacing.xs) {
                        if model.isBusy { ProgressView() }
                        Text(model.isBusy ? "Enregistrement…" : actionTitle)
                    }
                }.buttonStyle(DrivyPrimaryButtonStyle()).disabled(!valid || !confirmed || !model.canMutate)
            }
        }
    }
    private var formValues: [String] {
        [label, reference, category, termsText, reason, price, duration, unit, termsID?.uuidString ?? "",
         String(validFrom.timeIntervalSince1970), String(validUntil.timeIntervalSince1970), String(starts.timeIntervalSince1970),
         String(ends.timeIntervalSince1970), String(hasEnd), String(approved), String(enabled),
         days.sorted().map(String.init).joined(separator: ","), localStart, localEnd, model.instructorID?.uuidString ?? ""]
    }
    private var validityFields: some View {
        Section("Validité") {
            DatePicker("Dès le", selection: $validFrom, displayedComponents: .date)
            Toggle("Définir une date de fin", isOn: $hasEnd)
            if hasEnd { DatePicker("Jusqu’au", selection: $validUntil, in: validFrom..., displayedComponents: .date) }
        }
    }
    private var confirmationText: String {
        switch request.kind {
        case .terms: "J’ai relu les textes et leur validité"
        case .product: "J’ai vérifié le tarif et les conditions"
        case .availability: "Ces horaires sont corrects"
        case .closure: "Je confirme cette période de fermeture"
        case .removeAvailability, .removeClosure: "Je confirme le retrait"
        }
    }
    private var actionTitle: String {
        switch request.kind {
        case .terms: approved ? "Créer les conditions approuvées" : "Enregistrer le brouillon"
        case .product: enabled ? "Créer la prestation active" : "Créer la prestation inactive"
        case .availability: request.rule == nil ? "Ajouter la disponibilité" : "Enregistrer les horaires"
        case .closure: "Fermer cette période"
        case .removeAvailability, .removeClosure: "Confirmer le retrait"
        }
    }
    private var valid: Bool {
        guard !hasEnd || validUntil >= validFrom else { return false }
        switch request.kind {
        case .terms: return nonBlank(label, max: 200) && nonBlank(termsText, max: 20_000) && nonBlank(reason, max: 1000)
        case .product:
            guard nonBlank(label, max: 200), nonBlank(reference, max: 100), nonBlank(category, max: 30),
                  nonBlank(unit, max: 100), let duration = Int(duration), (1...480).contains(duration),
                  SchoolCatalogFormatting.cents(price) != nil, let terms = model.terms.first(where: { $0.id == termsID }) else { return false }
            return !enabled || terms.approved
        case .availability: return !days.isEmpty && validTime(localStart) && validTime(localEnd) && localEnd > localStart && (request.rule?.instructorMembershipId ?? model.instructorID) != nil
        case .closure: return ends > starts && reason.count <= 1000 && model.instructorID != nil
        case .removeAvailability, .removeClosure: return nonBlank(reason, max: 1000)
        }
    }
    private var validationHint: String? {
        guard !valid else { return nil }
        if hasEnd && validUntil < validFrom { return "La date de fin doit suivre la date de début." }
        switch request.kind {
        case .terms:
            if !nonBlank(label, max: 200) { return "Nommez les conditions, en 200 caractères maximum." }
            if !nonBlank(termsText, max: 20_000) { return "Renseignez les conditions, limitées à 20 000 caractères." }
            return "Indiquez le motif de cette version, limité à 1 000 caractères."
        case .product:
            if !nonBlank(label, max: 200) { return "Nommez la prestation, en 200 caractères maximum." }
            if !nonBlank(reference, max: 100) { return "Renseignez la référence, limitée à 100 caractères." }
            if !nonBlank(category, max: 30) { return "Renseignez la catégorie de permis." }
            if !nonBlank(unit, max: 100) { return "Précisez l’unité facturée, limitée à 100 caractères." }
            guard let minutes = Int(duration), (1...480).contains(minutes) else { return "La durée doit être comprise entre 1 et 480 minutes." }
            if SchoolCatalogFormatting.cents(price) == nil { return "Vérifiez le prix en CHF." }
            guard let terms = model.terms.first(where: { $0.id == termsID }) else { return "Choisissez les conditions commerciales à appliquer." }
            if enabled && !terms.approved { return "Approuvez les conditions avant d’activer la prestation." }
            return "Vérifiez les informations de la prestation."
        case .availability:
            if (request.rule?.instructorMembershipId ?? model.instructorID) == nil { return "Choisissez un moniteur." }
            if days.isEmpty { return "Choisissez au moins un jour." }
            if !validTime(localStart) || !validTime(localEnd) { return "Saisissez les deux horaires au format HH:mm." }
            return "L’heure de fin doit être après l’heure de début."
        case .closure:
            if model.instructorID == nil { return "Choisissez un moniteur." }
            if ends <= starts { return "La fermeture doit se terminer après son début." }
            return "Le motif est limité à 1 000 caractères."
        case .removeAvailability, .removeClosure:
            return "Indiquez le motif du retrait, limité à 1 000 caractères."
        }
    }
    private func nonBlank(_ text: String, max: Int) -> Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.count <= max }
    private func validTime(_ text: String) -> Bool {
        text.range(of: "^([01][0-9]|2[0-3]):[0-5][0-9]$", options: .regularExpression) != nil
    }
    private func populate() {
        if let terms = request.terms { label = terms.label; termsText = terms.termsText }
        if let product = request.product {
            label = product.label; reference = product.productKey; category = product.categoryCode ?? ""
            duration = product.durationMinutes.map(String.init) ?? ""; unit = product.unitLabel
            price = NSDecimalNumber(decimal: Decimal(product.unitPriceCents) / 100).stringValue; termsID = product.termsVersionId
        }
        if let rule = request.rule {
            days = Set(rule.weekdays); localStart = rule.localStart; localEnd = rule.localEnd
            let format = DateFormatter(); format.calendar = Calendar(identifier: .gregorian); format.locale = Locale(identifier: "en_US_POSIX")
            format.timeZone = TimeZone(identifier: model.timeZone); format.dateFormat = "yyyy-MM-dd"
            validFrom = format.date(from: rule.validFrom) ?? validFrom
            if let end = rule.validUntil.flatMap({ format.date(from: $0) }) { validUntil = end; hasEnd = true }
        }
    }
    private func save() {
        guard valid && confirmed else { return }
        let trim: (String) -> String = { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        var body: [String: Any] = [:]
        let kind: SchoolCommandKind
        var resourceID: UUID?, version = 0
        let date = SchoolCatalogFormatting.civilDate(validFrom, timeZone: model.timeZone)
        let until: Any = hasEnd ? SchoolCatalogFormatting.civilDate(validUntil, timeZone: model.timeZone) as Any : NSNull()
        switch request.kind {
        case .terms:
            kind = .createCommercialTerms
            body = ["label": trim(label), "termsText": trim(termsText), "validFrom": date, "validUntil": until,
                    "approved": approved, "approvalReason": trim(reason)]
        case .product:
            guard let termsID, let duration = Int(duration), let cents = SchoolCatalogFormatting.cents(price) else { return }
            kind = .createServiceProduct
            body = ["productKey": trim(reference), "label": trim(label), "type": "INDIVIDUAL_LESSON", "categoryCode": trim(category),
                    "siteId": NSNull(), "durationMinutes": duration, "unitLabel": trim(unit), "unitPriceCents": cents,
                    "validFrom": date, "validUntil": until, "termsVersionId": termsID.uuidString, "enabled": enabled]
        case .availability:
            guard let instructor = request.rule?.instructorMembershipId ?? model.instructorID else { return }
            kind = request.rule == nil ? .createAvailabilityRule : .updateAvailabilityRule
            resourceID = request.rule?.id; version = request.rule?.version ?? 0
            body = ["instructorMembershipId": instructor.uuidString, "weekdays": days.sorted(), "localStart": localStart,
                    "localEnd": localEnd, "validFrom": date, "validUntil": until]
        case .closure:
            guard let instructor = model.instructorID else { return }
            kind = .createClosure; let iso = ISO8601DateFormatter()
            body = ["instructorMembershipId": instructor.uuidString, "startsAt": iso.string(from: starts), "endsAt": iso.string(from: ends), "reason": trim(reason)]
        case .removeAvailability:
            guard let rule = request.rule else { return }
            kind = .removeAvailabilityRule; resourceID = rule.id; version = rule.version; body = ["reason": trim(reason)]
        case .removeClosure:
            guard let closure = request.closure else { return }
            kind = .removeClosure; resourceID = closure.id; version = closure.version; body = ["reason": trim(reason)]
        }
        Task {
            if await model.submit(kind, body: body, resourceID: resourceID, version: version) {
                dismiss()
            } else if let pending = model.pending, pending.kind == kind, pending.resourceID == resourceID {
                awaitingCommandID = pending.id
            }
        }
    }
}
