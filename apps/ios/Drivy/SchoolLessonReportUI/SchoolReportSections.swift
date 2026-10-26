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

    /// Le replay porte le titre de la fiche : le nom de l’élève pour l’équipe, celui du moniteur pour l’élève, qui
    /// connaît son propre nom. Sans nom de moniteur fourni par l’école, rien n’est deviné : « Trajet ».
    func openReplay(_ capture: SchoolCaptureSession, model: SchoolLessonReportWorkspace, context: SchoolReportContext) {
        let title = SchoolLessonHubRules.headerIdentity(learnerName: context.learnerName,
            instructorName: model.lesson?.providedInstructorName, isOwnLearner: model.isOwnLearner,
            roles: model.membership.roles)?.name ?? "Trajet"
        replay = SchoolTripReplayRoute(model: SchoolCaptureReplayWorkspace(scope: model.scope, client: context.agenda.captureClient,
            captureID: capture.id), learnerName: title, lessonTimeZone: model.lesson?.timeZone)
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
                    .disabled(!model.acceptsInput).drivyControlTint()
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
                    .frame(minHeight: DrivyLayout.tapTarget)
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
                status: SchoolLessonHubRules.status(of: observation), isSelected: router.selectedObservation == observation.id,
                glyph: observation.glyph(competencies: model.competencies),
                label: observation.text)
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
        SchoolLessonHubRules.status(of: observation)?.tone.signal ?? DrivyTheme.muted
    }

    var body: some View {
        if editable || !model.lessonObservations.isEmpty { section }
    }

    private var section: some View {
        Section {
            if editable && model.lessonObservations.isEmpty && isCompleted {
                Text("Aucune observation.").foregroundStyle(DrivyTheme.muted)
            }
            ForEach(Array(model.lessonObservations.enumerated()), id: \.element.id) { index, observation in
                DrivyThreadItem(position: .at(index, count: model.lessonObservations.count),
                    isCurrent: router.selectedObservation == observation.id,
                    markerColor: Self.color(observation),
                    markerGlyph: observation.glyph(competencies: model.competencies)) {
                    SchoolReportObservationRow(model: model, router: router, context: context, observation: observation,
                        editable: editable && model.isAuthor && isCompleted)
                }
                .listRowInsets(EdgeInsets(top: 0, leading: DrivySpacing.l, bottom: 0, trailing: DrivySpacing.l))
                .listRowSeparator(.hidden)
            }
            if editable && model.isAuthor {
                Button {
                    // Envoi bref en cours : l’appui est ignoré plutôt que le bouton grisé. Une relecture n’empêche rien.
                    guard !model.isBusy else { return }
                    if isCompleted { router.add(model: model, context: context) } else { router.openList() }
                } label: {
                    // Les observations se relisent avant la feuille : l’attente se lit dans le bouton touché.
                    let title = isCompleted ? "Ajouter une observation" : "Noter une observation"
                    DrivyBusyLabel(title: title, busyTitle: title, isBusy: router.isOpeningObservation)
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
    @Environment(\.dynamicTypeSize) private var typeSize

    private var competency: String? {
        guard let id = observation.competencyId else { return nil }
        return model.competencies.first(where: { $0.id == id })?.displayLabel
    }
    private var kept: Bool { model.isPrivate(observation) }
    private var isAnchored: Bool { model.anchor(of: observation) != nil }

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DrivySpacing.xs))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: DrivySpacing.s))
        layout {
            summary
            if editable { actions }
        }
    }

    @ViewBuilder private var summary: some View {
        let content = DrivyObservationSummary(observation: observation, competency: competency,
            detail: SchoolReportFlowRules.observationDetail(observation, zone: model.lesson?.timeZone), showsStatusSymbol: false)
        if isAnchored {
            // Une observation placée sur le trajet se retrouve sur la carte : son épingle grossit.
            content
                .contentShape(Rectangle())
                .onTapGesture { router.selectedObservation = router.selectedObservation == observation.id ? nil : observation.id }
                // Ligne touchable : VoiceOver l’annonce comme bouton, et dit celle qui est montrée sur la carte.
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(router.selectedObservation == observation.id ? [.isButton, .isSelected] : .isButton)
                .accessibilityAction(named: "Montrer sur la carte") { router.selectedObservation = observation.id }
        } else {
            content
        }
    }

    private var actions: some View {
        Menu {
            Button(observation.isMarker ? "Préciser" : "Modifier") { router.edit(observation, model: model, context: context) }
                .disabled(router.isOpeningObservation)
            if model.sharing != nil {
                Button(kept ? "Montrer à l’élève" : "Garder pour moi") {
                    Task { await model.updateSharing(observation: observation.id, observationPrivate: !kept) }
                }
            }
            Button("Retirer", role: .destructive) { router.remove(observation, model: model, context: context) }
                .disabled(router.isOpeningObservation)
        } label: {
            HStack(spacing: DrivySpacing.xxs) {
                if kept { Text("Pour moi").font(.caption).foregroundStyle(DrivyTheme.muted) }
                Image(systemName: "ellipsis").font(.body).foregroundStyle(DrivyTheme.muted)
            }
            .frame(minWidth: DrivyLayout.tapTarget, minHeight: DrivyLayout.tapTarget).contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(!model.acceptsInput)
        .accessibilityLabel("Actions pour l’observation, \(kept ? "pour moi" : "visible par l’élève")")
    }
}

