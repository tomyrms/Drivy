import MapKit
import SwiftUI

/// Ce dont les sections d’une leçon ont besoin pour ouvrir un replay ou une observation.
@MainActor struct SchoolReportContext {
    let agenda: SchoolAgendaClient
    let learnerName: String
    let schoolWorkspace: SchoolWorkspace
}

/// Feuille d’observation ouverte depuis une leçon.
enum SchoolReportObservationRoute: Identifiable {
    /// La liste complète : leçon planifiée (« Signaler »), ou repli quand l’édition directe est impossible.
    case list(UUID)
    case edit(SchoolObservationWorkspace, SchoolObservationEditor)
    case remove(SchoolObservationWorkspace, SchoolObservation)

    var id: UUID {
        switch self {
        case .list(let id): id
        case .edit(_, let editor): editor.id
        case .remove(_, let observation): observation.id
        }
    }
}

/// Présentations d’un écran de la leçon : replay du trajet, édition d’une observation, épingle mise en avant.
/// Chaque écran possède le sien : la fiche et une étape poussée ne se disputent jamais la même feuille.
@MainActor @Observable final class SchoolReportRouter {
    var replay: SchoolTripReplayRoute?
    var observation: SchoolReportObservationRoute?
    var selectedObservation: UUID?
    private(set) var isOpeningObservation = false
    @ObservationIgnored private var observations: SchoolObservationWorkspace?

    func openReplay(_ capture: SchoolCaptureSession, model: SchoolLessonReportWorkspace, context: SchoolReportContext) {
        replay = SchoolTripReplayRoute(model: SchoolCaptureReplayWorkspace(scope: model.scope, client: context.agenda.captureClient,
            captureID: capture.id), learnerName: context.learnerName, lessonTimeZone: model.lesson?.timeZone)
    }

    func openList() { observation = .list(UUID()) }

    func add(model: SchoolLessonReportWorkspace, context: SchoolReportContext) {
        Task { [self] in
            guard let workspace = await loadedObservations(model: model, context: context) else { return }
            if let editor = workspace.begin(marker: false) { observation = .edit(workspace, editor) }
            else { openList() }
        }
    }

    func edit(_ value: SchoolObservation, model: SchoolLessonReportWorkspace, context: SchoolReportContext) {
        Task { [self] in
            guard let workspace = await loadedObservations(model: model, context: context) else { return }
            if let current = workspace.observations.first(where: { $0.id == value.id }), let editor = workspace.edit(current) {
                observation = .edit(workspace, editor)
            } else { openList() }
        }
    }

    func remove(_ value: SchoolObservation, model: SchoolLessonReportWorkspace, context: SchoolReportContext) {
        Task { [self] in
            guard let workspace = await loadedObservations(model: model, context: context) else { return }
            if workspace.acceptsChanges, let current = workspace.observations.first(where: { $0.id == value.id }) {
                observation = .remove(workspace, current)
            } else { openList() }
        }
    }

    /// Les observations sont relues avant chaque geste : l’édition part de leur version actuelle.
    private func loadedObservations(model: SchoolLessonReportWorkspace, context: SchoolReportContext) async -> SchoolObservationWorkspace? {
        guard !isOpeningObservation, observation == nil else { return nil }
        isOpeningObservation = true
        defer { isOpeningObservation = false }
        let value = observations ?? SchoolObservationWorkspace(scope: model.scope, lessonID: model.lessonID,
            client: context.agenda.observationClient)
        observations = value
        await value.load()
        return value
    }
}

/// Replay et feuilles d’observation d’un écran de la leçon. La leçon est relue à la fermeture d’une observation.
struct SchoolReportPresentations: ViewModifier {
    @Bindable var router: SchoolReportRouter
    let model: SchoolLessonReportWorkspace
    let context: SchoolReportContext

    func body(content: Content) -> some View {
        content
            .fullScreenCover(item: $router.replay) { route in
                SchoolCaptureReplayView(model: route.model, learnerName: route.learnerName, lessonTimeZone: route.lessonTimeZone)
            }
            .sheet(item: $router.observation, onDismiss: { Task { await model.load() } }) { route in
                switch route {
                case .list:
                    SchoolObservationEntryView(client: context.agenda.observationClient, schoolWorkspace: context.schoolWorkspace,
                        lessonID: model.lessonID)
                case .edit(let workspace, let editor):
                    SchoolObservationComposer(model: workspace, editor: editor)
                case .remove(let workspace, let observation):
                    SchoolObservationRemoval(model: workspace, observation: observation)
                }
            }
    }
}

