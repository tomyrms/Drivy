import SwiftUI
import UIKit

/// Feedback outside the command panel; only the recorder can confirm a durable withdrawal.
struct SchoolObservationUndoBanner: View {
    @Bindable var recorder: SchoolLiveObservationRecorder
    let receipt: SchoolLiveObservationReceipt
    let close: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    private struct DismissalState: Equatable {
        let id: UUID
        let undo: SchoolLiveObservationUndoState
        let error: String?
        let sending: Bool
    }

    private var dismissalState: DismissalState {
        .init(id: receipt.id, undo: recorder.undoState, error: recorder.undoErrorMessage, sending: recorder.isSending)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xs) {
            if typeSize.isAccessibilitySize {
                HStack(alignment: .top) { message; Spacer(minLength: DrivySpacing.xs); closeButton }
                undoButton
            } else {
                HStack(spacing: DrivySpacing.xs) {
                    message
                    Spacer(minLength: 0)
                    undoButton
                    closeButton
                }
            }
            if let error = recorder.undoErrorMessage {
                Text(error).font(.footnote).foregroundStyle(DrivyTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.leading, DrivySpacing.m)
        .padding(.trailing, DrivySpacing.xxs)
        .padding(.vertical, DrivySpacing.xxs)
        .background(DrivyTheme.surface, in: RoundedRectangle(cornerRadius: DrivyRadius.content, style: .continuous))
        .drivyShadow(radius: 12, y: 4)
        // Le moniteur ne regarde pas l’écran : un refus de l’école se signale aussi au toucher.
        .sensoryFeedback(.error, trigger: recorder.undoState) { _, state in state == .refused }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("live-observation-notice")
        .onChange(of: title, initial: true) { _, message in
            UIAccessibility.post(notification: .announcement, argument: message)
        }
        .task(id: dismissalState) {
            guard !UIAccessibility.isVoiceOverRunning, recorder.undoState != .pending,
                  recorder.undoErrorMessage == nil, !recorder.isSending else { return }
            let delay = recorder.undoState == .confirmed ? 3 : 10
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard !UIAccessibility.isVoiceOverRunning else { return }
            close()
        }
    }

    private var message: some View {
        Label(title, systemImage: symbol)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(DrivyTheme.text)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(title)
            .accessibilityValue(recorder.undoState == .refused ? "" : receipt.displayTitle)
    }

    private var title: String {
        switch recorder.undoState {
        case .none: "Ajouté à la leçon"
        case .pending: "Annulation en attente"
        case .confirmed: "Signalement annulé"
        case .refused: "Non enregistré"
        }
    }

    private var symbol: String {
        switch recorder.undoState {
        case .pending: "clock"
        case .refused: "exclamationmark.triangle"
        case .none, .confirmed: "checkmark"
        }
    }

    @ViewBuilder private var undoButton: some View {
        if recorder.undoState == .none {
            Button { Task { _ = await recorder.undoLastAdded(id: receipt.id) } } label: {
                Text("Annuler").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
            }
                .disabled(!recorder.canUndo(receipt.id))
                .accessibilityIdentifier("live-observation-undo")
                .buttonStyle(.plain)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DrivyTheme.accent)
        } else if recorder.undoState == .pending && recorder.canRetry {
            Button { Task { await recorder.retry() } } label: {
                Text("Réessayer").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
            }
                .buttonStyle(.plain)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DrivyTheme.accent)
        }
    }

    private var closeButton: some View {
        Button(action: close) {
            Image(systemName: "xmark")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(DrivyTheme.muted)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Fermer la notification")
    }
}
