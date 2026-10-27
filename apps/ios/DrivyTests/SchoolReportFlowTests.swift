import Foundation
import Testing
@testable import Drivy

/// Rédaction du bilan en étapes : pas d’étape vide, un ordre tenu à un seul endroit, une saisie gardée sur
/// l’appareil sans jamais l’envoyer avant le geste final. Toutes les données sont synthétiques.
@MainActor struct SchoolReportFlowTests {
    private static let draftID = UUID(uuidString: "70000000-0000-4000-8000-000000000050")!

    // MARK: Étapes

    @Test(arguments: [
        SchoolReportStepCase(hasTrip: true, observations: 2, competencies: 9, expected: [.report, .competencies, .review]),
        SchoolReportStepCase(hasTrip: false, observations: 0, competencies: 9, expected: [.report, .competencies, .review]),
        SchoolReportStepCase(hasTrip: false, observations: 3, competencies: 9, expected: [.report, .competencies, .review]),
        SchoolReportStepCase(hasTrip: true, observations: 0, competencies: 0, expected: [.report, .review]),
        SchoolReportStepCase(hasTrip: false, observations: 0, competencies: 0, expected: [.report, .review])
    ])
    func noStepIsEverEmpty(_ value: SchoolReportStepCase) {
        #expect(SchoolReportFlowRules.steps(hasTrip: value.hasTrip, observationCount: value.observations,
            competencyCount: value.competencies) == value.expected)
    }

    @Test func theOrderIsDecidedInOnePlaceAndTheReviewComesLast() {
        #expect(SchoolReportFlowRules.order == [.report, .competencies, .review])
        #expect(Set(SchoolReportFlowRules.order) == Set(SchoolReportStep.allCases))
        let all = SchoolReportFlowRules.steps(hasTrip: true, observationCount: 1, competencyCount: 1)
        #expect(all == SchoolReportFlowRules.order)
        #expect(all.first == .report && all.last == .review)
    }

    @Test func positionIsSilentForASingleStep() {
        #expect(SchoolReportFlowRules.position(of: 1, count: 3) == "2 sur 3")
        #expect(SchoolReportFlowRules.position(of: 0, count: 1) == nil)
        #expect(SchoolReportFlowRules.position(of: 3, count: 3) == nil)
    }

    @Test func theReviewIsAlwaysNamedTheSameWithOrWithoutATrip() {
        #expect(SchoolReportFlowRules.title(of: .review, hasTrip: true) == "Récapitulatif")
        #expect(SchoolReportFlowRules.title(of: .review, hasTrip: false) == "Récapitulatif")
        #expect(SchoolReportFlowRules.title(of: .report, hasTrip: false) == "Bilan")
    }

    @Test func theEntryLabelSaysWhatTheGestureDoes() {
        #expect(SchoolReportFlowRules.editTitle(isEmpty: true, unsaved: false) == "Rédiger le bilan")
        #expect(SchoolReportFlowRules.editTitle(isEmpty: false, unsaved: false) == "Modifier le bilan")
        #expect(SchoolReportFlowRules.editTitle(isEmpty: false, unsaved: true) == "Reprendre le bilan")
    }

    // MARK: Lecture ou rédaction

    @Test func openingALessonNeverOpensTheEditorWhateverTheWidth() {
        for wide in [false, true] {
            #expect(SchoolReportFlowRules.presentation(entry: nil, canEdit: true, isWide: wide) == .reading)
            #expect(SchoolReportFlowRules.presentation(entry: nil, canEdit: false, isWide: wide) == .reading)
        }
    }

    @Test func everyOriginOfTheEditorIsNamedAndTheWidthOnlyChoosesItsShape() {
        #expect(Set(SchoolReportEntry.allCases) == [.lessonCompleted, .write, .edit, .resume])
        for entry in SchoolReportEntry.allCases {
            #expect(SchoolReportFlowRules.presentation(entry: entry, canEdit: true, isWide: false) == .steps)
            #expect(SchoolReportFlowRules.presentation(entry: entry, canEdit: true, isWide: true) == .sideBySide)
            // Qui ne rédige pas ce bilan ne reçoit jamais l’éditeur, même avec une origine.
            #expect(SchoolReportFlowRules.presentation(entry: entry, canEdit: false, isWide: true) == .reading)
        }
    }

    @Test func theWideCompositionStartsAt900PointsAndNeverInVeryLargeText() {
        #expect(!SchoolReportFlowRules.isWide(width: 899, accessibilitySize: false))
        #expect(SchoolReportFlowRules.isWide(width: 900, accessibilitySize: false))
        #expect(!SchoolReportFlowRules.isWide(width: 1_200, accessibilitySize: true))
    }

    @Test func theEntryFollowsTheStateOfTheReport() {
        #expect(SchoolReportFlowRules.entry(isEmpty: true, unsaved: false) == .write)
        #expect(SchoolReportFlowRules.entry(isEmpty: false, unsaved: false) == .edit)
        #expect(SchoolReportFlowRules.entry(isEmpty: false, unsaved: true) == .resume)
        #expect(SchoolReportFlowRules.entry(isEmpty: true, unsaved: true) == .resume)
    }

    @Test func aSavedReportIsEditedFromTheMenuSoThatReadingStaysReading() {
        #expect(SchoolReportFlowRules.placement(of: .edit) == .menu)
        #expect(SchoolReportFlowRules.placement(of: .resume) == .bottomBar(primary: true))
        #expect(SchoolReportFlowRules.placement(of: .write) == .bottomBar(primary: false))
    }

    // MARK: Récapitulatif

    @Test func theReviewUsesEditedValuesAndTheRealSharingStateWithoutInventingATrip() {
        let competency = Self.competency(1)
        let review = SchoolReportFlowRules.review(workedOn: "Créneaux", observationText: "Regarder loin",
            nextStep: "Giratoires", observations: [SchoolReportObservation(competencyId: competency.id,
                level: "GUIDED", context: "Centre-ville")], competencies: [competency], shared: false,
            hasTrip: false, lessonObservationCount: 0)

        #expect(review.texts.map(\.value) == ["Créneaux", "Regarder loin", "Giratoires"])
        #expect(review.competencies == [.init(label: "Compétence 1", level: "Avec accompagnement", context: "Centre-ville")])
        #expect(review.visibility == .forMe)
        #expect(!review.hasTrip && review.lessonObservationCount == 0)
    }

    @Test func anEmptyReviewStillExistsAndOnlyNamesWhatIsReal() {
        let review = SchoolReportFlowRules.review(workedOn: "", observationText: "", nextStep: "", observations: [],
            competencies: [], shared: true, hasTrip: false, lessonObservationCount: 2)
        #expect(review.texts.isEmpty && review.competencies.isEmpty)
        #expect(review.visibility == .shared)
        #expect(!review.hasTrip && review.lessonObservationCount == 2)
    }

    @Test func missingSharingDataStaysUnknownInsteadOfInventingASavedStatus() {
        let review = SchoolReportFlowRules.review(workedOn: "", observationText: "", nextStep: "", observations: [],
            competencies: [], shared: nil, hasTrip: false, lessonObservationCount: 0)
        #expect(review.visibility == .unknown)
    }

    @Test func anEditedCompetencyIsNotDroppedWhenItsCatalogLabelIsUnavailable() {
        let observation = SchoolReportObservation(competencyId: UUID(), level: "INDEPENDENT", context: "Route cantonale")
        let review = SchoolReportFlowRules.review(workedOn: "", observationText: "", nextStep: "",
            observations: [observation], competencies: [], shared: true, hasTrip: false, lessonObservationCount: 0)
        #expect(review.competencies == [.init(label: "Compétence à vérifier", level: "En autonomie", context: "Route cantonale")])
        #expect(review.showsCompetencies)
    }

    @Test func pendingVisibilityLabelsDescribeTheEffectOfTheFinalSave() {
        #expect(SchoolReportReviewVisibility.shared.pendingLabel == "Après enregistrement, visible par l’élève")
        #expect(SchoolReportReviewVisibility.forMe.pendingLabel == "Après enregistrement, pour moi")
        #expect(SchoolReportReviewVisibility.unknown.pendingLabel == "Visibilité à vérifier")
    }

    @Test func evidenceStaysEditableWithoutBeingDuplicatedInTheWideReviewColumn() {
        #expect(SchoolReportFlowRules.showsEvidenceInReview(isWide: false))
        #expect(!SchoolReportFlowRules.showsEvidenceInReview(isWide: true))
    }

    @Test func aLongListFoldsAndASingleExtraItemStaysVisible() {
        let short = SchoolReportFlowRules.fold(Array(1...5), limit: 5)
        #expect(short.shown == Array(1...5) && short.hidden.isEmpty)
        let oneMore = SchoolReportFlowRules.fold(Array(1...6), limit: 5)
        #expect(oneMore.shown.count == 6 && oneMore.hidden.isEmpty)
        let long = SchoolReportFlowRules.fold(Array(1...9), limit: 5)
        #expect(long.shown == Array(1...5) && long.hidden == Array(6...9))
        #expect(SchoolReportFlowRules.foldTitle(hidden: long.hidden.count, noun: "compétences") == "Afficher les 4 autres compétences")
        #expect(SchoolReportFlowRules.fold([Int](), limit: 4).shown.isEmpty)
    }

    // MARK: Compétences

    @Test func signalsMadeOnTheRoadAreRecalledOncePerAppraisal() {
        let id = UUID()
        let observations = [Self.observation(competency: id, status: "ATTENTION"), Self.observation(competency: id, status: "POSITIVE"),
                            Self.observation(competency: id, status: "ATTENTION"), Self.observation(competency: UUID(), status: "TO_REWORK")]
        #expect(SchoolReportFlowRules.signalled(for: id, in: observations) == "En route\u{00A0}: Attention, Point positif")
        #expect(SchoolReportFlowRules.signalled(for: UUID(), in: observations) == nil)
    }

    // MARK: Brouillon local chiffré

    @Test func theLocalDraftRoundTripsEncryptedAndOnlyForItsAccount() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("drivy-report-drafts-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EncryptedSchoolReportDraftStore(directory: directory, keyData: Data(repeating: 7, count: 32))
        let scope = ConfigurationFixture.scope()
        let draft = Self.localDraft(edited: "Créneau en marche arrière")
        #expect(try store.read(scope: scope, draftID: draft.draftID) == nil)
        try store.save(draft, scope: scope)
        #expect(try store.read(scope: scope, draftID: draft.draftID) == draft)

        let file = directory.appendingPathComponent("\(draft.draftID.uuidString.lowercased()).bin")
        let bytes = try Data(contentsOf: file)
        #expect(bytes.range(of: Data("Créneau".utf8)) == nil)

        let other = SchoolCommandScope(personID: UUID(), schoolID: scope.schoolID, membershipID: scope.membershipID,
            accessEpoch: scope.accessEpoch, apiBaseURL: scope.apiBaseURL)
        #expect(throws: SchoolConfigurationFailure.storage) { _ = try store.read(scope: other, draftID: draft.draftID) }
        #expect(throws: SchoolConfigurationFailure.storage) { try store.save(draft, scope: other) }
        #expect(throws: SchoolConfigurationFailure.storage) { try store.remove(scope: other, draftID: draft.draftID) }
        let otherKey = EncryptedSchoolReportDraftStore(directory: directory, keyData: Data(repeating: 9, count: 32))
        #expect(throws: SchoolConfigurationFailure.storage) { _ = try otherKey.read(scope: scope, draftID: draft.draftID) }
        #expect(throws: SchoolConfigurationFailure.storage) { try otherKey.save(draft, scope: scope) }
        #expect(throws: SchoolConfigurationFailure.storage) { try otherKey.remove(scope: scope, draftID: draft.draftID) }
        #expect(try Data(contentsOf: file) == bytes)

        try store.remove(scope: scope, draftID: draft.draftID)
        #expect(try store.read(scope: scope, draftID: draft.draftID) == nil)
    }

    @Test func corruptedLocalDraftRequiresExplicitDiscardBeforeReplacement() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("drivy-report-corrupt-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EncryptedSchoolReportDraftStore(directory: directory, keyData: Data(repeating: 7, count: 32))
        let scope = ConfigurationFixture.scope(), draft = Self.localDraft(edited: "Texte conservé")
        try store.save(draft, scope: scope)
        let file = directory.appendingPathComponent("\(draft.draftID.uuidString.lowercased()).bin")
        let corrupted = Data([1, 2, 3])
        try corrupted.write(to: file)
        #expect(throws: SchoolConfigurationFailure.storage) { try store.save(draft, scope: scope) }
        #expect(throws: SchoolConfigurationFailure.storage) { try store.remove(scope: scope, draftID: draft.draftID) }
        #expect(try Data(contentsOf: file) == corrupted)
        try store.discard(scope: scope, draftID: draft.draftID)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        try store.save(draft, scope: scope)
        #expect(try store.read(scope: scope, draftID: draft.draftID) == draft)
    }

    @Test func missingKeyWithExistingDraftNeverCreatesAReplacementKey() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("drivy-report-missing-key-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let vault = ReportDraftVaultStub()
        let store = EncryptedSchoolReportDraftStore(directory: directory, vault: vault)
        let scope = ConfigurationFixture.scope(), draft = Self.localDraft(edited: "Texte conservé")
        try store.save(draft, scope: scope)
        let file = directory.appendingPathComponent("\(draft.draftID.uuidString.lowercased()).bin")
        let bytes = try Data(contentsOf: file)
        vault.value = nil
        #expect(throws: SchoolConfigurationFailure.storage) { try store.save(draft, scope: scope) }
        let other = SchoolReportLocalDraft(draftID: UUID(), lessonID: UUID(), base: draft.base, edited: draft.edited, savedAt: Date())
        #expect(throws: SchoolConfigurationFailure.storage) { try store.save(other, scope: scope) }
        #expect(vault.writes == 0 && vault.value == nil)
        #expect(try Data(contentsOf: file) == bytes)
    }

    // MARK: Saisie gardée et reprise

    @Test func typingIsKeptOnTheDeviceAndNothingIsSentBeforeTheFinalGesture() async throws {
        let server = LessonFinishServer(), outbox = ConfigurationOutboxStub(), drafts = LocalDraftStub()
        let model = workspace(server, outbox: outbox, drafts: drafts)
        await model.load()
        model.persistLocalDraft()
        #expect(drafts.values.isEmpty)
        model.nextStep = "Reprendre les giratoires."
        model.persistLocalDraft()
        let kept = try #require(drafts.values[Self.draftID])
        #expect(kept.edited.nextStep == "Reprendre les giratoires." && kept.base.isEmpty)
        #expect(outbox.saves.isEmpty)
        #expect(await server.requests().allSatisfy { $0.httpMethod != "PUT" && $0.httpMethod != "POST" })
    }

    @Test func aKeptEntryComesBackWhenTheSchoolIsWhereItWasLeft() async {
        let drafts = LocalDraftStub()
        drafts.values[Self.draftID] = Self.localDraft(edited: "Texte repris après fermeture")
        let model = workspace(LessonFinishServer(), outbox: ConfigurationOutboxStub(), drafts: drafts)
        await model.load()
        #expect(model.workedOn == "Texte repris après fermeture")
        #expect(model.reportEdited && model.hasLocalEdits && !model.needsReload && model.canMutate)
    }

    @Test func aKeptEntryIsNeverLostNorSilentlyRebasedWhenTheSchoolMoved() async {
        let drafts = LocalDraftStub()
        drafts.values[Self.draftID] = Self.localDraft(base: "Ancienne version de l’école", edited: "Ma saisie")
        let model = workspace(LessonFinishServer(), outbox: ConfigurationOutboxStub(), drafts: drafts)
        await model.load()
        #expect(model.workedOn == "Ma saisie" && model.needsReload && !model.canMutate)
        #expect(model.retainedEditsText.contains("Ma saisie"))
        await model.load(discardingEdits: true)
        #expect(model.workedOn.isEmpty && !model.needsReload && drafts.values.isEmpty)
    }

    @Test func theKeptEntryIsErasedOnlyAfterTheDurableReceipt() async throws {
        let server = LessonFinishServer(), drafts = LocalDraftStub()
        let model = workspace(server, outbox: ConfigurationOutboxStub(), drafts: drafts)
        await model.load()
        model.observationText = "Regard loin avant de tourner."
        model.persistLocalDraft()
        await server.setReceiptAvailable(false)
        #expect(!(await model.saveDraft()))
        #expect(drafts.values[Self.draftID] != nil && !model.reportSaveConfirmed)
        await server.setReceiptAvailable(true)
        await model.verifyPending()
        #expect(model.reportSaveConfirmed && drafts.values.isEmpty)
    }

    @Test func withoutAVaultTheEntryStaysInMemoryAndTheReportStillSaves() async {
        let drafts = LocalDraftStub()
        let model = workspace(LessonFinishServer(), outbox: ConfigurationOutboxStub(), drafts: drafts)
        await model.load()
        drafts.fails = true
        model.nextStep = "À garder en mémoire"
        model.persistLocalDraft()
        #expect(drafts.values.isEmpty && model.nextStep == "À garder en mémoire" && model.localDraftError != nil)
        #expect(await model.saveDraft())
        #expect(model.reportSaveConfirmed)
    }

    @Test func givingUpTheEntryRemovesItFromTheDevice() async {
        let drafts = LocalDraftStub()
        let model = workspace(LessonFinishServer(), outbox: ConfigurationOutboxStub(), drafts: drafts)
        await model.load()
        model.workedOn = "Brouillon abandonné"
        model.persistLocalDraft()
        #expect(drafts.values.count == 1)
        model.discardLocalDraft()
        #expect(drafts.values.isEmpty)
    }

    @Test func keepingAndClosingWritesTheDraftBeforeClosingWithoutSendingIt() async {
        let server = LessonFinishServer(), drafts = LocalDraftStub(), outbox = ConfigurationOutboxStub()
        let model = workspace(server, outbox: outbox, drafts: drafts)
        await model.load()
        model.nextStep = "Reprendre les priorités"
        #expect(model.canKeepLocalDraft)
        #expect(model.keepLocalDraftAndClose())
        #expect(model.isInvalidated && !model.reportSaveConfirmed && drafts.values[Self.draftID]?.edited.nextStep == "Reprendre les priorités")
        #expect(outbox.saves.isEmpty)
        #expect(await server.requests().allSatisfy { $0.httpMethod != "PUT" && $0.httpMethod != "POST" })
        let reopened = workspace(server, outbox: outbox, drafts: drafts)
        await reopened.load()
        #expect(reopened.nextStep == "Reprendre les priorités" && reopened.hasLocalEdits)
    }

    @Test func failedLocalWriteKeepsTheScreenAndTextUntilRetrySucceeds() async {
        let drafts = LocalDraftStub()
        let retrying = workspace(LessonFinishServer(), outbox: ConfigurationOutboxStub(), drafts: drafts)
        await retrying.load()
        retrying.nextStep = "À ne pas perdre"
        drafts.fails = true
        #expect(!retrying.keepLocalDraftAndClose())
        #expect(!retrying.isInvalidated && retrying.nextStep == "À ne pas perdre" && retrying.localDraftError != nil)
        drafts.fails = false
        #expect(retrying.keepLocalDraftAndClose())
        #expect(retrying.localDraftError == nil && retrying.isInvalidated)
        // Une réponse tardive ou une action d'une ancienne fiche ne peut conserver un autre contexte.
        let model = workspace(LessonFinishServer(), outbox: ConfigurationOutboxStub(), drafts: drafts)
        await model.load()
        model.nextStep = "Ancien contexte"
        model.invalidate()
        #expect(!model.canKeepLocalDraft && !model.keepLocalDraftAndClose())
    }

    @Test func aLocalDraftNeverClaimsToKeepUnsavedPreparationOrCancelASentRequest() async {
        let server = LessonFinishServer(), outbox = ConfigurationOutboxStub(), drafts = LocalDraftStub()
        let model = workspace(server, outbox: outbox, drafts: drafts)
        await model.load()
        model.nextStep = "Bilan en cours"
        model.administrativeNote = "Note distincte"
        #expect(!model.canKeepLocalDraft)
        model.administrativeNote = model.preparation?.administrativeCheckNote ?? ""
        await server.setReceiptAvailable(false)
        #expect(!(await model.saveDraft()))
        let command = model.pending
        #expect(command != nil && model.keepLocalDraftAndClose())
        #expect(outbox.value == command && !model.reportSaveConfirmed)
    }

    @Test func failedDiscardDoesNotPretendTheOldDraftWasDeleted() async {
        let drafts = LocalDraftStub()
        let edited = workspace(LessonFinishServer(), outbox: ConfigurationOutboxStub(), drafts: drafts)
        await edited.load()
        edited.nextStep = "Brouillon conservé"
        #expect(edited.persistLocalDraft())
        drafts.fails = true
        #expect(!edited.discardLocalDraft())
        #expect(edited.localDraftError != nil && !edited.isInvalidated && drafts.values.count == 1)
        drafts.fails = false
        edited.retryLocalDraft()
        #expect(edited.localDraftError == nil && drafts.values.isEmpty)
    }

    @Test func unreadableLocalDraftIsNeverTreatedAsAbsentByAutosaveOrClose() async {
        let drafts = LocalDraftStub()
        let stored = Self.localDraft(edited: "Brouillon à retrouver")
        drafts.values[Self.draftID] = stored; drafts.failsReads = true
        let model = workspace(LessonFinishServer(), outbox: ConfigurationOutboxStub(), drafts: drafts)
        await model.load()
        #expect(model.localDraftReadFailed && !model.acceptsInput && !model.canMutate)
        #expect(!model.persistLocalDraft() && !model.closeWithoutLocalEdits() && !model.isInvalidated)
        drafts.failsReads = false
        #expect(!model.persistLocalDraft(), "Une reprise explicite doit relire la saisie avant tout remplacement.")
        #expect(drafts.values[Self.draftID] == stored)
        model.retryLocalDraft()
        #expect(!model.localDraftReadFailed && model.workedOn == "Brouillon à retrouver")
        #expect(model.acceptsInput && model.localDraftError == nil)
    }

    @Test func unreadableDraftCanOnlyBeRemovedByExplicitAbandonment() async {
        let drafts = LocalDraftStub()
        drafts.values[Self.draftID] = Self.localDraft(edited: "Brouillon illisible")
        drafts.failsReads = true
        let model = workspace(LessonFinishServer(), outbox: ConfigurationOutboxStub(), drafts: drafts)
        await model.load()
        #expect(!model.discardLocalDraft() && drafts.values.count == 1)
        #expect(model.discardLocalDraft(explicit: true))
        #expect(drafts.values.isEmpty && !model.localDraftReadFailed && model.localDraftError == nil)
    }

    @Test func closingAfterRevertingTheTextWaitsForDurableDraftRemoval() async {
        let drafts = LocalDraftStub(), server = LessonFinishServer()
        let model = workspace(server, outbox: ConfigurationOutboxStub(), drafts: drafts)
        await model.load()
        model.nextStep = "Ancien brouillon local"
        #expect(model.persistLocalDraft())
        model.nextStep = ""
        #expect(!model.hasLocalEdits)
        drafts.failsRemovals = true
        #expect(!model.closeWithoutLocalEdits())
        #expect(!model.isInvalidated && model.requiresLocalDraftResolution && drafts.values.count == 1)
        drafts.failsRemovals = false
        #expect(model.closeWithoutLocalEdits())
        #expect(model.isInvalidated && drafts.values.isEmpty)
        let reopened = workspace(server, outbox: ConfigurationOutboxStub(), drafts: drafts)
        await reopened.load()
        #expect(reopened.nextStep.isEmpty && !reopened.hasLocalEdits)
    }

    @Test func anUnconfirmedInvitationDoesNotBlockSavingTheLessonReport() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("drivy-report-domains-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let outbox = EncryptedSchoolCommandOutbox(directory: directory, keyData: Data(repeating: 8, count: 32))
        let operationID = UUID(), scope = ConfigurationFixture.scope()
        let invitation = PendingSchoolCommand(id: operationID, scope: scope, kind: .createInvitation,
            resourceVersion: 0, createdAt: Date(),
            body: try JSONSerialization.data(withJSONObject: ["operationId": operationID.uuidString]))
        try outbox.save(invitation)
        let model = workspace(LessonFinishServer(), outbox: outbox, drafts: LocalDraftStub())
        await model.load()
        #expect(model.pending == nil && model.canMutate)
        model.nextStep = "Reprendre les priorités"
        #expect(await model.saveDraft())
        #expect(model.reportSaveConfirmed)
        #expect(try outbox.pendingCommands(for: scope) == [invitation])
    }

    // MARK: Données de test

    private func workspace(_ server: LessonFinishServer, outbox: any SchoolCommandOutbox, drafts: LocalDraftStub) -> SchoolLessonReportWorkspace {
        let membership = SchoolMembership(membershipId: ConfigurationFixture.membershipID, schoolId: HubFixture.schoolID,
            schoolName: "École de test", roles: ["INSTRUCTOR"], grants: ["permit_review"], accessEpoch: 1)
        let client = SchoolLessonReportClient(baseURL: URL(string: ConfigurationFixture.scope().apiBaseURL)!, tokenSource: HubToken(), transport: server)
        return SchoolLessonReportWorkspace(scope: ConfigurationFixture.scope(), membership: membership, lessonID: HubFixture.lessonID,
            client: client, outbox: outbox, localDrafts: drafts)
    }

    private static func localDraft(base: String = "", edited: String) -> SchoolReportLocalDraft {
        SchoolReportLocalDraft(draftID: draftID, lessonID: HubFixture.lessonID,
            base: .init(workedOn: base, observationText: "", nextStep: "", observations: []),
            edited: .init(workedOn: edited, observationText: "", nextStep: "", observations: []),
            savedAt: Date(timeIntervalSince1970: 1_790_000_000))
    }

    private static func competency(_ order: Int) -> SchoolCatalogCompetency {
        SchoolCatalogCompetency(id: UUID(), schoolId: HubFixture.schoolID, version: 1, curriculumVersionId: UUID(),
            key: "c\(order)", label: "Compétence \(order)", description: "", sortOrder: order)
    }

    private static func observation(competency: UUID, status: String) -> SchoolObservation {
        SchoolObservation(id: UUID(), schoolId: HubFixture.schoolID, version: 1, lessonId: HubFixture.lessonID,
            trainingId: HubFixture.trainingID, draftId: nil, captureId: nil, segmentId: nil, pointSequence: nil,
            competencyId: competency, text: "Signalement", origin: "LIVE", observedAt: "2026-09-28T12:10:00Z",
            eventKind: "QUALIFIED", eventStatus: status, authorMembershipId: ConfigurationFixture.membershipID)
    }
}

