import XCTest
import UIKit
@testable import Drivy

/// Géométrie réservée des bulles photo (#473). Valeurs pures, sans interface.
final class MessagingMediaBubbleGeometryTests: XCTestCase {
    private typealias Geometry = MessagingMediaBubbleGeometry

    private func size(_ width: Int?, _ height: Int?, available: CGFloat? = nil) -> CGSize {
        Geometry.reservedSize(Geometry.plan(width: width, height: height), availableWidth: available)
    }

    func testLandscapeFourByThreeReservesFullWidth() {
        let reserved = size(4000, 3000)
        XCTAssertEqual(reserved.width, 260, accuracy: 0.01)
        XCTAssertEqual(reserved.height, 195, accuracy: 0.01)
    }

    func testPortraitThreeByFourIsLimitedByTheMaximumHeight() {
        let reserved = size(3000, 4000)
        XCTAssertEqual(reserved.height, 340, accuracy: 0.01)
        XCTAssertEqual(reserved.width, 255, accuracy: 0.01)
    }

    func testSquareReservesASquare() {
        let reserved = size(1000, 1000)
        XCTAssertEqual(reserved.width, 260, accuracy: 0.01)
        XCTAssertEqual(reserved.height, 260, accuracy: 0.01)
    }

    func testLongCaptureIsBoundedAndKeepsTheTop() {
        let plan = Geometry.plan(width: 390, height: 3000)
        XCTAssertEqual(plan.crop, .top)
        XCTAssertEqual(plan.ratio, Geometry.narrowestRatio, accuracy: 0.0001)
        let reserved = Geometry.reservedSize(plan, availableWidth: nil)
        XCTAssertEqual(reserved.height, 340, accuracy: 0.01)
        XCTAssertEqual(reserved.width, 204, accuracy: 0.01)
    }

    func testPanoramaIsBoundedAndKeepsTheCenter() {
        let plan = Geometry.plan(width: 8000, height: 1000)
        XCTAssertEqual(plan.crop, .center)
        XCTAssertEqual(plan.ratio, Geometry.widestRatio, accuracy: 0.0001)
        let reserved = Geometry.reservedSize(plan, availableWidth: nil)
        XCTAssertEqual(reserved.width, 260, accuracy: 0.01)
        XCTAssertEqual(reserved.height, 130, accuracy: 0.01)
    }

    func testMissingOrInvalidDimensionsFallBackToFourByThree() {
        for pair in [(Int?.none, Int?.none), (0, 100), (100, 0), (-5, 10), (nil, 10)] {
            let plan = Geometry.plan(width: pair.0, height: pair.1)
            XCTAssertEqual(plan.crop, .none)
            XCTAssertEqual(plan.ratio, Geometry.fallbackRatio, accuracy: 0.0001)
        }
    }

    func testNarrowColumnShrinksTheReservedWidth() {
        let reserved = size(4000, 3000, available: 200)
        XCTAssertEqual(reserved.width, 200, accuracy: 0.01)
        XCTAssertEqual(reserved.height, 150, accuracy: 0.01)
    }

    func testInvalidAvailableWidthFallsBackToTheMaximum() {
        XCTAssertEqual(size(1, 1, available: .infinity).width, 260, accuracy: 0.01)
        XCTAssertEqual(size(1, 1, available: 0).width, 260, accuracy: 0.01)
        XCTAssertEqual(size(1, 1, available: -10).width, 260, accuracy: 0.01)
    }

    func testReservedSizeStaysWithinBoundsForManyRatios() {
        let dimensions = [1, 2, 3, 7, 50, 390, 1000, 4000, 12000]
        for width in dimensions {
            for height in dimensions {
                let reserved = size(width, height)
                XCTAssertLessThanOrEqual(reserved.width, Geometry.maximumWidth + 0.01)
                XCTAssertLessThanOrEqual(reserved.height, Geometry.maximumHeight + 0.01)
                XCTAssertGreaterThan(reserved.width, 0)
                XCTAssertGreaterThan(reserved.height, 0)
            }
        }
    }
}

