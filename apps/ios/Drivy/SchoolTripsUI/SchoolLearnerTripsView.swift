import SwiftUI

/// Profil → Trajets (élève) : les trajets que l’école lui partage, du plus récent au plus ancien, jour par jour.
/// Le serveur décide de ce que ce compte lit, l’écran ne filtre rien. Un trajet reconstruit s’ouvre directement
/// en replay plein écran ; les autres se lisent mais ne s’ouvrent pas.
struct SchoolLearnerTripsView: View {
    let workspace: SchoolWorkspace
    let agendaClient: SchoolAgendaClient
    @State private var model: SchoolTripsWorkspace?
    /// Créé une fois : un changement de portée ne recrée que le modèle.
    @State private var captureClient: SchoolCaptureClient?
    /// Portée du modèle en place : la page qui réapparaît (replay refermé, retour d’onglet) ne le recrée pas.
    @State private var preparedKey: String?
    @State private var replay: SchoolTripReplayRoute?
    @State private var filterState = SchoolLearnerTripsFilterState(scopeKey: "")
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Une lecture plus récente que cela n’est pas refaite au retour sur la page ni au premier plan.
    private static let freshness: TimeInterval = 30

    init(workspace: SchoolWorkspace, agendaClient: SchoolAgendaClient) {
        self.workspace = workspace
        self.agendaClient = agendaClient
    }

    private var scopeKey: String {
        let parts: [String?] = [workspace.person?.personId.uuidString, workspace.membership?.schoolId.uuidString,
            workspace.membership?.membershipId.uuidString, workspace.membership.map { String($0.accessEpoch) },
            workspace.membership?.roles.joined(separator: ","), workspace.membership?.grants.joined(separator: ",")]
        return parts.map { $0 ?? "" }.joined(separator: ":")
    }

    /// Ce que la page montre ; chaque changement se fait en fondu, jamais par un remplacement sec.
    private enum Phase: Equatable { case loading, failed, empty, list }

    private var phase: Phase {
        guard let model else { return workspace.schoolError == nil ? .loading : .failed }
        if !model.trips.isEmpty { return .list }
        if model.isEmpty { return .empty }
        return model.errorMessage == nil ? .loading : .failed
    }

