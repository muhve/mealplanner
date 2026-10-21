import XCTest
@testable import MealPlannerCore

final class SyncRecoveryTests: XCTestCase {
  private func fixture() throws -> AppState {
    let dish = Dish(id: "d", name: "Keitto", ingredients: [Ingredient(name: "Peruna", amount: 2, unit: "kg")],
                    photo: "saved.jpg", instructions: "Keitä.")
    let state = try addMeal(saveDish(emptyState(1), dish), "d", "m")
    return try updateItem(state, generatedItems(state)[0].key, ItemPatch(checked: true))
  }
  func testCorruptOrMissingDocumentRestoresLedgerWithoutNewDeletionsOrPendingWork() throws {
    for rawDocument: String? in ["broken saved.jpg", nil] {
      for skipLegacy in [false, true] {
        let store = MemoryStore(), expected = try fixture()
        var ledger = bootstrapLedger(state: expected, now: 10)
        ledger.pending = ["dish-d"]
        ledger.bootstrapCompleted = true
        ledger.lastSync = 20
        ledger.serverState = "existing-engine-state"
        ledger.systemFields["dish-d"] = "existing-system-fields"
        // Existing real deletions must also survive unchanged.
        ledger.records["dish-old"] = SyncRecord(type: .dish, name: "dish-old", deletedAt: 5)
        store.values[documentKey] = rawDocument
        store.values[syncDocumentKey] = try encodeLedger(ledger)
        let startup = try loadSyncStartupState(store: store, now: 100, skipLegacy: skipLegacy) {
          XCTFail("A healthy ledger must take precedence over legacy import")
          return nil
        }
        XCTAssertEqual(startup.state, expected)
        XCTAssertEqual(startup.ledger, ledger)
        XCTAssertEqual(startup.ledger.pending, ["dish-d"])
        XCTAssertEqual(decodeState(store.values[documentKey], now: 0).state, expected)
        XCTAssertNil(startup.photoCleanupBackups)
        if let rawDocument { XCTAssertEqual(store.values[documentKey + "-backup-100"], rawDocument) }
        let healthyDevice = mergeRemote(ledger, incoming: Array(startup.ledger.records.values)).ledger
        XCTAssertEqual(compose(Array(healthyDevice.records.values)), expected)
        let relaunched = try loadSyncStartupState(store: store, now: 200) { nil }
        XCTAssertEqual(relaunched.state, expected)
        XCTAssertEqual(relaunched.ledger, ledger)
      }
    }
  }
  func testBothUnusableDocumentsStartEmptyAndBootstrapFromServerWithoutTombstones() throws {
    for rawDocument: String? in ["broken saved.jpg", nil] {
      let store = MemoryStore()
      store.values[documentKey] = rawDocument
      store.values[syncDocumentKey] = "broken ledger"
      let startup = try loadSyncStartupState(store: store, now: 100) {
        XCTFail("An existing corrupt sync store must recover through bootstrap")
        return nil
      }
      XCTAssertEqual(startup.state, emptyState(100))
      XCTAssertTrue(startup.ledger.needsBootstrap)
      XCTAssertNil(startup.ledger.serverState)
      XCTAssertNil(startup.ledger.lastSync)
      XCTAssertTrue(startup.ledger.systemFields.isEmpty)
      XCTAssertTrue(startup.ledger.records.values.allSatisfy { $0.deletedAt == nil })
      XCTAssertNil(startup.photoCleanupBackups)
      if let rawDocument { XCTAssertEqual(store.values[documentKey + "-backup-100"], rawDocument) }
      XCTAssertTrue(store.values.contains { $0.key.hasPrefix(syncDocumentKey + "-backup-") && $0.value == "broken ledger" })
      let serverState = try fixture()
      let server = bootstrapLedger(state: serverState, now: 10)
      let restored = rebaseBootstrap(local: startup.ledger, server: Array(server.records.values), now: 110)
      XCTAssertEqual(compose(Array(restored.records.values)), serverState)
      let healthyDevice = mergeRemote(server, incoming: Array(restored.records.values)).ledger
      XCTAssertEqual(compose(Array(healthyDevice.records.values)), serverState)
      let relaunched = try loadSyncStartupState(store: store, now: 200) { nil }
      XCTAssertTrue(relaunched.ledger.needsBootstrap)
      XCTAssertTrue(relaunched.ledger.records.values.allSatisfy { $0.deletedAt == nil })
    }
  }
  func testRecoveryBackupOrSaveFailureDoesNotReplaceEitherSource() throws {
    for rawLedger in [try encodeLedger(bootstrapLedger(state: fixture(), now: 10)), "broken ledger"] {
      let store = MemoryStore()
      store.values[documentKey] = "broken saved.jpg"
      store.values[syncDocumentKey] = rawLedger
      store.failSave = true
      XCTAssertThrowsError(try loadSyncStartupState(store: store, now: 100) { nil })
      XCTAssertEqual(store.values[documentKey], "broken saved.jpg")
      XCTAssertEqual(store.values[syncDocumentKey], rawLedger)
    }
  }
  func testValidDocumentStillReconcilesRealLocalDeletions() throws {
    let store = MemoryStore(), state = try fixture()
    let ledger = bootstrapLedger(state: state, now: 10)
    let deleted = deleteDish(state, "d")
    store.values[documentKey] = try encodeState(deleted)
    store.values[syncDocumentKey] = try encodeLedger(ledger)
    let startup = try loadSyncStartupState(store: store, now: 100) { nil }
    XCTAssertEqual(startup.state, deleted)
    XCTAssertEqual(startup.ledger.records["dish-d"]?.deletedAt, 100)
    XCTAssertTrue(startup.ledger.pending.contains("dish-d"))
  }
  func testValidDocumentWithCorruptLedgerKeepsDataAndRestartsBootstrap() throws {
    let store = MemoryStore(), state = try fixture()
    store.values[documentKey] = try encodeState(state)
    store.values[syncDocumentKey] = "broken ledger"
    let startup = try loadSyncStartupState(store: store, now: 100) { nil }
    XCTAssertEqual(startup.state, state)
    XCTAssertEqual(compose(Array(startup.ledger.records.values)), state)
    XCTAssertTrue(startup.ledger.needsBootstrap)
    XCTAssertTrue(startup.ledger.records.values.allSatisfy { $0.deletedAt == nil })
    XCTAssertNil(startup.photoCleanupBackups)
  }
}