/// Ce qu’une leçon contient, et les étapes attendues.
struct SchoolReportStepCase: Sendable {
    let hasTrip: Bool
    let observations: Int
    let competencies: Int
    let expected: [SchoolReportStep]
}

/// Coffre de test en mémoire ; `fails` reproduit un trousseau illisible.
@MainActor
final class LocalDraftStub: SchoolReportLocalDraftStore {
    var values: [UUID: SchoolReportLocalDraft] = [:]
    var fails = false
    var failsReads = false
    var failsRemovals = false

    func read(scope: SchoolCommandScope, draftID: UUID) throws -> SchoolReportLocalDraft? {
        if fails || failsReads { throw SchoolConfigurationFailure.storage }
        return values[draftID]
    }
    func save(_ draft: SchoolReportLocalDraft, scope: SchoolCommandScope) throws {
        if fails { throw SchoolConfigurationFailure.storage }
        values[draft.draftID] = draft
    }
    func remove(scope: SchoolCommandScope, draftID: UUID) throws {
        if fails || failsRemovals { throw SchoolConfigurationFailure.storage }
        values[draftID] = nil
    }
}

@MainActor private final class ReportDraftVaultStub: IdentityVault {
    var value: Data? = Data(repeating: 7, count: 32)
    var writes = 0
    func read() throws -> Data? { value }
    func write(_ data: Data) throws { writes += 1; value = data }
    func clear() throws { value = nil }

