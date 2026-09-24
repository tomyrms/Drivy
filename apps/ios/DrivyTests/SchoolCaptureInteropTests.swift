import Foundation
import Testing
@testable import Drivy

struct SchoolCaptureInteropTests {
    // Vecteur issu de canonicalCaptureJSON côté API : zéro négatif et exposants
    // éprouvent les divergences possibles entre les sérialisations de nombres.
    @Test func chunkHashMatchesServerECMAScriptVector() throws {
        let point = SchoolCapturePoint(sequence: 0, elapsedMs: 1, capturedAt: "2026-09-24T12:00:00.001Z",
                                       latitude: -0.0, longitude: 1e-7, accuracyMeters: 1e21)
        let first = try SchoolCaptureChunkEncoding.makeBody(operationID: UUID(), segmentIndex: 0,
            startedAt: "2026-09-24T12:00:00.000Z", reason: .start, points: [point], signedUploadAuthorization: "synthetic-upload-proof")
        let retry = try SchoolCaptureChunkEncoding.makeBody(operationID: UUID(), segmentIndex: 0,
            startedAt: "2026-09-24T12:00:00.000Z", reason: .start, points: [point], signedUploadAuthorization: "other-synthetic-proof")
        #expect(first.contentHash == "65e7f15eec6b99ce5ca16137a146a690bfabab9017619f8c7657da69e30b1ecd")
        #expect(retry.contentHash == first.contentHash)
    }

    @Test func exampleAccuracyCannotBecomeRecordedGPS() {
        let point = SchoolCapturePoint(sequence: 0, elapsedMs: 1, capturedAt: "2026-09-24T12:00:00.001Z",
                                       latitude: 47.0, longitude: 6.9, accuracyMeters: -1)
        #expect(throws: SchoolCaptureFailure.invalidResponse) {
            try SchoolCaptureChunkEncoding.makeBody(operationID: UUID(), segmentIndex: 0,
                startedAt: "2026-09-24T12:00:00.000Z", reason: .start, points: [point], signedUploadAuthorization: "synthetic-upload-proof")
        }
    }

    @Test func measurementTimeCannotBeReplacedWithUploadTime() {
        let point = SchoolCapturePoint(sequence: 0, elapsedMs: 1, capturedAt: "2026-09-24T12:01:00.001Z",
                                       latitude: 47.0, longitude: 6.9, accuracyMeters: 5)
        #expect(throws: SchoolCaptureFailure.invalidResponse) {
            try SchoolCaptureChunkEncoding.makeBody(operationID: UUID(), segmentIndex: 0,
                startedAt: "2026-09-24T12:00:00.000Z", reason: .start, points: [point], signedUploadAuthorization: "synthetic-upload-proof")
        }
    }
}
