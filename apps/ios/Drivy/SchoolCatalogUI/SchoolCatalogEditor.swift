import SwiftUI

struct SchoolCatalogEditor: View {
    @Bindable var model: SchoolCatalogWorkspace
    let kind: SchoolCatalogEditorKind
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

    init(model: SchoolCatalogWorkspace, kind: SchoolCatalogEditorKind, sourceOffering: SchoolOffering? = nil,
        sourceCurriculum: SchoolCurriculum? = nil, sourcePolicy: SchoolCatalogPolicy? = nil) {
        self.model = model; self.kind = kind
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
                    Section {
                        Text("Votre demande reste conservée. Vérifiez son résultat avant de la remplacer.").font(.subheadline)
                        Button("Vérifier la demande") {
                            Task {
                                await model.verifyPending()
                                if model.pending == nil && model.accessFailure == nil { dismiss() }
                            }
                        }.disabled(!model.canVerify)
                    }
                }
                editorFields
                Section {
                    Toggle("J’ai relu les informations et je confirme cette demande.", isOn: $reviewed)
                        .tint(DrivyTheme.accent)
                    Button { Task { await save() } } label: {
                        HStack {
                            if model.isBusy { ProgressView() }
                            Text(model.isBusy ? "Enregistrement…" : actionTitle)
                        }.frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(DrivyPrimaryButtonStyle())
                    .disabled(!isValid || !reviewed || !model.canMutate)
                } footer: {
                    Text("Une réponse interrompue conserve la même demande. Les informations ne sont confirmées qu’après l’enregistrement par l’école.")
                }
            }
            .disabled(model.isBusy)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() }.disabled(model.isBusy) } }
            .environment(\.timeZone, TimeZone(identifier: model.school?.timeZone ?? "Europe/Zurich") ?? .current)
            .interactiveDismissDisabled(model.isBusy)
            .onChange(of: offering.category) { _, _ in offering.curriculumID = nil; offering.policyID = nil; reviewed = false }
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
                TextField("Référence de l’offre", text: $offering.key).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("Catégorie", text: $offering.category).textInputAutocapitalization(.characters).autocorrectionDisabled()
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
                TextField("Durée en minutes", text: $offering.duration).keyboardType(.numberPad)
                TextField("Prix en CHF", text: $offering.price).keyboardType(.decimalPad)
                Toggle("Activer cette offre", isOn: $offering.enabled)
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
                Section("Compétence") {
                    TextField("Référence", text: $competency.key).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Intitulé", text: $competency.label)
                    TextField("Description", text: $competency.explanation, axis: .vertical).lineLimit(3...8)
                    if curriculum.competencies.count > 1 {
                        Button("Retirer cette compétence", role: .destructive) { curriculum.competencies.removeAll { $0.id == competency.id } }
                    }
                }
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
            Section("Sources facultatives") {
                TextField("Une adresse web par ligne", text: $policy.sources, axis: .vertical)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().lineLimit(2...6)
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
    private var title: String {
        switch kind { case .offering: "Nouvelle offre"; case .curriculum: "Nouveau référentiel"; case .policy: "Nouvelle procédure"
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