// MARK: Trajet

/// Le trajet d’une leçon dans un formulaire : carte, lecture, état inhabituel et, quand `editable`, le réglage
/// de son partage. Le récapitulatif lu compose les mêmes pièces sans formulaire.
struct SchoolReportTripSection: View {
    @Bindable var model: SchoolLessonReportWorkspace
    let router: SchoolReportRouter
    let context: SchoolReportContext
    var mapHeight: CGFloat = DrivyMapLayout.previewHeight
    /// Lecture seule : aucune commande de partage.
    var editable = true

    var body: some View {
        Section {
            if !model.track.isEmpty {
                SchoolLessonTripMap(model: model, router: router, context: context, height: mapHeight)
                    .listRowInsets(EdgeInsets())
            } else {
                SchoolLessonReplayLinks(model: model, router: router, context: context)
            }
            SchoolLessonTripNotes(captures: model.captures)
            if editable, model.isAuthor, model.sharing != nil {
                Toggle("Visible par l’élève", isOn: Binding(get: { model.captureShared },
                    set: { shared in Task { await model.updateSharing(captureHidden: !shared) } }))
                    .disabled(!model.acceptsInput)
            }
        } header: { Text("Trajet").drivyFormSectionHeader() }
            .drivyFormRows()
    }
}

/// Sans aperçu (tracé illisible ou vide), le replay s’ouvre par une ligne de texte par trajet.
struct SchoolLessonReplayLinks: View {
    let model: SchoolLessonReportWorkspace
    let router: SchoolReportRouter
    let context: SchoolReportContext

    var body: some View {
        let replayable = model.replayableCaptures
        ForEach(Array(replayable.enumerated()), id: \.element.id) { index, capture in
            Button { router.openReplay(capture, model: model, context: context) } label: {
                Text(replayable.count == 1 ? "Revoir le trajet" : "Revoir le trajet \(index + 1)")
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier("lesson-replay-\(capture.id.uuidString)")
        }
    }
}

/// L’état inhabituel d’un trajet (partiel, pas encore envoyé, retiré) : un mot de texte, comme dans les listes.
struct SchoolLessonTripNotes: View {
    let captures: [SchoolCaptureSession]

    var body: some View {
        let notes = SchoolReportFlowRules.tripNotes(captures)
        if !notes.isEmpty {
            Text(notes.joined(separator: " · "))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DrivyTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("lesson-trip-state")
        }
    }
}

/// Carte du trajet avec ses observations ancrées. Elle porte sa seule commande : lecture, en bas à droite.
struct SchoolLessonTripMap: View {
    let model: SchoolLessonReportWorkspace
    let router: SchoolReportRouter
    let context: SchoolReportContext
    var height: CGFloat = DrivyMapLayout.previewHeight

    private var pins: [LessonTrackMap.Pin] {
        model.lessonObservations.compactMap { observation in
            guard let point = model.anchor(of: observation) else { return nil }
            return LessonTrackMap.Pin(id: observation.id, latitude: point.latitude, longitude: point.longitude,
                color: SchoolReportObservationsSection.color(observation), isSelected: router.selectedObservation == observation.id)
        }
    }
    var body: some View {
        LessonTrackMap(segments: model.track, pins: pins, height: height)
            .overlay(alignment: .bottomTrailing) { replayControl(model.replayableCaptures) }
    }

