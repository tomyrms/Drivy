import SwiftUI

struct SchoolTrainingCreationView: View {
    @Bindable var model: SchoolTrainingCreationWorkspace
    @State private var reviewsCreation = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DrivySpacing.l) {
                    heading
                    if model.isLoading || model.isBusy {
                        ProgressView(model.isBusy ? "Création de la formation…" : "Ouverture des offres…")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let error = model.errorMessage { SchoolErrorNotice(message: error, retry: { Task { await model.load() } }) }
                    if let success = model.successMessage { DrivyInlineMessage(text: success) }
                    if let pending = model.pending { pendingCard(pending) }
                    if model.createdTrainingID == nil {
                        offerings
                        startDate
                    }
                }
                .drivyPageContent()
            }
            .background(DrivyTheme.surface).navigationTitle("Nouvelle formation").navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                DrivyStickyActionBar {
                    if model.createdTrainingID == nil {
                        if !model.canCreate && !model.isBusy && !model.isLoading && model.pending == nil && model.selectedOfferingID == nil && !model.offerings.isEmpty {
                            DrivyActionNote(text: "Choisissez une offre pour continuer.")
                        }
                        Button("Vérifier la formation") { reviewsCreation = true }
                            .buttonStyle(DrivyPrimaryButtonStyle()).disabled(!model.canCreate)
                            .accessibilityIdentifier("review-training-creation")
                    } else {
                        Button("Revenir au dossier") { dismiss() }.buttonStyle(DrivyPrimaryButtonStyle())
                    }
                }
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() }.disabled(model.isBusy) } }
            .sheet(isPresented: $reviewsCreation) { review }
            .onChange(of: model.createdTrainingID) { _, id in if id != nil { reviewsCreation = false } }
        }
        .tint(DrivyTheme.accent).interactiveDismissDisabled(model.isBusy)
        .task { await model.load() }
    }
    private var heading: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xs) {
            HStack(spacing: DrivySpacing.s) {
                DrivyAvatar(name: model.learner.displayName, size: 36)
                Text(model.learner.displayName).font(.subheadline.weight(.semibold)).foregroundStyle(DrivyTheme.muted)
            }
            .accessibilityElement(children: .combine)
            Text(model.createdTrainingID == nil ? "Nouvelle formation" : "Formation créée").font(.drivyScreenTitle)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
    }
    private var offerings: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.s) {
            DrivySectionHeader(title: "Offre de formation")
            if model.offerings.isEmpty && !model.isLoading && model.errorMessage == nil {
                DrivyEmptyState(title: "Aucune offre disponible",
                    message: "L’administration doit activer une offre avant d’ouvrir cette formation.", symbol: "list.bullet.rectangle")
            }
            ForEach(model.offerings) { offering in
                Button { model.selectedOfferingID = offering.id } label: {
                    HStack(alignment: .top, spacing: DrivySpacing.m) {
                        VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                            Text("Permis \(offering.categoryCode)").font(.headline).foregroundStyle(DrivyTheme.text)
                            Text(offering.offeringKey).font(.subheadline).foregroundStyle(DrivyTheme.muted)
                            Text("\(offering.defaultDurationMinutes) min · \(SchoolCatalogFormatting.price(offering.defaultPriceCents))")
                                .font(.subheadline.monospacedDigit()).foregroundStyle(DrivyTheme.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        DrivySelectionMark(isSelected: model.selectedOfferingID == offering.id)
                    }
                }
                .buttonStyle(DrivySelectionCardStyle(isSelected: model.selectedOfferingID == offering.id))
                .disabled(model.isBusy || model.pending != nil)
                .accessibilityAddTraits(model.selectedOfferingID == offering.id ? .isSelected : [])
            }
        }
    }
    private var startDate: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.m) {
            DrivySectionHeader(title: "Début")
            Toggle("Indiquer une date de début", isOn: $model.usesStartDate)
            if model.usesStartDate {
                DatePicker("Début", selection: $model.startDate, displayedComponents: .date)
                    .environment(\.timeZone, TimeZone(identifier: model.school?.timeZone ?? "Europe/Zurich") ?? .current)
            }
            Text("Le moniteur sera affecté à cette formation par l’administration.")
                .font(.footnote).foregroundStyle(DrivyTheme.muted)
        }
        .disabled(model.isBusy || model.pending != nil)
    }
    private func pendingCard(_ pending: PendingSchoolCommand) -> some View {
        DrivyPanel {
            VStack(alignment: .leading, spacing: DrivySpacing.s) {
                Label("Demande à vérifier", systemImage: "clock.arrow.circlepath").font(.headline).foregroundStyle(DrivyTheme.warning)
                Text(pending.kind == .createTraining && pending.routeResourceID == model.learner.id
                    ? "La confirmation de création n’est pas encore connue. Vérifiez cette demande avant d’en créer une autre."
                    : "Une autre modification de cette école attend sa confirmation. Vous pouvez consulter les offres.")
                    .font(.subheadline).foregroundStyle(DrivyTheme.muted)
                DisclosureGroup("Référence de la demande") {
                    Text(pending.id.uuidString).font(.caption.monospaced()).textSelection(.enabled)
                }
                Button("Vérifier auprès de l’école") { Task { await model.verify() } }.frame(minHeight: 44).disabled(model.isBusy)
                if model.canRetry { Button("Renvoyer la même demande") { Task { await model.retry() } }.frame(minHeight: 44) }
                else if pending.scope != model.scope {
                    Text("Vos accès ont changé. La référence reste conservée ; cette demande ne sera pas renvoyée avec un autre accès.")
                        .font(.footnote).foregroundStyle(DrivyTheme.muted)
                }
            }
        }
    }
    private var review: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DrivySpacing.l) {
                    Text(model.learner.displayName).font(.drivyTitle)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    if let offering = model.selectedOffering {
                        DrivyRowGroup {
                            DrivyLessonFactRow(title: "Formation", value: "Permis \(offering.categoryCode)")
                            DrivyLessonFactRow(title: "Offre", value: offering.offeringKey)
                            DrivyLessonFactRow(title: "Durée et prix par défaut", value: "\(offering.defaultDurationMinutes) min · \(SchoolCatalogFormatting.price(offering.defaultPriceCents))", monospaced: true)
                            DrivyLessonFactRow(title: "Version de l’offre", value: "\(offering.version)", monospaced: true)
                            DrivyLessonFactRow(title: "Début", value: model.usesStartDate
                                ? SchoolPresentation.civilDate(SchoolCatalogFormatting.civilDate(model.startDate, timeZone: model.school?.timeZone ?? "Europe/Zurich"))
                                : "Non renseigné")
                        }
                        Text("L’affectation du moniteur et les rendez-vous seront organisés ensuite.")
                            .font(.subheadline).foregroundStyle(DrivyTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let error = model.errorMessage {
                        SchoolErrorNotice(message: error, retry: model.pending == nil ? { Task { await model.load() } } : nil)
                    }
                    if let pending = model.pending { pendingCard(pending) }
                }
                .drivyPageContent()
            }
            .background(DrivyTheme.surface).navigationTitle("Confirmation").navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                DrivyStickyActionBar {
                    Button {
                        Task { if await model.create() { reviewsCreation = false } }
                    } label: {
                        HStack(spacing: DrivySpacing.xs) {
                            if model.isBusy { ProgressView() }
                            Text(model.isBusy ? "Création de la formation…" : model.pending != nil ? "Demande à vérifier" : "Créer la formation")
                        }
                    }
                    .buttonStyle(DrivyPrimaryButtonStyle()).disabled(!model.canCreate)
                    .accessibilityIdentifier("confirm-training-creation")
                }
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Revenir") { reviewsCreation = false }.disabled(model.isBusy) } }
        }
        .interactiveDismissDisabled(model.isBusy)
    }
}
