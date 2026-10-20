import Foundation

/// Live matching must not wait for an uncancellable shared OIDC refresh after its deadline.
/// One fetch is shared by all live callers of this client. Cancelling a waiter never cancels
/// the identity refresh used by the rest of the app, and repeated timeouts cannot pile up fetches.
@MainActor
final class SchoolLiveMatchTokenBroker {
    private let source: any AccessTokenSource
    private var fetch: Task<Void, Never>?
    private var waiters: [UUID: CheckedContinuation<String, Error>] = [:]

    init(source: any AccessTokenSource) { self.source = source }

    func value() async throws -> String {
        let id = UUID()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled else { continuation.resume(throwing: CancellationError()); return }
                waiters[id] = continuation
                guard fetch == nil else { return }
                fetch = Task { [weak self, source] in
                    let result: Result<String, Error>
                    do {
                        let token = try await source.accessToken()
                        guard !token.isEmpty, token.utf8.allSatisfy({ $0 > 32 && $0 < 127 }) else {
                            throw SchoolCaptureFailure.unauthorized
                        }
                        result = .success(token)
                    } catch IdentityFailure.reauthentication {
                        result = .failure(SchoolCaptureFailure.unauthorized)
                    } catch let failure as SchoolCaptureFailure {
                        result = .failure(failure)
                    } catch {
                        result = .failure(error.unlessCancelled(SchoolCaptureFailure.unavailable))
                    }
                    self?.complete(result)
                }
            }
        } onCancel: { [weak self] in
            Task { @MainActor in self?.cancel(id) }
        }
    }

    private func cancel(_ id: UUID) {
        waiters.removeValue(forKey: id)?.resume(throwing: CancellationError())
    }

    private func complete(_ result: Result<String, Error>) {
        fetch = nil
        let pending = waiters.values
        waiters.removeAll()
        for waiter in pending { waiter.resume(with: result) }
    }
}
