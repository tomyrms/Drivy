import Foundation
import Testing
@testable import Drivy

/// #106 L2 : preuve locale d'un envoi de planification, annulable seulement avant la remise au transport.
/// Ces tests n'utilisent ni réseau, ni coffre réel, ni transaction : seulement le type d'admission.
/// Aucune exécution Apple n'est revendiquée depuis Windows ; le RED/GREEN natif reste à observer au candidat.
@MainActor
struct SchoolCommandSendAdmissionTests {
    private let now = HubFixture.date("2027-01-15T10:00:00Z")

    @Test func aFreshAdmissionWaitsAndACheckDoesNotHandItOff() throws {
        let command = try creation()
        let admission = SchoolCommandSendAdmission(command: command)

        #expect(admission.phase == .waiting)
        try admission.check(command)
        #expect(admission.phase == .waiting)

        try admission.handOff(command)
        #expect(admission.phase == .handedToTransport)
    }

    @Test func everyStepRefusesAnotherCommandEvenWithTheSameUUID() throws {
        let command = try creation()
        let other = try creation()
        let sameIDOtherBody = try creation(id: command.id, start: now.addingTimeInterval(7_200))
        let sameIDOtherVersion = PendingSchoolCommand(id: command.id, scope: command.scope, kind: command.kind,
            resourceVersion: 3, createdAt: command.createdAt, body: command.body,
            routeResourceID: command.routeResourceID)
        let sameIDOtherScope = try creation(id: command.id, scope: ConfigurationFixture.scope(epoch: 4))
        let admission = SchoolCommandSendAdmission(command: command)

        for candidate in [other, sameIDOtherBody, sameIDOtherVersion, sameIDOtherScope] {
            #expect(throws: SchoolCommandAdmissionFailure.wrongCommand) { try admission.check(candidate) }
            #expect(throws: SchoolCommandAdmissionFailure.wrongCommand) { try admission.handOff(candidate) }
        }
        #expect(admission.phase == .waiting)
    }

    @Test func cancellingBeforeSendRemovesTheExactCommandAndClosesTheEmission() throws {
        let command = try creation()
        let admission = SchoolCommandSendAdmission(command: command)
        var removed: [PendingSchoolCommand] = []

        let result = admission.cancel { removed.append($0) }

        #expect(result == .cancelledBeforeSend)
        #expect(admission.phase == .cancelledBeforeSend)
        #expect(removed == [command])
        #expect(throws: SchoolCommandAdmissionFailure.cancelledBeforeSend) { try admission.check(command) }
        #expect(throws: SchoolCommandAdmissionFailure.cancelledBeforeSend) { try admission.handOff(command) }
    }

    @Test func repeatingCancelAfterSuccessIsIdempotentAndRemovesNothingTwice() throws {
        let command = try creation()
        let admission = SchoolCommandSendAdmission(command: command)
        var calls = 0

        #expect(admission.cancel { _ in calls += 1 } == .cancelledBeforeSend)
        #expect(admission.cancel { _ in calls += 1 } == .cancelledBeforeSend)

        #expect(calls == 1)
        #expect(admission.phase == .cancelledBeforeSend)
    }

    @Test func aFailedRemovalClosesTheEmissionAndTheRetryKeepsTheSameRecord() throws {
        let command = try creation()
        let admission = SchoolCommandSendAdmission(command: command)
        var attempts: [PendingSchoolCommand] = []

        let failed = admission.cancel { candidate in
            attempts.append(candidate)
            throw SchoolConfigurationFailure.storage
        }

        #expect(failed == .storageFailure)
        #expect(admission.phase == .cancellationStorageFailed)
        #expect(attempts == [command])
        #expect(throws: SchoolCommandAdmissionFailure.cancellationStorageFailed) { try admission.check(command) }
        #expect(throws: SchoolCommandAdmissionFailure.cancellationStorageFailed) { try admission.handOff(command) }

        let retried = admission.cancel { attempts.append($0) }

        #expect(retried == .cancelledBeforeSend)
        #expect(admission.phase == .cancelledBeforeSend)
        #expect(attempts == [command, command])
        // La reprise du retrait ne réécrit ni le corps, ni la version, ni l'horodatage du record.
        #expect(attempts.last?.id == command.id)
        #expect(attempts.last?.body == command.body)
        #expect(attempts.last?.resourceVersion == command.resourceVersion)
        #expect(attempts.last?.createdAt == command.createdAt)
    }

    @Test func aReentrantHandOffInsideTheRemovalCallbackIsAlreadyRefused() throws {
        let command = try creation()
        let admission = SchoolCommandSendAdmission(command: command)
        var phaseInsideCallback: SchoolCommandSendPhase?
        var reentrantFailure: SchoolCommandAdmissionFailure?
        var otherFailure = false
        var successfulHandOffs = 0
        var removed: [PendingSchoolCommand] = []

        let result = admission.cancel { candidate in
            removed.append(candidate)
            // Le retrait synchrone s'exécute après la fermeture : une remise réentrante doit déjà être refusée.
            phaseInsideCallback = admission.phase
            do {
                try admission.handOff(candidate)
                successfulHandOffs += 1
            } catch let failure as SchoolCommandAdmissionFailure {
                reentrantFailure = failure
            } catch {
                otherFailure = true
            }
        }

        #expect(result == .cancelledBeforeSend)
        #expect(phaseInsideCallback == .cancelledBeforeSend)
        #expect(reentrantFailure == .cancelledBeforeSend)
        #expect(!otherFailure)
        // Aucune remise n'a abouti pendant le callback : rien ne peut être émis pour cette commande.
        #expect(successfulHandOffs == 0)
        #expect(removed == [command])
        #expect(admission.phase == .cancelledBeforeSend)
        #expect(throws: SchoolCommandAdmissionFailure.cancelledBeforeSend) { try admission.check(command) }
        #expect(throws: SchoolCommandAdmissionFailure.cancelledBeforeSend) { try admission.handOff(command) }
    }

    @Test func handOffIsFinalAndCancellingThenNeverRemovesTheCommand() throws {
        let command = try creation()
        let admission = SchoolCommandSendAdmission(command: command)
        var removals = 0

        try admission.handOff(command)
        let result = admission.cancel { _ in removals += 1 }

        #expect(result == .alreadyHandedToTransport)
        #expect(removals == 0)
        #expect(admission.phase == .handedToTransport)
        // Une répétition interne (401) garde la même admission remise, sans redevenir annulable.
        try admission.check(command)
        try admission.handOff(command)
        #expect(admission.phase == .handedToTransport)
    }

    // MARK: - Outils

    private func creation(id: UUID = UUID(), scope: SchoolCommandScope = ConfigurationFixture.scope(),
                          start: Date? = nil) throws -> PendingSchoolCommand {
        let start = start ?? now.addingTimeInterval(3_600)
        return PendingSchoolCommand(id: id, scope: scope, kind: .createLesson, resourceVersion: 0, createdAt: now,
            body: try lessonBody(id: id, start: start), routeResourceID: HubFixture.trainingID)
    }

    private func lessonBody(id: UUID, start: Date) throws -> Data {
        let iso = ISO8601DateFormatter()
        return try JSONSerialization.data(withJSONObject: ["operationId": id.uuidString,
            "plannedStart": iso.string(from: start), "plannedEnd": iso.string(from: start.addingTimeInterval(3_000)),
            "timeZone": "Europe/Zurich", "trainingId": HubFixture.trainingID.uuidString,
            "instructorMembershipId": ConfigurationFixture.membershipID.uuidString], options: [.sortedKeys])
    }
}
