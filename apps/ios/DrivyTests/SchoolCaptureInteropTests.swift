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

    @Test @MainActor func lessonPreviewSharesReplaySelectionAcrossPagesAndKeepsOnlyExactAnchors() async throws {
        let schoolID = UUID(), captureID = UUID(), segmentID = UUID()
        let start = Date(timeIntervalSince1970: 1_790_755_200)
        let points = (0...3).map { index in
            SchoolCapturePoint(sequence: index, elapsedMs: index * 1_000,
                capturedAt: SchoolCaptureLocationTime.timestamp(start.addingTimeInterval(Double(index))),
                latitude: 0, longitude: Double(index) / 10_000, accuracyMeters: index == 1 ? 100 : 3)
        }
        func page(_ part: [SchoolCapturePoint], continuation: Bool, next: String?) -> SchoolPrivateReplayPage {
            SchoolPrivateReplayPage(captureId: captureID, quality: "SYNCED", publicationState: .privateCapture,
                segments: [.init(segmentId: segmentID, segmentIndex: 0, points: part, hasGapBefore: false,
                    qualityLabel: "LOW_ACCURACY", continuesFromPreviousPage: continuation, continuesOnNextPage: next != nil)],
                observations: [], nextCursor: next, generatedAt: SchoolCaptureLocationTime.timestamp(start),
                reportRevisionId: nil, geometrySnapshotId: nil)
        }
        let transport = DisplayReplayTransport(pages: [page(Array(points.prefix(2)), continuation: false, next: "synthetic-page-2"),
                                                      page(Array(points.suffix(2)), continuation: true, next: nil)])
        let client = SchoolCaptureClient(baseURL: URL(string: "https://example.invalid")!, tokenSource: HubToken(), transport: transport)
        let track = try await client.replayTrack(schoolID: schoolID, captureID: captureID)
        #expect(track.segments.map { $0.map(\.sequence) } == [[0], [2, 3]])
        #expect(track.pointsByAnchor["\(segmentID.uuidString.lowercased()):1"] == nil)
        #expect(track.pointsByAnchor["\(segmentID.uuidString.lowercased()):2"] == points[2])
    }
}

private actor DisplayReplayTransport: SchoolHTTPTransport {
    private var pages: [SchoolPrivateReplayPage]
    init(pages: [SchoolPrivateReplayPage]) { self.pages = pages }

    func send(_ request: URLRequest) async throws -> SchoolHTTPResponse {
        guard !pages.isEmpty else { throw SchoolCaptureFailure.invalidResponse }
        let data = try JSONSerialization.jsonObject(with: JSONEncoder().encode(pages.removeFirst()))
        return SchoolHTTPResponse(data: try JSONSerialization.data(withJSONObject: ["data": data,
            "requestId": UUID().uuidString, "serverTime": "2026-09-30T08:00:00Z"]), status: 200,
            url: request.url!, contentType: "application/json")
    }
}
