import Foundation
import Testing
@testable import Drivy

/// Attente nommée et bornée des feuilles d’accès : le temps est injecté, aucun réseau, aucun accès accordé ici.
@MainActor
struct SchoolWaitMonitorTests {
    /// Horloge monotone pilotable. Annulation coopérative, sans attente réelle.
    @MainActor final class Clock {
        struct Gate {
            let deadline: ContinuousClock.Instant
            let continuation: CheckedContinuation<Void, Error>
        }
        private var gates: [UUID: Gate] = [:]
        private(set) var requested: [Duration] = []
        private var instant = ContinuousClock.now
        var pendingCount: Int { gates.count }
        func now() -> ContinuousClock.Instant { instant }

        func sleep(_ duration: Duration) async throws {
            let id = UUID()
            requested.append(duration)
            try await withTaskCancellationHandler {
                try Task.checkCancellation()
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    if duration <= .zero { continuation.resume() }
                    else { gates[id] = Gate(deadline: instant.advanced(by: duration), continuation: continuation) }
                }
                try Task.checkCancellation()
            } onCancel: {
                Task { @MainActor in
                    self.gates.removeValue(forKey: id)?.continuation.resume(throwing: CancellationError())
                }
            }
        }

        func advance(by duration: Duration = .seconds(5)) {
            instant = instant.advanced(by: duration)
            let due = gates.filter { $0.value.deadline <= instant }.map(\.key)
            for id in due { gates.removeValue(forKey: id)?.continuation.resume() }
        }
    }

    /// Cède la main jusqu’à ce que la condition soit vraie (les tâches du moniteur s’exécutent sur le même acteur).
    private func settle(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<200 where !condition() { await Task.yield() }
        #expect(condition())
    }

    @Test func aWaitBecomesSlowOnlyAfterTenSecondsAndStaysSlowOnce() async {
        let clock = Clock()
        let monitor = SchoolWaitMonitor(sleep: clock.sleep, now: clock.now)
        #expect(monitor.phase == .idle)

        var release: CheckedContinuation<Void, Never>?
        monitor.run { await withCheckedContinuation { release = $0 } }
        #expect(monitor.phase == .waiting)
        await settle { clock.requested.count == 1 && release != nil }
        #expect(clock.requested == [.seconds(5)])
        #expect(monitor.phase == .waiting)
        clock.advance(by: .milliseconds(4999))
        await Task.yield()
        #expect(monitor.phase == .waiting)

        clock.advance(by: .milliseconds(1))
        await settle { clock.requested.count == 2 }
        #expect(monitor.phase == .pending)
        clock.advance(by: .milliseconds(4999))
        await Task.yield()
        #expect(monitor.phase == .pending)
        clock.advance(by: .milliseconds(1))
        await settle { monitor.phase == .slow }
        #expect(monitor.phase == .slow)

        release?.resume()
        await monitor.waitUntilIdle()
        #expect(monitor.phase == .idle)
    }

    @Test func aFastAnswerNeverShowsTheSlowLine() async {
        let clock = Clock()
        let monitor = SchoolWaitMonitor(sleep: clock.sleep, now: clock.now)
        var phases: [SchoolWaitMonitor.Phase] = []
        monitor.onPhase = { phases.append($0) }
        monitor.run { }
        await monitor.waitUntilIdle()
        await settle { clock.pendingCount == 0 }
        #expect(phases == [.waiting, .idle])
        #expect(monitor.phase == .idle)
        clock.advance()
        await Task.yield()
        #expect(monitor.phase == .idle)
    }

    @Test func retryCancelsTheSentCallThenReplaysTheSameOperationOnce() async {
        let clock = Clock()
        let monitor = SchoolWaitMonitor(sleep: clock.sleep, now: clock.now)
        var sends = 0
        var cancelled = 0
        // « Même opération » : la fermeture rejouée est celle du modèle, qui garde son identifiant d’opération.
        let operationID = UUID()
        var sentIDs: [UUID] = []
        monitor.run {
            sends += 1; sentIDs.append(operationID)
            while !Task.isCancelled { await Task.yield() }
            cancelled += 1
        }
        await settle { clock.requested.count == 1 }
        clock.advance()
        await settle { clock.requested.count == 2 }
        #expect(monitor.phase == .pending)
        clock.advance()
        await settle { monitor.phase == .slow }

        monitor.retry {
            sends += 1; sentIDs.append(operationID)
        }
        // La relance repart d’une attente neuve, pas d’un « lent » déjà annoncé.
        #expect(monitor.phase == .waiting)
        await monitor.waitUntilIdle()
        #expect(cancelled == 1 && sends == 2)
        #expect(Set(sentIDs).count == 1)
        #expect(monitor.phase == .idle)
    }

    @Test func aRetryDoesNothingWhenTheFirstCallAlreadyAnswered() async {
        let clock = Clock()
        let monitor = SchoolWaitMonitor(sleep: clock.sleep, now: clock.now)
        var answered = false
        var replayed = false
        monitor.run { answered = true }
        monitor.retry {
            // Le modèle refuse de renvoyer une fois confirmé : la relance ne crée rien.
            if !answered { replayed = true }
        }
        await monitor.waitUntilIdle()
        #expect(answered && !replayed)
        #expect(monitor.phase == .idle)
    }

    @Test func slowIsAnnouncedOncePerWaitNotOnEveryTick() async {
        let clock = Clock()
        let monitor = SchoolWaitMonitor(sleep: clock.sleep, now: clock.now)
        var phases: [SchoolWaitMonitor.Phase] = []
        monitor.onPhase = { phases.append($0) }
        var release: CheckedContinuation<Void, Never>?
        monitor.run { await withCheckedContinuation { release = $0 } }
        await settle { clock.requested.count == 1 && release != nil }
        clock.advance()
        await settle { clock.requested.count == 2 }
        #expect(monitor.phase == .pending)
        clock.advance()
        await settle { monitor.phase == .slow }
        clock.advance()
        await Task.yield()
        release?.resume()
        await monitor.waitUntilIdle()
        #expect(phases == [.waiting, .pending, .slow, .idle])
        #expect(phases.compactMap { $0.announcement(title: "Vérification…") }
                == ["Vérification…", "Demande en cours", "La réponse tarde."])
        await settle { clock.pendingCount == 0 }
    }

    @Test func answerBetweenThresholdsCancelsTheRemainingTimer() async {
        let clock = Clock()
        let monitor = SchoolWaitMonitor(sleep: clock.sleep, now: clock.now)
        var phases: [SchoolWaitMonitor.Phase] = []
        monitor.onPhase = { phases.append($0) }
        var release: CheckedContinuation<Void, Never>?
        monitor.run { await withCheckedContinuation { release = $0 } }
        await settle { clock.pendingCount == 1 && release != nil }
        clock.advance()
        await settle { clock.requested.count == 2 }
        release?.resume()
        await monitor.waitUntilIdle()
        await settle { clock.pendingCount == 0 }
        clock.advance(by: .seconds(20))
        await Task.yield()
        #expect(phases == [.waiting, .pending, .idle])
    }

    @Test func oldCompletionCannotFinishANewRun() async {
        let clock = Clock()
        let monitor = SchoolWaitMonitor(sleep: clock.sleep, now: clock.now)
        var oldRelease: CheckedContinuation<Void, Never>?
        var newRelease: CheckedContinuation<Void, Never>?
        monitor.run { await withCheckedContinuation { oldRelease = $0 } }
        await settle { oldRelease != nil && clock.pendingCount == 1 }
        monitor.run { await withCheckedContinuation { newRelease = $0 } }
        await settle { newRelease != nil && clock.requested.count == 2 }
        oldRelease?.resume()
        await Task.yield()
        #expect(monitor.phase == .waiting)
        clock.advance()
        await settle { monitor.phase == .pending }
        newRelease?.resume()
        await monitor.waitUntilIdle()
        await settle { clock.pendingCount == 0 }
        #expect(monitor.phase == .idle)
    }

    @Test func cancelledTimerReleasesItsContinuationWithoutAdvancingTime() async {
        let clock = Clock()
        let monitor = SchoolWaitMonitor(sleep: clock.sleep, now: clock.now)
        var release: CheckedContinuation<Void, Never>?
        monitor.run { await withCheckedContinuation { release = $0 } }
        await settle { clock.pendingCount == 1 && release != nil }
        release?.resume()
        await monitor.waitUntilIdle()
        await settle { clock.pendingCount == 0 }
        #expect(monitor.phase == .idle)
    }

    @Test func anObsoleteTimerCannotAnnounceInANewAttempt() async {
        // Double hostile volontaire : ignore l’annulation, contrairement à Task.sleep et à Clock.
        // Toutes ses continuations sont explicitement reprises pour ne rien abandonner.
        var timers: [CheckedContinuation<Void, Never>] = []
        let monitor = SchoolWaitMonitor(sleep: { _ in
            await withCheckedContinuation { timers.append($0) }
        })
        var releases: [CheckedContinuation<Void, Never>] = []
        var phases: [SchoolWaitMonitor.Phase] = []
        monitor.onPhase = { phases.append($0) }
        monitor.run { await withCheckedContinuation { releases.append($0) } }
        await settle { timers.count == 1 && releases.count == 1 }
        monitor.run { await withCheckedContinuation { releases.append($0) } }
        await settle { timers.count == 2 && releases.count == 2 }
        timers[0].resume()
        releases[0].resume()
        for _ in 0..<20 { await Task.yield() }
        #expect(monitor.phase == .waiting)
        #expect(phases == [.waiting])
        releases[1].resume()
        await monitor.waitUntilIdle()
        timers[1].resume()
        for _ in 0..<20 { await Task.yield() }
        #expect(phases == [.waiting, .idle])
    }
    @Test func aLateFirstWakeDoesNotPushTheTenSecondThresholdBack() async {
        let clock = Clock()
        let monitor = SchoolWaitMonitor(sleep: clock.sleep, now: clock.now)
        var release: CheckedContinuation<Void, Never>?
        monitor.run { await withCheckedContinuation { release = $0 } }
        await settle { clock.pendingCount == 1 && release != nil }
        clock.advance(by: .seconds(8))
        await settle { clock.requested.count == 2 }
        #expect(clock.requested == [.seconds(5), .seconds(2)])
        #expect(monitor.phase == .pending)
        clock.advance(by: .seconds(2))
        await settle { monitor.phase == .slow }
        release?.resume()
        await monitor.waitUntilIdle()
        #expect(monitor.phase == .idle)
    }

}
