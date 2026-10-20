import Foundation
import MealPlannerCore
import Observation

final class FileDocumentStore: DocumentStore {
  private let directory: URL
  init() throws {
    directory = try FileManager.default.url(
      for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
    ).appendingPathComponent("MealPlanner", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }
  private func url(_ key: String) -> URL {
    directory.appendingPathComponent(key).appendingPathExtension("json")
  }
  func backupKeys() throws -> [String] {
    try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
      .filter { $0.pathExtension == "json" }
      .map { $0.deletingPathExtension().lastPathComponent }
      .filter { $0.hasPrefix(documentKey + "-backup-") }
      .sorted()
  }
  func exists(_ key: String) throws -> Bool {
    FileManager.default.fileExists(atPath: url(key).path)
  }
  func load(_ key: String) throws -> String? {
    guard try exists(key) else { return nil }
    return try String(contentsOf: url(key), encoding: .utf8)
  }
  func save(_ key: String, _ value: String) throws {
    try Data(value.utf8).write(to: url(key), options: .atomic)
  }
}

@Observable @MainActor final class AppStore {
  private(set) var state: AppState?
  var loadFailed = false
  private var documents: FileDocumentStore?
  private var didCleanUpPhotos = false
  private(set) var ledger = SyncLedger()
  var syncStatus: SyncStatus = .syncing
  @ObservationIgnored private var sync: CloudSync?
  private var persistenceBlocked = false

  func activateSync() async {
    if persistenceBlocked { load() }
    guard state != nil, !persistenceBlocked else { return }
    if sync == nil { sync = CloudSync(store: self) }
    await sync?.activate()
  }
  func iCloudAccountChanged() async {
    if sync == nil { await activateSync() }
    else { await sync?.accountChanged() }
  }
  func saveLedger(_ next: SyncLedger) throws {
    guard let documents, !persistenceBlocked else { throw CoreError("Tallennus ei ole käytettävissä.") }
    do {
      try documents.save(syncDocumentKey, encodeLedger(next))
      ledger = next
    } catch { persistenceBlocked = true; throw error }
  }
  func applySync(_ next: SyncLedger) throws {
    guard let old = state, let documents, !persistenceBlocked else { throw CoreError("Tallennus ei ole käytettävissä.") }
    let composed = compose(Array(next.records.values))
    do { try saveSyncSnapshot(store: documents, state: composed, ledger: next) }
    catch { persistenceBlocked = true; throw error }
    ledger = next
    state = composed
    cleanPhotos(old: old, new: composed)
  }
  private func cleanPhotos(old: AppState, new: AppState) {
    let referenced = Set(new.dishes.compactMap(\.photo))
    for dish in old.dishes {
      if let file = photoFileToDelete(old: dish, new: new.dishes.first { $0.id == dish.id }),
         !referenced.contains(file) { PhotoStore().delete(file) }
    }
  }
  init() { load() }
  func load(skipLegacy: Bool = false) {
    sync?.pause()
    do {
      let documents = try FileDocumentStore()
      let now = Date().timeIntervalSince1970 * 1000
      let startup = try loadSyncStartupState(store: documents, now: now, skipLegacy: skipLegacy) {
        try LegacyExpoStore.read()
      }
      let loaded = startup.state
      let loadedLedger = startup.ledger
      self.documents = documents
      ledger = loadedLedger
      persistenceBlocked = false
      if !didCleanUpPhotos {
        // Once after the first successful load, before publishing state or opening forms.
        // Drafts abandoned by back navigation or termination are reclaimed next launch.
        // Recovery/migration launches and unreadable backups leave every photo intact.
        if let backups = startup.photoCleanupBackups {
          PhotoStore().cleanUp(state: loaded, backups: backups)
        }
        didCleanUpPhotos = true
      }
      state = loaded
      loadFailed = false
      Task { await activateSync() }
    } catch {
      loadFailed = true
    }
  }
  @discardableResult func change(_ operation: (AppState) throws -> AppState) -> String? {
    guard let state, let documents else { return "Tietojen lataaminen epäonnistui." }
    do {
      let next = try operation(state)
      guard !persistenceBlocked else { return "Tallennus epäonnistui. Avaa sovellus uudelleen." }
      let updated = recordLocalChange(ledger, old: state, new: next,
                                      now: Date().timeIntervalSince1970 * 1000)
      do { try saveSyncSnapshot(store: documents, state: next, ledger: updated) }
      catch { persistenceBlocked = true; throw error }
      ledger = updated
      self.state = next
      cleanPhotos(old: state, new: next)
      sync?.enqueue()
      return nil
    } catch {
      return error.localizedDescription
    }
  }
  func saveDishEdits(original: Dish?, edited: Dish) -> String? {
    change { try saveDish($0, edited, original: original) }
  }
  func id() -> String { UUID().uuidString }
  func item(_ key: String, _ patch: ItemPatch) -> String? {
    change { try updateItem($0, key, patch) }
  }
  func extra(_ id: String, _ patch: Marks) -> String? { change { updateExtra($0, id, patch) } }
}