    /// Lecture du trajet, posée sur la carte. Un trajet : l’appui ouvre le replay. Plusieurs : la même commande
    /// ouvre leur liste, pour ne jamais poser deux boutons sur la carte.
    @ViewBuilder private func replayControl(_ captures: [SchoolCaptureSession]) -> some View {
        if captures.count == 1, let capture = captures.first {
            Button { router.openReplay(capture, model: model, context: context) } label: { LessonReplayGlyph() }
                .buttonStyle(.plain)
                .accessibilityLabel("Revoir le trajet")
                .accessibilityIdentifier("lesson-replay-\(capture.id.uuidString)")
                .padding(DrivySpacing.s)
        } else if captures.count > 1 {
            Menu {
                ForEach(Array(captures.enumerated()), id: \.element.id) { index, capture in
                    Button("Trajet \(index + 1)") { router.openReplay(capture, model: model, context: context) }
                        .accessibilityIdentifier("lesson-replay-\(capture.id.uuidString)")
                }
            } label: { LessonReplayGlyph() }
                .buttonStyle(.plain)
                .accessibilityLabel("Revoir le trajet")
                .accessibilityHint("Ouvre la liste des trajets de la leçon")
                .accessibilityIdentifier("lesson-replay-menu")
                .padding(DrivySpacing.s)
        }
    }
}

// MARK: Observations

/// Ce qui a été noté pendant la leçon. Sur une leçon terminée, le moniteur modifie, retire ou garde pour lui
/// chaque observation depuis sa ligne ; sur une leçon planifiée, il ouvre la liste pour signaler.
struct SchoolReportObservationsSection: View {
    @Bindable var model: SchoolLessonReportWorkspace
    let router: SchoolReportRouter
    let context: SchoolReportContext
    /// Lecture seule : ni ajout, ni menu de ligne, ni section vide.
    var editable = true

    private var isCompleted: Bool { model.lesson?.status == "COMPLETED" }

    static func color(_ observation: SchoolObservation) -> Color {
        switch SchoolLessonHubRules.status(of: observation) {
        case .positive: DrivyTheme.success
        case .attention: DrivyTheme.warning
        case .toWorkOn: DrivyTheme.danger
        case nil: DrivyTheme.muted
        }
    }

    var body: some View {
        if editable || !model.lessonObservations.isEmpty { section }
    }

    private var section: some View {
        Section {
            if editable && model.lessonObservations.isEmpty && isCompleted {
                Text("Aucune observation.").foregroundStyle(DrivyTheme.muted)
            }
            ForEach(model.lessonObservations) { observation in
                SchoolReportObservationRow(model: model, router: router, context: context, observation: observation,
                    editable: editable && model.isAuthor && isCompleted)
            }
            if editable && model.isAuthor {
                Button(isCompleted ? "Ajouter une observation" : "Noter une observation") {
                    // Envoi bref en cours : l’appui est ignoré plutôt que le bouton grisé. Une relecture n’empêche rien.
                    guard !model.isBusy else { return }
                    if isCompleted { router.add(model: model, context: context) } else { router.openList() }
                }
                .accessibilityIdentifier("lesson-private-observations")
            }
        } header: { Text("Pendant la leçon").drivyFormSectionHeader() }
            .drivyFormRows()
    }
}

/// Constat par symbole, libellé et couleur : jamais par la couleur seule.
private struct SchoolReportObservationRow: View {
    @Bindable var model: SchoolLessonReportWorkspace
    let router: SchoolReportRouter
    let context: SchoolReportContext
    let observation: SchoolObservation
    let editable: Bool

    private var competency: String? {
        guard let id = observation.competencyId else { return nil }
        return model.competencies.first(where: { $0.id == id })?.displayLabel
    }
    private var kept: Bool { model.isPrivate(observation) }
    private var isAnchored: Bool { model.anchor(of: observation) != nil }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DrivySpacing.s) {
            summary
            Spacer(minLength: 0)
            if editable { actions }
        }
    }

    @ViewBuilder private var summary: some View {
        let content = DrivyObservationSummary(observation: observation, competency: competency,
            detail: SchoolReportFlowRules.observationDetail(observation, zone: model.lesson?.timeZone))
        if isAnchored {
            // Une observation placée sur le trajet se retrouve sur la carte : son épingle grossit.
            content
                .contentShape(Rectangle())
                .onTapGesture { router.selectedObservation = router.selectedObservation == observation.id ? nil : observation.id }
                .accessibilityAction(named: "Montrer sur la carte") { router.selectedObservation = observation.id }
        } else {
            content
        }
    }

    private var actions: some View {
        Menu {
            Button(observation.isMarker ? "Préciser" : "Modifier") { router.edit(observation, model: model, context: context) }
            if model.sharing != nil {
                Button(kept ? "Montrer à l’élève" : "Garder pour moi") {
                    Task { await model.updateSharing(observation: observation.id, observationPrivate: !kept) }
                }
            }
            Button("Retirer", role: .destructive) { router.remove(observation, model: model, context: context) }
        } label: {
            HStack(spacing: DrivySpacing.xxs) {
                if kept { Text("Pour moi").font(.caption).foregroundStyle(DrivyTheme.muted) }
                Image(systemName: "ellipsis").font(.body).foregroundStyle(DrivyTheme.muted)
            }
            .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(!model.acceptsInput)
        .accessibilityLabel("Actions pour l’observation, \(kept ? "pour moi" : "visible par l’élève")")
    }
}

