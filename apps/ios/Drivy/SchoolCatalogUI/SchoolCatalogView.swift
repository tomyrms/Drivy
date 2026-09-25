import SwiftUI

struct SchoolCatalogView: View {
    @Bindable var model: SchoolCatalogWorkspace
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var section: CatalogSection = .offerings
    @State private var editor: CatalogEditorPresentation?
    @State private var showsTeam = false
    private enum CatalogSection: String, CaseIterable { case offerings = "Offres", curricula = "Référentiels", policies = "Procédures" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DrivySpacing.l) {
                    heading
                    feedback
                    if model.learner != nil { learnerTrainings }
                    else { catalog }
                }
                .drivyPageContent()
            }
            .background(DrivyTheme.surface)
            .navigationTitle(model.learner == nil ? "Formations" : "Dossier de formation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fermer") { dismiss() } }
                if model.learner == nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { showsTeam = true } label: { Label("Équipe", systemImage: "person.2") }
                    }
                }
            }
            .refreshable { await model.load() }
            .task { await model.load() }
            .sheet(item: $editor) { presentation in
                SchoolCatalogEditor(model: model, kind: presentation.kind, sourceOffering: presentation.sourceOffering,
                    sourceCurriculum: presentation.sourceCurriculum, sourcePolicy: presentation.sourcePolicy)
            }
            .sheet(isPresented: $showsTeam) { team }
        }
        .tint(DrivyTheme.accent)
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
            Text(model.school?.name ?? "Votre école")
                .font(.subheadline.weight(.semibold)).foregroundStyle(DrivyTheme.muted)
            Text(model.learner?.displayName ?? "Formations")
                .font(.drivyScreenTitle).foregroundStyle(DrivyTheme.text)
                .accessibilityAddTraits(.isHeader)
            if model.learner != nil {
                Text("Choisissez une formation, puis affectez le moniteur qui accompagnera cet élève.")
                    .font(.subheadline).foregroundStyle(DrivyTheme.muted)
                    .padding(.top, DrivySpacing.xxs)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var feedback: some View {
        if model.isLoading { ProgressView("Actualisation de l’école…").frame(maxWidth: .infinity, minHeight: 44) }
        if let school = model.school, school.status != "ACTIVE" {
            DrivyInlineMessage(text: "Activez l’école dans sa configuration avant de créer son catalogue.", tone: .warning)
        }
        if let error = model.errorMessage { SchoolErrorNotice(message: error, retry: { Task { await model.load() } }) }
        if let message = model.successMessage {
            DrivyInlineMessage(text: message)
        }
        if let pending = model.pending {
            DrivyPanel {
                DrivyPendingRequest(message: model.pendingSummary,
                    notes: ["Sa référence et son contenu sont conservés. Une nouvelle demande ne la remplace pas."],
                    reference: pending.id,
                    verify: { Task { await model.verifyPending() } }, canVerify: model.canVerify,
                    retry: model.canRetry ? { Task { await model.retryPending() } } : nil)
            }
        }
    }

    private var catalog: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.l) {
            if dynamicTypeSize.isAccessibilitySize {
                sectionPicker.pickerStyle(.menu)
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            } else {
                sectionPicker.pickerStyle(.segmented)
            }
            switch section {
            case .offerings: offerings
            case .curricula: curricula
            case .policies: policies
            }
        }
    }

    private var sectionPicker: some View {
        Picker("Afficher", selection: $section) {
            ForEach(CatalogSection.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        .accessibilityIdentifier("school-catalog-section")
    }

    private var offerings: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.m) {
            catalogActions("Créer une offre", kind: .offering, summary: model.currentOfferings.isEmpty ? nil
                : "\(model.currentOfferings.count) offre\(model.currentOfferings.count == 1 ? "" : "s") · \(model.availableOfferings.count) active\(model.availableOfferings.count == 1 ? "" : "s")")
            if model.currentOfferings.isEmpty && !model.isLoading {
                VStack(alignment: .leading, spacing: 0) {
                    DrivyEmptyState(title: "Votre première offre",
                        message: "Commencez par un référentiel et une procédure. Vous pourrez ensuite définir la durée et le prix de l’offre.",
                        symbol: "steeringwheel")
                    if model.curricula.isEmpty {
                        prerequisiteButton("Créer le référentiel", kind: .curriculum)
                    }
                    if model.policies.isEmpty {
                        prerequisiteButton("Créer la procédure", kind: .policy)
                    }
                }
            }
            DrivyRowGroup {
                ForEach(model.currentOfferings) { offer in
                    catalogEntry(title: "Permis \(offer.categoryCode)", meta: offer.offeringKey,
                        badge: DrivyStatusBadge(title: offer.enabled ? "Ouverte" : "Fermée",
                            symbol: offer.enabled ? "checkmark" : "pause.fill", tone: offer.enabled ? .success : .neutral),
                        symbol: "steeringwheel") {
                        Text("\(offer.defaultDurationMinutes) min · \(SchoolCatalogFormatting.price(offer.defaultPriceCents))")
                            .font(.headline.monospacedDigit()).foregroundStyle(DrivyTheme.text)
                        Text(offer.enabled ? "Ouverte aux nouvelles formations" : "Fermée aux nouvelles formations")
                            .font(.footnote).foregroundStyle(DrivyTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        DisclosureGroup("Contenu de la version \(offer.version)") {
                            VStack(alignment: .leading, spacing: DrivySpacing.xs) {
                                if let curriculum = model.curricula.first(where: { $0.id == offer.curriculumVersionId }) {
                                    Text("Référentiel · révision \(curriculum.revision)")
                                }
                                if let policy = model.policies.first(where: { $0.id == offer.policyVersionId }) {
                                    Text("Procédure · version \(policy.version)")
                                }
                                Text("Une nouvelle version ne modifie pas les formations déjà ouvertes.")
                                    .foregroundStyle(DrivyTheme.muted)
                            }
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, DrivySpacing.xs)
                        }
                        .font(.subheadline)
                        revisionButton("Préparer une nouvelle version") {
                            editor = CatalogEditorPresentation(kind: .offering, sourceOffering: offer)
                        }
                    }
                }
            }
        }
    }
    private var curricula: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.m) {
            catalogActions("Créer un référentiel", kind: .curriculum, summary: "Compétences travaillées dans chaque catégorie.")
            if model.curricula.isEmpty && !model.isLoading {
                DrivyEmptyState(title: "Les compétences de votre école",
                    message: "Définissez ce qui sera travaillé dans chaque catégorie. L’approbation vous appartient.",
                    symbol: "list.bullet.rectangle")
            }
            DrivyRowGroup {
                ForEach(model.curricula.sorted { ($0.categoryCode, -$0.revision) < ($1.categoryCode, -$1.revision) }) { curriculum in
                    catalogEntry(title: "Permis \(curriculum.categoryCode)", meta: "Révision \(curriculum.revision)",
                        badge: DrivyStatusBadge(title: curriculum.approved ? "Approuvé" : "Brouillon",
                            symbol: curriculum.approved ? "checkmark.seal" : "pencil", tone: curriculum.approved ? .success : .warning),
                        symbol: "list.bullet.rectangle") {
                        DisclosureGroup("\(curriculum.competencies.count) compétence\(curriculum.competencies.count == 1 ? "" : "s")") {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(curriculum.competencies.sorted { $0.sortOrder < $1.sortOrder }) { competency in
                                    VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                                        Text(competency.label).font(.headline).foregroundStyle(DrivyTheme.text)
                                        Text(competency.description).font(.subheadline).foregroundStyle(DrivyTheme.muted)
                                    }
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, DrivySpacing.xs)
                                }
                            }
                        }
                        .font(.subheadline)
                        revisionButton("Préparer une nouvelle révision") {
                            editor = CatalogEditorPresentation(kind: .curriculum, sourceCurriculum: curriculum)
                        }
                    }
                }
            }
        }
    }
    private var policies: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.m) {
            catalogActions("Créer une procédure", kind: .policy, summary: "Déroulement et conditions d’annulation par catégorie.")
            if model.policies.isEmpty && !model.isLoading {
                DrivyEmptyState(title: "Vos procédures de formation",
                    message: "Précisez le déroulement et les conditions d’annulation de chaque catégorie.",
                    symbol: "doc.text")
            }
            DrivyRowGroup {
                ForEach(model.policies.sorted { ($0.categoryCode, -$0.version) < ($1.categoryCode, -$1.version) }) { policy in
                    catalogEntry(title: "Permis \(policy.categoryCode)", meta: "Version \(policy.version)",
                        badge: DrivyStatusBadge(title: policy.approved ? "Approuvée" : "Brouillon",
                            symbol: policy.approved ? "checkmark.seal" : "pencil", tone: policy.approved ? .success : .warning),
                        symbol: "doc.text") {
                        DisclosureGroup("Lire la procédure et ses conditions") {
                            VStack(alignment: .leading, spacing: DrivySpacing.s) {
                                Text(policy.procedureText).textSelection(.enabled)
                                Text("Annulation").font(.headline)
                                Text(policy.cancellationPolicyText).textSelection(.enabled)
                                ForEach(Array(policy.sourceUrls.enumerated()), id: \.offset) { _, source in
                                    if let url = URL(string: source), ["https", "http"].contains(url.scheme ?? ""), url.user == nil, url.password == nil {
                                        Link(url.host ?? "Source", destination: url)
                                    }
                                }
                            }
                            .font(.subheadline)
                            .foregroundStyle(DrivyTheme.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, DrivySpacing.s)
                        }
                        .font(.subheadline)
                        revisionButton("Préparer une nouvelle version") {
                            editor = CatalogEditorPresentation(kind: .policy, sourcePolicy: policy)
                        }
                    }
                }
            }
        }
    }

    /// One catalogue entry: the entity row anatomy (symbol, title, meta,
    /// badge), then its details and its revision action.
    private func catalogEntry<Details: View>(title: String, meta: String, badge: DrivyStatusBadge, symbol: String,
                                             @ViewBuilder details: () -> Details) -> some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xs) {
            DrivyEntityRow(title: title, meta: meta, leading: .symbol(symbol), badge: badge)
            VStack(alignment: .leading, spacing: DrivySpacing.xs) { details() }
                .padding(.leading, dynamicTypeSize.isAccessibilitySize ? 0 : 44 + DrivySpacing.s)
        }
        .padding(.vertical, DrivySpacing.xs)
    }

    private func revisionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: "square.and.pencil")
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(model.canMutate ? DrivyTheme.accent : DrivyTheme.disabledText)
        .disabled(!model.canMutate)
    }

    private func prerequisiteButton(_ title: String, kind: SchoolCatalogEditorKind) -> some View {
        Button { editor = CatalogEditorPresentation(kind: kind) } label: {
            Label(title, systemImage: "plus")
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(model.canMutate ? DrivyTheme.accent : DrivyTheme.disabledText)
        .disabled(!model.canMutate)
        .padding(.leading, dynamicTypeSize.isAccessibilitySize ? 0 : DrivySpacing.xl + DrivySpacing.m)
    }

    /// The creation action of the displayed section is the dominant action.
    @ViewBuilder private func catalogActions(_ title: String, kind: SchoolCatalogEditorKind, summary: String?) -> some View {
        let button = Button { editor = CatalogEditorPresentation(kind: kind) } label: { Label(title, systemImage: "plus") }
            .buttonStyle(DrivyPrimaryButtonStyle())
            .disabled(!model.canMutate)
        if horizontalSizeClass == .regular && !dynamicTypeSize.isAccessibilitySize {
            HStack(alignment: .center, spacing: DrivySpacing.l) {
                if let summary { Text(summary).font(.subheadline).foregroundStyle(DrivyTheme.muted) }
                Spacer(minLength: DrivySpacing.xs)
                button.fixedSize()
            }
        } else {
            VStack(alignment: .leading, spacing: DrivySpacing.s) {
                if let summary { Text(summary).font(.subheadline).foregroundStyle(DrivyTheme.muted) }
                button
            }
        }
    }

    private var learnerTrainings: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.m) {
            if model.trainings.isEmpty && !model.isLoading {
                DrivyEmptyState(title: "Aucune formation ouverte",
                    message: "Une formation utilise une offre précise de votre école. L’affectation du moniteur se fait ensuite.",
                    symbol: "steeringwheel")
            }
            ForEach(model.trainings) { training in
                let isSelected = model.selectedTraining?.id == training.id
                Button { Task { await model.selectTraining(training) } } label: {
                    HStack(spacing: DrivySpacing.m) {
                        Image(systemName: "steeringwheel").font(.title3)
                            .foregroundStyle(isSelected ? DrivyTheme.accent : DrivyTheme.muted)
                            .frame(width: 28)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                            Text("Permis \(training.categoryCode)").font(.headline).foregroundStyle(DrivyTheme.text)
                            Text(SchoolPresentation.trainingStatus(training.status)).font(.subheadline).foregroundStyle(DrivyTheme.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        DrivySelectionMark(isSelected: isSelected)
                    }
                }
                .buttonStyle(DrivySelectionCardStyle(isSelected: isSelected))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .disabled(model.isBusy || model.isLoading)
            }
            createButton("Créer une formation", symbol: "plus", kind: .training)
            if model.availableOfferings.isEmpty && !model.isLoading {
                Text("L’administration doit activer une offre dans École → Formations avant d’ouvrir une formation.")
                    .font(.footnote).foregroundStyle(DrivyTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let training = model.selectedTraining {
                assignments(training)
                    .padding(.top, DrivySpacing.s)
            }
        }
    }
    private func assignments(_ training: SchoolTraining) -> some View {
        VStack(alignment: .leading, spacing: DrivySpacing.s) {
            DrivySectionHeader(title: "Moniteurs de cette formation")
            if model.assignments.isEmpty && !model.isLoading {
                DrivyEmptyState(title: "Aucun moniteur affecté",
                    message: "La formation existe déjà ; choisissez la personne qui l’accompagnera.",
                    symbol: "person.badge.plus")
            }
            DrivyRowGroup {
                ForEach(model.assignments) { assignment in
                    let name = model.members.first(where: { $0.id == assignment.instructorMembershipId })?.displayName ?? "Moniteur de l’école"
                    DrivyEntityRow(title: name,
                        meta: assignment.validUntil.map { "Du \(assignmentDate(assignment.validFrom)) au \(assignmentDate($0))" }
                            ?? "Dès le \(assignmentDate(assignment.validFrom))",
                        leading: .avatar(name))
                }
            }
            if training.status == "ACTIVE" {
                createButton("Affecter un moniteur", symbol: "person.badge.plus", kind: .assignment)
                if model.instructors.isEmpty && !model.isLoading {
                    Text("Un membre actif avec le rôle Moniteur est nécessaire pour cette affectation.")
                        .font(.footnote).foregroundStyle(DrivyTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text("Le contrôle du permis reste une vérification distincte. Une formation ne confirme pas une autorisation de conduire.")
                .font(.footnote).foregroundStyle(DrivyTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    private var team: some View {
        NavigationStack {
            List(model.members) { member in
                DrivyEntityRow(title: member.displayName, meta: SchoolPresentation.roles(member.roles),
                    leading: .avatar(member.displayName),
                    badge: member.status != "ACTIVE" ? DrivyStatusBadge(title: "Accès révoqué", symbol: "lock", tone: .warning) : nil)
            }
            .scrollContentBackground(.hidden)
            .background(DrivyTheme.canvas)
            .overlay {
                if model.members.isEmpty {
                    ContentUnavailableView("Aucun membre", systemImage: "person.2",
                        description: Text("Les membres de l’école apparaîtront ici."))
                }
            }
            .navigationTitle("Équipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fermer") { showsTeam = false } } }
        }
        .tint(DrivyTheme.accent)
    }
    private func createButton(_ title: String, symbol: String, kind: SchoolCatalogEditorKind) -> some View {
        Button { editor = CatalogEditorPresentation(kind: kind) } label: { Label(title, systemImage: symbol) }
            .buttonStyle(DrivySecondaryButtonStyle())
            .disabled(!model.canMutate || kind == .training && model.availableOfferings.isEmpty || kind == .assignment && model.instructors.isEmpty)
    }
    private func assignmentDate(_ text: String) -> String {
        guard let date = SchoolInvitation.date(text) else { return "Date indisponible" }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "fr_CH")
        formatter.timeZone = TimeZone(identifier: model.school?.timeZone ?? "Europe/Zurich")
        formatter.dateStyle = .medium; formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

private struct CatalogEditorPresentation: Identifiable {
    let id = UUID()
    let kind: SchoolCatalogEditorKind
    let sourceOffering: SchoolOffering?
    let sourceCurriculum: SchoolCurriculum?
    let sourcePolicy: SchoolCatalogPolicy?

    init(kind: SchoolCatalogEditorKind, sourceOffering: SchoolOffering? = nil,
         sourceCurriculum: SchoolCurriculum? = nil, sourcePolicy: SchoolCatalogPolicy? = nil) {
        self.kind = kind
        self.sourceOffering = sourceOffering
        self.sourceCurriculum = sourceCurriculum
        self.sourcePolicy = sourcePolicy
    }
}

enum SchoolCatalogEditorKind: String, Identifiable {
    case offering, curriculum, policy, training, assignment
    var id: String { rawValue }
}
