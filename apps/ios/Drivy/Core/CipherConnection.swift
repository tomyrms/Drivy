import Foundation
import SQLCipher

// Chaque instance appartient à un seul acteur de stockage. Aucun handle, statement ou
// objet de connexion ne traverse sa frontière ; cette classe n’est pas Sendable.
enum SQLValue {
    case text(String), number(Double), blob(Data)
}

final class CipherConnection {
    private var handle: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(url: URL, key: Data) throws {
        var pointer: OpaquePointer?
        guard sqlite3_open_v2(url.path, &pointer, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let pointer else {
            if let pointer { sqlite3_close_v2(pointer) }
            throw SessionError.storageUnavailable
        }
        handle = pointer
        do {
            let hex = key.map { String(format: "%02x", $0) }.joined()
            try execute("PRAGMA key = \"x'\(hex)'\"")
            guard !(try strings("PRAGMA cipher_version")).isEmpty else { throw SessionError.encryptionUnavailable }
            _ = try integer("SELECT COUNT(*) FROM sqlite_master")
            guard try integer("PRAGMA cipher_status") == 1 else { throw SessionError.encryptionUnavailable }
            try execute("PRAGMA cipher_memory_security=ON; PRAGMA temp_store=MEMORY; PRAGMA foreign_keys=ON; PRAGMA secure_delete=ON; PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL;")
            sqlite3_busy_timeout(handle, 2_000)
        } catch {
            sqlite3_close_v2(pointer)
            handle = nil
            throw error
        }
    }

    deinit { sqlite3_close_v2(handle) }

    func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do { try body(); try execute("COMMIT") }
        catch { try? execute("ROLLBACK"); throw error }
    }

    func execute(_ sql: String, _ values: [SQLValue] = []) throws {
        if values.isEmpty {
            guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw SessionError.storageUnavailable }
            return
        }
        let statement = try prepare(sql, values)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw SessionError.storageUnavailable }
    }

    func integer(_ sql: String) throws -> Int {
        let statement = try prepare(sql, [])
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw SessionError.storageUnavailable }
        return Int(sqlite3_column_int64(statement, 0))
    }

    func strings(_ sql: String) throws -> [String] {
        let statement = try prepare(sql, [])
        defer { sqlite3_finalize(statement) }
        var result: [String] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return result }
            guard status == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) else { throw SessionError.storageUnavailable }
            result.append(String(cString: text))
        }
    }

    func records<T: Decodable>(_ sql: String, _ values: [SQLValue] = [], as: T.Type) throws -> [T] {
        let statement = try prepare(sql, values)
        defer { sqlite3_finalize(statement) }
        var result: [T] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return result }
            guard status == SQLITE_ROW, let bytes = sqlite3_column_blob(statement, 0) else { throw SessionError.storageUnavailable }
            let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
            result.append(try JSONDecoder().decode(T.self, from: data))
        }
    }

    private func prepare(_ sql: String, _ values: [SQLValue]) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SessionError.storageUnavailable
        }
        do {
            for (offset, value) in values.enumerated() {
                let index = Int32(offset + 1)
                let status: Int32
                switch value {
                case .text(let text):
                    status = text.withCString { sqlite3_bind_text(statement, index, $0, -1, transient) }
                case .number(let number): status = sqlite3_bind_double(statement, index, number)
                case .blob(let data):
                    status = data.withUnsafeBytes { sqlite3_bind_blob(statement, index, $0.baseAddress, Int32($0.count), transient) }
                }
                guard status == SQLITE_OK else { throw SessionError.storageUnavailable }
            }
            return statement
        } catch { sqlite3_finalize(statement); throw error }
    }
}
