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
            VStack(alignment: .leading, spacing: 24) {
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
                        VStack(alignment: .leading, spacing: 20) {
                            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                                .font(.largeTitle)
                                .foregroundStyle(DrivyTheme.accent)
                                .padding(18)
                                .background(DrivyTheme.accentSoft, in: RoundedRectangle(cornerRadius: 20))
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Prendre des repères")
                                    .font(.title2.weight(.semibold))
                                Text("Démarrez une séance locale, avec ou sans trajet GPS.")
                                    .foregroundStyle(DrivyTheme.muted)
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

                VStack(alignment: .leading, spacing: 12) {
                    Text("Un espace d’essai personnel")
                        .font(.headline)
                    Text("Utilisez vos propres données d’essai, à l’arrêt ou comme passager. Les séances et les bilans restent sur cet appareil.")
                        .font(.subheadline)
                        .foregroundStyle(DrivyTheme.muted)
                    Text("Jusqu’à 2 h par séance d’essai.")
                        .font(.footnote)
                        .foregroundStyle(DrivyTheme.muted)
                    StorageCaption(message: controller.storageStatus)
                }
                .padding(.horizontal, 4)
            }
            .padding(20)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .background(DrivyTheme.canvas)
    }

    private func activeSessionCard(_ session: DrivingSession) -> some View {
        DrivyPanel {
            VStack(alignment: .leading, spacing: 20) {
                Label(controller.isCapturing ? "Séance en cours" : "Capture arrêtée", systemImage: controller.isCapturing ? "record.circle" : "stop.circle")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DrivyTheme.accent)
                if controller.isCapturing {
                    TimelineView(.periodic(from: .now, by: 1)) { timeline in
                        Text(timeline.date.sessionElapsed(since: session.startedAt))
                            .font(.largeTitle.weight(.semibold).monospacedDigit())
                            .accessibilityLabel("Durée de la séance")
                            .accessibilityValue(timeline.date.sessionElapsed(since: session.startedAt))
                    }
                }
                Text(session.usesGPS ? controller.gpsStatus.label : "Sans GPS")
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
}

private struct StartSessionView: View {
    @Bindable var controller: SessionController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Image(systemName: "location")
                        .font(.largeTitle)
                        .foregroundStyle(DrivyTheme.accent)
                        .accessibilityHidden(true)
                    Text("Le trajet est facultatif.")
                        .font(.title.weight(.bold))
                    Text("Avec le GPS, Drivy conserve votre position pendant cet essai. Sans GPS, vous pouvez noter vos observations et rédiger votre bilan.")
                        .foregroundStyle(DrivyTheme.muted)
                    VStack(spacing: 12) {
                        Button { start(useGPS: true) } label: {
                            Label("Démarrer avec le GPS", systemImage: "location.fill")
                        }
                        .buttonStyle(DrivyPrimaryButtonStyle())
                        .accessibilityIdentifier("start-with-gps")
                        Button { start(useGPS: false) } label: {
                            Label("Continuer sans GPS", systemImage: "note.text")
                        }
                        .buttonStyle(DrivySecondaryButtonStyle())
                        .accessibilityIdentifier("start-without-gps")
                    }
                    .disabled(controller.isBusy)
                    if controller.isBusy {
                        ProgressView("Préparation de la séance…")
                    }
                    if let error = controller.errorMessage {
                        InlineErrorView(message: error)
                    }
                    Text("Le choix du GPS n’active aucun partage. Vous pouvez arrêter la séance à tout moment.")
                        .font(.footnote)
                        .foregroundStyle(DrivyTheme.muted)
                    Text("Jusqu’à 2 h · données sur cet appareil")
                        .font(.footnote)
                        .foregroundStyle(DrivyTheme.muted)
                }
                .padding(24)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .background(DrivyTheme.canvas)
            .navigationTitle("Nouvelle séance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                        .disabled(controller.isBusy)
                }
            }
        }
        .interactiveDismissDisabled(controller.isBusy)
        .tint(DrivyTheme.accent)
    }

    private func start(useGPS: Bool) {
        Task {
            controller.dismissError()
            await controller.startSession(useGPS: useGPS)
            if controller.activeSession != nil { dismiss() }
        }
    }
}