    // MARK: Ce que verra l’élève (#165)

    @Test func learnerPreviewSplitsSharedAndKeptObservations() {
        let items = SchoolReportFlowRules.learnerPreview(sharingKnown: true, tripShared: false, hasTrip: true,
            observationCount: 3, privateObservationCount: 1, goalCount: 2, hasPrivateNote: true)
        #expect(items == [
            .init(label: "Trajet pour moi", visible: false),
            .init(label: "2 observations visibles par l’élève", visible: true),
            .init(label: "1 observation pour moi", visible: false),
            .init(label: "2 objectifs visibles par l’élève", visible: true),
            .init(label: "Note pour moi, jamais montrée à l’élève", visible: false),
        ])
    }

    @Test func learnerPreviewAffirmsNothingWithoutSharingSettings() {
        let items = SchoolReportFlowRules.learnerPreview(sharingKnown: false, tripShared: true, hasTrip: true,
            observationCount: 2, privateObservationCount: 0, goalCount: 0, hasPrivateNote: false)
        #expect(items.allSatisfy { $0.visible == nil })
        #expect(items.count == 2)
    }

    @Test func learnerPreviewIsEmptyWithoutContent() {
        #expect(SchoolReportFlowRules.learnerPreview(sharingKnown: true, tripShared: true, hasTrip: false,
            observationCount: 0, privateObservationCount: 0, goalCount: 0, hasPrivateNote: false).isEmpty)
    }
}
