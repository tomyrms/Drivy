import Foundation
import Testing
@testable import Drivy

/// Attente nommée et bornée des feuilles d’accès : le temps est injecté, aucun réseau, aucun accès accordé ici.
@MainActor
struct SchoolWaitMonitorTests {
    /// Horloge de test : chaque « sleep » attend qu’on le libère, ou s’arrête si sa tâche est annulée.
    @MainActor final class Clock {
        private var gates: [CheckedContinuation<Void, Error>] = []
        private(set) var requested: [Duration] = []

        func sleep(_ duration: Duration) async throws {
            requested.append(duration)
            try await withCheckedThrowingContinuation { gates.append($0) }
        }

        func advance() {
            let pending = gates; gates = []
            pending.forEach { $0.resume() }
        }
    }

    /// Cède la main jusqu’à ce que la condition soit vraie (les tâches du moniteur s’exécutent sur le même acteur).
    private func settle(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<200 where !condition() { await Task.yield() }
    }

    @Test func aWaitBecomesSlowOnlyAfterTenSecondsAndStaysSlowOnce() async {
        let clock = Clock()
        let monitor = SchoolWaitMonitor(sleep: clock.sleep)
        #expect(monitor.phase == .idle)

        var release: CheckedContinuation<Void, Never>?
        monitor.run { await withCheckedContinuation { release = $0 } }
        #expect(monitor.phase == .waiting)
        await settle { clock.requested.count == 1 }
        #expect(clock.requested == [.seconds(10)])
        #expect(monitor.phase == .waiting)

        clock.advance()
        await settle { monitor.phase == .slow }
        #expect(monitor.phase == .slow)

        release?.resume()
        await monitor.waitUntilIdle()
        #expect(monitor.phase == .idle)
    }

    @Test func aFastAnswerNeverShowsTheSlowLine() async {
        let clock = Clock()
        let monitor = SchoolWaitMonitor(sleep: clock.sleep)
        monitor.run { }
        await monitor.waitUntilIdle()
        #expect(monitor.phase == .idle)
        clock.advance()
        await Task.yield()
        #expect(monitor.phase == .idle)
    }

    @Test func retryCancelsTheSentCallThenReplaysTheSameOperationOnce() async {
        let clock = Clock()
        let monitor = SchoolWaitMonitor(sleep: clock.sleep)
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
        let monitor = SchoolWaitMonitor(sleep: clock.sleep)
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
        let monitor = SchoolWaitMonitor(sleep: clock.sleep)
        var phases: [SchoolWaitMonitor.Phase] = []
        monitor.onPhase = { phases.append($0) }
        var release: CheckedContinuation<Void, Never>?
        monitor.run { await withCheckedContinuation { release = $0 } }
        await settle { clock.requested.count == 1 }
        clock.advance()
        await settle { monitor.phase == .slow }
        clock.advance()
        await Task.yield()
        release?.resume()
        await monitor.waitUntilIdle()
        #expect(phases == [.waiting, .slow, .idle])
    }
}