    var body: some View {
        ScrollView {
            content
                .drivyPageContent()
        }
        .refreshable { await reload() }
        .background(DrivyTheme.surface)
        .navigationTitle("Trajets")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: scopeKey) { await prepare() }
        // Retour au premier plan : la liste se relit sans s’effacer, seulement si la dernière lecture est ancienne.
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active { Task { await rereadIfStale() } }
        }
        // Session expirée ou accès retiré : la page n’offre plus de « Réessayer ». Le compte est relu pour ouvrir
        // la reconnexion ou recharger l’école, au lieu de laisser la page sans issue.
        .onChange(of: model?.accessRevoked) { _, revoked in
            if revoked == true { Task { await workspace.refreshAccount(minimumInterval: 0) } }
        }
        .fullScreenCover(item: $replay) { route in
            // Pas de zoom vers le replay : son geste de fermeture disputerait la carte aux doigts.
            SchoolCaptureReplayView(model: route.model, learnerName: route.learnerName, lessonTimeZone: route.lessonTimeZone)
        }
    }

    // MARK: Contenu

    private var content: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.m) {
            if let model {
                loaded(model)
            } else if let message = workspace.schoolError {
                // L’école n’a pas pu être lue : jamais une liste vide à la place.
                SchoolErrorNotice(message: message, retry: { retrySchool() })
            } else {
                skeleton
            }
        }
        .animation(DrivyMotion.reveal(reduceMotion), value: phase)
        .animation(DrivyMotion.reveal(reduceMotion), value: model?.errorMessage)
        .animation(DrivyMotion.reveal(reduceMotion), value: model?.trips.count)
        // Un conteneur d’accessibilité : l’identifiant ne remplace pas ceux des lignes.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("learner-trips-list")
    }

    /// Squelette de la première lecture seulement : une relecture ne remplace jamais des trajets déjà affichés.
    private var skeleton: some View {
        DrivySkeletonRows(count: 4, leading: .time)
            .drivySkeleton("Chargement des trajets…")
    }

    @ViewBuilder private func loaded(_ model: SchoolTripsWorkspace) -> some View {
        if let message = model.errorMessage {
            SchoolErrorNotice(message: message, retry: model.accessRevoked ? nil : { Task { await model.load() } })
        }
        filterControl(model)
        let visibleTrips = model.trips(matching: filterState.filter)
        if visibleTrips.isEmpty {
            if model.isEmpty {
                DrivyEmptyState(title: "Aucun trajet", symbol: "point.topleft.down.to.point.bottomright.curvepath")
            } else if model.errorMessage == nil && model.nextCursor != nil && filterState.filter != .all {
                DrivyEmptyState(title: "Aucun trajet parmi ceux chargés", symbol: "line.3.horizontal.decrease.circle",
                    actionTitle: "Charger d’autres trajets", action: { Task { await model.loadMore() } })
            } else if model.errorMessage == nil && model.nextCursor == nil {
                DrivyEmptyState(title: filterState.filter == .all ? "Aucun trajet" : "Aucun trajet pour ce filtre",
                    symbol: filterState.filter == .all ? "point.topleft.down.to.point.bottomright.curvepath" : "line.3.horizontal.decrease.circle",
                    actionTitle: filterState.filter == .all ? nil : "Afficher tous les trajets",
                    action: filterState.filter == .all ? nil : { filterState.filter = .all })
            } else if model.errorMessage == nil {
                skeleton
            }
        } else {
            ForEach(model.days(filter: filterState.filter)) { day in
                DrivyRowGroup(title: day.title) {
                    ForEach(day.trips) { trip in row(trip) }
                }
            }
        }
        if !(visibleTrips.isEmpty && filterState.filter != .all && model.nextCursor != nil) {
            more(model)
        }
    }

    @ViewBuilder private func filterControl(_ model: SchoolTripsWorkspace) -> some View {
        let options = filterOptions(model)
        if options.count > 1 {
            Menu {
                ForEach(options) { option in
                    Button { filterState.filter = option.filter } label: {
                        if option.filter == filterState.filter {
                            Label(option.title, systemImage: "checkmark")
                        } else {
                            Text(option.title)
                        }
                    }
                }
            } label: {
                Label(filterTitle(model), systemImage: "line.3.horizontal.decrease.circle")
                    .font(.subheadline.weight(.semibold))
            }
            .accessibilityIdentifier("learner-trips-filter")
            .accessibilityLabel("Filtrer les trajets")
            .accessibilityValue(filterTitle(model))
            .frame(minHeight: DrivyLayout.tapTarget, maxWidth: .infinity, alignment: .leading)
        }
    }

    private func filterTitle(_ model: SchoolTripsWorkspace) -> String {
        switch filterState.filter {
        case .all: "Tous les trajets"
        case .mine: "Mes trajets"
        case .instructor(let id): model.otherInstructors().first(where: { $0.id == id })?.name ?? "Moniteur"
        }
    }

    private func filterOptions(_ model: SchoolTripsWorkspace) -> [SchoolLearnerTripsFilterOption] {
        var options = [SchoolLearnerTripsFilterOption(filter: .all, title: "Tous les trajets")]
        let roles = Set(workspace.membership?.roles ?? [])
        if roles.contains("INSTRUCTOR") { options.append(.init(filter: .mine, title: "Mes trajets")) }
        if roles.contains("ADMIN") {
            options.append(contentsOf: model.otherInstructors().map { .init(filter: .instructor($0.id), title: $0.name) })
        }
        return options
    }

    /// Un trajet reconstruit est un bouton qui ouvre son replay. Les autres ne sont pas un contrôle : ils reculent
    /// (encre atténuée, sans chevron) et VoiceOver ne les annonce pas comme actifs.
    @ViewBuilder private func row(_ trip: SchoolCaptureTrip) -> some View {
        if SchoolTripsWorkspace.isReplayable(trip.capture) {
            Button { open(trip) } label: { SchoolLearnerTripRow(trip: trip, opens: true) }
                .buttonStyle(DrivyRowButtonStyle())
                .accessibilityHint("Ouvre le replay du trajet")
                .accessibilityIdentifier("learner-trip-\(trip.id.uuidString)")
        } else {
            SchoolLearnerTripRow(trip: trip, opens: false)
                .accessibilityIdentifier("learner-trip-\(trip.id.uuidString)")
        }
    }

    @ViewBuilder private func more(_ model: SchoolTripsWorkspace) -> some View {
        if model.nextCursor != nil {
            if let message = model.moreErrorMessage {
                SchoolErrorNotice(message: message, retry: { Task { await model.loadMore() } })
            } else {
                Button { Task { await model.loadMore() } } label: {
                    DrivyBusyLabel(title: "Afficher d’autres trajets", busyTitle: "Chargement…", isBusy: model.isLoadingMore)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(DrivySecondaryButtonStyle())
                .disabled(model.isLoadingMore)
                .accessibilityIdentifier("learner-trips-more")
            }
        }
    }

    // MARK: Lecture

    private func prepare() async {
        let key = scopeKey
        if preparedKey == key, model != nil {
            // Retour sur la page : la liste en place reste affichée, relue seulement si elle est ancienne
            // (ou si la première lecture n’a pas abouti).
            await rereadIfStale()
            return
        }
        filterState.updateScope(key)
        preparedKey = nil
        model?.invalidate()
        replay?.model.invalidate()
        replay = nil
        model = nil
        guard let person = workspace.person, let membership = workspace.membership else { return }
        let client = captureClient ?? agendaClient.captureClient
        captureClient = client
        let scope = SchoolCommandScope(personID: person.personId, schoolID: membership.schoolId,
            membershipID: membership.membershipId, accessEpoch: membership.accessEpoch, apiBaseURL: client.baseURL.absoluteString)
        let value = SchoolTripsWorkspace(scope: scope, client: client)
        model = value
        preparedKey = key
        await value.load()
    }

    /// Relecture silencieuse : ce qui est affiché reste en place jusqu’à la réponse. Pendant un replay, rien n’est relu.
    private func rereadIfStale() async {
        guard replay == nil, let model, !model.isLoading, !model.accessRevoked else { return }
        if let loadedAt = model.loadedAt, Date().timeIntervalSince(loadedAt) <= Self.freshness { return }
        await model.load()
    }

    private func reload() async { await model?.load() }

    private func retrySchool() {
        guard let membership = workspace.membership else { return }
        Task { await workspace.selectSchool(membership) }
    }

    /// Le replay porte le nom du moniteur du trajet, comme l’en-tête de la fiche de leçon pour l’élève.
    private func open(_ trip: SchoolCaptureTrip) {
        guard replay == nil, let model, SchoolTripsWorkspace.isReplayable(trip.capture) else { return }
        replay = SchoolTripReplayRoute(
            model: SchoolCaptureReplayWorkspace(scope: model.scope, client: model.client, captureID: trip.capture.id),
            learnerName: SchoolTripsWorkspace.learnerTitle(trip), lessonTimeZone: trip.lessonTimeZone)
    }
}