/// Chargeur de miniatures du fil (#473) : déduplication, concurrence bornée, mémoire bornée,
/// résultat tardif ignoré, reprise ciblée. Double de fournisseur contrôlé, décodeur factice.
@MainActor
final class MessagingMediaThumbnailLoaderTests: XCTestCase {
    private func wire(_ id: UUID = UUID()) -> MessagingWireMessage {
        MessagingWireMessage(id: id, conversationID: UUID(), schoolID: UUID(), senderID: UUID(),
            acceptedAt: Date(),
            ciphertext: MessagingCiphertext(scheme: "TEST", keyID: "k", payload: Data([1])),
            meta: MessagingMessageMeta())
    }

    private func makeLoader(_ provider: ThumbnailProviderDouble?, concurrent: Int = 3,
                            memory: Int = 24, queue: Int = 12) -> MessagingMediaThumbnailLoader {
        MessagingMediaThumbnailLoader(provider: provider, maximumConcurrent: concurrent,
            memoryLimit: memory, queueLimit: queue,
            decode: { _ in MessagingDecodedThumbnail(image: UIImage()) })
    }

    /// Attend une condition sans horloge fixe : cède la main puis dort brièvement, plafonné.
    private func waitUntil(_ condition: @MainActor () async -> Bool) async -> Bool {
        for _ in 0..<400 {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return false
    }

    func testAppearingTwiceRequestsTheThumbnailOnce() async {
        let provider = ThumbnailProviderDouble(holding: false)
        let loader = makeLoader(provider)
        let message = wire()

        loader.appear(message)
        loader.appear(message)
        let loaded = await waitUntil { loader.slot(for: message.id).phase == .loaded }

        XCTAssertTrue(loaded)
        loader.appear(message)
        loader.prefetch(message)
        let calls = await provider.callCount
        XCTAssertEqual(calls, 1, "Une seule demande par pièce, même si elle réapparaît.")
        XCTAssertNotNil(loader.slot(for: message.id).image)
    }

    func testConcurrencyIsBoundedAndQueuedItemsFollow() async {
        let provider = ThumbnailProviderDouble(holding: true)
        let loader = makeLoader(provider, concurrent: 2)
        let messages = (0..<5).map { _ in wire() }
        messages.forEach { loader.appear($0) }

        let started = await waitUntil { await provider.callCount == 2 }
        XCTAssertTrue(started)
        XCTAssertEqual(loader.inflightCount, 2)
        XCTAssertEqual(loader.queuedCount, 3)

        await provider.releaseAll()
        let done = await waitUntil { messages.allSatisfy { loader.slot(for: $0.id).phase == .loaded } }
        XCTAssertTrue(done)
        let peak = await provider.peakConcurrency
        XCTAssertLessThanOrEqual(peak, 2)
        XCTAssertEqual(loader.inflightCount, 0)
    }

    func testVisibleCellJumpsAheadOfPrefetchedNeighbours() async {
        let provider = ThumbnailProviderDouble(holding: true)
        let loader = makeLoader(provider, concurrent: 1)
        let first = wire(), neighbour = wire(), visible = wire()
        loader.appear(first)
        loader.prefetch(neighbour)
        loader.appear(visible)

        _ = await waitUntil { await provider.callCount == 1 }
        await provider.release(first.id)
        _ = await waitUntil { await provider.callCount == 2 }
        let order = await provider.calledIDs
        XCTAssertEqual(order, [first.id, visible.id], "La cellule visible passe avant la voisine.")
        await provider.releaseAll()
    }

    func testLateResultAfterDiscardIsIgnored() async {
        let provider = ThumbnailProviderDouble(holding: true)
        let loader = makeLoader(provider)
        let message = wire()
        loader.appear(message)
        _ = await waitUntil { await provider.callCount == 1 }

        loader.discard(message.id)
        await provider.releaseAll()
        _ = await waitUntil { loader.inflightCount == 0 }

        XCTAssertEqual(loader.slot(for: message.id).phase, .idle)
        XCTAssertNil(loader.slot(for: message.id).image, "Une pièce retirée n'est jamais réaffichée.")
        XCTAssertEqual(loader.decodedCount, 0)
    }

    func testLateResultAfterSuspendIsIgnored() async {
        let provider = ThumbnailProviderDouble(holding: true)
        let loader = makeLoader(provider)
        let message = wire()
        loader.appear(message)
        _ = await waitUntil { await provider.callCount == 1 }

        loader.suspend()
        await provider.releaseAll()
        _ = await waitUntil { loader.inflightCount == 0 }

        XCTAssertEqual(loader.slot(for: message.id).phase, .idle)
        XCTAssertNil(loader.slot(for: message.id).image)
        XCTAssertEqual(loader.decodedCount, 0)
    }

    func testResultIsDroppedWhenTheMessageIsNoLongerAuthorized() async {
        let provider = ThumbnailProviderDouble(holding: true)
        let loader = makeLoader(provider)
        let message = wire()
        loader.appear(message)
        _ = await waitUntil { await provider.callCount == 1 }

        loader.isAuthorized = { _ in false }
        await provider.releaseAll()
        _ = await waitUntil { loader.inflightCount == 0 }

        XCTAssertNil(loader.slot(for: message.id).image, "Une révocation ne réaffiche jamais la miniature.")
        XCTAssertNotEqual(loader.slot(for: message.id).phase, .loaded)
    }

    func testSuspendFreesTheConcurrencySlotsOnlyWhenWorkReallyEnds() async {
        let provider = ThumbnailProviderDouble(holding: true)
        let loader = makeLoader(provider, concurrent: 1)
        let first = wire(), second = wire()
        loader.appear(first)
        _ = await waitUntil { await provider.callCount == 1 }
        loader.suspend()
        loader.appear(second)
        XCTAssertEqual(loader.inflightCount, 1, "Le travail réel en vol compte encore dans la borne.")
        let calls = await provider.callCount
        XCTAssertEqual(calls, 1)

        await provider.releaseAll()
        let secondStarted = await waitUntil { await provider.callCount == 2 }
        XCTAssertTrue(secondStarted)
        await provider.releaseAll()
    }

    func testFailureIsPerAttachmentAndRetryIsTargeted() async {
        let provider = ThumbnailProviderDouble(holding: false)
        let loader = makeLoader(provider)
        let broken = wire(), healthy = wire()
        await provider.fail(broken.id, with: .unreadable)

        loader.appear(broken)
        loader.appear(healthy)
        let settled = await waitUntil {
            loader.slot(for: broken.id).phase == .unavailable(retryable: true)
                && loader.slot(for: healthy.id).phase == .loaded
        }
        XCTAssertTrue(settled, "L'échec d'une pièce n'affecte pas les autres.")

        await provider.fail(broken.id, with: nil)
        loader.retry(broken.id)
        let recovered = await waitUntil { loader.slot(for: broken.id).phase == .loaded }
        XCTAssertTrue(recovered)
        let calls = await provider.callCount
        XCTAssertEqual(calls, 3, "La reprise ne relance que la pièce concernée.")
    }

    func testPermanentRefusalOffersNoRetry() async {
        let provider = ThumbnailProviderDouble(holding: false)
        let loader = makeLoader(provider)
        let removed = wire()
        await provider.fail(removed.id, with: .removed)

        loader.appear(removed)
        _ = await waitUntil { loader.slot(for: removed.id).phase != .loading }
        XCTAssertEqual(loader.slot(for: removed.id).phase, .unavailable(retryable: false))

        loader.retry(removed.id)
        XCTAssertEqual(loader.slot(for: removed.id).phase, .unavailable(retryable: false))
        let calls = await provider.callCount
        XCTAssertEqual(calls, 1)
    }

    func testRetryabilityMapping() {
        typealias Loader = MessagingMediaThumbnailLoader
        XCTAssertTrue(Loader.isRetryable(.unavailable))
        XCTAssertTrue(Loader.isRetryable(.unreadable))
        XCTAssertTrue(Loader.isRetryable(.protectionUnavailable))
        XCTAssertTrue(Loader.isRetryable(.resultUnknown))
        XCTAssertFalse(Loader.isRetryable(.removed))
        XCTAssertFalse(Loader.isRetryable(.contextChanged))
        XCTAssertFalse(Loader.isRetryable(.integrity))
        XCTAssertFalse(Loader.isRetryable(.invalidFormat))
    }

    func testDecodedMemoryIsBoundedAndEvictsTheOldestHiddenItems() async {
        let provider = ThumbnailProviderDouble(holding: false)
        let loader = makeLoader(provider, concurrent: 1, memory: 2)
        let messages = (0..<4).map { _ in wire() }
        for message in messages {
            loader.appear(message)
            _ = await waitUntil { loader.slot(for: message.id).phase == .loaded }
            loader.disappear(message.id)
        }

        XCTAssertLessThanOrEqual(loader.decodedCount, 2)
        XCTAssertNil(loader.slot(for: messages[0].id).image)
        XCTAssertEqual(loader.slot(for: messages[0].id).phase, .idle)
        XCTAssertNotNil(loader.slot(for: messages[3].id).image)
    }

    func testVisibleItemsAreNeverEvicted() async {
        let provider = ThumbnailProviderDouble(holding: false)
        let loader = makeLoader(provider, concurrent: 1, memory: 1)
        let messages = (0..<3).map { _ in wire() }
        for message in messages {
            loader.appear(message)
            _ = await waitUntil { loader.slot(for: message.id).phase == .loaded }
        }
        for message in messages {
            XCTAssertNotNil(loader.slot(for: message.id).image, "Une pièce visible garde son image.")
        }
    }

    func testEvictedItemReloadsOnReappearance() async {
        let provider = ThumbnailProviderDouble(holding: false)
        let loader = makeLoader(provider, concurrent: 1, memory: 1)
        let first = wire(), second = wire()
        loader.appear(first)
        _ = await waitUntil { loader.slot(for: first.id).phase == .loaded }
        loader.disappear(first.id)
        loader.appear(second)
        _ = await waitUntil { loader.slot(for: second.id).phase == .loaded }
        XCTAssertEqual(loader.slot(for: first.id).phase, .idle)

        loader.appear(first)
        let back = await waitUntil { loader.slot(for: first.id).phase == .loaded }
        XCTAssertTrue(back)
    }

    func testQueueIsBoundedAndDropsHiddenNeighboursFirst() async {
        let provider = ThumbnailProviderDouble(holding: true)
        let loader = makeLoader(provider, concurrent: 1, queue: 3)
        let visible = wire()
        loader.appear(visible)
        _ = await waitUntil { await provider.callCount == 1 }
        let neighbours = (0..<6).map { _ in wire() }
        neighbours.forEach { loader.prefetch($0) }

        XCTAssertLessThanOrEqual(loader.queuedCount, 3)
        await provider.releaseAll()
    }

    func testWithoutProviderEveryAttachmentIsUnavailableWithoutRetry() {
        let loader = makeLoader(nil)
        let message = wire()

        loader.appear(message)

        XCTAssertFalse(loader.isSupported)
        XCTAssertEqual(loader.slot(for: message.id).phase, .unavailable(retryable: false))
        loader.retry(message.id)
        XCTAssertEqual(loader.slot(for: message.id).phase, .unavailable(retryable: false))
    }
}

/// Fournisseur de miniatures contrôlé : retient les appels tant que le test ne les libère pas
/// et mesure la concurrence réelle.
private actor ThumbnailProviderDouble: MessagingMediaThumbnailProviding {
    private let holding: Bool
    private var held: [UUID: CheckedContinuation<Void, Never>] = [:]
    private var failures: [UUID: MessagingMediaRuntimeFailure] = [:]
    private var releasedAhead: Set<UUID> = []
    private var current = 0
    private(set) var peakConcurrency = 0
    private(set) var calledIDs: [UUID] = []

    init(holding: Bool) { self.holding = holding }

    var callCount: Int { calledIDs.count }

    func fail(_ id: UUID, with failure: MessagingMediaRuntimeFailure?) { failures[id] = failure }

    func release(_ id: UUID) {
        if let continuation = held.removeValue(forKey: id) { continuation.resume() } else { releasedAhead.insert(id) }
    }

    func releaseAll() {
        let all = held
        held.removeAll()
        for continuation in all.values { continuation.resume() }
    }

    func thumbnail(for message: MessagingWireMessage) async throws -> Data {
        calledIDs.append(message.id)
        current += 1
        peakConcurrency = max(peakConcurrency, current)
        defer { current -= 1 }
        if holding, !releasedAhead.contains(message.id) {
            await withCheckedContinuation { held[message.id] = $0 }
        }
        if let failure = failures[message.id] { throw failure }
        return Data([1])
    }
}