// MARK: Bilan : rédaction

/// Les trois textes du bilan et son partage. Tout est facultatif.
struct SchoolReportTextSection: View {
    @Bindable var model: SchoolLessonReportWorkspace

    var body: some View {
        Section {
            if model.sharing != nil {
                Toggle("Visible par l’élève", isOn: Binding(get: { model.reportShared },
                    set: { shared in Task { await model.updateSharing(reportPrivate: !shared) } }))
                    .disabled(!model.acceptsInput)
            }
            field("Travail réalisé", text: $model.workedOn)
            field("À retenir", text: $model.observationText)
            field("Prochaine étape", text: $model.nextStep)
        } header: { Text("Bilan").drivyFormSectionHeader() }
            .drivyFormRows()
    }

    private func field(_ label: String, text: Binding<String>) -> some View {
        let count = text.wrappedValue.unicodeScalars.count
        return VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
            Text(label).font(.subheadline.weight(.semibold)).foregroundStyle(DrivyTheme.muted).accessibilityHidden(true)
            TextField("Facultatif", text: text, axis: .vertical).lineLimit(1...10).disabled(!model.acceptsInput)
                .accessibilityLabel(label)
                .accessibilityHint("Facultatif")
            // Le compteur n’apparaît qu’à l’approche de la limite.
            if count > 3_600 {
                Text("\(count) / 4 000").font(.caption.monospacedDigit())
                    .foregroundStyle(count > 4_000 ? DrivyTheme.danger : DrivyTheme.muted)
            }
        }
        .padding(.vertical, DrivySpacing.xs)
    }
}

/// Niveaux par compétence. Celles de la leçon viennent d’abord ; les autres restent à un geste, repliées.
struct SchoolReportCompetenciesSection: View {
    @Bindable var model: SchoolLessonReportWorkspace
    @State private var expanded = Set<UUID>()
    @State private var showsOthers = false

    private var competencyGroups: SchoolReportCompetencyGroups {
        SchoolReportFlowRules.competencyGroups(model.competencies, observations: model.lessonObservations,
            goals: model.preparation?.goals ?? [], saved: model.draft?.observations ?? [])
    }

    var body: some View {
        let groups = competencyGroups
        if !model.competencies.isEmpty {
            Section {
                ForEach(groups.worked) { competency in
                    SchoolReportCompetencyRow(model: model, competency: competency, expanded: $expanded)
                }
                if !groups.others.isEmpty {
                    // Une compétence déjà notée dans ce groupe le garde ouvert : rien de saisi n’est caché.
                    let rated = groups.others.contains { other in model.observations.contains { $0.id == other.id } }
                    DisclosureGroup("Autres compétences", isExpanded: Binding(get: { showsOthers || rated }, set: { showsOthers = $0 })) {
                        ForEach(groups.others) { competency in
                            SchoolReportCompetencyRow(model: model, competency: competency, expanded: $expanded)
                        }
                    }
                    .accessibilityIdentifier("lesson-competency-others")
                }
            } header: { Text("Compétences").drivyFormSectionHeader() }
                .drivyFormRows()
        }
    }
}

/// Un niveau choisi suffit : le jour et le lieu sont proposés comme situation, modifiable.
private struct SchoolReportCompetencyRow: View {
    @Bindable var model: SchoolLessonReportWorkspace
    let competency: SchoolCatalogCompetency
    @Binding var expanded: Set<UUID>

