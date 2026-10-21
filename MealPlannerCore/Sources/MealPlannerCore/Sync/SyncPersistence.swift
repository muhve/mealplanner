import Foundation

private let syncTransactionKey = "ruokalista-sync-transaction-v1"
private struct SyncTransaction: Codable {
  var state: String
  var ledger: String
}
public func encodeLedger(_ ledger: SyncLedger) throws -> String {
  String(decoding: try JSONEncoder().encode(ledger), as: UTF8.self)
}
/// A write-ahead journal keeps the unchanged v1 document and separate sync ledger recoverable
/// together. A failed write must block further changes until recovery succeeds.
public func saveSyncSnapshot(store: DocumentStore, state: AppState, ledger: SyncLedger) throws {
  let transaction = SyncTransaction(state: try encodeState(state), ledger: try encodeLedger(ledger))
  try store.save(syncTransactionKey, String(decoding: JSONEncoder().encode(transaction), as: UTF8.self))
  try recoverSyncSnapshot(store: store)
}
public func recoverSyncSnapshot(store: DocumentStore) throws {
  guard let raw = try store.load(syncTransactionKey), !raw.isEmpty else { return }
  let transaction: SyncTransaction
  do { transaction = try JSONDecoder().decode(SyncTransaction.self, from: Data(raw.utf8)) }
  catch {
    // Preserve unreadable evidence before replacing it; do not guess which half committed.
    try store.save(syncTransactionKey + "-backup-" + UUID().uuidString, raw)
    throw CoreError("Synkronoinnin tallennusta ei voitu palauttaa.")
  }
  try store.save(documentKey, transaction.state)
  try store.save(syncDocumentKey, transaction.ledger)
  try store.save(syncTransactionKey, "")
}
/// Reconcile a known-good document only. Startup recovery must use
/// loadSyncStartupState so a recovery placeholder is never diffed as user data.
public func loadSyncLedger(store: DocumentStore, state: AppState, now: Double) throws -> SyncLedger {
  guard let raw = try store.load(syncDocumentKey) else { return bootstrapLedger(state: state, now: now) }
  do {
    let ledger = try JSONDecoder().decode(SyncLedger.self, from: Data(raw.utf8))
    // Reconcile a v1 document edited by an older app version while sync was absent.
    return recordLocalChange(ledger, old: compose(Array(ledger.records.values)), new: state, now: now)
  } catch {
    try store.save(syncDocumentKey + "-backup-" + UUID().uuidString, raw)
    return bootstrapLedger(state: state, now: now)
  }
}

public struct SyncStartupState {
  public let state: AppState
  public let ledger: SyncLedger
  public let photoCleanupBackups: [String]?
}

/// Inspect both documents before legacy loading can replace an unreadable v1
/// document with an empty state. Recovery is never interpreted as a user edit.
public func loadSyncStartupState(
  store: DocumentStore, now: Double, skipLegacy: Bool = false,
  legacyValue: () throws -> String?
) throws -> SyncStartupState {
  try recoverSyncSnapshot(store: store)
  let rawState = try store.load(documentKey)
  let decoded = decodeState(rawState, now: now)
  let rawLedger = try store.load(syncDocumentKey)
  let existingLedger = rawLedger.flatMap {
    try? JSONDecoder().decode(SyncLedger.self, from: Data($0.utf8))
  }
  let documentUsable = rawState != nil && decoded.unreadableRaw == nil
  if !documentUsable, let existingLedger {
    if let raw = decoded.unreadableRaw { try backupDocument(store: store, raw: raw, now: now) }
    let restored = compose(Array(existingLedger.records.values))
    // Preserve queue, field times and tombstones exactly; do not reconcile an
    // empty recovery placeholder against the healthy ledger.
    try saveSyncSnapshot(store: store, state: restored, ledger: existingLedger)
    return SyncStartupState(state: restored, ledger: existingLedger, photoCleanupBackups: nil)
  }
  if !documentUsable, let rawLedger {
    if let raw = decoded.unreadableRaw { try backupDocument(store: store, raw: raw, now: now) }
    try store.save(syncDocumentKey + "-backup-" + UUID().uuidString, rawLedger)
    let state = emptyState(now)
    let ledger = bootstrapLedger(state: state, now: now)
    try saveSyncSnapshot(store: store, state: state, ledger: ledger)
    return SyncStartupState(state: state, ledger: ledger, photoCleanupBackups: nil)
  }
  let startup = try loadStartupState(store: store, now: now, skipLegacy: skipLegacy,
                                     legacyValue: legacyValue)
  let ledger = try loadSyncLedger(store: store, state: startup.state, now: now)
  try saveSyncSnapshot(store: store, state: startup.state, ledger: ledger)
  return SyncStartupState(state: startup.state, ledger: ledger,
    photoCleanupBackups: rawLedger != nil && existingLedger == nil ? nil : startup.photoCleanupBackups)
}
