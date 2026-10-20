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
  init() { load() }
  func load(skipLegacy: Bool = false) {
    do {
      let documents = try FileDocumentStore()
      let now = Date().timeIntervalSince1970 * 1000
      let loaded: AppState
      if skipLegacy {
        loaded = try startWithoutLegacyData(store: documents, now: now)
      } else {
        try legacyMigration(store: documents, now: now) { try LegacyExpoStore.read() }
        loaded = try loadState(store: documents, now: now)
      }
      // Establish the Swift document even on a fresh install, making migration one-time.
      try documents.save(documentKey, encodeState(loaded))
      self.documents = documents
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