    private var chosen: SchoolReportObservation? { model.observations.first(where: { $0.id == competency.id }) }
    private var displayedLevel: String {
        chosen?.level ?? (model.currentLevels[competency.id]?.sourceLessonId == model.lessonID ? "" : model.currentLevels[competency.id]?.level ?? "")
    }
    private var levelLabel: String { chosen?.levelLabel ?? model.unchangedChoiceLabel(for: competency.id) }
    private var level: Binding<String> {
        Binding(get: { model.observations.first(where: { $0.id == competency.id })?.level ?? "" },
                set: { model.setObservationLevel($0, for: competency.id) })
    }
    private var situation: Binding<String> {
        Binding(get: { model.observations.first(where: { $0.id == competency.id })?.context ?? "" },
                set: { value in
                    if let index = model.observations.firstIndex(where: { $0.id == competency.id }) { model.observations[index].context = value }
                })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
            picker
            // Bilan « Pour moi » : le niveau choisi ne compte dans la progression qu’une fois le bilan partagé.
            if model.levelIsHeldBack(for: competency.id) {
                Text("Pour moi").font(.caption).foregroundStyle(DrivyTheme.muted)
                    .accessibilityLabel("Cette évaluation reste pour toi")
                    .accessibilityIdentifier("lesson-competency-private-\(competency.id.uuidString)")
            }
        }
        if expanded.contains(competency.id), chosen != nil {
            TextField("Situation", text: situation, axis: .vertical)
                .font(.subheadline)
                .foregroundStyle(DrivyTheme.muted)
                .disabled(!model.acceptsInput)
                .accessibilityLabel("Situation, \(competency.displayLabel)")
        }
    }

    private var picker: some View {
        Menu {
            Picker(competency.displayLabel, selection: level) {
                Text(model.unchangedChoiceLabel(for: competency.id)).tag("")
                Text("En découverte").tag("DISCOVERING")
                Text("Avec accompagnement").tag("GUIDED")
                Text("En autonomie").tag("INDEPENDENT")
            }
            if chosen != nil {
                Button("Retirer l’évaluation de cette leçon") {
                    model.setObservationLevel("", for: competency.id)
                    expanded.remove(competency.id)
                }
                Button("Préciser la situation") { expanded.insert(competency.id) }
            }
        } label: {
            HStack(spacing: DrivySpacing.s) {
                VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                    Text(competency.displayLabel).font(.subheadline.weight(.medium)).foregroundStyle(DrivyTheme.text)
                    Text(levelLabel).font(.caption).foregroundStyle(DrivyTheme.muted)
                    // Ce que le moniteur a signalé en route sur cette compétence, pour noter sans se souvenir.
                    if let signalled = SchoolReportFlowRules.signalled(for: competency.id, in: model.lessonObservations) {
                        Text(signalled).font(.caption).foregroundStyle(DrivyTheme.muted)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                DrivyCompetencyMeter(level: displayedLevel)
                Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(DrivyTheme.muted)
            }
            .frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(!model.acceptsInput)
        .accessibilityIdentifier("lesson-competency-level-\(competency.id.uuidString)")
    }
}

/// La leçon est déjà terminée : ce bouton enregistre le bilan, puis ferme la fiche. L’école en fait aussitôt
/// la version lue par l’élève, sauf bilan gardé pour soi ; le libellé le dit avant le geste.
struct SchoolReportSaveBar: View {
    @Bindable var model: SchoolLessonReportWorkspace

    private var title: String {
        SchoolLessonHubRules.saveReportTitle(isEmpty: model.reportIsEmpty, shared: model.sharing == nil ? nil : model.reportShared)
    }
    private var isSending: Bool { model.isBusy && model.pending?.kind == .saveReportDraft }

    var body: some View {
        DrivyStickyActionBar {
            if !model.validTexts { DrivyActionNote(text: "Un texte dépasse 4 000 caractères.", isError: true) }
            else if !model.observationsValid { DrivyActionNote(text: "Vérifie les niveaux et limite chaque situation à 500 caractères.", isError: true) }
            Button { Task { await model.saveDraft() } } label: {
                DrivyBusyLabel(title: title, isBusy: isSending)
            }
            .buttonStyle(DrivyPrimaryButtonStyle())
            .disabled(!model.acceptsInput || !model.validTexts || !model.observationsValid)
            .accessibilityIdentifier("lesson-save-report")
        }
    }
}

// MARK: Demandes et saisie conservée

/// Saisie gardée après un conflit, et demande au résultat inconnu : mêmes blocs sur la fiche et dans la rédaction.
struct SchoolReportNotices: View {
    let model: SchoolLessonReportWorkspace

    var body: some View {
        if model.needsReload && model.hasLocalEdits {
            Section { Text(model.retainedEditsText).textSelection(.enabled) } header: { Text("Saisie conservée").drivyFormSectionHeader() }
                .drivyFormRows()
        }
        if model.pendingAwaitsReview { pending }
    }

    /// Même présentation que partout ailleurs pour une demande au résultat inconnu.
    private var pending: some View {
        let idle = !(model.isBusy || model.isLoading)
        let retry: (() -> Void)? = model.pending?.kind.isReport == true
            ? { model.reviewPending(); Task { await model.retryPending() } }
            : nil
        return Section {
            DrivyPendingRequest(
                message: "La demande est conservée sur cet appareil. Vérifie son résultat avant une nouvelle action.",
                verify: { Task { await model.verifyPending() } }, canVerify: idle,
                retry: retry, canRetry: idle
            ) {
                DisclosureGroup {
                    Text(model.pendingDescription)
                        .font(.footnote)
                        .foregroundStyle(DrivyTheme.muted)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Text("Voir la demande").font(.footnote).foregroundStyle(DrivyTheme.muted)
                }
            }
        }
        .drivyFormRows()
    }
}

// MARK: Carte

/// Commande de lecture posée sur l’aperçu du trajet : même vitre teintée et même cible de 48 pt que les
/// commandes des écrans carte, lisible sur la carte en clair comme en sombre.
private struct LessonReplayGlyph: View {
    var body: some View {
        Image(systemName: "play.fill")
            .font(DrivyMapGlyph.control)
            .foregroundStyle(DrivyTheme.text)
            // Le triangle de lecture paraît décalé à gauche dans un cercle : un point le recentre à l’œil.
            .offset(x: 1)
            .frame(width: 48, height: 48)
            .drivyLegibleMapControl(in: Circle())
            .contentShape(Circle())
    }
}

/// Carte d’un trajet enregistré, avec les observations ancrées. Aucune position n’est inventée :
/// sans mesure, la section n’est pas affichée.
struct LessonTrackMap: View {
    struct Pin: Identifiable {
        let id: UUID
        let latitude: Double
        let longitude: Double
        let color: Color
        /// Observation touchée dans la liste : son épingle grossit, sa couleur ne change pas.
        var isSelected = false
        var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
    }
    private struct Line: Identifiable {
        let id: Int
        let coordinates: [CLLocationCoordinate2D]
    }
    let segments: [[SchoolCapturePoint]]
    let pins: [Pin]
    var height: CGFloat = DrivyMapLayout.previewHeight

    private var lines: [Line] {
        segments.enumerated().map { index, points in
            Line(id: index, coordinates: points.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) })
        }
    }

    var body: some View {
        Map(initialPosition: .automatic) {
            ForEach(lines) { line in
                if line.coordinates.count > 1 {
                    MapPolyline(coordinates: line.coordinates).stroke(DrivyTheme.routeHalo, lineWidth: 8)
                    MapPolyline(coordinates: line.coordinates).stroke(DrivyTheme.route, lineWidth: 4)
                } else if let coordinate = line.coordinates.first {
                    Annotation("Position enregistrée", coordinate: coordinate) {
                        Circle().fill(DrivyTheme.route).frame(width: 8, height: 8)
                    }.annotationTitles(.hidden)
                }
            }
            ForEach(pins) { pin in
                Annotation("", coordinate: pin.coordinate) {
                    Circle().fill(pin.color).frame(width: pin.isSelected ? 24 : 16, height: pin.isSelected ? 24 : 16)
                        .overlay(Circle().stroke(DrivyTheme.routeHalo, lineWidth: pin.isSelected ? 3 : 2))
                        .accessibilityHidden(true)
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .frame(height: height)
        .accessibilityLabel("Trajet de la leçon")
    }
}
