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
  init() { load() }
  func load(skipLegacy: Bool = false) {
    do {
      let documents = try FileDocumentStore()
      let now = Date().timeIntervalSince1970 * 1000
      let startup = try loadStartupState(store: documents, now: now, skipLegacy: skipLegacy) {
        try LegacyExpoStore.read()
      }
      let loaded = startup.state
      self.documents = documents
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
    } catch {
      loadFailed = true
    }
  }
  @discardableResult func change(_ operation: (AppState) throws -> AppState) -> String? {
    guard let state, let documents else { return "Tietojen lataaminen epäonnistui." }
    do {
      let next = try operation(state)
      try documents.save(documentKey, encodeState(next))
      self.state = next
      // Files remain intact if validation or document persistence fails.
      let referenced = Set(next.dishes.compactMap(\.photo))
      for old in state.dishes {
        let new = next.dishes.first { $0.id == old.id }
        if let file = photoFileToDelete(old: old, new: new), !referenced.contains(file) {
          PhotoStore().delete(file)
        }
      }
      return nil
    } catch {
      return error.localizedDescription
    }
  }
  func id() -> String { UUID().uuidString }
  func item(_ key: String, _ patch: ItemPatch) -> String? {
    change { try updateItem($0, key, patch) }
  }
  func extra(_ id: String, _ patch: Marks) -> String? { change { updateExtra($0, id, patch) } }
}
