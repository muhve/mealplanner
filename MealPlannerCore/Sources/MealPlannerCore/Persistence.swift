import Foundation

public let documentKey = "ruokalista-v1"
public protocol DocumentStore {
  func load(_ key: String) throws -> String?
  func save(_ key: String, _ value: String) throws
  func exists(_ key: String) throws -> Bool
  func backupKeys() throws -> [String]
}
public func encodeState(_ state: AppState) throws -> String {
  String(decoding: try JSONEncoder().encode(state), as: UTF8.self)
}
public func backupDocument(store: DocumentStore, raw: String, now: Double) throws {
  var timestamp = Int64(now)
  while try store.exists("\(documentKey)-backup-\(timestamp)") { timestamp += 1 }
  try store.save("\(documentKey)-backup-\(timestamp)", raw)
}
public func loadState(store: DocumentStore, now: Double) throws -> AppState {
  let decoded = decodeState(try store.load(documentKey), now: now)
  if let raw = decoded.unreadableRaw {
    try backupDocument(store: store, raw: raw, now: now)
    try store.save(documentKey, encodeState(decoded.state))
  }
  return decoded.state
}
@discardableResult public func legacyMigration(
  store: DocumentStore, now: Double, legacyValue: () throws -> String?
) throws -> Bool {
  guard try !store.exists(documentKey) else { return false }
  let legacy: String?
  do { legacy = try legacyValue() } catch LegacyReadFailure.unreadableDatabase {
    // The untouched legacy database remains the backup; only establish the Swift document.
    _ = try startWithoutLegacyData(store: store, now: now)
    return true
  }
  guard let raw = legacy else { return false }
  let decoded = decodeState(raw, now: now)
  if let bad = decoded.unreadableRaw { try backupDocument(store: store, raw: bad, now: now) }
  try store.save(documentKey, encodeState(decoded.state))
  return true
}

/// SQLite primary result codes are stable; extended codes carry the primary code in the low byte.
public enum LegacyReadFailure: Error, Equatable, Sendable {
  case unreadableDatabase
  case retryable(String)

  public static func sqlite(code: Int32, message: String) -> LegacyReadFailure {
    switch code & 0xff {
    case 11, 26: return .unreadableDatabase  // SQLITE_CORRUPT, SQLITE_NOTADB
    default: return .retryable(message)
    }
  }
}

/// Explicitly bypass legacy import without discarding an existing Swift document.
public func startWithoutLegacyData(store: DocumentStore, now: Double) throws -> AppState {
  if try store.exists(documentKey) { return try loadState(store: store, now: now) }
  let state = emptyState(now)
  try store.save(documentKey, encodeState(state))
  return state
}


/// A nil backup list means startup photo cleanup must be skipped.
public struct StartupState {
  public let state: AppState
  public let photoCleanupBackups: [String]?
}

public func loadStartupState(
  store: DocumentStore, now: Double, skipLegacy: Bool = false,
  legacyValue: () throws -> String?
) throws -> StartupState {
  let before = try? store.backupKeys()
  let migrated: Bool
  let state: AppState
  if skipLegacy {
    migrated = false
    state = try startWithoutLegacyData(store: store, now: now)
  } else {
    migrated = try legacyMigration(store: store, now: now, legacyValue: legacyValue)
    state = try loadState(store: store, now: now)
  }
  // Establish the Swift document even on a fresh install, making migration one-time.
  try store.save(documentKey, encodeState(state))
  guard !migrated, let before, let after = try? store.backupKeys(),
        Set(before) == Set(after) else {
    return StartupState(state: state, photoCleanupBackups: nil)
  }
  // Failed enumeration or reading must never turn an unknown backup into deleted images.
  do {
    let backups = try after.map { key -> String in
      guard let raw = try store.load(key) else { throw CoreError("Varmuuskopiota ei voitu lukea.") }
      return raw
    }
    return StartupState(state: state, photoCleanupBackups: backups)
  } catch {
    return StartupState(state: state, photoCleanupBackups: nil)
  }
}
