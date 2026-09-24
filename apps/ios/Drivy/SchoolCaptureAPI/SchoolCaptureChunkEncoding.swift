import CryptoKit
import Foundation
import JavaScriptCore

struct SchoolCaptureChunkBody: Codable, Sendable {
    enum StartReason: String, Codable, Sendable {
        case start = "START", resume = "RESUME", restart = "RESTART"
        case permissionRestored = "PERMISSION_RESTORED", signalRecovered = "SIGNAL_RECOVERED"
    }
    let operationId: UUID
    let segmentIndex: Int
    let segmentStartedAt: String
    let segmentStartReason: StartReason
    let contentHash: String
    let points: [SchoolCapturePoint]
    let signedUploadAuthorization: String
}

enum SchoolCaptureChunkEncoding {
    /// Hash partagé avec canonicalCaptureJSON du serveur. Le moteur ECMAScript natif
    /// évite d’assimiler les rendus de Double de Foundation à JSON.stringify (-0,
    /// exposants, plus courte représentation). Aucun script reçu n’est exécuté.
    /// Le contexte ne reçoit que le JSON borné en argument et n’expose aucun objet hôte.
    static func makeBody(operationID: UUID, segmentIndex: Int, startedAt: String,
                         reason: SchoolCaptureChunkBody.StartReason, points: [SchoolCapturePoint],
                         signedUploadAuthorization: String) throws -> SchoolCaptureChunkBody {
        guard (0..<200).contains(segmentIndex), let start = SchoolLesson.date(startedAt),
              !points.isEmpty, points.count <= 1000, points.allSatisfy(\.isValid),
              Set(points.map(\.sequence)).count == points.count,
              points.allSatisfy({ $0.sequence <= 2_147_483_646 && $0.elapsedMs <= 10_800_000 && SchoolLesson.date($0.capturedAt)! >= start
                  && abs(SchoolLesson.date($0.capturedAt)!.timeIntervalSince(start) * 1000 - Double($0.elapsedMs)) <= 1 }),
              zip(points, points.dropFirst()).allSatisfy({ $0.sequence < $1.sequence && $0.elapsedMs < $1.elapsedMs
                  && SchoolLesson.date($0.capturedAt)! < SchoolLesson.date($1.capturedAt)! }),
              !signedUploadAuthorization.isEmpty, signedUploadAuthorization.utf8.count <= 12_000 else { throw SchoolCaptureFailure.invalidResponse }
        let content = Content(segmentIndex: segmentIndex, segmentStartedAt: startedAt, segmentStartReason: reason, points: points)
        let data = try JSONEncoder().encode(content)
        let canonical = try canonicalJSON(data)
        let hash = SHA256.hash(data: canonical).map { String(format: "%02x", $0) }.joined()
        return SchoolCaptureChunkBody(operationId: operationID, segmentIndex: segmentIndex,
            segmentStartedAt: startedAt, segmentStartReason: reason, contentHash: hash,
            points: points, signedUploadAuthorization: signedUploadAuthorization)
    }

    private struct Content: Encodable {
        let segmentIndex: Int
        let segmentStartedAt: String
        let segmentStartReason: SchoolCaptureChunkBody.StartReason
        let points: [SchoolCapturePoint]
    }

    private static func canonicalJSON(_ data: Data) throws -> Data {
        guard data.count <= 2 * 1_024 * 1_024, let json = String(data: data, encoding: .utf8),
              let context = JSContext() else { throw SchoolCaptureFailure.invalidResponse }
        let source = #"""
        (function (input) {
            function canonical(value) {
                if (Array.isArray(value)) return '[' + value.map(canonical).join(',') + ']';
                if (value !== null && typeof value === 'object') {
                    return '{' + Object.keys(value).sort().map(function (key) {
                        return JSON.stringify(key) + ':' + canonical(value[key]);
                    }).join(',') + '}';
                }
                return JSON.stringify(value);
            }
            return canonical(JSON.parse(input));
        })
        """#
        guard let function = context.evaluateScript(source), context.exception == nil,
              let result = function.call(withArguments: [json]), context.exception == nil,
              result.isString, let canonical = result.toString(), let bytes = canonical.data(using: .utf8),
              bytes.count <= 2 * 1_024 * 1_024 else { throw SchoolCaptureFailure.invalidResponse }
        return bytes
    }
}
