import SwiftUI
import UIKit

/// Accord GPS de l’élève posé dans le parcours, sans feuille de plus : la question et ses deux réponses de même
/// poids tant que rien ne vaut pour l’information actuelle de l’école, sinon la réponse et « Modifier ».
/// L’hôte décide de ce qu’un toucher fait (au démarrage immédiat, la réponse attend « Démarrer maintenant »).
struct SchoolRecordingChoiceInline: View {
    @Bindable var model: SchoolRecordingChoiceWorkspace
    /// Réponse montrée : celle donnée ici et pas encore enregistrée, sinon le choix enregistré.
    let answer: SchoolRecordingChoice.Status?
    var isEnabled = true
    let choose: (SchoolRecordingChoice.Status) -> Void
    @State private var editing = false
    @State private var document: RecordingDocument?
    @State private var reviewsPending = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Presentation: Equatable { case loading, unavailable, needsReview, question, answered }

    private var presentation: Presentation {
        if model.notice == nil { return model.isLoading || model.errorMessage == nil ? .loading : .unavailable }
        if model.accessRevoked { return .unavailable }
        if !model.relatedPending.isEmpty || model.hasOldScope { return .needsReview }
        return editing || answer == nil ? .question : .answered
    }

    /// Un choix existe, mais pour une information de l’école qui a changé depuis : seul cas où une phrase s’ajoute.
    private var noticeChanged: Bool {
        guard let choice = model.choice, let notice = model.notice else { return false }
        return choice.status != .unknown && choice.noticeVersionId != notice.noticeVersionId
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.s) {
            switch presentation {
            case .loading:
                DrivySkeletonRow(lines: 2).drivySkeleton("Lecture de l’accord GPS…")
            case .unavailable:
                DrivyInlineMessage(text: model.errorMessage ?? "L’accord GPS n’a pas pu être lu. La leçon peut démarrer sans GPS.",
                    tone: .warning)
                if !model.accessRevoked {
                    Button { Task { await model.load() } } label: { Label("Réessayer", systemImage: "arrow.clockwise") }
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                        .disabled(model.isLoading)
                }
            case .needsReview:
                summaryRow(title: "Accord GPS à vérifier", symbol: "clock.arrow.circlepath", action: "Vérifier") {
                    reviewsPending = true
                }
            case .question:
                question
            case .answered:
                summaryRow(title: answer == .allowed ? "Avec GPS" : "Sans GPS",
                    symbol: answer == .allowed ? "location.fill" : "location.slash", action: "Modifier") {
                    withAnimation(DrivyMotion.reveal(reduceMotion)) { editing = true }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(DrivyMotion.reveal(reduceMotion), value: presentation)
        .sheet(item: $document) { RecordingDocumentView(document: $0) }
        .sheet(isPresented: $reviewsPending, onDismiss: { Task { await model.load() } }) {
            SchoolRecordingChoiceView(model: model)
        }
    }

    private var question: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.s) {
            Text("L’élève accepte-t-il le GPS ?")
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if noticeChanged {
                Text("L’information de l’école a changé.")
                    .font(.subheadline).foregroundStyle(DrivyTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Deux cartes de même taille, même poids, même teinte : aucune réponse n’est mise en avant.
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: DrivySpacing.s))
                : AnyLayout(HStackLayout(spacing: DrivySpacing.s))
            layout {
                card(.allowed, title: "Avec GPS", symbol: "location.fill")
                card(.refused, title: "Sans GPS", symbol: "location.slash")
            }
            if model.verbalAgreementIsProtected {
                DrivyInlineMessage(text: "L’élève a refusé depuis son compte. Lui seul peut modifier ce choix.", tone: .warning)
            }
            if let error = model.storageError { DrivyInlineMessage(text: error, tone: .warning) }
            if let notice = model.notice {
                Button("Information et conservation") {
                    document = .init(id: "notice", title: "Information et conservation",
                        text: notice.noticeText + "\n\n" + notice.retentionText, contact: notice.contactEmail)
                }
                .font(.subheadline)
                .foregroundStyle(DrivyTheme.accent)
                .frame(minHeight: 44)
                .accessibilityIdentifier("gps-answer-notice")
            }
        }
    }

    private func card(_ status: SchoolRecordingChoice.Status, title: String, symbol: String) -> some View {
        let enabled = isEnabled && model.mayChoose && !(status == .allowed && model.verbalAgreementIsProtected)
        let chosen = answer == status
        return Button {
            choose(status)
            withAnimation(DrivyMotion.reveal(reduceMotion)) { editing = false }
        } label: {
            VStack(spacing: DrivySpacing.s) {
                Image(systemName: symbol)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(enabled ? DrivyTheme.accent : DrivyTheme.disabledText)
                    .frame(width: 44, height: 44)
                    .background(chosen ? DrivyTheme.surface : DrivyTheme.accentSoft, in: Circle())
                    .accessibilityHidden(true)
                HStack(spacing: DrivySpacing.xs) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(enabled ? DrivyTheme.text : DrivyTheme.disabledText)
                        .fixedSize(horizontal: false, vertical: true)
                    DrivySelectionMark(isSelected: chosen)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 96)
        }
        .buttonStyle(DrivySelectionCardStyle(isSelected: chosen))
        .disabled(!enabled)
        .accessibilityHint(status == .allowed ? "Le trajet de l’élève sera enregistré" : "La leçon se déroule sans GPS")
        .accessibilityIdentifier(status == .allowed ? "gps-answer-allowed" : "gps-answer-refused")
    }

    private func summaryRow(title: String, symbol: String, action: String, perform: @escaping () -> Void) -> some View {
        HStack(spacing: DrivySpacing.s) {
            HStack(spacing: DrivySpacing.s) {
                Image(systemName: symbol)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DrivyTheme.muted)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                    Text("Accord GPS").font(.subheadline).foregroundStyle(DrivyTheme.muted)
                    Text(title).font(.headline).foregroundStyle(DrivyTheme.text)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("gps-answer")
            Spacer(minLength: DrivySpacing.xs)
            Button(action, action: perform)
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
                .disabled(!isEnabled)
                .accessibilityLabel(action == "Modifier" ? "Modifier l’accord GPS" : "Vérifier l’accord GPS")
        }
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
    }
}
