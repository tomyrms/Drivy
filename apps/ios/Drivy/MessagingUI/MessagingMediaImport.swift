import CoreTransferable
import Foundation
import UniformTypeIdentifiers

enum MessagingMediaImportFailure: Error, Equatable, Sendable {
    case invalidSize, unreadable
}

/// Lecture seule : aucun temporaire créé par l'application. Le fournisseur peut fournir
/// son propre fichier éphémère ; ses octets sont lus avant la fin du callback Transferable.
enum MessagingMediaImport {
    static func document(_ url: URL) async throws -> MessagingImportedMedia {
        let task = Task.detached(priority: .userInitiated) {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            try Task.checkCancellation()
            var result: Result<Data, Error>?
            var coordinationError: NSError?
            NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { readable in
                result = Result { try readFile(readable) }
            }
            guard coordinationError == nil, let result else { throw MessagingMediaImportFailure.unreadable }
            return MessagingImportedMedia(data: try result.get(), suggestedName: url.lastPathComponent)
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: { task.cancel() }
    }

    static func readFile(_ url: URL) throws -> Data {
        guard url.isFileURL else { throw MessagingMediaImportFailure.unreadable }
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true else { throw MessagingMediaImportFailure.unreadable }
            if let size = values.fileSize, size > MessagingMediaAttachment.maximumByteSize {
                throw MessagingMediaImportFailure.invalidSize
            }
            guard let stream = InputStream(url: url) else { throw MessagingMediaImportFailure.unreadable }
            return try read(stream)
        } catch is CancellationError { throw CancellationError() }
        catch let failure as MessagingMediaImportFailure { throw failure }
        catch { throw MessagingMediaImportFailure.unreadable }
    }

    /// The extra byte detects a lying or changing provider without allocating its full file.
    static func read(_ stream: InputStream, cancelled: () -> Bool = { Task.isCancelled }) throws -> Data {
        let limit = MessagingMediaAttachment.maximumByteSize
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        stream.open()
        defer { stream.close() }
        while true {
            if cancelled() { throw CancellationError() }
            let count = stream.read(&buffer, maxLength: min(buffer.count, limit - data.count + 1))
            guard count >= 0 else { throw MessagingMediaImportFailure.unreadable }
            if count == 0 { break }
            guard count <= limit - data.count else { throw MessagingMediaImportFailure.invalidSize }
            data.append(contentsOf: buffer.prefix(count))
        }
        guard data.count >= MessagingMediaAttachment.minimumByteSize else {
            throw MessagingMediaImportFailure.invalidSize
        }
        return data
    }
}

/// File representations bound the read before allocating Data; DataRepresentation would
/// accept an arbitrarily large provider payload before the application can check its size.
struct MessagingImportedMedia: Transferable, Sendable {
    let data: Data
    let suggestedName: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .jpeg, shouldAttemptToOpenInPlace: true) { received in
            MessagingImportedMedia(data: try MessagingMediaImport.readFile(received.file), suggestedName: "Photo.jpg")
        }
        FileRepresentation(importedContentType: .png, shouldAttemptToOpenInPlace: true) { received in
            MessagingImportedMedia(data: try MessagingMediaImport.readFile(received.file), suggestedName: "Photo.png")
        }
    }
}
