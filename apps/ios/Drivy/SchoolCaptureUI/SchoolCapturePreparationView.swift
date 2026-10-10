import SwiftUI
import UIKit

struct SchoolCapturePreparationView: View {
    @Bindable var model: SchoolCapturePreparationWorkspace
    @Bindable var schoolWorkspace: SchoolWorkspace
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var choiceRoute: ChoiceRoute?
    @State private var resendRoute: SchoolCaptureQueuedMutation?
    @State private var confirmsResend = false
    @State private var startReview: SchoolCaptureStartReview?
    /// Demande dont l’abandon attend sa confirmation, comme sur les autres écrans de l’école.
    @State private var abandonCandidate: SchoolCaptureQueuedMutation?
    @State private var confirmsAbandon = false
    @Environment(SchoolCaptureSessionController.self) private var capture: SchoolCaptureSessionController?

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
                    quickStart
                    if model.quickBlock != nil && model.quickStep == nil && !model.captureStarted && model.pendingStarts.isEmpty {
                        Button("Continuer sans GPS", systemImage: "location.slash") {
                            model.invalidate()
                            dismiss()
                        }
                        .buttonStyle(DrivySecondaryButtonStyle())
                        .disabled(model.isBusy || model.isLoading)
                        .accessibilityIdentifier("capture-continue-without-gps")
                    }
                    if !model.pendingAssessments.isEmpty { pendingPanel }
                    if !model.pendingStarts.isEmpty { pendingStartsPanel }
                    if model.hasOldScope {
                        DrivyInlineMessage(text: "Une demande conservée dépend de tes anciens accès. Elle ne sera pas renvoyée avec ces nouveaux droits.",
                            tone: .warning)
                    }
                    if model.contextIsCurrent && model.isInstructor && model.quickStep == nil && model.quickBlock != nil {
                        DisclosureGroup {
                            VStack(alignment: .leading, spacing: DrivySpacing.l) {
                                feedback
                                choicePanel
                                diagnosticPanel
                                if model.collectionIsIntegrated { startPanel }
                            }
                            .padding(.top, DrivySpacing.s)
                        } label: {
                            // L’attente se lit sur la ligne du titre : aucune ligne n’est insérée dans les panneaux.
                            HStack(spacing: DrivySpacing.xs) {
                                Text("Détails")
                                if isWaiting {
                                    ProgressView()
                                        .accessibilityLabel(model.isBusy ? "Vérification auprès de l’école…" : "Ouverture de la préparation…")
                                }
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                }
                .drivyPageContent(maxWidth: DrivyLayout.compactColumn)
                } else {
                    ContentUnavailableView("Accès à actualiser", systemImage: "lock", description: Text("Tes droits ont changé. Rouvre la préparation depuis ta leçon."))
                        .fixedSize(horizontal: false, vertical: true)
                        .drivyPageContent(maxWidth: DrivyLayout.compactColumn)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            .background(DrivyTheme.surface)
            .navigationTitle("Démarrer le trajet").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { model.invalidate(); dismiss() }
                        .disabled(model.isBusy)
                }
            }
            // Clé sur la validité de la portée : si les droits ne sont pas encore lisibles à l’ouverture
            // (feuille présentée juste après une autre), le départ se lance dès qu’ils le deviennent,
            // au lieu de laisser un écran vide.
            .task(id: currentScope == model.scope) { await start() }
            .onDisappear {
                model.suspend()
                if !model.captureStarted { Task { await DrivyLaunchCurtain.shared.hide() } }
            }
            .onChange(of: model.diagnosticIsAvailable) { _, available in if !available { model.closeDiagnostic() } }
            .onChange(of: currentScope) { _, scope in
                // Une lecture du compte en cours vide un instant la portée : ce n’est pas un changement
                // de droits. Seule une autre portée lisible ferme la préparation.
                guard let scope, scope != model.scope else { return }
                model.invalidate(); choiceRoute = nil; resendRoute = nil; startReview = nil; dismiss()
            }
            .sheet(item: $choiceRoute, onDismiss: {
                Task {
                    await model.load()
                    if model.choice?.status == .allowed { await start(reload: false) }
                    else if model.choice?.status == .refused { dismiss() }
                }
            }) { route in
                SchoolRecordingChoiceEntryView(client: model.client, reader: model.reader, agenda: model.agenda,
                    schoolWorkspace: schoolWorkspace, lessonID: route.lessonID,
                    onRefusalConfirmed: { learnerID, lessonID in model.learnerRefused(learnerID, lessonID: lessonID) }, store: route.store)
            }
            .sheet(item: $resendRoute) { queued in resendSheet(queued) }
            .sheet(item: $startReview) { review in SchoolCaptureStartReviewView(model: model, review: review) }
            // Un seul dialogue pour toutes les demandes : l’abandon se confirme, comme sur les autres écrans.
            .confirmationDialog("Abandonner cette demande ?", isPresented: $confirmsAbandon, titleVisibility: .visible) {
                Button("Abandonner la demande", role: .destructive) {
                    if let queued = abandonCandidate { Task { await model.abandon(queued) } }
                    abandonCandidate = nil
                }
                Button("Conserver", role: .cancel) { abandonCandidate = nil }
            } message: { Text("Elle est retirée de cet appareil et ne sera pas envoyée à l’école.") }
            .onChange(of: model.captureStarted) { _, started in
                guard started else { return }
                // Départ confirmé par l’école : la préparation se referme sous le rideau, qui attend la fin de
                // sa séquence et la première position avant de découvrir la carte.
                dismiss()
                let controller = capture
                Task { await DrivyLaunchCurtain.shared.hide(afterSequence: true, waitingFor: { (controller?.displayedPointCount ?? 1) > 0 }) }
            }
            .onChange(of: model.quickStep) { _, step in
                DrivyLaunchCurtain.shared.step = step
                if step != nil { DrivyLaunchCurtain.shared.advanceStep() }
            }
        }
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationSizing(.form)
        .tint(DrivyTheme.accent)
        .interactiveDismissDisabled(model.isBusy)
    }

    /// Même rappel compact que la fiche de leçon : la feuille s’ouvre depuis une leçon dont l’élève est déjà connu,
    /// son nom n’a pas à redevenir un titre d’écran.
    @ViewBuilder private var heading: some View {
        let date = model.lesson.map { lessonDate($0) }
        if let name = model.learner?.displayName {
            DrivyLearnerIdentity(name: name, detail: date, variant: .compact)
        } else {
            VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                Text("Ta leçon").font(.headline).fixedSize(horizontal: false, vertical: true)
                if let date { Text(date).font(.subheadline).foregroundStyle(DrivyTheme.muted) }
            }
        }
    }

    private func start(reload: Bool = true) async {
        guard currentScope == model.scope else { return }
        // La lecture initiale a toujours lieu, même s’il reste une demande à vérifier : ce sont
        // ces panneaux qui les montrent. Le départ lui-même refuse d’avancer dans ce cas.
        let curtain = DrivyLaunchCurtain.shared
        if !model.pendingAssessments.isEmpty || !model.pendingStarts.isEmpty {
            if reload { await model.load() }
            await curtain.hide()
            return
        }
        // Les vérifications partent aussitôt ; le rideau de marque se joue en parallèle, une fois par départ.
        curtain.show()
        let started = await model.begin(reload: reload)
        // Un accord à demander, une autorisation ou une erreur : le rideau s’efface tout de suite.
        if !started { await curtain.hide() }
    }

    /// Une lecture de la leçon ou une vérification auprès de l’école est en cours.
    private var isWaiting: Bool { model.isLoading || model.isBusy }

    /// Un seul état visible : le départ en cours, ou ce qui l’empêche et comment le lever.
    @ViewBuilder private var quickStart: some View {
        if model.quickStep != nil {
            // Le départ en cours se lit sur le rideau de marque (DrivyLaunchCurtain), au-dessus de cet écran.
            EmptyView()
        } else if case .failed(let message) = model.quickBlock {
            // Même présentation d’erreur que partout : notice danger et « Réessayer », sans panneau autour.
            SchoolErrorNotice(message: message, retry: model.isLoading || model.isBusy ? nil : { Task { await start() } })
                .accessibilityIdentifier("capture-quick-start-block")
        } else if let block = model.quickBlock {
            DrivyPanel {
                VStack(alignment: .leading, spacing: DrivySpacing.m) {
                    switch block {
                    case .choice:
                        panelTitle("Accord de l’élève pour le GPS", symbol: "person.crop.circle.badge.questionmark")
                        Button {
                            model.closeDiagnostic()
                            choiceRoute = ChoiceRoute(lessonID: model.lessonID, store: model.store)
                        } label: { Label("Demander l’accord", systemImage: "hand.raised") }
                            .buttonStyle(DrivyPrimaryButtonStyle(size: .field)).disabled(!model.mayOpenChoice)
                            .accessibilityIdentifier("preparation-open-choice")
                    case .refused:
                        // Un refus est un choix normal : ton neutre, pas de phrase de rappel sous le titre.
                        panelTitle("L’élève a refusé l’enregistrement du trajet", symbol: "location.slash")
                        Button("Modifier l’accord") {
                            model.closeDiagnostic()
                            choiceRoute = ChoiceRoute(lessonID: model.lessonID, store: model.store)
                        }
                        .buttonStyle(DrivySecondaryButtonStyle()).disabled(!model.mayOpenChoice)
                    case .permission(let denied):
                        panelTitle("Autorise la localisation", symbol: "location.slash")
                        if denied {
                            Button("Ouvrir les réglages", systemImage: "gearshape") {
                                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                            }.buttonStyle(DrivyPrimaryButtonStyle(size: .field))
                        }
                        retryButton
                    case .failed:
                        EmptyView()
                    }
                }
            }
            .accessibilityIdentifier("capture-quick-start-block")
        } else if model.captureStarted == false && !model.accessRevoked && model.pendingAssessments.isEmpty && model.pendingStarts.isEmpty {
            // L’attente se lit dans le bouton, qui ne se grise pas : un appui pendant la lecture reste sans effet.
            Button {
                guard !isWaiting else { return }
                Task { await start() }
            } label: {
                if isWaiting {
                    DrivyBusyLabel(title: "Démarrer le trajet", busyTitle: "Vérification de la leçon…", isBusy: true)
                } else {
                    Label("Démarrer le trajet", systemImage: "location.fill")
                }
            }
            .buttonStyle(DrivyPrimaryButtonStyle(size: .field))
            .accessibilityIdentifier("capture-quick-start")
        }
    }

    /// Titre d’un panneau d’état : le pictogramme reste en teinte discrète, l’accent est pour l’action.
    private func panelTitle(_ title: String, symbol: String) -> some View {
        Label {
            Text(title).font(.headline).foregroundStyle(DrivyTheme.text)
        } icon: {
            Image(systemName: symbol).foregroundStyle(DrivyTheme.muted)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var retryButton: some View {
        Button { Task { await start() } } label: { Label("Réessayer", systemImage: "arrow.clockwise") }
            .buttonStyle(DrivySecondaryButtonStyle()).disabled(model.isLoading || model.isBusy)
    }

    @ViewBuilder private var feedback: some View {
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
                        DrivyInlineMessage(text: "L’information de l’école a changé. Relis-la avant de confirmer un nouvel accord.",
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
                    DrivyInlineMessage(text: "Arrête et sauvegarde le trajet en cours avant de vérifier un autre départ.", tone: .warning)
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
                if model.isSampling { DrivyLoadingState(title: "Recherche d’une mesure ponctuelle…") }
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
                        abandonButton(queued)
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
                        abandonButton(queued)
                        Text("Aucune collecte ne reprend automatiquement.").font(.footnote).foregroundStyle(DrivyTheme.muted)
                        DisclosureGroup("Référence") { Text(queued.id.uuidString).font(.caption.monospaced()).textSelection(.enabled) }
                    }
                }
            }
        }
    }

    /// Offert seulement après la réponse de l’école : elle n’a jamais reçu cette demande.
    @ViewBuilder private func abandonButton(_ queued: SchoolCaptureQueuedMutation) -> some View {
        if model.unknownRequestIDs.contains(queued.id) {
            DrivyInlineMessage(text: "L’école n’a pas reçu cette demande : rien n’a été enregistré.", tone: .warning)
            Button("Abandonner la demande", role: .destructive) { abandonCandidate = queued; confirmsAbandon = true }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(model.mayAbandon(queued) ? DrivyTheme.danger : DrivyTheme.disabledText)
                .frame(minHeight: 44).disabled(!model.mayAbandon(queued))
                .accessibilityIdentifier("capture-request-abandon")
        }
    }

    private func resendSheet(_ queued: SchoolCaptureQueuedMutation) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DrivySpacing.l) {
                    Text("Cette reprise conserve le diagnostic déjà sauvegardé. Elle ne prend aucune nouvelle mesure.")
                        .fixedSize(horizontal: false, vertical: true)
                    Toggle("Je confirme la reprise de cette demande", isOn: $confirmsResend)
                        .disabled(model.isBusy)
                    Button("Renvoyer la même demande") {
                        Task { await model.resume(queued, verifyFirst: false); resendRoute = nil }
                    }
                    .buttonStyle(DrivyPrimaryButtonStyle())
                    .disabled(!confirmsResend || !model.mayResume(queued))
                }
                .drivyPageContent(maxWidth: DrivyLayout.compactColumn)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            .background(DrivyTheme.surface)
            .navigationTitle("Reprendre le diagnostic").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Retour") { resendRoute = nil }.disabled(model.isBusy) } }
        }
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationSizing(.form)
        .interactiveDismissDisabled(model.isBusy)
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                    DisclosureGroup("Relire l’information GPS de l’école") {
                        VStack(alignment: .leading, spacing: DrivySpacing.m) {
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
                    if model.isBusy { DrivyLoadingState(title: "Vérification et ouverture du trajet…") }
                    Button {
                        Task { if await model.confirmStart(review, acknowledged: acknowledged) { dismiss() } }
                    } label: { Label("Démarrer le GPS", systemImage: "location.fill") }
                        .buttonStyle(DrivyPrimaryButtonStyle()).disabled(!acknowledged || !model.mayConfirmStart)
                        .accessibilityIdentifier("capture-start")
                }.drivyPageContent(maxWidth: DrivyLayout.compactColumn)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            .background(DrivyTheme.surface)
            .navigationTitle("Démarrer le GPS").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Retour") { dismiss() }.disabled(model.isBusy) } }
        }
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationSizing(.form)
        .interactiveDismissDisabled(model.isBusy)
        .tint(DrivyTheme.accent)
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
