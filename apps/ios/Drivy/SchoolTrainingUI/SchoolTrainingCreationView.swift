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
                        Text(success).font(.body).foregroundStyle(DrivyTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let pending = model.pending { pendingCard(pending) }
                    if model.createdTrainingID == nil {
                        offerings
                        startDate
                    }
                }
                .padding(24).frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity)
            }
            .background(DrivyTheme.canvas).navigationTitle("Nouvelle formation").navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Group {
                    if model.createdTrainingID == nil {
                        Button("Vérifier la formation") { reviewsCreation = true }
                            .buttonStyle(DrivyPrimaryButtonStyle()).disabled(!model.canCreate)
                            .accessibilityIdentifier("review-training-creation")
                    } else {
                        Button("Revenir au dossier") { dismiss() }.buttonStyle(DrivyPrimaryButtonStyle())
                    }
                }
                .padding(16).frame(maxWidth: 680).frame(maxWidth: .infinity).background(DrivyTheme.surface)
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() }.disabled(model.isBusy) } }
            .sheet(isPresented: $reviewsCreation) { review }
            .onChange(of: model.createdTrainingID) { _, id in if id != nil { reviewsCreation = false } }
        }
        .tint(DrivyTheme.accent).interactiveDismissDisabled(model.isBusy)
        .task { await model.load() }
    }
    private var heading: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.createdTrainingID == nil ? "Nouvelle formation" : "Formation créée").font(.largeTitle.bold())
            Text(model.learner.displayName).font(.title3).foregroundStyle(DrivyTheme.muted)
        }
    }
    private var offerings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Offre de formation").font(.title3.bold())
            if model.offerings.isEmpty && !model.isLoading && model.errorMessage == nil {
                Text("Aucune offre disponible. L’administration doit activer une offre avant d’ouvrir cette formation.")
                    .font(.subheadline).foregroundStyle(DrivyTheme.muted)
            }
            ForEach(model.offerings) { offering in
                Button { model.selectedOfferingID = offering.id } label: {
                    HStack(alignment: .top, spacing: 14) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("Catégorie \(offering.categoryCode)").font(.headline).foregroundStyle(DrivyTheme.text)
                            Text(offering.offeringKey).font(.subheadline).foregroundStyle(DrivyTheme.muted)
                            Text("\(offering.defaultDurationMinutes) min · \(SchoolCatalogFormatting.price(offering.defaultPriceCents))")
                                .font(.subheadline).foregroundStyle(DrivyTheme.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: model.selectedOfferingID == offering.id ? "checkmark.circle.fill" : "circle")
                            .font(.title2).foregroundStyle(model.selectedOfferingID == offering.id ? DrivyTheme.accent : DrivyTheme.muted)
                    }
                    .padding(.vertical, 16).frame(minHeight: 80).contentShape(Rectangle())
                }
                .buttonStyle(.plain).disabled(model.isBusy || model.pending != nil)
                .accessibilityAddTraits(model.selectedOfferingID == offering.id ? .isSelected : [])
                Divider()
            }
        }
    }
    private var startDate: some View {
        VStack(alignment: .leading, spacing: 16) {
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
            VStack(alignment: .leading, spacing: 12) {
                Label("Demande à vérifier", systemImage: "clock.arrow.circlepath").font(.headline)
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
                VStack(alignment: .leading, spacing: 24) {
                    Text(model.learner.displayName).font(.title2.bold())
                    if let offering = model.selectedOffering {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Catégorie \(offering.categoryCode)").font(.headline)
                            Text(offering.offeringKey).foregroundStyle(DrivyTheme.muted)
                            Text("\(offering.defaultDurationMinutes) min · \(SchoolCatalogFormatting.price(offering.defaultPriceCents))")
                            Text("Version \(offering.version) de l’offre").font(.subheadline).foregroundStyle(DrivyTheme.muted)
                            Text(model.usesStartDate
                                ? "Début : \(SchoolPresentation.civilDate(SchoolCatalogFormatting.civilDate(model.startDate, timeZone: model.school?.timeZone ?? "Europe/Zurich")))"
                                : "Date de début non renseignée").font(.subheadline)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Text("L’affectation du moniteur et les rendez-vous seront organisés ensuite.")
                            .font(.subheadline).foregroundStyle(DrivyTheme.muted)
                    }
                    if let error = model.errorMessage {
                        SchoolErrorNotice(message: error, retry: model.pending == nil ? { Task { await model.load() } } : nil)
                    }
                    if let pending = model.pending { pendingCard(pending) }
                }
                .padding(24).frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity)
            }
            .background(DrivyTheme.canvas).navigationTitle("Confirmation").navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Button {
                    Task { if await model.create() { reviewsCreation = false } }
                } label: {
                    HStack(spacing: 10) {
                        if model.isBusy { ProgressView() }
                        Text(model.isBusy ? "Enregistrement…" : model.pending != nil ? "Résultat à vérifier" : "Créer la formation")
                    }
                }
                .buttonStyle(DrivyPrimaryButtonStyle()).disabled(!model.canCreate)
                .accessibilityIdentifier("confirm-training-creation")
                .padding(16).frame(maxWidth: 680).frame(maxWidth: .infinity).background(DrivyTheme.surface)
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Revenir") { reviewsCreation = false }.disabled(model.isBusy) } }
        }
        .interactiveDismissDisabled(model.isBusy)
    }
}
