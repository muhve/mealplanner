import XCTest
@testable import MealPlannerCore

final class PhotoRecoveryTests: XCTestCase {
  func testRawBackupsProtectPhotosAnywhereEvenWhenMalformed() {
    var state = emptyState(1)
    state.dishes = [Dish(id: "d", name: "A", ingredients: [], photo: "live.jpg")]
    let backups = [
      #"{"otherField":"backup-only.jpg"}"#,
      #"broken {"photo": "malformed.jpg" unfinished"#
    ]
    XCTAssertEqual(
      orphanedPhotos(state: state,
                     files: ["live.jpg", "backup-only.jpg", "malformed.jpg", "unreferenced.jpg"],
                     backups: backups),
      ["unreferenced.jpg"])
  }

  func testNormalStartupLoadsAllRawBackupsOnly() throws {
    let store = MemoryStore()
    store.values[documentKey] = try encodeState(emptyState(1))
    store.values[documentKey + "-backup-1"] = "broken photo.jpg"
    store.values[documentKey + "-backup-2"] = "another.jpg"
    store.values["unrelated"] = "not-a-backup.jpg"
    let startup = try loadStartupState(store: store, now: 2) {
      XCTFail("existing document must bypass legacy")
      return nil
    }
    XCTAssertEqual(startup.state, emptyState(1))
    XCTAssertEqual(startup.photoCleanupBackups, ["broken photo.jpg", "another.jpg"])
  }

  func testRecoverySkipsCleanupThenNextLaunchProtectsBackupPhotos() throws {
    for skipLegacy in [false, true] {
      let store = MemoryStore()
      store.values[documentKey] = "broken recovered.jpg"
      let recovered = try loadStartupState(store: store, now: 2, skipLegacy: skipLegacy) { nil }
      XCTAssertEqual(recovered.state, emptyState(2))
      XCTAssertNil(recovered.photoCleanupBackups)
      XCTAssertEqual(store.values[documentKey + "-backup-2"], "broken recovered.jpg")
      let next = try loadStartupState(store: store, now: 3) { nil }
      let backups = try XCTUnwrap(next.photoCleanupBackups)
      XCTAssertEqual(orphanedPhotos(state: next.state,
                                   files: ["recovered.jpg", "orphan.jpg"], backups: backups),
                     ["orphan.jpg"])
    }
  }

  func testEveryCompletedMigrationSkipsCleanup() throws {
    let valid = try encodeState(emptyState(1))
    for raw in [valid, "broken legacy.jpg"] {
      let store = MemoryStore()
      let startup = try loadStartupState(store: store, now: 2) { raw }
      XCTAssertNil(startup.photoCleanupBackups)
      XCTAssertNotNil(store.values[documentKey])
    }
    let store = MemoryStore()
    let startup = try loadStartupState(store: store, now: 2) {
      throw LegacyReadFailure.unreadableDatabase
    }
    XCTAssertNil(startup.photoCleanupBackups)
  }

  func testFreshInstallCanCleanUpAndExplicitSkipDoesNotReadLegacy() throws {
    let fresh = try loadStartupState(store: MemoryStore(), now: 1) { nil }
    XCTAssertEqual(fresh.photoCleanupBackups, [])
    let skipped = try loadStartupState(store: MemoryStore(), now: 1, skipLegacy: true) {
      XCTFail("legacy explicitly skipped")
      return "legacy"
    }
    XCTAssertEqual(skipped.photoCleanupBackups, [])
  }

  func testBackupListingOrReadingFailureSkipsCleanupWithoutBlockingLoad() throws {
    let store = MemoryStore()
    store.values[documentKey] = try encodeState(emptyState(1))
    store.failBackupKeys = true
    XCTAssertNil(try loadStartupState(store: store, now: 2) { nil }.photoCleanupBackups)
    store.failBackupKeys = false
    let backup = documentKey + "-backup-1"
    store.values[backup] = "protected.jpg"
    store.unreadableBackup = backup
    XCTAssertNil(try loadStartupState(store: store, now: 2) { nil }.photoCleanupBackups)
  }

  func testFailedRecoveryDoesNotPublishStartupStateOrReplaceDocument() {
    let store = MemoryStore()
    store.values[documentKey] = "broken protected.jpg"
    store.failSave = true
    XCTAssertThrowsError(try loadStartupState(store: store, now: 2) { nil })
    XCTAssertEqual(store.values[documentKey], "broken protected.jpg")
  }
}
