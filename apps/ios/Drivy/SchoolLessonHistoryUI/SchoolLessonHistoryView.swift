import SwiftUI

/// Profil → Leçons : les leçons passées et à terminer, les plus récentes d’abord, par mois.
/// Un moniteur lit les siennes ; l’administration lit toute l’école (le serveur relit la portée).
/// Une leçon s’ouvre dans la même feuille que depuis l’Agenda.
struct SchoolLessonHistoryView: View {
    let workspace: SchoolWorkspace
    let agendaClient: SchoolAgendaClient
    var captureController: SchoolCaptureSessionController? = nil
    @State private var model: SchoolLessonHistoryWorkspace?
    @State private var uploads: SchoolCaptureHistoryWorkspace?
    /// Portée du modèle en place : la page qui réapparaît (feuille refermée, retour d’onglet) ne le recrée pas.
    @State private var preparedKey: String?
    @State private var filter: SchoolLessonHistoryFilter = .all
    @State private var search = ""
    @State private var selectedLesson: SchoolLesson?

    private var roles: [String] { workspace.membership?.roles ?? [] }
    private var scopeKey: String {
        [workspace.person?.personId.uuidString, workspace.membership?.membershipId.uuidString,
         workspace.membership.map { String($0.accessEpoch) }, workspace.membership?.roles.joined(separator: ","),
         workspace.school?.status].map { $0 ?? "" }.joined(separator: ":")
    }
    private var needsFullHistory: Bool { SchoolLessonHistoryWorkspace.needsFullHistory(filter: filter, search: search) }
    private var fullHistoryKey: String { "\(model?.id.uuidString ?? ""):\(needsFullHistory)" }