struct SchoolLearnerTripsFilterState {
    private(set) var scopeKey: String
    var filter: SchoolTripFilter = .all

    mutating func updateScope(_ newScopeKey: String) {
        guard scopeKey != newScopeKey else { return }
        scopeKey = newScopeKey
        filter = .all
    }
}

struct SchoolLearnerTripsFilterOption: Identifiable {
    let filter: SchoolTripFilter
    let title: String
    var id: String {
        switch filter {
        case .all: "all"
        case .mine: "mine"
        case .instructor(let id): "instructor-\(id.uuidString)"
        }
    }
}

/// Un état inhabituel (partiel, interrompu, retiré) tient en un mot, jamais en pastille.
private struct SchoolLearnerTripRow: View {
    let trip: SchoolCaptureTrip
    /// Vrai pour un trajet qui s’ouvre en replay : chevron et encre pleine. Sinon la ligne recule.
    let opens: Bool

    var body: some View {
        let badge = SchoolTripsWorkspace.badge(trip.capture)
        DrivyLessonRow(start: SchoolTripsWorkspace.time(trip), title: SchoolTripsWorkspace.learnerTitle(trip),
            details: SchoolTripsWorkspace.duration(trip.capture).map { [$0] } ?? [],
            note: badge.map { DrivyRowNote(text: $0.title, tone: $0.tone) },
            showsChevron: opens, isSecondary: !opens)
            .accessibilityLabel(spokenLabel(badge))
    }

    /// Lue d’une traite : moniteur, heure, durée dite en toutes lettres, état inhabituel.
    private func spokenLabel(_ badge: SchoolTripBadge?) -> String {
        let parts: [String?] = [SchoolTripsWorkspace.learnerTitle(trip), SchoolTripsWorkspace.time(trip),
            SchoolTripsWorkspace.spokenDuration(trip.capture), badge?.title]
        return parts.compactMap { $0 }.joined(separator: ", ")
    }
}
