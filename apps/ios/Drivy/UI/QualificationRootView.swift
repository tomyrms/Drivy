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
                LiveSessionView(controller: controller)
            }
            .tint(DrivyTheme.accent)
        }
    }

    private var home: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DrivySpacing.l) {
                Text("Votre trajet, vos observations, votre bilan.")
                    .font(.title3)
                    .foregroundStyle(DrivyTheme.muted)

                if controller.isLoading {
                    ProgressView("Ouverture des séances…")
                        .frame(maxWidth: .infinity, minHeight: 180)
                } else if let active = controller.activeSession {
                    activeSessionCard(active)
                } else {
                    DrivyPanel {
                        VStack(alignment: .leading, spacing: DrivySpacing.l) {
                            DrivyRouteGlyph()
                                .frame(height: 72)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: DrivySpacing.xs) {
                                Text("Prendre des repères")
                                    .font(.drivyTitle)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text("Démarrez une séance locale, avec ou sans trajet GPS.")
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
                if controller.isCapturing {
                    TimelineView(.periodic(from: .now, by: 1)) { timeline in
                        Text(timeline.date.sessionElapsed(since: session.startedAt))
                            .font(.drivyScreenTitle.monospacedDigit())
                            .foregroundStyle(DrivyTheme.text)
                            .accessibilityLabel("Durée de la séance")
                            .accessibilityValue(timeline.date.sessionElapsed(since: session.startedAt))
                    }
                }
                Text(DrivySeanceText.observations(session.observations.count))
                    .font(.subheadline)
                    .foregroundStyle(DrivyTheme.muted)
                Button {
                    if controller.isCapturing { presentsLive = true }
                    else { Task { await controller.load() } }
                } label: {
                    Label(controller.isCapturing ? "Revenir à la séance" : "Vérifier la sauvegarde", systemImage: "arrow.up.right")
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
                VStack(alignment: .leading, spacing: DrivySpacing.xl) {
                    VStack(alignment: .leading, spacing: DrivySpacing.s) {
                        Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                            .font(.largeTitle.weight(.medium)).foregroundStyle(DrivyTheme.accent)
                            .frame(width: 68, height: 68)
                            .background(DrivyTheme.accentSoft, in: RoundedRectangle(cornerRadius: DrivyRadius.mapPanel, style: .continuous))
                            .accessibilityHidden(true)
                        Text("Un trajet à retenir").font(.drivyScreenTitle)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Choisissez comment garder les moments de votre séance.")
                            .font(.body).foregroundStyle(DrivyTheme.muted)
                    }
                    VStack(spacing: DrivySpacing.s) {
                        startOption(title: "Avec le GPS", detail: "Parcours, observations et bilan", symbol: "location.fill", useGPS: true)
                        startOption(title: "Sans GPS", detail: "Observations et bilan", symbol: "text.bubble", useGPS: false)
                    }
                    .disabled(controller.isBusy)
                    if controller.isBusy { ProgressView("Préparation du trajet…").frame(maxWidth: .infinity) }
                    if let error = controller.errorMessage { InlineErrorView(message: error) }
                    VStack(alignment: .leading, spacing: DrivySpacing.xs) {
                        Label("Privé sur cet appareil", systemImage: "lock").font(.subheadline.weight(.semibold))
                        Text("Aucun partage automatique. Jusqu’à 2 h par trajet.")
                            .font(.footnote).foregroundStyle(DrivyTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, DrivySpacing.xs)
                .drivyPageContent(maxWidth: 560)
            }
            .background(DrivyTheme.surface)
            .navigationTitle("Préparer le trajet").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() }.disabled(controller.isBusy) }
            }
        }
        .interactiveDismissDisabled(controller.isBusy)
        .tint(DrivyTheme.accent)
        .foregroundStyle(DrivyTheme.text)
    }
    private func startOption(title: String, detail: String, symbol: String, useGPS: Bool) -> some View {
        Button { start(useGPS: useGPS) } label: {
            HStack(spacing: DrivySpacing.m) {
                Image(systemName: symbol).font(.title2).frame(width: 32).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                    Text(title).font(.headline)
                    Text(detail).font(.subheadline).opacity(0.85)
                }.fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.right").font(.body.weight(.semibold)).accessibilityHidden(true)
            }
            .padding(DrivySpacing.l).frame(maxWidth: .infinity, minHeight: 96)
            .foregroundStyle(useGPS ? DrivyTheme.onAccent : DrivyTheme.text)
            .background(useGPS ? DrivyTheme.accent : DrivyTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: DrivyRadius.mapPanel, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: DrivyRadius.mapPanel, style: .continuous))
        }
        .buttonStyle(DrivyTileButtonStyle())
        .accessibilityLabel(useGPS ? "Démarrer avec le GPS" : "Continuer sans GPS")
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
