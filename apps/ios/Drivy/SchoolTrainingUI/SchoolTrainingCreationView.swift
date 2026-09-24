import SwiftUI

struct SchoolTrainingCreationView: View {
    @Bindable var model: SchoolTrainingCreationWorkspace
    @State private var reviewsCreation = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    heading
                    if model.isLoading || model.isBusy { ProgressView(model.isBusy ? "Enregistrement…" : "Ouverture des offres…") }
                    if let error = model.errorMessage { SchoolErrorNotice(message: error, retry: { Task { await model.load() } }) }
                    if let success = model.successMessage {
                        Label(success, systemImage: "checkmark.circle.fill")
                            .font(.headline).foregroundStyle(DrivyTheme.accent).fixedSize(horizontal: false, vertical: true)
                            .padding(20).background(DrivyTheme.accentSoft, in: RoundedRectangle(cornerRadius: 20))
                    }
                    if let pending = model.pending { pendingCard(pending) }
                    if model.createdTrainingID == nil {
                        offerings
                        startDate
                        Button { reviewsCreation = true } label: {
                            Text("Vérifier la formation").frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent).disabled(!model.canCreate)
                        .accessibilityIdentifier("review-training-creation")
                    } else {
                        Button("Revenir au dossier") { dismiss() }.buttonStyle(.borderedProminent).frame(minHeight: 48)
                    }
                }
                .padding(24).frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity)
            }
            .background(DrivyTheme.canvas).navigationTitle("Nouvelle formation").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() }.disabled(model.isBusy) } }
            .sheet(isPresented: $reviewsCreation) { review }
        }
        .tint(DrivyTheme.accent).interactiveDismissDisabled(model.isBusy)
        .task { await model.load() }
    }
    private var heading: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "steeringwheel").font(.title).foregroundStyle(DrivyTheme.accent)
                .frame(width: 60, height: 60).background(DrivyTheme.accentSoft, in: RoundedRectangle(cornerRadius: 18))
            Text("Un nouveau parcours").font(.largeTitle.bold())
            Text(model.learner.displayName).font(.title3).foregroundStyle(DrivyTheme.muted)
            Text("Choisissez l’offre de l’école pour ouvrir cette formation.").font(.subheadline).foregroundStyle(DrivyTheme.muted)
        }
    }
    private var offerings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Offre de formation").font(.title3.bold())
            if model.offerings.isEmpty && !model.isLoading && model.errorMessage == nil {
                ContentUnavailableView("Aucune offre disponible", systemImage: "steeringwheel", description: Text("L’administration doit activer une offre avec son référentiel et sa procédure avant d’ouvrir une formation."))
            }
            ForEach(model.offerings) { offering in
                Button { model.selectedOfferingID = offering.id } label: {
                    HStack(alignment: .top, spacing: 14) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("Catégorie \(offering.categoryCode)").font(.headline).foregroundStyle(DrivyTheme.text)
                            Text(offering.offeringKey).font(.subheadline).foregroundStyle(DrivyTheme.muted)
                            Text("Référentiel et procédure approuvés").font(.caption).foregroundStyle(DrivyTheme.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: model.selectedOfferingID == offering.id ? "checkmark.circle.fill" : "circle")
                            .font(.title2).foregroundStyle(model.selectedOfferingID == offering.id ? DrivyTheme.accent : DrivyTheme.muted)
                    }
                    .padding(20).frame(minHeight: 96)
                    .background(model.selectedOfferingID == offering.id ? DrivyTheme.accentSoft : DrivyTheme.surface, in: RoundedRectangle(cornerRadius: 20))
                }
                .buttonStyle(.plain).disabled(model.isBusy || model.pending != nil)
                .accessibilityAddTraits(model.selectedOfferingID == offering.id ? .isSelected : [])
            }
        }
    }
    private var startDate: some View {
        DrivyPanel {
            VStack(alignment: .leading, spacing: 16) {
                Toggle("Indiquer une date de début", isOn: $model.usesStartDate)
                if model.usesStartDate {
                    DatePicker("Début", selection: $model.startDate, displayedComponents: .date)
                        .environment(\.timeZone, TimeZone(identifier: model.school?.timeZone ?? "Europe/Zurich") ?? .current)
                }
                Text("Le moniteur sera affecté à cette formation par l’administration.")
                    .font(.footnote).foregroundStyle(DrivyTheme.muted)
            }
        }
        .disabled(model.isBusy || model.pending != nil)
    }
    private func pendingCard(_ pending: PendingSchoolCommand) -> some View {
        DrivyPanel {
            VStack(alignment: .leading, spacing: 12) {
                Label("Demande à vérifier", systemImage: "clock.arrow.circlepath").font(.headline)
                Text(pending.kind == .createTraining && pending.routeResourceID == model.learner.id
                    ? "La confirmation de création n’est pas encore connue. Vérifiez cette demande avant d’en créer une autre."
                    : "Une autre modification de cette école attend sa confirmation. Vous pouvez consulter les offres.")
                    .font(.subheadline).foregroundStyle(DrivyTheme.muted)
                Text(pending.id.uuidString).font(.caption.monospaced()).textSelection(.enabled)
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
                VStack(alignment: .leading, spacing: 24) {
                    Text("Ouvrir cette formation ?").font(.largeTitle.bold())
                    if let offering = model.selectedOffering {
                        DrivyPanel {
                            VStack(alignment: .leading, spacing: 16) {
                                Text(model.learner.displayName).font(.title3.bold())
                                Text("Catégorie \(offering.categoryCode)").font(.headline)
                                Text(offering.offeringKey).foregroundStyle(DrivyTheme.muted)
                                Text(model.usesStartDate
                                    ? "Début : \(SchoolPresentation.civilDate(SchoolCatalogFormatting.civilDate(model.startDate, timeZone: model.school?.timeZone ?? "Europe/Zurich")))"
                                    : "Date de début non renseignée").font(.subheadline)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Text("L’affectation du moniteur et les rendez-vous seront organisés ensuite.")
                            .font(.subheadline).foregroundStyle(DrivyTheme.muted)
                        Button {
                            Task { _ = await model.create(); reviewsCreation = false }
                        } label: { Text("Créer la formation").frame(maxWidth: .infinity, minHeight: 44) }
                            .buttonStyle(.borderedProminent).disabled(!model.canCreate)
                            .accessibilityIdentifier("confirm-training-creation")
                    }
                    if model.isBusy { ProgressView("Enregistrement…") }
                }
                .padding(24).frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity)
            }
            .background(DrivyTheme.canvas).navigationTitle("Confirmation").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Revenir") { reviewsCreation = false }.disabled(model.isBusy) } }
        }
        .interactiveDismissDisabled(model.isBusy)
    }
}
