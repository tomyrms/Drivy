#if DEBUG && targetEnvironment(simulator)
import Foundation
import Testing
@testable import Drivy

/// Régression Q6 : le témoin appartient aux attentes actives, pas au dernier defer exécuté.
@MainActor struct SchoolPlanningFixtureWaitTests {
    @Test func cancellingBLeavesAWaitingUntilRemoval() async throws {
        let gate = SchoolPlanningL2FixtureGate(mode: "token", refusesRemoval: false)
        let command = makeCommand()
        gate.arm(command)
        let a = Task { try await gate.waitForRemoval() }
        let b = Task { try await gate.waitForRemoval() }
        do {
            let deadline = Date().addingTimeInterval(3)
            while gate.activeWaitCount != 2 && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
            try #require(gate.activeWaitCount == 2, "Les deux attentes doivent entrer avant l'annulation")
            b.cancel()
            let bResult = await b.result
            switch bResult {
            case .failure(let error): #expect(error is CancellationError)
            case .success: Issue.record("B doit se terminer par annulation")
            }
            #expect(gate.activeWaitCount == 1)
            #expect(gate.evidence == "waiting-token|me=0|mutations=0")
            try gate.remove(command)
            try await a.value
            #expect(gate.activeWaitCount == 0)
            #expect(gate.evidence == "removed|me=0|mutations=0")
        } catch {
            a.cancel(); b.cancel()
            _ = await a.result; _ = await b.result
            throw error
        }
    }

    @Test func cancellingTheOnlyWaitDoesNotLeaveAFalseWitness() async throws {
        let gate = SchoolPlanningL2FixtureGate(mode: "token", refusesRemoval: false)
        gate.arm(makeCommand())
        let waiting = Task { try await gate.waitForRemoval() }
        do {
            let deadline = Date().addingTimeInterval(3)
            while gate.activeWaitCount != 1 && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
            try #require(gate.activeWaitCount == 1, "L'attente doit être entrée")
            waiting.cancel()
            let result = await waiting.result
            switch result {
            case .failure(let error): #expect(error is CancellationError)
            case .success: Issue.record("L'attente doit se terminer par annulation")
            }
            #expect(gate.activeWaitCount == 0)
            #expect(gate.evidence == "admitted|me=0|mutations=0")
        } catch {
            waiting.cancel(); _ = await waiting.result
            throw error
        }
    }

    @Test func theTwentyFiveSecondBoundaryStillRefusesRemoval() async throws {
        let clock = PlanningFixtureClock()
        let gate = SchoolPlanningL2FixtureGate(mode: "token", refusesRemoval: false, now: { clock.instant })
        let command = makeCommand()
        gate.arm(command)
        let waiting = Task { try await gate.waitForRemoval() }
        do {
            let deadline = Date().addingTimeInterval(3)
            while gate.activeWaitCount != 1 && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
            try #require(gate.activeWaitCount == 1, "L'attente doit être entrée avant d'avancer l'horloge")
            clock.instant = clock.instant.addingTimeInterval(25)
            let expiryDeadline = Date().addingTimeInterval(3)
            while gate.activeWaitCount != 0 && Date() < expiryDeadline { try await Task.sleep(for: .milliseconds(10)) }
            try #require(gate.activeWaitCount == 0, "L'échéance doit terminer l'attente")
            let result = await waiting.result
            switch result {
            case .failure(let error): #expect(error is SchoolPlanningL2FixtureGate.Failure)
            case .success: Issue.record("L'échéance ne doit pas libérer l'attente comme un retrait")
            }
            #expect(gate.evidence == "expired|me=0|mutations=0")
            #expect(throws: SchoolPlanningL2FixtureGate.Failure.self) { try gate.remove(command) }
            #expect(gate.evidence == "expired|me=0|mutations=0")
        } catch {
            waiting.cancel(); _ = await waiting.result
            throw error
        }
    }

    private func makeCommand() -> PendingSchoolCommand {
        PendingSchoolCommand(id: UUID(), scope: ConfigurationFixture.scope(), kind: .createLesson,
            resourceVersion: 0, createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            body: Data("{}".utf8), routeResourceID: HubFixture.trainingID)
    }
}

@MainActor private final class PlanningFixtureClock {
    var instant = Date(timeIntervalSince1970: 1_800_000_000)
}
#endif
