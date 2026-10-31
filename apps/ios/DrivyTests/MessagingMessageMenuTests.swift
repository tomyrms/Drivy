import XCTest
@testable import Drivy

@MainActor
final class MessagingMessageMenuTests: XCTestCase {
    private let scope = MessagingScope(accountID: UUID(), schoolID: UUID(), accessEpoch: 1, apiBaseURL: "https://menu.example.invalid")
    private let conversation = UUID()

    private func setup(isGeneral: Bool = false) async -> (MessagingThreadModel, MenuMessageService, MessagingWireMessage) {
        let message = MessagingWireMessage(id: UUID(), conversationID: conversation, schoolID: scope.schoolID,
            senderID: scope.accountID, acceptedAt: Date(timeIntervalSince1970: 1_000),
            ciphertext: .init(scheme: "TEST_ONLY", keyID: "k", payload: Data("synthetic".utf8)),
            meta: .init(sequence: 1))
        let service = MenuMessageService(message: message)
        let scope = scope
        let workspace = MessagingWorkspace(scope: scope, service: service, currentScope: { scope })
        await workspace.loadMessages(conversation)
        let composer = MessagingComposerModel(workspace: workspace, conversationID: conversation)
        return (MessagingThreadModel(workspace: workspace, composer: composer, conversationID: conversation, isGeneral: isGeneral), service, message)
    }

    func testDestructiveChoiceWaitsForMenuDismissalAndOnlyRequestsDrivyConfirmation() async {
        let (thread, _, message) = await setup()
        let id = message.id.uuidString
        thread.openMenu(displayID: id)
        thread.chooseMenuAction(.deleteForEveryone, displayID: id)
        XCTAssertNil(thread.menuTarget)
        XCTAssertNil(thread.confirmDeleteForEveryone)
        XCTAssertNil(thread.workspace.mutation(.deleteForEveryone, on: message))
        thread.completeMenuChoice()
        XCTAssertEqual(thread.confirmDeleteForEveryone?.id, message.id)
        XCTAssertNil(thread.workspace.mutation(.deleteForEveryone, on: message))
    }

    func testClosingTheConversationCancelsAnAlreadyChosenAction() async {
        let (thread, _, message) = await setup()
        thread.openMenu(displayID: message.id.uuidString)
        thread.chooseMenuAction(.deleteForEveryone, displayID: message.id.uuidString)
        thread.cancelMenu()
        thread.completeMenuChoice()
        XCTAssertNil(thread.confirmDeleteForEveryone)
        XCTAssertNil(thread.workspace.mutation(.deleteForEveryone, on: message))
    }

    func testRightsAreReadAgainAfterMenuDismissalAndAfterConfirmation() async {
        let (thread, service, message) = await setup()
        let id = message.id.uuidString
        thread.openMenu(displayID: id)
        thread.chooseMenuAction(.deleteForEveryone, displayID: id)
        await service.makeReadOnly()
        await thread.workspace.loadMessages(conversation)
        thread.completeMenuChoice()
        XCTAssertNil(thread.confirmDeleteForEveryone)
        thread.confirmDeletion(message, for: .everyone)
        XCTAssertNil(thread.workspace.mutation(.deleteForEveryone, on: message))
        XCTAssertFalse(thread.canReact(displayID: id))
        let item = try? XCTUnwrap(thread.item(id))
        XCTAssertTrue(item.map { thread.menuActions($0).contains(.deleteForMe) } == true)
    }

    func testAChoiceCannotTargetAnotherMessageThanTheOpenedMenu() async {
        let (thread, _, message) = await setup()
        thread.openMenu(displayID: message.id.uuidString)
        thread.chooseMenuAction(.deleteForEveryone, displayID: UUID().uuidString)
        thread.completeMenuChoice()
        XCTAssertEqual(thread.menuTarget?.id, message.id.uuidString)
        XCTAssertNil(thread.confirmDeleteForEveryone)
    }

    func testDeleteForMeHasItsOwnConfirmationEvenInReadOnlyHistory() async {
        let (thread, service, message) = await setup()
        await service.makeReadOnly()
        await thread.workspace.loadMessages(conversation)
        thread.openMenu(displayID: message.id.uuidString)
        thread.chooseMenuAction(.deleteForMe, displayID: message.id.uuidString)
        thread.completeMenuChoice()
        XCTAssertEqual(thread.confirmDeleteForMe?.id, message.id)
        XCTAssertNil(thread.confirmDeleteForEveryone)
        thread.cancelMenu()
        XCTAssertNil(thread.confirmDeleteForMe)
    }

    func testGeneralPinningRequiresTheCurrentGroupAdministratorRole() async throws {
        let (thread, service, message) = await setup(isGeneral: true)
        let item = try XCTUnwrap(thread.item(message.id.uuidString))
        XCTAssertTrue(thread.menuActions(item).contains(.reply))
        XCTAssertFalse(thread.menuActions(item).contains(.pin))
        await service.makeGroupAdmin()
        await thread.workspace.loadMessages(conversation)
        XCTAssertTrue(thread.menuActions(item).contains(.pin))
    }
}

private actor MenuMessageService: MessagingService {
    let message: MessagingWireMessage
    private var access = MessagingConversationAccess.full
    init(message: MessagingWireMessage) { self.message = message }
    func makeReadOnly() { access = .init(canWrite: false, readableUntilSequence: 1, isGroupAdmin: false) }
    func makeGroupAdmin() { access = .init(canWrite: true, readableUntilSequence: nil, isGroupAdmin: true) }
    func conversations(scope: MessagingScope, cursor: String?) -> MessagingPage<MessagingConversation> { .init(items: [], nextCursor: nil) }
    func messages(scope: MessagingScope, conversationID: UUID, before: String?) -> MessagingPage<MessagingWireMessage> {
        .init(items: [message], nextCursor: nil, access: access)
    }
    func send(scope: MessagingScope, pending: MessagingPending) throws -> MessagingAcknowledgement { throw MessagingFailure.unavailable }
}
