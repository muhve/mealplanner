import Foundation
import MealPlannerCore
import SQLite3

enum LegacyExpoStore {
  static func read() throws -> String? {
    // expo-sqlite kv-store default: Documents/SQLite/ExpoSQLiteStorage — verify on device.
    guard
      let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    else { throw CoreError("Vanhojen tietojen kansiota ei löytynyt.") }
    let path = documents.appendingPathComponent("SQLite/ExpoSQLiteStorage").path
    guard FileManager.default.fileExists(atPath: path) else { return nil }

    var handle: OpaquePointer?
    // No CREATE: never create a legacy database. READWRITE allows SQLite to recover
    // WAL sidecars when -shm is missing; this reader executes only SELECT statements.
    let result = sqlite3_open_v2(path, &handle, SQLITE_OPEN_READWRITE, nil)
    defer { if let handle { sqlite3_close(handle) } }
    guard result == SQLITE_OK, let database = handle else {
      throw failure(handle, operation: "open", code: result)
    }
    guard try hasStorageTable(database) else { return nil }

    let statement = try prepare("SELECT value FROM storage WHERE key = ?", database: database)
    defer { sqlite3_finalize(statement) }
    // Keep the bound text alive until sqlite3_step has completed (SQLITE_STATIC).
    return try documentKey.withCString { key in
      let bound = sqlite3_bind_text(statement, 1, key, -1, nil)
      guard bound == SQLITE_OK else { throw failure(database, operation: "bind", code: bound) }
      let step = sqlite3_step(statement)
      if step == SQLITE_DONE { return nil }
      guard step == SQLITE_ROW else { throw failure(database, operation: "step", code: step) }
      guard let value = sqlite3_column_text(statement, 0) else {
        throw CoreError("Vanhojen tietojen arvoa ei voitu lukea.")
      }
      return String(cString: value)
    }
  }

  private static func hasStorageTable(_ database: OpaquePointer) throws -> Bool {
    let statement = try prepare(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'storage' COLLATE NOCASE",
      database: database)
    defer { sqlite3_finalize(statement) }
    let result = sqlite3_step(statement)
    switch result {
    case SQLITE_ROW: return true
    case SQLITE_DONE: return false
    default: throw failure(database, operation: "schema step", code: result)
    }
  }

  private static func prepare(_ sql: String, database: OpaquePointer) throws -> OpaquePointer {
    var statement: OpaquePointer?
    let result = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
    guard result == SQLITE_OK, let prepared = statement else {
      if let statement { sqlite3_finalize(statement) }
      throw failure(database, operation: "prepare", code: result)
    }
    return prepared
  }

  private static func failure(_ database: OpaquePointer?, operation: String, code: Int32)
    -> LegacyReadFailure
  {
    let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite unavailable"
    return .sqlite(
      code: code,
      message: "Vanhojen tietojen lukeminen epäonnistui (\(operation), \(code)): \(message)")
  }
}
