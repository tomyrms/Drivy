import SwiftUI

/// L’instant est figé à l’ouverture. Le choix du thème ne crée aucune observation.
struct SchoolLiveObservationSheet: View {
    @Bindable var recorder: SchoolLiveObservationRecorder
    let observedAt: Date
    @State private var selected: SchoolLiveObservationTheme?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DrivySpacing.l) {
                    if let selected {
                        Text(selected.title).font(.drivyScreenTitle)
                            .fixedSize(horizontal: false, vertical: true)
                        ForEach(SchoolObservationStatus.allCases) { status in
                            Button {
                                if recorder.record(theme: selected, status: status, at: observedAt) { dismiss() }
                            } label: {
                                Label(status.label, systemImage: status.symbol)
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            }
                            .buttonStyle(DrivySecondaryButtonStyle()).disabled(!recorder.canRecord)
                            .accessibilityIdentifier("live-observation-status-\(status.rawValue)")
                        }
                    } else {
                        if recorder.isLoadingCompetencies { ProgressView("Chargement des thèmes…") }
                        LazyVGrid(columns: dynamicTypeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.adaptive(minimum: 145))], spacing: DrivySpacing.s) {
                            ForEach(recorder.themes) { theme in
                                Button { selected = theme } label: {
                                    VStack(spacing: DrivySpacing.xs) {
                                        Image(systemName: theme.symbol).font(.title2).accessibilityHidden(true)
                                        Text(theme.title).font(.headline)
                                    }
                                        .frame(maxWidth: .infinity, minHeight: 80)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .buttonStyle(DrivySecondaryButtonStyle())
                                .accessibilityIdentifier("live-observation-theme-\(theme.title)")
                            }
                        }
                        if let message = recorder.competenciesMessage {
                            DrivyInlineMessage(text: message, tone: .warning)
                            Button("Réessayer") { Task { await recorder.loadCompetencies() } }
                        }
                        Button("Marquer un moment", systemImage: "bookmark") {
                            if recorder.markMoment(at: observedAt) { dismiss() }
                        }
                        .frame(minHeight: 44).disabled(!recorder.canRecord)
                        .accessibilityIdentifier("live-observation-marker")
                    }
                    if let error = recorder.errorMessage { SchoolErrorNotice(message: error) }
                }.drivyPageContent()
            }
            .background(DrivyTheme.surface)
            .navigationTitle("Signaler").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if selected != nil { Button("Thèmes") { selected = nil } }
                    else { Button("Annuler") { dismiss() } }
                }
            }
            .task { await recorder.loadCompetencies() }
        }.tint(DrivyTheme.accent)
    }
}