// MARK: Bilan : rédaction

enum SchoolReportTextField: Hashable {
    case workedOn, observation, nextStep
}

/// Les trois textes du bilan et son partage. Tout est facultatif.
struct SchoolReportTextSection: View {
    @Bindable var model: SchoolLessonReportWorkspace
    /// L’étape compacte peut fermer le clavier ; la rédaction en colonnes conserve un focus local.
    var focusedField: FocusState<SchoolReportTextField?>.Binding? = nil
    @FocusState private var localFocusedField: SchoolReportTextField?

    var body: some View {
        Section {
            if model.sharing != nil {
                Toggle("Visible par l’élève", isOn: Binding(get: { model.reportShared },
                    set: { shared in Task { await model.updateSharing(reportPrivate: !shared) } }))
                    .disabled(!model.acceptsInput).drivyControlTint()
            }
            field("Travail réalisé", text: $model.workedOn, focus: .workedOn)
            field("À retenir", text: $model.observationText, focus: .observation)
            field("Prochaine étape", text: $model.nextStep, focus: .nextStep)
        } header: { Text("Bilan").drivyFormSectionHeader() }
            .drivyFormRows()
    }

    private func field(_ label: String, text: Binding<String>, focus: SchoolReportTextField) -> some View {
        let count = text.wrappedValue.unicodeScalars.count
        return VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
            Text(label).font(.subheadline.weight(.semibold)).foregroundStyle(DrivyTheme.muted).accessibilityHidden(true)
            TextField("Facultatif", text: text, axis: .vertical).lineLimit(1...10).disabled(!model.acceptsInput)
                .focused(focusedField ?? $localFocusedField, equals: focus)
                .accessibilityLabel(label)
                .accessibilityHint("Facultatif")
            // Le compteur n’apparaît qu’à l’approche de la limite.
            if count > 3_600 {
                Text("\(count) / 4 000").font(.caption.monospacedDigit())
                    .foregroundStyle(count > 4_000 ? DrivyTheme.danger : DrivyTheme.muted)
            }
        }
        .padding(.vertical, DrivySpacing.xs)
        .id(focus)
    }
}

/// Niveaux par compétence : toutes celles du référentiel de la formation, à plat et dans son ordre. Les signalements
/// du trajet, les objectifs et les niveaux déjà notés n’en choisissent, n’en trient ni n’en replient aucune (#56, #57).
struct SchoolReportCompetenciesSection: View {
    @Bindable var model: SchoolLessonReportWorkspace
    @State private var expanded = Set<UUID>()