    var body: some View {
        Group {
            if let model {
                SchoolLessonHistoryList(model: model, uploads: uploads, filter: $filter, search: search,
                    learnerName: learnerName, open: { selectedLesson = $0 }, refresh: refresh)
            } else {
                placeholder
            }
        }
        .navigationTitle("Leçons")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Rechercher un élève")
        .toolbar {
            if let model {
                ToolbarItem(placement: .topBarTrailing) {
                    SchoolLessonHistoryMenu(model: model, filter: $filter,
                        choosesReach: roles.contains("ADMIN") && roles.contains("INSTRUCTOR"))
                }
            }
        }
        .task(id: scopeKey) {
            if preparedKey == scopeKey, let model {
                if model.loadedAt == nil { await refresh() }
                return
            }
            await prepare()
        }
        // Une recherche ou un filtre porte sur tout l’historique ; l’abandonner arrête la lecture en cours.
        .task(id: fullHistoryKey) { await model?.setFullHistory(needsFullHistory) }
        .onAppear {
            if selectedLesson == nil, let loadedAt = model?.loadedAt, Date().timeIntervalSince(loadedAt) > 30 { Task { await refresh() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: .drivyLessonsDidChange)) { notification in
            if let change = notification.object as? SchoolLessonChange, change.schoolID != workspace.membership?.schoolId { return }
            // La fermeture de la feuille relit déjà la liste.
            if selectedLesson == nil { Task { await refresh() } }
        }
        .onChange(of: captureController?.finalizedSyncState) { _, state in
            if state == .synced || state == .partial { Task { await refresh() } }
        }
        // Session expirée ou accès retiré : la liste n’offre plus de « Réessayer ». Le compte est relu pour ouvrir
        // la reconnexion ou recharger l’école, au lieu de laisser la page sans issue.
        .onChange(of: model?.accessRevoked) { _, revoked in
            if revoked == true { Task { await workspace.refreshAccount(minimumInterval: 0) } }
        }
        .sheet(item: $selectedLesson, onDismiss: { Task { await refresh() } }) { lesson in
            NavigationStack {
                SchoolLessonReportView(client: agendaClient.reportClient, schoolWorkspace: workspace, lessonID: lesson.id,
                    learnerName: learnerName(lesson))
            }
            .tint(DrivyTheme.accent)
            .environment(captureController)
        }
    }

    /// L’école se charge, ou n’a pas pu être lue : jamais une liste vide à la place.
    private var placeholder: some View {
        List {
            Section {
                if let error = workspace.schoolError {
                    SchoolErrorNotice(message: error, retry: {
                        guard let membership = workspace.membership else { return }
                        Task { await workspace.selectSchool(membership) }
                    })
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } else {
                    DrivySkeletonRows(count: 4, leading: .time)
                        .drivySkeleton("Chargement des leçons…")
                }
            }
            .drivyFormRows()
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .frame(maxWidth: DrivyLayout.formColumn)
        .frame(maxWidth: .infinity)
        .background(DrivyTheme.canvas)
    }

    private func prepare() async {
        let key = scopeKey
        preparedKey = nil
        model?.invalidate(); uploads?.invalidate(); selectedLesson = nil
        model = nil; uploads = nil; filter = .all; search = ""
        guard let person = workspace.person, let membership = workspace.membership, workspace.school != nil else { return }
        let scope = agendaClient.scope(person: person, membership: membership)
        // Un moniteur ouvre sur ses leçons, même s’il administre aussi ; l’administration seule lit l’école.
        model = SchoolLessonHistoryWorkspace(scope: scope, client: agendaClient,
            reach: membership.roles.contains("INSTRUCTOR") ? .mine : .school)
        preparedKey = key
        if let captureController, membership.roles.contains("INSTRUCTOR"), workspace.school?.status != "ARCHIVED" {
            uploads = SchoolCaptureHistoryWorkspace(scope: scope, client: agendaClient.captureClient, owner: captureController)
        }
        await refresh()
    }

    /// Relecture silencieuse : ce qui est affiché reste en place jusqu’à la réponse.
    private func refresh() async {
        guard let model else { return }
        let local = uploads
        await model.load(keepingCurrent: true)
        await local?.load()
    }

    /// Nom fourni avec la leçon, sinon celui d’un dossier déjà chargé ; jamais deviné.
    private func learnerName(_ lesson: SchoolLesson) -> String {
        lesson.providedLearnerName ?? workspace.learners.first { $0.id == lesson.learnerId }?.displayName ?? "Leçon de conduite"
    }

    private func learnerName(_ learnerID: UUID) -> String {
        if let name = model?.lessons.first(where: { $0.learnerId == learnerID })?.providedLearnerName { return name }
        if workspace.learner?.id == learnerID, let name = workspace.learner?.displayName { return name }
        return workspace.learners.first { $0.id == learnerID }?.displayName ?? "Élève"
    }
}

/// Le seul menu de la page : ce qui est affiché, l’ordre, et la portée quand le lecteur en a deux.
private struct SchoolLessonHistoryMenu: View {
    let model: SchoolLessonHistoryWorkspace
    @Binding var filter: SchoolLessonHistoryFilter
    let choosesReach: Bool

    private var sortTitle: String { model.newestFirst ? "Récentes d’abord" : "Anciennes d’abord" }
    private var reachTitle: String { model.reach == .mine ? "Mes leçons" : "Toute l’école" }

    var body: some View {
        Menu {
            Section("Afficher") {
                Picker("Afficher", selection: $filter) {
                    ForEach(SchoolLessonHistoryFilter.allCases) { item in Text(item.title).tag(item) }
                }
                .pickerStyle(.inline)
            }
            Section("Trier") {
                Picker("Trier", selection: Binding(get: { model.newestFirst },
                    set: { value in Task { await model.sort(newestFirst: value) } })) {
                    Text("Récentes d’abord").tag(true)
                    Text("Anciennes d’abord").tag(false)
                }
                .pickerStyle(.inline)
            }
            if choosesReach {
                Section("Leçons") {
                    Picker("Leçons", selection: Binding(get: { model.reach },
                        set: { value in Task { await model.show(value) } })) {
                        Text("Mes leçons").tag(SchoolLessonHistoryScope.mine)
                        Text("Toute l’école").tag(SchoolLessonHistoryScope.school)
                    }
                    .pickerStyle(.inline)
                }
            }
        } label: {
            // Le symbole plein dit qu’un filtre réduit la liste.
            Label("Afficher et trier", systemImage: filter == .all
                ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
        }
        .accessibilityLabel("Afficher et trier les leçons")
        .accessibilityValue(([filter.title, sortTitle] + (choosesReach ? [reachTitle] : [])).joined(separator: ", "))
        .accessibilityIdentifier("lessons-history-filter")
    }
}

private struct SchoolLessonHistoryList: View {
    let model: SchoolLessonHistoryWorkspace
    let uploads: SchoolCaptureHistoryWorkspace?
    @Binding var filter: SchoolLessonHistoryFilter
    let search: String
    let learnerName: (UUID) -> String
    let open: (SchoolLesson) -> Void
    let refresh: () async -> Void

    /// Rows left under the one that asks for the next page.
    private static let prefetchDistance = 20

    private var hasUploads: Bool { !(uploads?.pendingUploads.isEmpty ?? true) }
    private var hasUploadError: Bool { uploads?.errorMessage != nil }
    private var isSearching: Bool { !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var needsFullHistory: Bool { SchoolLessonHistoryWorkspace.needsFullHistory(filter: filter, search: search) }

    var body: some View {
        let visible = model.visible(filter: filter, search: search)
        let months = SchoolLessonHistoryWorkspace.months(visible)
        let prefetchID = model.nextCursor != nil && visible.count > Self.prefetchDistance
            ? visible[visible.count - Self.prefetchDistance].id : nil
        return List {
            if let uploads, hasUploads || hasUploadError {
                SchoolCaptureUploadsSection(model: uploads, learnerName: learnerName,
                    onChange: { Task { await model.load(keepingCurrent: true) } })
            }
            if let error = model.errorMessage {
                Section {
                    SchoolErrorNotice(message: error, retry: model.accessRevoked ? nil : { Task { await refresh() } })
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            if model.isLoading && model.lessons.isEmpty {
                Section {
                    DrivySkeletonRows(count: 4, leading: .time)
                        .drivySkeleton("Chargement des leçons…")
                }
                .drivyFormRows()
            }
            ForEach(months) { month in
                Section {
                    ForEach(month.lessons) { lesson in
                        Button { open(lesson) } label: {
                            SchoolLessonHistoryRow(lesson: lesson, title: .learner, instructor: model.instructorName(lesson))
                        }
                        .accessibilityHint("Ouvre la leçon")
                        .accessibilityIdentifier("history-lesson-\(lesson.id.uuidString)")
                        // La rangée porte déjà son propre espacement vertical : sans cela, la liste le double.
                        .listRowInsets(EdgeInsets(top: 0, leading: DrivySpacing.m, bottom: 0, trailing: DrivySpacing.m))
                        .onAppear {
                            if lesson.id == prefetchID { Task { await model.loadMore() } }
                        }
                    }
                } header: {
                    Text(month.title)
                        .font(.headline).foregroundStyle(DrivyTheme.text).textCase(nil)
                        .accessibilityAddTraits(.isHeader)
                }
                .drivyFormRows()
            }
            emptyState(isEmpty: visible.isEmpty)
            if model.nextCursor != nil && model.errorMessage == nil {
                Section { nextPage }
                    .drivyFormRows()
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        // Sur iPad, la liste reste une colonne lisible au lieu de s’étirer d’un bord à l’autre.
        .frame(maxWidth: DrivyLayout.formColumn)
        .frame(maxWidth: .infinity)
        .background(DrivyTheme.canvas)
        .accessibilityIdentifier("lessons-history")
        .refreshable { await refresh() }
    }

    /// Rien n’est affirmé tant qu’il reste des pages à lire ou qu’une lecture a échoué.
    @ViewBuilder private func emptyState(isEmpty: Bool) -> some View {
        if isEmpty && model.isComplete && !model.isLoading && !model.isLoadingMore && model.errorMessage == nil {
            if model.lessons.isEmpty {
                if !hasUploads && !hasUploadError {
                    Section {
                        ContentUnavailableView("Aucune leçon passée", systemImage: "calendar")
                            .frame(maxWidth: .infinity)
                            .accessibilityIdentifier("lessons-history-empty")
                    }
                    .listRowBackground(Color.clear)
                }
            } else if isSearching {
                Section {
                    ContentUnavailableView("Aucun résultat", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("lessons-history-no-result")
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    DrivyEmptyState(title: filter.emptyTitle, symbol: "calendar",
                        actionTitle: "Tout afficher", action: { filter = .all })
                        .frame(maxWidth: .infinity)
                }
                .listRowBackground(Color.clear)
            }
        }
    }

    @ViewBuilder private var nextPage: some View {
        if let error = model.moreErrorMessage {
            SchoolErrorNotice(message: error, retry: { Task { await model.retryMore() } })
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
        } else {
            DrivyLoadingState(title: needsFullHistory ? "Chargement de l’historique…" : "Chargement des autres leçons…")
                .task(id: model.nextCursor) { await model.loadMore() }
        }
    }
}
