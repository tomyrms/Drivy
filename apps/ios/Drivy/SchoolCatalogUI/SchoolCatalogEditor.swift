import SwiftUI

struct SchoolCatalogEditor: View {
    @Bindable var model: SchoolCatalogWorkspace
    let kind: SchoolCatalogEditorKind
    private let isRevision: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var offering = SchoolOfferingDraft()
    @State private var curriculum = SchoolCurriculumDraft()
    @State private var policy = SchoolCatalogPolicyDraft()
    @State private var offeringID: UUID?
    @State private var memberID: UUID?
    @State private var includesStart = false
    @State private var startDate = Date()
    @State private var includesEnd = false
    @State private var endDate = Date().addingTimeInterval(86_400)
    @State private var reviewed = false
    @State private var showsReview = false
    @State private var hasSubmitted = false

    init(model: SchoolCatalogWorkspace, kind: SchoolCatalogEditorKind, sourceOffering: SchoolOffering? = nil,
        sourceCurriculum: SchoolCurriculum? = nil, sourcePolicy: SchoolCatalogPolicy? = nil) {
        self.model = model; self.kind = kind
        isRevision = sourceOffering != nil || sourceCurriculum != nil || sourcePolicy != nil
        var offerDraft = SchoolOfferingDraft()
        if let sourceOffering {
            offerDraft.key = sourceOffering.offeringKey; offerDraft.category = sourceOffering.categoryCode
            offerDraft.duration = String(sourceOffering.defaultDurationMinutes)
            offerDraft.price = "\(sourceOffering.defaultPriceCents / 100).\(String(format: "%02lld", sourceOffering.defaultPriceCents % 100))"
            offerDraft.curriculumID = sourceOffering.curriculumVersionId; offerDraft.policyID = sourceOffering.policyVersionId
        }
        _offering = State(initialValue: offerDraft)
        var curriculumDraft = SchoolCurriculumDraft()
        if let sourceCurriculum {
            curriculumDraft.category = sourceCurriculum.categoryCode
            curriculumDraft.competencies = sourceCurriculum.competencies.sorted { $0.sortOrder < $1.sortOrder }.map { source in
                var row = SchoolCompetencyDraft(); row.key = source.key; row.label = source.label; row.explanation = source.description
                return row
            }
        }
        _curriculum = State(initialValue: curriculumDraft)
        var policyDraft = SchoolCatalogPolicyDraft()
        if let sourcePolicy {
            policyDraft.category = sourcePolicy.categoryCode; policyDraft.procedure = sourcePolicy.procedureText
            policyDraft.cancellation = sourcePolicy.cancellationPolicyText; policyDraft.sources = sourcePolicy.sourceUrls.joined(separator: "\n")
        }
        _policy = State(initialValue: policyDraft)
        // A new revision always requires a new approval/activation and reason.
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(model.learner?.displayName ?? model.school?.name ?? "Votre école").font(.headline)
                    Text(introduction).font(.subheadline).foregroundStyle(DrivyTheme.muted)
                }
                if let error = model.errorMessage {
                    Section { SchoolErrorNotice(message: error, retry: { Task { await model.load() } }) }
                }
                if model.pending != nil {
                    Section { pendingNotice }
                }
                editorFields
            }
            .scrollContentBackground(.hidden)
            .background(DrivyTheme.canvas)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 10) {
                    if !isValid, model.canMutate {
                        Text(validationHint)
                            .font(.footnote).foregroundStyle(DrivyTheme.muted)
                    }
                    Button("Relire avant d’enregistrer") {
                        reviewed = false
                        hasSubmitted = false
                        showsReview = true
                    }
                    .buttonStyle(DrivyPrimaryButtonStyle())
                    .disabled(!isValid || !model.canMutate)
                }
                .padding(16).frame(maxWidth: 680).frame(maxWidth: .infinity)
                .background(DrivyTheme.surface)
            }
            .disabled(model.isBusy)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() }.disabled(model.isBusy) } }
            .environment(\.timeZone, TimeZone(identifier: model.school?.timeZone ?? "Europe/Zurich") ?? .current)
            .interactiveDismissDisabled(model.isBusy)
            .onChange(of: offering.category) { _, _ in offering.curriculumID = nil; offering.policyID = nil; reviewed = false }
            .sheet(isPresented: $showsReview, onDismiss: { reviewed = false }) { reviewSheet }
        }
        .tint(DrivyTheme.accent)
    }

    @ViewBuilder private var editorFields: some View {
        switch kind {
        case .offering: offeringFields
        case .curriculum: curriculumFields
        case .policy: policyFields
        case .training: trainingFields
        case .assignment: assignmentFields
        }
    }

    private var trainingFields: some View {
        Group {
            Section("Offre de l’école") {
                Picker("Offre", selection: $offeringID) {
                    Text("Choisir une offre").tag(nil as UUID?)
                    ForEach(model.availableOfferings) { offer in
                        Text("\(offer.categoryCode) · \(offer.offeringKey)").tag(Optional(offer.id))
                    }
                }
                if let selected = model.availableOfferings.first(where: { $0.id == offeringID }) {
                    LabeledContent("Durée proposée", value: "\(selected.defaultDurationMinutes) min")
                    LabeledContent("Prix proposé", value: SchoolCatalogFormatting.price(selected.defaultPriceCents))
                    Text("Version \(selected.version) de l’offre").font(.footnote).foregroundStyle(DrivyTheme.muted)
                }
            }
            Section {
                Toggle("Préciser une date de début", isOn: $includesStart)
                if includesStart { DatePicker("Début", selection: $startDate, displayedComponents: .date) }
            } footer: { Text("Sans date choisie, la formation reste sans date de début déclarée.") }
        }
    }

    private var assignmentFields: some View {
        Group {
            Section("Accompagnement") {
                Picker("Moniteur", selection: $memberID) {
                    Text("Choisir un moniteur").tag(nil as UUID?)
                    ForEach(model.instructors) { member in Text(member.displayName).tag(Optional(member.id)) }
                }
                if model.instructors.isEmpty { Text("Aucun membre actif ne dispose du rôle Moniteur.").foregroundStyle(DrivyTheme.muted) }
            }
            Section {
                DatePicker("Début de l’affectation", selection: $startDate)
                Toggle("Prévoir une fin", isOn: $includesEnd)
                if includesEnd { DatePicker("Fin de l’affectation", selection: $endDate, in: startDate...) }
            } footer: { Text("Heures de l’école : \(model.school?.timeZone ?? "Europe/Zurich"). La fin, si définie, ferme cet accès à cette heure.") }
        }
    }

    private var offeringFields: some View {
        Group {
            Section("Identifier l’offre") {
                labeledField("Référence de l’offre", text: $offering.key)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                labeledField("Catégorie", text: $offering.category)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
            }
            Section("Contenus de cette catégorie") {
                Picker("Référentiel", selection: $offering.curriculumID) {
                    Text("Choisir un référentiel").tag(nil as UUID?)
                    ForEach(matchingCurricula) { value in
                        Text("Révision \(value.revision) · \(value.approved ? "Approuvée" : "Brouillon")").tag(Optional(value.id))
                    }
                }
                Picker("Procédure", selection: $offering.policyID) {
                    Text("Choisir une procédure").tag(nil as UUID?)
                    ForEach(matchingPolicies) { value in
                        Text("Version \(value.version) · \(value.approved ? "Approuvée" : "Brouillon")").tag(Optional(value.id))
                    }
                }
                if matchingCurricula.isEmpty || matchingPolicies.isEmpty {
                    Text("Créez d’abord les contenus de cette catégorie dans Référentiels et Procédures.")
                        .font(.footnote).foregroundStyle(DrivyTheme.muted)
                }
            }
            Section {
                labeledField("Durée en minutes", text: $offering.duration).keyboardType(.numberPad)
                labeledField("Prix en CHF", text: $offering.price).keyboardType(.decimalPad)
                Toggle("Activer cette offre", isOn: $offering.enabled)
                if offering.enabled && !offeringReferencesApproved {
                    Text("L’activation exige un référentiel et une procédure approuvés. Choisissez leurs versions, ou gardez l’offre désactivée.")
                        .font(.subheadline).foregroundStyle(DrivyTheme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text("Conditions proposées")
            } footer: {
                Text("Une offre activée permet d’ouvrir de nouvelles formations. Elle exige un référentiel et une procédure approuvés ; ce choix ne les approuve pas.")
            }
        }
    }

    private var curriculumFields: some View {
        Group {
            Section("Catégorie") {
                TextField("Catégorie", text: $curriculum.category).textInputAutocapitalization(.characters).autocorrectionDisabled()
            }
            ForEach($curriculum.competencies) { $competency in
                Section {
                    labeledField("Intitulé", text: $competency.label)
                    labeledField("Référence", text: $competency.key).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Description", text: $competency.explanation, axis: .vertical).lineLimit(3...8)
                    if curriculum.competencies.count > 1 {
                        Button("Retirer cette compétence", role: .destructive) { curriculum.competencies.removeAll { $0.id == competency.id } }
                    }
                } header: { Text("Compétence \((curriculum.competencies.firstIndex(where: { $0.id == competency.id }) ?? 0) + 1)") }
            }
            Section {
                Button { curriculum.competencies.append(SchoolCompetencyDraft()) } label: { Label("Ajouter une compétence", systemImage: "plus") }
                    .disabled(curriculum.competencies.count >= 200)
            }
            Section {
                Toggle("Approuver ce référentiel", isOn: $curriculum.approved)
                TextField("Motif de cette version", text: $curriculum.reason, axis: .vertical).lineLimit(3...6)
            } footer: {
                Text("Sans approbation, cette version reste un brouillon. Une version existante n’est jamais réécrite.")
            }
        }
    }

    private var policyFields: some View {
        Group {
            Section("Catégorie") {
                TextField("Catégorie", text: $policy.category).textInputAutocapitalization(.characters).autocorrectionDisabled()
            }
            Section("Déroulement de la formation") {
                TextField("Procédure de l’école", text: $policy.procedure, axis: .vertical).lineLimit(5...12)
            }
            Section("Conditions d’annulation") {
                TextField("Conditions applicables", text: $policy.cancellation, axis: .vertical).lineLimit(5...12)
            }
            Section {
                DisclosureGroup("Sources · facultatif") {
                    TextField("Une adresse web par ligne", text: $policy.sources, axis: .vertical)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().lineLimit(2...6)
                }
            }
            Section {
                Toggle("Approuver ces textes", isOn: $policy.approved)
                TextField("Motif de cette version", text: $policy.reason, axis: .vertical).lineLimit(3...6)
            } footer: {
                Text("Vous approuvez les textes affichés pour cette catégorie. Cette procédure est distincte de la notice de données et des informations du profil.")
            }
        }
    }

    private var matchingCurricula: [SchoolCurriculum] {
        model.curricula.filter { $0.categoryCode == offering.category.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
    private var matchingPolicies: [SchoolCatalogPolicy] {
        model.policies.filter { $0.categoryCode == offering.category.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
    private var offeringReferencesApproved: Bool {
        matchingCurricula.first(where: { $0.id == offering.curriculumID })?.approved == true
            && matchingPolicies.first(where: { $0.id == offering.policyID })?.approved == true
    }
    private var isValid: Bool {
        switch kind {
        case .offering:
            guard offering.isValid else { return false }
            guard let curriculum = matchingCurricula.first(where: { $0.id == offering.curriculumID }),
                  let policy = matchingPolicies.first(where: { $0.id == offering.policyID }) else { return false }
            return !offering.enabled || curriculum.approved && policy.approved
        case .curriculum: return curriculum.isValid
        case .policy: return policy.isValid
        case .training: return model.availableOfferings.contains { $0.id == offeringID }
        case .assignment: return model.instructors.contains { $0.id == memberID } && (!includesEnd || endDate > startDate)
        }
    }
    private var validationHint: String {
        switch kind {
        case .offering:
            if offering.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Donnez une référence à l’offre." }
            if offering.key.count > 80 { return "La référence est limitée à 80 caractères." }
            if offering.category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Indiquez la catégorie de l’offre." }
            if offering.category.count > 30 { return "La catégorie est limitée à 30 caractères." }
            if Int(offering.duration).map({ (1...480).contains($0) }) != true { return "Indiquez une durée entre 1 et 480 minutes." }
            if SchoolCatalogFormatting.cents(offering.price) == nil { return "Indiquez un prix valide en CHF." }
            if !matchingCurricula.contains(where: { $0.id == offering.curriculumID }) { return "Choisissez un référentiel de cette catégorie." }
            if !matchingPolicies.contains(where: { $0.id == offering.policyID }) { return "Choisissez une procédure de cette catégorie." }
            return "L’activation exige un référentiel et une procédure approuvés."
        case .curriculum:
            if curriculum.category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Indiquez la catégorie du référentiel." }
            if curriculum.category.count > 30 { return "La catégorie est limitée à 30 caractères." }
            if let index = curriculum.competencies.firstIndex(where: { !$0.isValid }) {
                let competency = curriculum.competencies[index]
                if competency.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Nommez la compétence \(index + 1)." }
                if competency.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Donnez une référence à la compétence \(index + 1)." }
                if competency.explanation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Décrivez la compétence \(index + 1)." }
                return "Compétence \(index + 1) : référence 80 caractères, intitulé 200, description 4 000 maximum."
            }
            if Set(curriculum.competencies.map { $0.key.trimmingCharacters(in: .whitespacesAndNewlines) }).count != curriculum.competencies.count {
                return "Chaque compétence doit avoir une référence différente."
            }
            return curriculum.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Indiquez le motif de cette version." : "Le motif est limité à 1 000 caractères."
        case .policy:
            if policy.category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Indiquez la catégorie de la procédure." }
            if policy.category.count > 30 { return "La catégorie est limitée à 30 caractères." }
            if policy.procedure.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Décrivez le déroulement de la formation." }
            if policy.procedure.count > 4000 { return "Le déroulement est limité à 4 000 caractères." }
            if policy.cancellation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Renseignez les conditions d’annulation." }
            if policy.cancellation.count > 4000 { return "Les conditions d’annulation sont limitées à 4 000 caractères." }
            if policy.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Indiquez le motif de cette version." }
            if policy.reason.count > 1000 { return "Le motif est limité à 1 000 caractères." }
            return "Vérifiez les sources : une adresse web complète par ligne, 30 au maximum."
        case .training:
            return "Choisissez une offre de l’école."
        case .assignment:
            return !model.instructors.contains(where: { $0.id == memberID }) ? "Choisissez le moniteur de cette formation." : "La fin de l’affectation doit suivre son début."
        }
    }
    private var title: String {
        switch kind { case .offering: isRevision ? "Nouvelle version d’offre" : "Nouvelle offre"
        case .curriculum: isRevision ? "Réviser le référentiel" : "Nouveau référentiel"
        case .policy: isRevision ? "Réviser la procédure" : "Nouvelle procédure"
        case .training: "Nouvelle formation"; case .assignment: "Affecter un moniteur" }
    }
    private var introduction: String {
        switch kind {
        case .offering: "Une offre précise les contenus, la durée et le prix proposés pour une catégorie."
        case .curriculum: "Définissez les compétences à travailler. Les noms et descriptions sont propres à cette version."
        case .policy: "Rédigez la procédure et les conditions que votre école applique à cette catégorie."
        case .training: "La formation conservera la version exacte de l’offre choisie. L’affectation du moniteur se fait ensuite."
        case .assignment: "Cette affectation donne au moniteur l’accès autorisé à cette formation pendant la période choisie."
        }
    }
    private var actionTitle: String {
        switch kind {
        case .offering: offering.enabled ? "Créer et activer l’offre" : "Créer l’offre désactivée"
        case .curriculum: curriculum.approved ? "Créer le référentiel approuvé" : "Enregistrer le brouillon"
        case .policy: policy.approved ? "Créer la procédure approuvée" : "Enregistrer le brouillon"
        case .training: "Créer la formation"
        case .assignment: "Confirmer l’affectation"
        }
    }

    private func labeledField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.subheadline).foregroundStyle(DrivyTheme.muted)
            TextField(label, text: text).accessibilityLabel(label)
        }.padding(.vertical, 4)
    }

    private var pendingNotice: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Résultat à vérifier").font(.headline)
            Text("Votre demande est conservée. Vérifiez son résultat avant de la remplacer.").font(.subheadline)
            Button("Vérifier la demande") {
                Task {
                    await model.verifyPending()
                    if model.pending == nil && model.accessFailure == nil && model.successMessage != nil { dismiss() }
                }
            }.frame(minHeight: 44).disabled(!model.canVerify)
            if model.canRetry {
                Button("Renvoyer la même demande") {
                    Task {
                        await model.retryPending()
                        if model.pending == nil && model.accessFailure == nil && model.successMessage != nil { dismiss() }
                    }
                }.frame(minHeight: 44)
            }
        }
    }

    private var reviewSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(model.learner?.displayName ?? model.school?.name ?? "Votre école")
                        .font(.subheadline).foregroundStyle(DrivyTheme.muted)
                    reviewContent
                    Divider()
                    if hasSubmitted, let error = model.errorMessage {
                        SchoolErrorNotice(message: error, retry: model.pending == nil ? { Task { await model.load() } } : nil)
                    }
                    if model.pending != nil {
                        pendingNotice
                    } else {
                        Toggle(reviewAcknowledgement, isOn: $reviewed)
                            .disabled(model.isBusy)
                    }
                }
                .padding(24).frame(maxWidth: 680, alignment: .leading).frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    hasSubmitted = true
                    Task { await save() }
                } label: {
                    HStack(spacing: 10) {
                        if model.isBusy { ProgressView() }
                        Text(model.isBusy ? "Enregistrement…" : model.pending != nil ? "Résultat à vérifier" : actionTitle)
                    }
                }
                .buttonStyle(DrivyPrimaryButtonStyle())
                .disabled(!isValid || !reviewed || !model.canMutate)
                .padding(16).frame(maxWidth: 680).frame(maxWidth: .infinity)
                .background(DrivyTheme.surface)
            }
            .background(DrivyTheme.canvas)
            .navigationTitle("Relire et confirmer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Retour") { showsReview = false }.disabled(model.isBusy)
                }
            }
            .interactiveDismissDisabled(model.isBusy)
        }
    }

    @ViewBuilder private var reviewContent: some View {
        switch kind {
        case .offering:
            Text("Catégorie \(offering.category)").font(.title2.weight(.bold))
            reviewValue("Référence", offering.key)
            reviewValue("Durée", "\(offering.duration) min")
            if let cents = SchoolCatalogFormatting.cents(offering.price) {
                reviewValue("Prix", SchoolCatalogFormatting.price(cents))
            }
            if let reference = matchingCurricula.first(where: { $0.id == offering.curriculumID }) {
                reviewValue("Référentiel", "Révision \(reference.revision) · \(reference.approved ? "Approuvée" : "Brouillon")")
            }
            if let reference = matchingPolicies.first(where: { $0.id == offering.policyID }) {
                reviewValue("Procédure", "Version \(reference.version) · \(reference.approved ? "Approuvée" : "Brouillon")")
            }
            Text(offering.enabled ? "Cette offre sera ouverte aux nouvelles formations." : "Cette offre restera désactivée.")
                .font(.headline)
        case .curriculum:
            Text("Catégorie \(curriculum.category)").font(.title2.weight(.bold))
            ForEach(curriculum.competencies) { competency in
                VStack(alignment: .leading, spacing: 8) {
                    Text(competency.label).font(.headline)
                    Text(competency.explanation)
                    Text(competency.key).font(.caption).foregroundStyle(DrivyTheme.muted)
                }
            }
            reviewValue("Motif de la version", curriculum.reason)
            Text(curriculum.approved ? "Le référentiel sera approuvé pour cette catégorie." : "Le référentiel restera un brouillon.")
                .font(.headline)
        case .policy:
            Text("Catégorie \(policy.category)").font(.title2.weight(.bold))
            reviewValue("Déroulement de la formation", policy.procedure)
            reviewValue("Conditions d’annulation", policy.cancellation)
            if !policy.urls.isEmpty { reviewValue("Sources", policy.urls.joined(separator: "\n")) }
            reviewValue("Motif de la version", policy.reason)
            Text(policy.approved ? "Ces textes seront approuvés pour cette catégorie." : "Ces textes resteront un brouillon.")
                .font(.headline)
        case .training:
            if let selected = model.availableOfferings.first(where: { $0.id == offeringID }) {
                Text("Catégorie \(selected.categoryCode)").font(.title2.weight(.bold))
                reviewValue("Offre", "\(selected.offeringKey) · version \(selected.version)")
                reviewValue("Conditions proposées", "\(selected.defaultDurationMinutes) min · \(SchoolCatalogFormatting.price(selected.defaultPriceCents))")
            }
            reviewValue("Date de début", includesStart ? reviewDate(startDate, includesTime: false) : "Non précisée")
        case .assignment:
            Text(model.instructors.first(where: { $0.id == memberID })?.displayName ?? "Moniteur")
                .font(.title2.weight(.bold))
            reviewValue("Début de l’affectation", reviewDate(startDate))
            reviewValue("Fin", includesEnd ? reviewDate(endDate) : "Aucune date prévue")
        }
    }

    private func reviewValue(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text(value).textSelection(.enabled)
        }
    }

    private var reviewAcknowledgement: String {
        switch kind {
        case .offering: offering.enabled ? "Je confirme ces conditions et l’activation de cette offre." : "Je confirme ces conditions, sans activer l’offre."
        case .curriculum: curriculum.approved ? "J’ai relu les compétences et je confirme leur approbation." : "Je confirme l’enregistrement de ce brouillon."
        case .policy: policy.approved ? "J’ai relu ces textes et je confirme leur approbation." : "Je confirme l’enregistrement de ce brouillon."
        case .training: "Je confirme l’ouverture de cette formation avec cette offre."
        case .assignment: "Je confirme ce moniteur et cette période d’affectation."
        }
    }

    private func reviewDate(_ date: Date, includesTime: Bool = true) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_CH")
        formatter.timeZone = TimeZone(identifier: model.school?.timeZone ?? "Europe/Zurich")
        formatter.dateStyle = .long
        formatter.timeStyle = includesTime ? .short : .none
        return formatter.string(from: date)
    }
    private func save() async {
        guard reviewed, isValid else { return }
        let success: Bool
        switch kind {
        case .offering: success = await model.createOffering(offering)
        case .curriculum: success = await model.createCurriculum(curriculum)
        case .policy: success = await model.createPolicy(policy)
        case .training:
            guard let offeringID else { return }
            success = await model.createTraining(offeringID: offeringID,
                startedOn: includesStart ? SchoolCatalogFormatting.civilDate(startDate, timeZone: model.school?.timeZone ?? "Europe/Zurich") : nil)
        case .assignment:
            guard let memberID else { return }
            success = await model.createAssignment(memberID: memberID, from: startDate, until: includesEnd ? endDate : nil)
        }
        if success { dismiss() }
    }
}