    var body: some View {
        if !model.competencies.isEmpty {
            Section {
                ForEach(model.competencies) { competency in
                    SchoolReportCompetencyRow(model: model, competency: competency, expanded: $expanded)
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
    @Environment(\.dynamicTypeSize) private var typeSize

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
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: DrivySpacing.xs))
                : AnyLayout(HStackLayout(spacing: DrivySpacing.s))
            layout {
                VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                    Text(competency.displayLabel).font(.subheadline.weight(.medium)).foregroundStyle(DrivyTheme.text)
                    Text(levelLabel).font(.caption).foregroundStyle(DrivyTheme.muted)
                    // Ce que le moniteur a signalé en route sur cette compétence, pour noter sans se souvenir.
                    if let signalled = SchoolReportFlowRules.signalled(for: competency.id, in: model.lessonObservations) {
                        Text(signalled).font(.caption).foregroundStyle(DrivyTheme.muted)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: DrivySpacing.s) {
                    DrivyCompetencyMeter(level: displayedLevel)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2).foregroundStyle(DrivyTheme.muted).accessibilityHidden(true)
                }
            }
            .frame(minHeight: DrivyLayout.tapTarget).contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(!model.acceptsInput)
        .accessibilityIdentifier("lesson-competency-level-\(competency.id.uuidString)")
    }
}

/// Aperçu fidèle de ce qui sera enregistré. Il lit les valeurs éditées du modèle, jamais une révision déjà publiée.
/// Le trajet et les observations n’apparaissent que lorsqu’ils existent réellement.
struct SchoolReportReviewSection: View {
    let model: SchoolLessonReportWorkspace
    let router: SchoolReportRouter
    let context: SchoolReportContext
    var showsHeading = false
    var showsEvidence = true

    private var hasTrip: Bool { !model.track.isEmpty || !model.replayableCaptures.isEmpty }
    private var review: SchoolReportReview {
        SchoolReportFlowRules.review(workedOn: model.workedOn, observationText: model.observationText,
            nextStep: model.nextStep, observations: model.observations, competencies: model.competencies,
            shared: model.sharing.map { _ in model.reportShared }, hasTrip: hasTrip,
            lessonObservationCount: model.lessonObservations.count)
    }

    var body: some View {
        if showsHeading {
            Section {
                Text("Récapitulatif")
                    .font(.drivySection)
                    .foregroundStyle(DrivyTheme.text)
                    .accessibilityAddTraits(.isHeader)
            }
            .drivyClearRow()
            .accessibilityIdentifier("lesson-report-review-heading")
        }
        report
        competencies
        visibility
        if showsEvidence, review.hasTrip {
            SchoolReportTripSection(model: model, router: router, context: context,
                mapHeight: SchoolReportLayout.evidenceMapHeight, editable: true)
        }
        // Avec un trajet, la section reste présente même vide : elle porte l'ajout d'une observation.
        if showsEvidence, review.hasTrip || review.lessonObservationCount > 0 {
            SchoolReportObservationsSection(model: model, router: router, context: context, editable: true)
        }
    }

