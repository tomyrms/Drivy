import SwiftUI

/// Native controls keep destructive roles and French confirmation under Drivy's ownership.
struct MessagingMessageMenu: View {
    let thread: MessagingThreadModel
    let displayID: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let item = thread.item(displayID) {
                    if thread.canReact(displayID: displayID) {
                        Section("Réagir") {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: DrivyLayout.tapTarget))]) {
                                ForEach(MessagingReactionPalette.all, id: \.self) { emoji in
                                    Button { thread.chooseMenuReaction(emoji, displayID: displayID) } label: {
                                        Text(emoji).font(.title2)
                                            .frame(minWidth: DrivyLayout.tapTarget, minHeight: DrivyLayout.tapTarget)
                                    }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel("Réagir : \(MessagingReactionPalette.label(emoji))")
                                }
                            }
                        }
                    }
                    Section {
                        ForEach(thread.menuActions(item).filter { !$0.isDeletion }, id: \.self) { action in
                            actionButton(action)
                        }
                    }
                    if thread.menuActions(item).contains(where: \.isDeletion) {
                        Section("Suppression") {
                            ForEach(thread.menuActions(item).filter(\.isDeletion), id: \.self) { action in
                                actionButton(action)
                            }
                        }
                    }
                } else {
                    ContentUnavailableView("Message indisponible", systemImage: "bubble.left")
                }
            }
            .scrollContentBackground(.hidden)
            .background(DrivyTheme.canvas)
            .navigationTitle("Actions du message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } } }
        }
        .tint(DrivyTheme.accent)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func actionButton(_ action: MessagingExyteMenuAction) -> some View {
        Button(role: action.nativeRole) { thread.chooseMenuAction(action, displayID: displayID) } label: {
            Label { Text(action.title()) } icon: { action.icon() }
                .frame(minHeight: DrivyLayout.tapTarget, alignment: .leading)
        }
        .accessibilityHint(action.consequence ?? "")
        .accessibilityIdentifier("messaging.menu.\(action.rawValue)")
    }
}
