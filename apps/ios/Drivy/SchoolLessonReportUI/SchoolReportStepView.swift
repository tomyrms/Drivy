import SwiftUI

/// Une étape de la rédaction du bilan, poussée dans la pile de la fiche. La saisie vit dans le modèle de la leçon :
/// revenir en arrière ou avancer ne la touche pas. « Continuer » n’envoie rien ; seule la dernière étape enregistre.
struct SchoolReportStepView: View {
    @Bindable var model: SchoolLessonReportWorkspace
    let context: SchoolReportContext
    /// Étapes figées à l’entrée : un trajet qui finit d’arriver ne change pas le compte en cours de route.
    let steps: [SchoolReportStep]
    let index: Int
    @State private var router = SchoolReportRouter()
    @State private var showsNext = false
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @FocusState private var focusedReportField: SchoolReportTextField?

    private var step: SchoolReportStep { steps[index] }
    private var isLast: Bool { index == steps.count - 1 }
    private var hasTrip: Bool { !model.captures.isEmpty || !model.track.isEmpty }
    private var title: String { SchoolReportFlowRules.title(of: step, hasTrip: hasTrip) }
    private var needsEditingSpace: Bool { verticalSizeClass == .compact && focusedReportField != nil }

    var body: some View {
        Form {
            SchoolReportStepMessages(model: model)
            SchoolReportNotices(model: model)
            content
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .frame(maxWidth: DrivyLayout.formColumn)
        .frame(maxWidth: .infinity)
        .background(DrivyTheme.canvas)
        // En paysage bas, la saisie passe avant la barre fixe ; le formulaire garde son identité et son focus.
        .safeAreaInset(edge: .bottom, spacing: 0) { if !needsEditingSpace { bar } }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                SchoolReportStepTitle(title: title, position: SchoolReportFlowRules.position(of: index, count: steps.count))
            }
            if needsEditingSpace {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { focusedReportField = nil } label: {
                        Label("Fermer le clavier", systemImage: "keyboard.chevron.compact.down")
                    }
                    .labelStyle(.iconOnly)
                    .accessibilityIdentifier("lesson-report-dismiss-keyboard")
                }
            }
        }
        .navigationDestination(isPresented: $showsNext) {
            if !isLast {
                SchoolReportStepView(model: model, context: context, steps: steps, index: index + 1)
            }
        }
        .modifier(SchoolReportPresentations(router: router, model: model, context: context))
        .modifier(SchoolReportLocalDraftKeeper(model: model))
        .onDisappear { model.persistLocalDraft() }
        .tint(DrivyTheme.accent)
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .trip:
            if hasTrip {
                SchoolReportTripSection(model: model, router: router, context: context, mapHeight: SchoolReportLayout.evidenceMapHeight)
            }
            SchoolReportObservationsSection(model: model, router: router, context: context)
        case .competencies:
            SchoolReportCompetenciesSection(model: model)
        case .report:
            SchoolReportTextSection(model: model, focusedField: $focusedReportField)
        }
    }

    @ViewBuilder private var bar: some View {
        if isLast {
            SchoolReportSaveBar(model: model)
        } else {
            DrivyStickyActionBar {
                Button("Continuer") {
                    model.persistLocalDraft()
                    showsNext = true
                }
                .buttonStyle(DrivySecondaryButtonStyle())
                .accessibilityIdentifier("lesson-report-next")
            }
        }
    }
}

/// Dimensions propres à la rédaction du bilan.
enum SchoolReportLayout {
    /// Carte du trajet quand elle est le sujet de l’écran (étape Trajet, colonne de contexte sur iPad).
    static let evidenceMapHeight: CGFloat = 240
}

/// Titre de l’étape et sa position, lus d’un seul tenant par VoiceOver.
private struct SchoolReportStepTitle: View {
    let title: String
    let position: String?

    var body: some View {
        VStack(spacing: 0) {
            Text(title).font(.headline).foregroundStyle(DrivyTheme.text)
            if let position {
                Text(position).font(.caption).monospacedDigit().foregroundStyle(DrivyTheme.muted)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(position.map { "\(title), étape \($0)" } ?? title)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("lesson-report-step")
    }
}

/// Ce que la fiche dit en tête, repris dans une étape : une erreur avec sa reprise, une confirmation.
private struct SchoolReportStepMessages: View {
    let model: SchoolLessonReportWorkspace

    var body: some View {
        if model.errorMessage != nil || model.confirmation != nil {
            Section {
                if let error = model.errorMessage {
                    SchoolErrorNotice(message: error, retry: model.isBusy || model.isLoading ? nil : { Task { await model.load() } })
                }
                if let message = model.confirmation { DrivyInlineMessage(text: message) }
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }
}

/// Garde la saisie du bilan sur l’appareil après une pause de frappe. Le passage en arrière-plan et le changement
/// d’étape l’écrivent aussi, depuis la fiche et les étapes.
struct SchoolReportLocalDraftKeeper: ViewModifier {
    let model: SchoolLessonReportWorkspace

    func body(content: Content) -> some View {
        content.task(id: model.editedReport) {
            do { try await Task.sleep(for: .seconds(1.5)) } catch { return }
            model.persistLocalDraft()
        }
    }
}