    private var report: some View {
        Section {
            if review.texts.isEmpty {
                Text("Aucun texte ajouté.").foregroundStyle(DrivyTheme.muted)
            } else {
                ForEach(review.texts, id: \.label) { item in
                    VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                        Text(item.label).font(.caption).foregroundStyle(DrivyTheme.muted)
                        Text(item.value).fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        } header: { Text("Bilan").drivyFormSectionHeader() }
            .drivyFormRows()
            .accessibilityIdentifier("lesson-report-review-text")
    }

    @ViewBuilder private var competencies: some View {
        if !model.competencies.isEmpty || review.showsCompetencies {
            Section {
                if review.competencies.isEmpty {
                    Text("Aucune compétence évaluée.").foregroundStyle(DrivyTheme.muted)
                } else {
                    ForEach(Array(review.competencies.enumerated()), id: \.offset) { _, competency in
                        VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                            Text(competency.label).font(.subheadline.weight(.medium))
                            Text(competency.level).font(.caption).foregroundStyle(DrivyTheme.muted)
                            if !competency.context.isEmpty {
                                Text(competency.context).font(.caption).foregroundStyle(DrivyTheme.muted)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            } header: { Text("Compétences").drivyFormSectionHeader() }
                .drivyFormRows()
                .accessibilityIdentifier("lesson-report-review-competencies")
        }
    }

    private var visibility: some View {
        Section {
            switch review.visibility {
            case .shared:
                Label(review.visibility.pendingLabel, systemImage: "person.2")
            case .forMe:
                Label(review.visibility.pendingLabel, systemImage: "lock")
            case .unknown:
                Label(review.visibility.pendingLabel, systemImage: "exclamationmark.circle")
                    .foregroundStyle(DrivyTheme.muted)
            }
        } header: { Text("Partage").drivyFormSectionHeader() }
            .drivyFormRows()
            .accessibilityIdentifier("lesson-report-review-visibility")
    }
}

/// En fenêtre large, l’action durable se trouve après le récapitulatif, jamais dès l’entrée dans la rédaction.
struct SchoolReportSaveSection: View {
    @Bindable var model: SchoolLessonReportWorkspace

    var body: some View {
        Section {
            SchoolReportSaveControl(model: model)
        }
        .drivyFormRows()
    }
}

/// La leçon est déjà terminée : ce bouton enregistre le bilan, puis ferme la fiche. L’école en fait aussitôt
/// la version lue par l’élève, sauf bilan gardé pour soi ; le libellé le dit avant le geste.
struct SchoolReportSaveBar: View {
    @Bindable var model: SchoolLessonReportWorkspace

    var body: some View {
        DrivyStickyActionBar { SchoolReportSaveControl(model: model) }
    }
}

private struct SchoolReportSaveControl: View {
    @Bindable var model: SchoolLessonReportWorkspace

    private var title: String {
        SchoolLessonHubRules.saveReportTitle(isEmpty: model.reportIsEmpty, shared: model.sharing == nil ? nil : model.reportShared)
    }
    private var isSending: Bool { model.isBusy && model.pending?.kind == .saveReportDraft }

    var body: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xs) {
            if !model.validTexts { DrivyActionNote(text: "Un texte dépasse 4 000 caractères.", isError: true) }
            else if !model.observationsValid { DrivyActionNote(text: "Vérifie les niveaux et limite chaque situation à 500 caractères.", isError: true) }
            Button { Task { await model.saveDraft() } } label: {
                DrivyBusyLabel(title: title, isBusy: isSending)
            }
            .buttonStyle(DrivyPrimaryButtonStyle())
            .disabled(!model.acceptsInput || !model.validTexts || !model.observationsValid)
            .accessibilityIdentifier("lesson-save-report")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: Demandes et saisie conservée

/// Saisie gardée après un conflit, et demande au résultat inconnu : mêmes blocs sur la fiche et dans la rédaction.
struct SchoolReportNotices: View {
    let model: SchoolLessonReportWorkspace

    var body: some View {
        if let error = model.localDraftError {
            Section {
                SchoolErrorNotice(message: error, retry: model.isInvalidated ? nil : { model.retryLocalDraft() })
                    .accessibilityIdentifier("lesson-local-draft-error")
            }
            .drivyClearRow()
            .listRowSeparator(.hidden)
        }
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
                message: model.pending?.waitingMessage(absent: model.pendingAbsent) ?? "",
                verify: model.pendingAbsent ? nil : { Task { await model.verifyPending() } }, canVerify: idle,
                retry: retry, canRetry: idle,
                abandon: model.pendingAbsent ? { Task { await model.abandonPending() } } : nil, canAbandon: idle
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
