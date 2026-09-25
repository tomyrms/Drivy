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
                VStack(alignment: .leading, spacing: 24) {
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
        VStack(alignment: .leading, spacing: 10) {
            Text(model.school?.name ?? "Votre école").font(.subheadline).foregroundStyle(DrivyTheme.muted)
            Text(model.learner?.displayName ?? "Formations").font(.drivyScreenTitle)
            if model.learner != nil {
                Text("Choisissez une offre, puis affectez le moniteur qui accompagnera cet élève.")
                    .font(.subheadline).foregroundStyle(DrivyTheme.muted)
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
                VStack(alignment: .leading, spacing: 12) {
                    Label("Demande à vérifier", systemImage: "clock.arrow.circlepath").font(.headline)
                    Text(model.pendingSummary).font(.subheadline)
                    Text("Sa référence et son contenu sont conservés. Une nouvelle demande ne la remplace pas.")
                        .font(.footnote).foregroundStyle(DrivyTheme.muted)
                    DisclosureGroup("Référence de la demande") {
                        Text(pending.id.uuidString).font(.caption.monospaced()).textSelection(.enabled)
                    }.font(.footnote)
                    Button("Vérifier le résultat") { Task { await model.verifyPending() } }
                        .buttonStyle(DrivySecondaryButtonStyle()).disabled(!model.canVerify)
                    if model.canRetry {
                        Button("Renvoyer la même demande") { Task { await model.retryPending() } }
                            .frame(minHeight: 44)
                    }
                }
            }
        }
    }

    private var catalog: some View {
        VStack(alignment: .leading, spacing: 20) {
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
        VStack(alignment: .leading, spacing: 16) {
            catalogActions("Créer une offre", kind: .offering, summary: model.currentOfferings.isEmpty ? nil
                : "\(model.currentOfferings.count) offre\(model.currentOfferings.count == 1 ? "" : "s") · \(model.availableOfferings.count) active\(model.availableOfferings.count == 1 ? "" : "s")")
            if model.currentOfferings.isEmpty && !model.isLoading {
                empty("Votre première offre", text: "Commencez par un référentiel et une procédure. Vous pourrez ensuite définir la durée et le prix de l’offre.", symbol: "steeringwheel")
                if model.curricula.isEmpty {
                    Button("Créer le référentiel") { editor = CatalogEditorPresentation(kind: .curriculum) }
                        .frame(minHeight: 44).disabled(!model.canMutate)
                }
                if model.policies.isEmpty {
                    Button("Créer la procédure") { editor = CatalogEditorPresentation(kind: .policy) }
                        .frame(minHeight: 44).disabled(!model.canMutate)
                }
            }
            ForEach(model.currentOfferings) { offer in
                VStack(alignment: .leading, spacing: 12) {
                    Divider()
                    HStack(alignment: .firstTextBaseline) {
                        Text("Permis \(offer.categoryCode)").font(.drivySection)
                        Spacer(minLength: DrivySpacing.xs)
                        DrivyStatusBadge(title: offer.enabled ? "Ouverte" : "Fermée",
                            symbol: offer.enabled ? "checkmark" : "pause.fill", tone: offer.enabled ? .success : .neutral)
                    }
                    Text(offer.offeringKey).font(.subheadline).foregroundStyle(DrivyTheme.muted)
                    Text("\(offer.defaultDurationMinutes) min · \(SchoolCatalogFormatting.price(offer.defaultPriceCents))")
                        .font(.headline.monospacedDigit())
                    Text(offer.enabled ? "Ouverte aux nouvelles formations" : "Fermée aux nouvelles formations")
                        .font(.footnote).foregroundStyle(DrivyTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    DisclosureGroup("Contenu de la version \(offer.version)") {
                        VStack(alignment: .leading, spacing: 10) {
                            if let curriculum = model.curricula.first(where: { $0.id == offer.curriculumVersionId }) {
                                Text("Référentiel · révision \(curriculum.revision)")
                            }
                            if let policy = model.policies.first(where: { $0.id == offer.policyVersionId }) {
                                Text("Procédure · version \(policy.version)")
                            }
                            Text("Une nouvelle version ne modifie pas les formations déjà ouvertes.")
                                .foregroundStyle(DrivyTheme.muted)
                        }.font(.subheadline).padding(.top, 8)
                    }
                    Button("Préparer une nouvelle version") {
                        editor = CatalogEditorPresentation(kind: .offering, sourceOffering: offer)
                    }.frame(minHeight: 44).disabled(!model.canMutate)
                }.padding(.vertical, 4)
            }
        }
    }
    private var curricula: some View {
        VStack(alignment: .leading, spacing: 16) {
            catalogActions("Créer un référentiel", kind: .curriculum, summary: "Compétences travaillées dans chaque catégorie.")
            if model.curricula.isEmpty && !model.isLoading {
                empty("Les compétences de votre école", text: "Définissez ce qui sera travaillé dans chaque catégorie. L’approbation vous appartient.", symbol: "list.bullet.rectangle")
            }
            ForEach(model.curricula.sorted { ($0.categoryCode, -$0.revision) < ($1.categoryCode, -$1.revision) }) { curriculum in
                VStack(alignment: .leading, spacing: 12) {
                    Divider()
                    HStack(alignment: .firstTextBaseline) {
                        Text("Permis \(curriculum.categoryCode)").font(.drivySection)
                        Spacer(minLength: DrivySpacing.xs)
                        DrivyStatusBadge(title: curriculum.approved ? "Approuvé" : "Brouillon",
                            symbol: curriculum.approved ? "checkmark.seal" : "pencil", tone: curriculum.approved ? .success : .warning)
                    }
                    Text("Révision \(curriculum.revision)").font(.subheadline).foregroundStyle(DrivyTheme.muted)
                    DisclosureGroup("\(curriculum.competencies.count) compétence\(curriculum.competencies.count == 1 ? "" : "s")") {
                        ForEach(curriculum.competencies.sorted { $0.sortOrder < $1.sortOrder }) { competency in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(competency.label).font(.headline)
                                Text(competency.description).font(.subheadline).foregroundStyle(DrivyTheme.muted)
                            }.padding(.vertical, 8)
                        }
                    }
                    Button("Préparer une nouvelle révision") {
                        editor = CatalogEditorPresentation(kind: .curriculum, sourceCurriculum: curriculum)
                    }.frame(minHeight: 44).disabled(!model.canMutate)
                }.padding(.vertical, 4)
            }
        }
    }
    private var policies: some View {
        VStack(alignment: .leading, spacing: 16) {
            catalogActions("Créer une procédure", kind: .policy, summary: "Déroulement et conditions d’annulation par catégorie.")
            if model.policies.isEmpty && !model.isLoading {
                empty("Vos procédures de formation", text: "Précisez le déroulement et les conditions d’annulation de chaque catégorie.", symbol: "doc.text")
            }
            ForEach(model.policies.sorted { ($0.categoryCode, -$0.version) < ($1.categoryCode, -$1.version) }) { policy in
                VStack(alignment: .leading, spacing: 12) {
                    Divider()
                    HStack(alignment: .firstTextBaseline) {
                        Text("Permis \(policy.categoryCode)").font(.drivySection)
                        Spacer(minLength: DrivySpacing.xs)
                        DrivyStatusBadge(title: policy.approved ? "Approuvée" : "Brouillon",
                            symbol: policy.approved ? "checkmark.seal" : "pencil", tone: policy.approved ? .success : .warning)
                    }
                    Text("Version \(policy.version)").font(.subheadline).foregroundStyle(DrivyTheme.muted)
                    DisclosureGroup("Lire la procédure et ses conditions") {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(policy.procedureText).textSelection(.enabled)
                            Text("Annulation").font(.headline)
                            Text(policy.cancellationPolicyText).textSelection(.enabled)
                            ForEach(Array(policy.sourceUrls.enumerated()), id: \.offset) { _, source in
                                if let url = URL(string: source), ["https", "http"].contains(url.scheme ?? ""), url.user == nil, url.password == nil {
                                    Link(url.host ?? "Source", destination: url)
                                }
                            }
                        }.font(.subheadline).padding(.top, 12)
                    }
                    Button("Préparer une nouvelle version") {
                        editor = CatalogEditorPresentation(kind: .policy, sourcePolicy: policy)
                    }.frame(minHeight: 44).disabled(!model.canMutate)
                }.padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder private func catalogActions(_ title: String, kind: SchoolCatalogEditorKind, summary: String?) -> some View {
        if horizontalSizeClass == .regular && !dynamicTypeSize.isAccessibilitySize {
            HStack(alignment: .firstTextBaseline, spacing: 20) {
                if let summary { Text(summary).font(.subheadline).foregroundStyle(DrivyTheme.muted) }
                Spacer(minLength: 8)
                Button { editor = CatalogEditorPresentation(kind: kind) } label: {
                    Label(title, systemImage: "plus").frame(minHeight: 32)
                }.buttonStyle(.borderedProminent).fixedSize().disabled(!model.canMutate)
            }
        } else {
            VStack(alignment: .leading, spacing: 16) {
                if let summary { Text(summary).font(.subheadline).foregroundStyle(DrivyTheme.muted) }
                Button { editor = CatalogEditorPresentation(kind: kind) } label: { Label(title, systemImage: "plus") }
                    .buttonStyle(DrivyPrimaryButtonStyle()).disabled(!model.canMutate)
            }
        }
    }

    private var learnerTrainings: some View {
        VStack(alignment: .leading, spacing: 20) {
            if model.trainings.isEmpty && !model.isLoading {
                empty("Ouvrir une formation", text: "Une formation utilise une offre précise de votre école. L’affectation du moniteur se fait ensuite.", symbol: "steeringwheel")
            }
            ForEach(model.trainings) { training in
                Button { Task { await model.selectTraining(training) } } label: {
                    HStack(spacing: 16) {
                        Image(systemName: "steeringwheel").font(.title2).foregroundStyle(DrivyTheme.accent)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Permis \(training.categoryCode)").font(.headline)
                            Text(SchoolPresentation.trainingStatus(training.status)).font(.subheadline).foregroundStyle(DrivyTheme.muted)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: model.selectedTraining?.id == training.id ? "checkmark.circle.fill" : "chevron.right")
                            .foregroundStyle(DrivyTheme.accent)
                    }
                }.buttonStyle(DrivySelectionCardStyle(isSelected: model.selectedTraining?.id == training.id))
                .disabled(model.isBusy || model.isLoading)
            }
            createButton("Créer une formation", symbol: "plus", kind: .training)
            if model.availableOfferings.isEmpty && !model.isLoading {
                Text("L’administration doit activer une offre dans École → Formations avant d’ouvrir une formation.")
                    .font(.footnote).foregroundStyle(DrivyTheme.muted)
            }
            if let training = model.selectedTraining {
                assignments(training)
            }
        }
    }
    private func assignments(_ training: SchoolTraining) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Moniteurs de cette formation").font(.drivySection)
            if model.assignments.isEmpty && !model.isLoading {
                Text("Aucun moniteur affecté. La formation existe déjà ; choisissez la personne qui l’accompagnera.")
                    .foregroundStyle(DrivyTheme.muted)
            }
            ForEach(model.assignments) { assignment in
                DrivyPanel {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(model.members.first(where: { $0.id == assignment.instructorMembershipId })?.displayName ?? "Moniteur de l’école")
                            .font(.headline)
                        Text("Dès le \(assignmentDate(assignment.validFrom))").font(.subheadline).foregroundStyle(DrivyTheme.muted)
                        if let end = assignment.validUntil { Text("Jusqu’au \(assignmentDate(end))").font(.subheadline).foregroundStyle(DrivyTheme.muted) }
                    }
                }
            }
            if training.status == "ACTIVE" {
                createButton("Affecter un moniteur", symbol: "person.badge.plus", kind: .assignment)
                if model.instructors.isEmpty && !model.isLoading {
                    Text("Un membre actif avec le rôle Moniteur est nécessaire pour cette affectation.")
                        .font(.footnote).foregroundStyle(DrivyTheme.muted)
                }
            }
            Text("Le contrôle du permis reste une vérification distincte. Une formation ne confirme pas une autorisation de conduire.")
                .font(.footnote).foregroundStyle(DrivyTheme.muted)
        }
    }
    private var team: some View {
        NavigationStack {
            List(model.members) { member in
                VStack(alignment: .leading, spacing: 8) {
                    Text(member.displayName).font(.headline)
                    Text(SchoolPresentation.roles(member.roles)).font(.subheadline).foregroundStyle(DrivyTheme.muted)
                    if member.status != "ACTIVE" { Text("Accès révoqué").font(.caption).foregroundStyle(DrivyTheme.muted) }
                }.padding(.vertical, 8)
            }
            .navigationTitle("Équipe et membres")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fermer") { showsTeam = false } } }
        }
    }
    private func createButton(_ title: String, symbol: String, kind: SchoolCatalogEditorKind) -> some View {
        Button { editor = CatalogEditorPresentation(kind: kind) } label: { Label(title, systemImage: symbol) }
            .buttonStyle(DrivySecondaryButtonStyle())
            .disabled(!model.canMutate || kind == .training && model.availableOfferings.isEmpty || kind == .assignment && model.instructors.isEmpty)
    }
    private func empty(_ title: String, text: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: symbol).font(.largeTitle).foregroundStyle(DrivyTheme.muted)
            Text(title).font(.drivyTitle)
            Text(text).font(.subheadline).foregroundStyle(DrivyTheme.muted)
        }.padding(.vertical, 16).fixedSize(horizontal: false, vertical: true)
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
