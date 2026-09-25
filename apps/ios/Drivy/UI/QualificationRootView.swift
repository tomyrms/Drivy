import SwiftUI

struct QualificationRootView: View {
    @Bindable var controller: SessionController
    @State private var selectedTab = QualificationTab.session
    @State private var presentsStart = false
    @State private var presentsLive = false
    @State private var historyPath: [UUID] = []

    private enum QualificationTab { case session, history }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                home
                    .navigationTitle("Séance d’essai")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Text("Drivy")
                                .font(.headline)
                                .foregroundStyle(DrivyTheme.accent)
                        }
                    }
            }
            .tabItem { Label("Séance", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }
            .tag(QualificationTab.session)

            NavigationStack(path: $historyPath) {
                SessionHistoryView(controller: controller)
                    .navigationDestination(for: UUID.self) { sessionID in
                        SessionDetailView(controller: controller, sessionID: sessionID)
                    }
            }
            .tabItem { Label("Historique", systemImage: "clock.arrow.circlepath") }
            .tag(QualificationTab.history)
            .accessibilityIdentifier("history-tab")
        }
        .tint(DrivyTheme.accent)
        .foregroundStyle(DrivyTheme.text)
        .sheet(isPresented: $presentsStart, onDismiss: {
            if controller.activeSession != nil { presentsLive = true }
        }) {
            StartSessionView(controller: controller)
        }
        .fullScreenCover(isPresented: $presentsLive) {
            NavigationStack {
                LiveSessionView(controller: controller, openReplay: { id in
                    historyPath = [id]
                    selectedTab = .history
                })
            }
            .tint(DrivyTheme.accent)
        }
    }

    private var home: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DrivySpacing.l) {
                Text("Votre trajet, vos observations, votre bilan.")
                    .font(.subheadline)
                    .foregroundStyle(DrivyTheme.muted)

                if controller.isLoading {
                    ProgressView("Ouverture des séances…")
                        .frame(maxWidth: .infinity, minHeight: 180)
                } else if let active = controller.activeSession {
                    activeSessionCard(active)
                } else {
                    DrivyPanel {
                        VStack(alignment: .leading, spacing: DrivySpacing.m) {
                            VStack(alignment: .leading, spacing: DrivySpacing.xs) {
                                Text("Prêt pour une séance d’essai")
                                    .font(.drivyTitle)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text("Avec ou sans GPS. Signalez les moments à revoir, puis retrouvez-les dans le replay et le bilan.")
                                    .foregroundStyle(DrivyTheme.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Button { presentsStart = true } label: {
                                Label("Nouvelle séance", systemImage: "plus")
                            }
                            .buttonStyle(DrivyPrimaryButtonStyle())
                            .accessibilityIdentifier("new-session")
                            .disabled(controller.isBusy || controller.errorMessage != nil)
                        }
                    }
                    if let last = controller.sessions.filter({ !$0.isExample && $0.state != .active }).max(by: { $0.startedAt < $1.startedAt }) {
                        VStack(alignment: .leading, spacing: DrivySpacing.xs) {
                            DrivySectionHeader(title: "Dernière séance")
                            Button {
                                historyPath = [last.id]
                                selectedTab = .history
                            } label: {
                                JourneySummaryRow(session: last, showsChevron: true)
                                    .padding(.vertical, DrivySpacing.s)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(DrivyRowButtonStyle())
                            .accessibilityHint("Ouvrir le replay et le bilan de cette séance")
                        }
                    }
                }

                if let error = controller.errorMessage {
                    InlineErrorView(message: error, retry: controller.isCapturing ? nil : {
                        Task { await controller.load() }
                    })
                }

                VStack(alignment: .leading, spacing: DrivySpacing.s) {
                    Text("Un espace d’essai personnel")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    Text("Utilisez vos propres données d’essai, à l’arrêt ou comme passager. Les séances et les bilans restent sur cet appareil.")
                        .font(.subheadline)
                        .foregroundStyle(DrivyTheme.muted)
                    Text("Jusqu’à 2 h par séance d’essai.")
                        .font(.footnote)
                        .foregroundStyle(DrivyTheme.muted)
                    StorageCaption(message: controller.storageStatus)
                }
            }
            .drivyPageContent(maxWidth: 680)
        }
        .background(DrivyTheme.surface)
    }

    private func activeSessionCard(_ session: DrivingSession) -> some View {
        DrivyPanel {
            VStack(alignment: .leading, spacing: DrivySpacing.m) {
                DrivyMapStatusLabel(status: activeStatus(session))
                Text(controller.isCapturing ? "Séance en cours" : "Enregistrement arrêté")
                    .font(.drivyTitle)
                    .fixedSize(horizontal: false, vertical: true)
                if !controller.isCapturing {
                    Text("Vérifiez la sauvegarde : les données déjà écrites sont conservées.")
                        .font(.subheadline)
                        .foregroundStyle(DrivyTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if controller.isCapturing {
                    TimelineView(.periodic(from: .now, by: 1)) { timeline in
                        Text(timeline.date.sessionElapsed(since: session.startedAt))
                            .font(.drivyScreenTitle.monospacedDigit())
                            .foregroundStyle(DrivyTheme.text)
                            .accessibilityLabel("Durée de la séance")
                            .accessibilityValue(timeline.date.sessionElapsed(since: session.startedAt))
                    }
                }
                Label(DrivySeanceText.observations(session.observations.count) + " · privées", systemImage: "lock")
                    .font(.subheadline)
                    .foregroundStyle(DrivyTheme.muted)
                Button {
                    if controller.isCapturing { presentsLive = true }
                    else { Task { await controller.load() } }
                } label: {
                    Label(controller.isCapturing ? "Revenir à la séance" : "Vérifier la sauvegarde",
                          systemImage: controller.isCapturing ? "arrow.up.forward.app" : "arrow.clockwise")
                }
                .buttonStyle(DrivyPrimaryButtonStyle())
                .disabled(controller.isBusy)
                .accessibilityIdentifier("resume-session")
            }
        }
    }

    private func activeStatus(_ session: DrivingSession) -> DrivyMapStatus {
        guard controller.isCapturing else {
            return DrivyMapStatus(title: "Sauvegarde à vérifier", symbol: "exclamationmark.triangle", tone: .warning)
        }
        return session.usesGPS ? controller.gpsStatus.mapStatus : DrivyMapStatus(title: "Sans GPS", symbol: "location.slash")
    }
}

struct StartSessionView: View {
    @Bindable var controller: SessionController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DrivySpacing.l) {
                    VStack(alignment: .leading, spacing: DrivySpacing.xs) {
                        Text("Comment enregistrer ce trajet ?").font(.drivyTitle)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Dans les deux cas, « Signaler » retient le moment et vous retrouvez les observations dans le replay et le bilan.")
                            .font(.body).foregroundStyle(DrivyTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    // Both choices have the same weight: the GPS is optional (F15).
                    VStack(spacing: DrivySpacing.s) {
                        startOption(title: "Avec le GPS", detail: "Le tracé est enregistré ; les observations sont placées sur la carte.",
                            symbol: "location.fill", useGPS: true)
                        startOption(title: "Sans GPS", detail: "Aucune position. Les observations gardent leur heure.",
                            symbol: "clock", useGPS: false)
                    }
                    .disabled(controller.isBusy)
                    if controller.isBusy { DrivyLoadingState(title: "Préparation du trajet…") }
                    if let error = controller.errorMessage { InlineErrorView(message: error) }
                    VStack(alignment: .leading, spacing: DrivySpacing.xs) {
                        Label("Privé sur cet appareil", systemImage: "lock").font(.subheadline.weight(.semibold))
                        Text("Aucun partage automatique. Jusqu’à 2 h par trajet. Si la localisation est refusée, le trajet continue sans position.")
                            .font(.footnote).foregroundStyle(DrivyTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, DrivySpacing.xs)
                .drivyPageContent(maxWidth: 560)
            }
            .background(DrivyTheme.surface)
            .navigationTitle("Nouveau trajet").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() }.disabled(controller.isBusy) }
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(controller.isBusy)
        .tint(DrivyTheme.accent)
        .foregroundStyle(DrivyTheme.text)
    }
    private func startOption(title: String, detail: String, symbol: String, useGPS: Bool) -> some View {
        Button { start(useGPS: useGPS) } label: {
            HStack(spacing: DrivySpacing.m) {
                Image(systemName: symbol).font(.title2.weight(.semibold))
                    .foregroundStyle(DrivyTheme.accent)
                    .frame(width: 52, height: 52)
                    .background(DrivyTheme.accentSoft, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                    Text(title).font(.headline).foregroundStyle(DrivyTheme.text)
                    Text(detail).font(.subheadline).foregroundStyle(DrivyTheme.muted)
                }.fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.right.circle.fill").font(.title2).foregroundStyle(DrivyTheme.accent).accessibilityHidden(true)
            }
            .padding(DrivySpacing.m).frame(maxWidth: .infinity, minHeight: 96)
            .background(DrivyTheme.canvas, in: RoundedRectangle(cornerRadius: DrivyRadius.mapPanel, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DrivyRadius.mapPanel, style: .continuous)
                    .strokeBorder(DrivyTheme.border, lineWidth: 0.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: DrivyRadius.mapPanel, style: .continuous))
        }
        .buttonStyle(DrivyTileButtonStyle())
        .accessibilityLabel(useGPS ? "Démarrer avec le GPS" : "Démarrer sans GPS")
        .accessibilityHint(detail)
        .accessibilityIdentifier(useGPS ? "start-with-gps" : "start-without-gps")
    }
    private func start(useGPS: Bool) {
        Task {
            controller.dismissError()
            await controller.startSession(useGPS: useGPS)
            if controller.activeSession != nil { dismiss() }
        }
    }
}
