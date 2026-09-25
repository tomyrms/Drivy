import SwiftUI
import UIKit

struct SchoolCapturePreparationView: View {
    @Bindable var model: SchoolCapturePreparationWorkspace
    @Bindable var schoolWorkspace: SchoolWorkspace
    @Environment(\.dismiss) private var dismiss
    @State private var choiceRoute: ChoiceRoute?
    @State private var resendRoute: SchoolCaptureQueuedMutation?
    @State private var confirmsResend = false
    @State private var startReview: SchoolCaptureStartReview?

    private struct ChoiceRoute: Identifiable {
        let id = UUID()
        let lessonID: UUID
        let store: SQLCipherSchoolCaptureStore?
    }
    private var currentScope: SchoolCommandScope? {
        guard let person = schoolWorkspace.person, let member = schoolWorkspace.membership else { return nil }
        return model.agenda.scope(person: person, membership: member)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if currentScope == model.scope {
                VStack(alignment: .leading, spacing: DrivySpacing.l) {
                    heading
                    feedback
                    if model.contextIsCurrent {
                        choicePanel
                        if model.isInstructor { diagnosticPanel }
                        else {
                            Label("Le diagnostic GPS est réalisé sur l’appareil du moniteur.", systemImage: "iphone")
                                .font(.subheadline).foregroundStyle(DrivyTheme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if !model.pendingAssessments.isEmpty { pendingPanel }
                    if !model.pendingStarts.isEmpty { pendingStartsPanel }
                    if model.contextIsCurrent && model.isInstructor && model.collectionIsIntegrated { startPanel }
                    if model.hasOldScope {
                        DrivyInlineMessage(text: "Une demande conservée dépend de vos anciens accès. Elle ne sera pas renvoyée avec ces nouveaux droits.",
                            tone: .warning)
                    }
                    if !model.accessRevoked {
                        Button("Actualiser la préparation", systemImage: "arrow.clockwise") { Task { await model.load() } }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(DrivyTheme.accent)
                            .frame(minHeight: 44).disabled(model.isLoading || model.isBusy)
                    }
                }
                .drivyPageContent()
                } else {
                    ContentUnavailableView("Accès à actualiser", systemImage: "lock", description: Text("Vos droits ont changé. Rouvrez la préparation depuis votre leçon."))
                }
            }
            .background(DrivyTheme.surface)
            .navigationTitle("Préparation GPS").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { model.invalidate(); dismiss() }
                }
            }
            .task { await model.load() }
            .onDisappear { model.suspend() }
            .onChange(of: model.diagnosticIsAvailable) { _, available in if !available { model.closeDiagnostic() } }
            .onChange(of: currentScope) { _, scope in
                guard scope != model.scope else { return }
                model.invalidate(); choiceRoute = nil; resendRoute = nil; startReview = nil; dismiss()
            }
            .sheet(item: $choiceRoute, onDismiss: { Task { await model.load() } }) { route in
                SchoolRecordingChoiceEntryView(client: model.client, reader: model.reader, agenda: model.agenda,
                    schoolWorkspace: schoolWorkspace, lessonID: route.lessonID,
                    onRefusalConfirmed: { learnerID, lessonID in model.learnerRefused(learnerID, lessonID: lessonID) }, store: route.store)
            }
            .sheet(item: $resendRoute) { queued in resendSheet(queued) }
            .sheet(item: $startReview) { review in SchoolCaptureStartReviewView(model: model, review: review) }
            .onChange(of: model.captureStarted) { _, started in if started { dismiss() } }
        }.tint(DrivyTheme.accent)
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xs) {
            DrivyStatusBadge(title: "GPS facultatif", symbol: "location", tone: .accent)
            Text(model.learner?.displayName ?? "Votre leçon").font(.drivyScreenTitle)
                .fixedSize(horizontal: false, vertical: true)
            if let lesson = model.lesson { Text(lessonDate(lesson)).font(.subheadline).foregroundStyle(DrivyTheme.muted) }
            Text("La leçon peut se dérouler sans enregistrer de trajet.").font(.body).foregroundStyle(DrivyTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var feedback: some View {
        if model.isLoading || model.isBusy {
            ProgressView(model.isBusy ? "Vérification auprès de l’école…" : "Ouverture de la préparation…")
                .frame(maxWidth: .infinity)
        }
        if let message = model.errorMessage {
            SchoolErrorNotice(message: message,
                retry: model.accessRevoked || model.isLoading || model.isBusy ? nil : { Task { await model.load() } })
        }
        if let message = model.storageError { DrivyInlineMessage(text: message, tone: .warning) }
    }

    private var choicePanel: some View {
        DrivyPanel {
            VStack(alignment: .leading, spacing: DrivySpacing.m) {
                Label("Le choix de l’élève", systemImage: "person.crop.circle.badge.checkmark").font(.drivySection)
                DrivyMapStatusLabel(status: choiceStatus, font: .headline)
                    .accessibilityIdentifier("preparation-choice-state")
                if let notice = model.notice {
                    if let choice = model.choice, choice.noticeVersionId != notice.noticeVersionId {
                        DrivyInlineMessage(text: "L’information de l’école a changé. Relisez-la avant de confirmer un nouvel accord.",
                            tone: .warning)
                    }
                    DisclosureGroup("Information et conservation des données") {
                        VStack(alignment: .leading, spacing: DrivySpacing.m) {
                            Text(notice.noticeText)
                            Text("Conservation").font(.headline)
                            Text(notice.retentionText)
                            Label(notice.contactEmail, systemImage: "envelope").font(.subheadline)
                        }.textSelection(.enabled).fixedSize(horizontal: false, vertical: true).padding(.top, DrivySpacing.s)
                    }
                }
                if let error = model.noticeError { DrivyInlineMessage(text: error, tone: .warning) }
                Button {
                    model.closeDiagnostic()
                    choiceRoute = ChoiceRoute(lessonID: model.lessonID, store: model.store)
                } label: { Label("Lire la notice et choisir", systemImage: "doc.text") }
                    .buttonStyle(DrivySecondaryButtonStyle()).disabled(!model.mayOpenChoice)
                    .accessibilityIdentifier("preparation-open-choice")
            }
        }
    }

    private var diagnosticPanel: some View {
        DrivyPanel {
            VStack(alignment: .leading, spacing: DrivySpacing.m) {
                Label("L’appareil du moniteur", systemImage: "iphone").font(.drivySection)
                if !model.diagnosticIsAvailable {
                    DrivyInlineMessage(text: "Arrêtez et sauvegardez le trajet en cours avant de vérifier un autre départ.", tone: .warning)
                }
                if let snapshot = model.snapshot {
                    DrivyMapStatusLabel(status: DrivyMapStatus(title: permissionLabel(snapshot.permission),
                        symbol: snapshot.permission.permitsLocation ? "location.fill" : "location.slash",
                        tone: snapshot.permission.permitsLocation ? .success : (snapshot.permission == .notDetermined ? .neutral : .warning)),
                        font: .subheadline.weight(.semibold))
                    if let age = snapshot.sampleAgeSeconds, let accuracy = snapshot.horizontalAccuracyMeters {
                        Text("À la dernière vérification : mesure âgée de \(age) s · précision annoncée ±\(Int(ceil(accuracy))) m")
                            .font(.subheadline).foregroundStyle(DrivyTheme.muted)
                    } else { Text("Aucune mesure récente pour le diagnostic.").font(.subheadline).foregroundStyle(DrivyTheme.muted) }
                }
                diagnosticActions
                if model.isSampling { ProgressView("Recherche d’une mesure ponctuelle…") }
                Text("La mesure reste sur cet appareil. Seuls sa fraîcheur, sa précision et les paramètres du téléphone servent au diagnostic.")
                    .font(.footnote).foregroundStyle(DrivyTheme.muted)
                Divider()
                assessmentStatus
                Button { Task { await model.assess() } } label: {
                    Label("Envoyer le diagnostic", systemImage: "checkmark.shield")
                }.buttonStyle(DrivyPrimaryButtonStyle()).disabled(!model.maySendAssessment)
                    .accessibilityIdentifier("preparation-send-diagnostic")
                if !model.collectionIsIntegrated {
                    Text("Aucun trajet n’est enregistré depuis cet écran. Le démarrage du GPS scolaire n’est pas encore disponible.")
                        .font(.footnote).foregroundStyle(DrivyTheme.muted)
                }
            }
        }
    }

    private var diagnosticActions: some View {
        VStack(spacing: DrivySpacing.s) {
            if model.snapshot?.permission == .denied || model.snapshot?.permission == .restricted {
                Button("Ouvrir les réglages de localisation", systemImage: "gearshape") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }.buttonStyle(DrivySecondaryButtonStyle())
            } else if model.snapshot?.permission.permitsLocation != true {
                Button { Task { await model.requestPermission() } } label: { Label("Autoriser la localisation", systemImage: "location") }
                    .buttonStyle(DrivySecondaryButtonStyle()).disabled(!model.mayDiagnose)
            }
            Button { Task { await model.requestSample() } } label: { Label("Prendre une mesure ponctuelle", systemImage: "scope") }
                .buttonStyle(DrivySecondaryButtonStyle())
                .disabled(!model.mayDiagnose || model.isSampling || model.snapshot?.permission.permitsLocation != true)
                .accessibilityIdentifier("preparation-diagnostic-sample")
        }
    }

    @ViewBuilder private var assessmentStatus: some View {
        if let value = model.assessment {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                let expired = SchoolLesson.date(value.expiresAt).map { $0 <= timeline.date } ?? true
                VStack(alignment: .leading, spacing: DrivySpacing.s) {
                    Label(expired ? "Diagnostic à renouveler" : assessmentLabel(value.status),
                          systemImage: !expired && value.status == .qualified ? "checkmark.shield.fill" : "exclamationmark.shield")
                        .font(.headline).foregroundStyle(!expired && value.status == .qualified ? DrivyTheme.success : DrivyTheme.warning)
                    if !expired { Text("Vérifié à \(time(value.assessedAt)). Valable jusqu’à \(time(value.expiresAt)).").font(.caption).foregroundStyle(DrivyTheme.muted) }
                    ForEach(Array(value.blockers.enumerated()), id: \.offset) { _, blocker in
                        Text(blocker.message).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    }
                }.accessibilityIdentifier("preparation-diagnostic-result")
            }
        } else if let message = model.assessmentMessage { DrivyInlineMessage(text: message, tone: .warning) }
        else if model.pendingAssessments.isEmpty {
            DrivyMapStatusLabel(status: DrivyMapStatus(title: "Diagnostic de l’école non effectué", symbol: "shield"),
                font: .subheadline.weight(.semibold))
        }
    }

    private var pendingPanel: some View {
        DrivyPanel {
            VStack(alignment: .leading, spacing: DrivySpacing.m) {
                Label("Diagnostic en attente", systemImage: "clock.arrow.circlepath").font(.drivySection)
                ForEach(model.pendingAssessments) { queued in
                    VStack(alignment: .leading, spacing: DrivySpacing.s) {
                        DrivyMapStatusLabel(status: DrivyMapStatus(
                            title: queued.state == .queued ? "Demande sauvegardée, envoi à reprendre" : "Réponse à confirmer",
                            symbol: "arrow.up.circle", tone: .accent), font: .headline)
                        Text("La même demande sera conservée, même si la connexion est interrompue.")
                            .font(.subheadline).foregroundStyle(DrivyTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Vérifier auprès de l’école") { Task { await model.resume(queued, verifyFirst: true) } }
                            .buttonStyle(DrivySecondaryButtonStyle()).disabled(!model.mayResume(queued))
                        Button("Reprendre cet envoi") { confirmsResend = false; resendRoute = queued }
                            .font(.subheadline.weight(.semibold)).foregroundStyle(DrivyTheme.accent)
                            .frame(minHeight: 44).disabled(!model.mayResume(queued))
                        DisclosureGroup("Référence de la demande") { Text(queued.id.uuidString).font(.caption.monospaced()).textSelection(.enabled) }
                    }
                }
            }
        }
    }

    private var startPanel: some View {
        DrivyPanel {
            VStack(alignment: .leading, spacing: DrivySpacing.m) {
                Label("Le départ du trajet", systemImage: "location.fill").font(.drivySection)
                Text("Après confirmation, seules les positions de cette leçon seront enregistrées. Vous pourrez arrêter le GPS à tout moment.")
                    .font(.subheadline).foregroundStyle(DrivyTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if let message = model.startMessage { DrivyInlineMessage(text: message, tone: .neutral) }
                Button { Task { startReview = await model.reviewStart() } } label: { Label("Relire et démarrer", systemImage: "arrow.right.circle") }
                    .buttonStyle(DrivyPrimaryButtonStyle()).disabled(!model.mayReviewStart)
                    .accessibilityIdentifier("preparation-review-start")
                if model.choice?.status != .allowed {
                    Label("Le choix GPS de l’élève doit être confirmé avant le départ.", systemImage: "info.circle")
                        .font(.footnote).foregroundStyle(DrivyTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var pendingStartsPanel: some View {
        DrivyPanel {
            VStack(alignment: .leading, spacing: DrivySpacing.m) {
                Label("Départ à vérifier", systemImage: "clock.arrow.circlepath").font(.drivySection)
                ForEach(model.pendingStarts) { queued in
                    VStack(alignment: .leading, spacing: DrivySpacing.s) {
                        Text(queued.mutation.targetID == model.lessonID ? "Une demande de départ est conservée pour cette leçon." : "Une demande de départ concerne une autre leçon de cette école.")
                            .font(.subheadline)
                        if model.mayVerifyPendingStart(queued) {
                            Button("Vérifier auprès de l’école") { Task { await model.verifyStart(queued) } }
                                .buttonStyle(DrivySecondaryButtonStyle())
                        }
                        if model.mayReviewPendingStart(queued) {
                            Button("Relire ce départ") { Task { startReview = await model.reviewStart(resuming: queued) } }
                                .font(.subheadline.weight(.semibold)).foregroundStyle(DrivyTheme.accent)
                                .frame(minHeight: 44)
                        }
                        Text("Aucune collecte ne reprend automatiquement.").font(.footnote).foregroundStyle(DrivyTheme.muted)
                        DisclosureGroup("Référence") { Text(queued.id.uuidString).font(.caption.monospaced()).textSelection(.enabled) }
                    }
                }
            }
        }
    }

    private func resendSheet(_ queued: SchoolCaptureQueuedMutation) -> some View {
        NavigationStack {
            Form {
                Section {
                    Text("Cette reprise conserve le diagnostic déjà sauvegardé. Elle ne prend aucune nouvelle mesure.")
                    Toggle("Je confirme la reprise de cette demande", isOn: $confirmsResend)
                    Button("Renvoyer la même demande") {
                        Task { await model.resume(queued, verifyFirst: false); resendRoute = nil }
                    }.disabled(!confirmsResend || !model.mayResume(queued))
                }
            }.navigationTitle("Reprendre le diagnostic").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Retour") { resendRoute = nil } } }
        }
    }

    /// A refusal is a normal choice, stated calmly; only an unreadable state asks for attention.
    private var choiceStatus: DrivyMapStatus {
        guard let choice = model.choice else {
            return model.noticeError == nil
                ? DrivyMapStatus(title: "Choix non renseigné", symbol: "questionmark.circle")
                : DrivyMapStatus(title: "Choix à vérifier", symbol: "exclamationmark.triangle", tone: .warning)
        }
        switch choice.status {
        case .allowed: return DrivyMapStatus(title: "GPS accepté", symbol: "location.fill", tone: .success)
        case .refused: return DrivyMapStatus(title: "Sans GPS", symbol: "location.slash")
        case .unknown: return DrivyMapStatus(title: "Choix non renseigné", symbol: "questionmark.circle")
        }
    }
    private func permissionLabel(_ value: SchoolCaptureLocationPermission) -> String {
        switch value {
        case .notDetermined: "Permission à demander"
        case .denied: "Localisation refusée"
        case .restricted: "Localisation limitée par cet appareil"
        case .foreground: "Localisation autorisée dans l’application"
        case .background: "Localisation autorisée en arrière-plan"
        }
    }
    private func assessmentLabel(_ value: SchoolDeviceAssessment.Status) -> String {
        switch value { case .qualified: "Appareil qualifié par l’école"; case .needsCheck: "Vérifications nécessaires"; case .unsupported: "Appareil non pris en charge" }
    }
    private func lessonDate(_ lesson: SchoolLesson) -> String {
        guard let date = lesson.startsAt else { return "" }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "fr_CH")
        formatter.timeZone = TimeZone(identifier: lesson.timeZone); formatter.dateStyle = .long; formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    private func time(_ value: String) -> String {
        guard let date = SchoolLesson.date(value) else { return "—" }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "fr_CH")
        formatter.timeZone = TimeZone(identifier: model.lesson?.timeZone ?? "Europe/Zurich"); formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

private struct SchoolCaptureStartReviewView: View {
    @Bindable var model: SchoolCapturePreparationWorkspace
    let review: SchoolCaptureStartReview
    @State private var acknowledged = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DrivySpacing.l) {
                    VStack(alignment: .leading, spacing: DrivySpacing.xs) {
                        Text(review.learnerName).font(.drivyScreenTitle)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(lessonDate).font(.subheadline).foregroundStyle(DrivyTheme.muted)
                        Label(review.lesson.meetingPoint, systemImage: "mappin")
                            .font(.subheadline).foregroundStyle(DrivyTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    DrivyPanel {
                        VStack(alignment: .leading, spacing: DrivySpacing.s) {
                            Label("Accord GPS de l’élève confirmé", systemImage: "person.crop.circle.badge.checkmark")
                                .foregroundStyle(DrivyTheme.success)
                            Label("Diagnostic de l’appareil qualifié", systemImage: "checkmark.shield")
                                .foregroundStyle(DrivyTheme.success)
                            Label("Le trajet reste privé. Cette action ne publie ni carte ni bilan.", systemImage: "lock")
                                .font(.subheadline).foregroundStyle(DrivyTheme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                    DisclosureGroup("Relire l’information GPS de l’école") {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(review.notice.noticeText)
                            Text("Conservation des données").font(.headline)
                            Text(review.notice.retentionText)
                            Text(review.notice.contactEmail).font(.subheadline)
                        }.padding(.top, DrivySpacing.s).textSelection(.enabled)
                    }
                    if review.pendingMutation != nil {
                        Text("Cette confirmation reprend exactement la demande de départ conservée. La leçon, l’accord et le diagnostic seront vérifiés à nouveau.")
                            .font(.subheadline).foregroundStyle(DrivyTheme.muted)
                    }
                    Toggle("Je confirme le départ GPS maintenant pour cette leçon", isOn: $acknowledged)
                        .disabled(model.isBusy).accessibilityIdentifier("capture-confirm-start")
                    if let error = model.errorMessage { SchoolErrorNotice(message: error) }
                    if let message = model.startMessage { DrivyInlineMessage(text: message, tone: .neutral) }
                    if model.isBusy { ProgressView("Vérification et ouverture du trajet…").frame(maxWidth: .infinity) }
                    Button {
                        Task { if await model.confirmStart(review, acknowledged: acknowledged) { dismiss() } }
                    } label: { Label("Démarrer le GPS", systemImage: "location.fill") }
                        .buttonStyle(DrivyPrimaryButtonStyle()).disabled(!acknowledged || !model.mayConfirmStart)
                        .accessibilityIdentifier("capture-start")
                }.drivyPageContent()
            }.background(DrivyTheme.surface)
                .navigationTitle("Démarrer le GPS").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Retour") { dismiss() }.disabled(model.isBusy) } }
                .interactiveDismissDisabled(model.isBusy)
        }.tint(DrivyTheme.accent)
    }

    private var lessonDate: String {
        guard let start = review.lesson.startsAt, let end = review.lesson.endsAt else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_CH")
        formatter.timeZone = TimeZone(identifier: review.lesson.timeZone)
        formatter.dateStyle = .long; formatter.timeStyle = .short
        let beginning = formatter.string(from: start)
        formatter.dateStyle = .none
        return beginning + " – " + formatter.string(from: end)
    }
}
