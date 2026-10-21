import XCTest
@testable import MealPlannerCore

final class SyncTests: XCTestCase {
  func fixture() -> AppState {
    let dish = Dish(id: "d", name: "Keitto", ingredients: [Ingredient(name: "Peruna", amount: 2, unit: "kg")], photo: "photo.jpg", instructions: "Keitä.")
    return AppState(version: 1, dishes: [dish], trip: Trip(createdAt: 1,
      meals: [Meal(id: "m", dishId: "d")], items: [:], extras: [Extra(id: "e", name: "Leipä", checked: true, have: false)]), history: [])
  }
  func testRoundTrip() throws {
    var state = fixture()
    let key = generatedItems(state)[0].key
    state = try updateItem(state, key, ItemPatch(checked: true))
    XCTAssertEqual(compose(Array(decompose(state).values)), state)
    state = try archiveTrip(state, 20, "a")
    XCTAssertEqual(compose(Array(decompose(state).values)), state)
  }
  func testFieldMergeAndTie() {
    let state = fixture(), base = bootstrapLedger(state: state, now: 1)
    var a = state, b = state
    a.dishes[0].name = "A"; b.dishes[0].instructions = "B"
    let left = recordLocalChange(base, old: state, new: a, now: 2)
    let right = recordLocalChange(base, old: state, new: b, now: 3)
    let merged = mergeRemote(left, incoming: Array(right.records.values)).ledger
    XCTAssertEqual(compose(Array(merged.records.values)).dishes[0].name, "A")
    XCTAssertEqual(compose(Array(merged.records.values)).dishes[0].instructions, "B")
    b.dishes[0].name = "Z"
    let newer = recordLocalChange(base, old: state, new: b, now: 3)
    XCTAssertEqual(compose(Array(mergeRemote(left, incoming: Array(newer.records.values)).ledger.records.values)).dishes[0].name, "Z")
    let tie = recordLocalChange(base, old: state, new: b, now: 2)
    XCTAssertEqual(mergeRemote(left, incoming: Array(tie.records.values)).ledger.records,
                   mergeRemote(tie, incoming: Array(left.records.values)).ledger.records)
  }
  func testDeletionAndArchiveAgainstConcurrentAdd() throws {
    let state = fixture(), base = bootstrapLedger(state: state, now: 1)
    let archived = try archiveTrip(state, 10, "a")
    let left = recordLocalChange(base, old: state, new: archived, now: 10)
    var edited = try addMeal(state, "d", "concurrent")
    edited.trip.meals[0].dishId = "other"
    let right = recordLocalChange(base, old: state, new: edited, now: 20)
    let merged = mergeRemote(left, incoming: Array(right.records.values)).ledger
    XCTAssertTrue(compose(Array(merged.records.values)).trip.meals.isEmpty)
    XCTAssertNotNil(merged.records["meal-m"]?.deletedAt)
    XCTAssertEqual(compose(Array(merged.records.values)).history.count, 1)
    // Identical ingredient keys can be checked again on the next trip.
    let next = try addMeal(archived, "d", "next")
    let checked = try updateItem(next, generatedItems(next)[0].key, ItemPatch(checked: true))
    let nextLedger = recordLocalChange(left, old: archived, new: checked, now: 30)
    XCTAssertTrue(readTrip(compose(Array(nextLedger.records.values))).items[0].checked)
  }
  func testChecksAndReset() throws {
    var state = fixture()
    state.dishes[0].ingredients.append(Ingredient(name: "Suola", amount: nil, unit: ""))
    let keys = generatedItems(state).map(\.key), base = bootstrapLedger(state: state, now: 1)
    let a = try updateItem(state, keys[0], ItemPatch(checked: true))
    let b = try updateItem(state, keys[1], ItemPatch(checked: true))
    let left = recordLocalChange(base, old: state, new: a, now: 2)
    let right = recordLocalChange(base, old: state, new: b, now: 2)
    let merged = mergeRemote(left, incoming: Array(right.records.values)).ledger
    XCTAssertEqual(readTrip(compose(Array(merged.records.values))).items.filter(\.checked).count, 2)
    XCTAssertEqual(mergeRemote(left, incoming: Array(left.records.values)).ledger.records, left.records)
    let reset = recordLocalChange(left, old: a, new: state, now: 3)
    XCTAssertFalse(readTrip(compose(Array(reset.records.values))).items[0].checked)
  }
  func testBootstrapPendingAndCoding() throws {
    let state = fixture(), local = bootstrapLedger(state: state, now: 1)
    XCTAssertEqual(local.pending, Set(local.records.keys))
    XCTAssertEqual(mergeRemote(local, incoming: []).ledger, local)
    var other = state; other.dishes[0].id = "other"; other.trip.meals = []; other.trip.extras = []
    let merged = mergeRemote(local, incoming: Array(bootstrapLedger(state: other, now: 2).records.values)).ledger
    XCTAssertEqual(compose(Array(merged.records.values)).dishes.count, 2)
    XCTAssertEqual(try JSONDecoder().decode(SyncLedger.self, from: JSONEncoder().encode(merged)), merged)
    var clean = rebaseBootstrap(local: local, server: [], now: 1); clean.pending = []
    var remote = clean.records["dish-d"]!; remote.fields["name"] = .string("Old")
    remote.modified["name"] = 0
    XCTAssertTrue(mergeRemote(clean, incoming: [remote]).ledger.pending.contains("dish-d"))
    let same = recordLocalChange(clean, old: state, new: state, now: 4)
    XCTAssertTrue(same.pending.isEmpty)
  }
  func testNamesAndOrder() throws {
    XCTAssertEqual(syncHash("hello"), "a430d84680aabd0b")
    for id in ["ä/../../", String(repeating: "a", count: 500), "", "normal_1-ID"] {
      let name = syncRecordName("dish", id)
      XCTAssertLessThanOrEqual(name.utf8.count, 255)
      XCTAssertTrue(name.utf8.allSatisfy { $0 < 128 })
      XCTAssertFalse(name.contains("/"))
    }
    var state = fixture(); state = try addMeal(state, "d", "second")
    let base = bootstrapLedger(state: state, now: 1)
    let next = removeMeal(state, "m")
    let ledger = recordLocalChange(base, old: state, new: next, now: 2)
    XCTAssertEqual(compose(Array(ledger.records.values)), next)
    XCTAssertEqual(ledger.records["meal-second"]?.fields["order"], base.records["meal-second"]?.fields["order"])
  }
}

private final class SyncFailingStore: DocumentStore {
  var values: [String: String] = [:]
  var writes = 0
  var failAt: Int?
  func load(_ key: String) throws -> String? { values[key] }
  func exists(_ key: String) throws -> Bool { values[key] != nil }
  func backupKeys() throws -> [String] { [] }
  func save(_ key: String, _ value: String) throws {
    writes += 1
    if writes == failAt { throw CoreError("disk") }
    values[key] = value
  }
}
extension SyncTests {
  func testSnapshotRecoveryAtEveryWriteBoundary() throws {
    for boundary in 1...4 {
      let store = SyncFailingStore()
      let old = emptyState(1), next = fixture()
      store.values[documentKey] = try encodeState(old)
      let ledger = bootstrapLedger(state: next, now: 2)
      store.failAt = boundary
      XCTAssertThrowsError(try saveSyncSnapshot(store: store, state: next, ledger: ledger))
      store.failAt = nil
      try recoverSyncSnapshot(store: store)
      let expected = boundary == 1 ? old : next
      XCTAssertEqual(decodeState(try store.load(documentKey), now: 0).state, expected)
      if boundary > 1 {
        XCTAssertEqual(try JSONDecoder().decode(SyncLedger.self, from: Data(store.values[syncDocumentKey]!.utf8)), ledger)
      }
    }
  }
  func testUnreadableLedgerBackedUpBeforeReplacement() throws {
    let store = SyncFailingStore(); store.values[syncDocumentKey] = "broken photo.jpg"
    store.failAt = 1
    XCTAssertThrowsError(try loadSyncLedger(store: store, state: fixture(), now: 1))
    XCTAssertEqual(store.values[syncDocumentKey], "broken photo.jpg")
    store.failAt = nil
    let ledger = try loadSyncLedger(store: store, state: fixture(), now: 1)
    XCTAssertEqual(ledger.pending, Set(ledger.records.keys))
    XCTAssertTrue(store.values.contains { $0.key.hasPrefix(syncDocumentKey + "-backup-") && $0.value == "broken photo.jpg" })
  }
  func testFreshInstallationAdoptsServerTrip() {
    let server = bootstrapLedger(state: fixture(), now: 2)
    let fresh = bootstrapLedger(state: emptyState(50), now: 50)
    let result = rebaseBootstrap(local: fresh, server: Array(server.records.values))
    XCTAssertEqual(compose(Array(result.records.values)), fixture())
  }
}
extension SyncTests {
  func testRemovingAndReaddingMealAllowsCheckingAgain() throws {
    let initial = fixture()
    let key = generatedItems(initial)[0].key
    let checked = try updateItem(initial, key, ItemPatch(checked: true))
    let base = bootstrapLedger(state: checked, now: 1)
    let removed = removeMeal(checked, "m")
    let removedLedger = recordLocalChange(base, old: checked, new: removed, now: 2)
    let readded = try addMeal(removed, "d", "new")
    let readdedLedger = recordLocalChange(removedLedger, old: removed, new: readded, now: 3)
    XCTAssertEqual(compose(Array(readdedLedger.records.values)), readded)
    let next = try updateItem(readded, key, ItemPatch(checked: true))
    let nextLedger = recordLocalChange(readdedLedger, old: readded, new: next, now: 4)
    XCTAssertEqual(compose(Array(nextLedger.records.values)), next)
  }
}
extension SyncTests {
  func testConcurrentMealCreationDoesNotEraseCheck() throws {
    var initial = fixture(); initial.trip.meals = []
    let base = bootstrapLedger(state: initial, now: 1)
    var a = try addMeal(initial, "d", "a")
    a = try updateItem(a, generatedItems(a)[0].key, ItemPatch(checked: true))
    let b = try addMeal(initial, "d", "b")
    let left = recordLocalChange(base, old: initial, new: a, now: 2)
    let right = recordLocalChange(base, old: initial, new: b, now: 3)
    let merged = mergeRemote(left, incoming: Array(right.records.values)).ledger
    XCTAssertTrue(readTrip(compose(Array(merged.records.values))).items[0].checked)
    XCTAssertEqual(mergeRemote(left, incoming: Array(right.records.values)).ledger.records,
                   mergeRemote(right, incoming: Array(left.records.values)).ledger.records)
  }
}
extension SyncTests {
  func testUploadAcknowledgesOnlyMatchingSnapshot() {
    let state = fixture(), base = bootstrapLedger(state: state, now: 1)
    let acknowledged = acknowledgeUploaded(base, saved: Array(base.records.values))
    XCTAssertTrue(acknowledged.pending.isEmpty)
    var next = state; next.dishes[0].instructions = "Uusi ohje"
    let edited = recordLocalChange(base, old: state, new: next, now: 2)
    XCTAssertTrue(acknowledgeUploaded(edited, saved: Array(base.records.values)).pending.contains("dish-d"))
  }
  func testUnknownPhysicalDeletionWinsOverOfflineEdit() {
    let deletion = recordServerDeletion(SyncLedger(), name: "dish-d", type: .dish, now: 2)
    var state = fixture(); state.dishes[0].name = "Later"
    let offline = bootstrapLedger(state: state, now: 10)
    let merged = mergeRemote(deletion, incoming: Array(offline.records.values)).ledger
    XCTAssertTrue(compose(Array(merged.records.values)).dishes.isEmpty)
    XCTAssertTrue(merged.pending.contains("dish-d"))
  }
}

extension SyncTests {
  private func secondDevice() -> AppState {
    var state = fixture()
    state.trip.createdAt = 100
    state.trip.meals[0].id = "second-meal"
    state.trip.extras = [Extra(id: "second-extra", name: "Kahvi", checked: false, have: true)]
    return state
  }
  func testBootstrapRebasesTwoPopulatedListsAndConvergesOnBothDevices() throws {
    let first = fixture(), second = secondDevice()
    let a = bootstrapLedger(state: first, now: 10)
    let b = bootstrapLedger(state: second, now: 200)
    let rebased = rebaseBootstrap(local: b, server: Array(a.records.values))
    let state = compose(Array(rebased.records.values))
    XCTAssertEqual(state.trip.createdAt, first.trip.createdAt)
    XCTAssertEqual(Set(state.trip.meals.map(\.id)), ["m", "second-meal"])
    XCTAssertEqual(Set(state.trip.extras.map(\.id)), ["e", "second-extra"])
    let onA = mergeRemote(a, incoming: Array(rebased.records.values)).ledger
    let onB = mergeRemote(rebased, incoming: Array(onA.records.values)).ledger
    XCTAssertEqual(compose(Array(onA.records.values)), state)
    XCTAssertEqual(compose(Array(onB.records.values)), state)
    XCTAssertFalse(rebased.needsBootstrap)
    XCTAssertNil(rebased.bootstrapServer)
    XCTAssertFalse(rebased.pending.contains("trip-current"))
    let oldItemNames = Set(decompose(second).values.filter { $0.type == .item }.map(\.name))
    for name in oldItemNames {
      XCTAssertNotNil(rebased.records[name]?.deletedAt)
      XCTAssertTrue(rebased.pending.contains(name))
    }
    for record in rebased.records.values where record.deletedAt == nil && [.meal, .extra, .item].contains(record.type) {
      XCTAssertEqual(record.fields["tripCreatedAt"], .double(first.trip.createdAt))
    }
    let restored = try JSONDecoder().decode(SyncLedger.self, from: JSONEncoder().encode(rebased))
    XCTAssertFalse(restored.needsBootstrap)
    XCTAssertEqual(compose(Array(restored.records.values)), state)
  }
  func testBootstrapWithNoServerKeepsLocalListAndWithEmptyLocalAdoptsServer() {
    let populated = bootstrapLedger(state: fixture(), now: 1)
    let first = rebaseBootstrap(local: populated, server: [])
    XCTAssertEqual(compose(Array(first.records.values)), fixture())
    XCTAssertEqual(first.pending, populated.pending)
    XCTAssertEqual(first.bootstrapTripPending, true)
    let empty = bootstrapLedger(state: emptyState(100), now: 100)
    let adopted = rebaseBootstrap(local: empty, server: Array(populated.records.values))
    XCTAssertEqual(compose(Array(adopted.records.values)), fixture())
  }
  func testBootstrapMergesSharedItemMarksWithoutErasingChecks() throws {
    for checkedLocal in [true, false] {
      var local = secondDevice(), server = fixture()
      let key = generatedItems(local)[0].key
      if checkedLocal { local = try updateItem(local, key, ItemPatch(checked: true)) }
      else { server = try updateItem(server, key, ItemPatch(checked: true)) }
      // A later bootstrap of default marks must not undo a genuine check.
      let rebased = rebaseBootstrap(local: bootstrapLedger(state: local, now: 200),
        server: Array(bootstrapLedger(state: server, now: 10).records.values))
      let trip = readTrip(compose(Array(rebased.records.values)))
      XCTAssertEqual(trip.items.count, 1)
      XCTAssertTrue(trip.items[0].checked)
      XCTAssertFalse(trip.items[0].have)
    }
  }
  func testBootstrapIncludesEditsMadeDuringFetchAndHonorsDeletion() throws {
    let old = secondDevice(), server = bootstrapLedger(state: fixture(), now: 10)
    var local = bootstrapLedger(state: old, now: 200)
    let edited = try addExtra(old, "Maito", "during-fetch")
    local = recordLocalChange(local, old: old, new: edited, now: 210)
    let rebased = rebaseBootstrap(local: local, server: Array(server.records.values))
    XCTAssertEqual(Set(compose(Array(rebased.records.values)).trip.extras.map(\.id)),
      ["e", "second-extra", "during-fetch"])
    var deleted = server.records["meal-m"]!
    deleted.deletedAt = 20
    let result = rebaseBootstrap(local: bootstrapLedger(state: fixture(), now: 300),
      server: [server.records["trip-current"]!, deleted])
    XCTAssertNotNil(result.records["meal-m"]?.deletedAt)
    XCTAssertTrue(compose(Array(result.records.values)).trip.meals.isEmpty)
  }
  func testItemMarkIsOneLWWChoiceIncludingUnmarkingAndTies() throws {
    let state = fixture(), key = generatedItems(state)[0].key
    let base = bootstrapLedger(state: state, now: 1)
    let checked = try updateItem(state, key, ItemPatch(checked: true))
    let have = try updateItem(state, key, ItemPatch(have: true))
    let a = recordLocalChange(base, old: state, new: checked, now: 2)
    let b = recordLocalChange(base, old: state, new: have, now: 3)
    let merged = mergeRemote(a, incoming: Array(b.records.values)).ledger
    let item = readTrip(compose(Array(merged.records.values))).items[0]
    XCTAssertFalse(item.checked)
    XCTAssertTrue(item.have)
    let tie = recordLocalChange(base, old: state, new: have, now: 2)
    XCTAssertEqual(mergeRemote(a, incoming: Array(tie.records.values)).ledger.records,
      mergeRemote(tie, incoming: Array(a.records.values)).ledger.records)
    let cleared = recordLocalChange(b, old: have, new: state, now: 4)
    let final = readTrip(compose(Array(mergeRemote(a, incoming: Array(cleared.records.values)).ledger.records.values))).items[0]
    XCTAssertFalse(final.checked)
    XCTAssertFalse(final.have)
    let record = decompose(have).values.first { $0.type == .item }!
    XCTAssertEqual(record.fields["mark"], .string("have"))
    XCTAssertNil(record.fields["checked"])
    XCTAssertNil(record.fields["have"])
  }
  func testExtraMarkIsOneLWWChoice() {
    var state = fixture(); state.trip.extras[0].checked = false
    let base = bootstrapLedger(state: state, now: 1)
    let aState = updateExtra(state, "e", Marks(checked: true))
    let bState = updateExtra(state, "e", Marks(have: true))
    let a = recordLocalChange(base, old: state, new: aState, now: 2)
    let b = recordLocalChange(base, old: state, new: bState, now: 3)
    let merged = mergeRemote(a, incoming: Array(b.records.values)).ledger
    let extra = compose(Array(merged.records.values)).trip.extras[0]
    XCTAssertFalse(extra.checked)
    XCTAssertTrue(extra.have)
    XCTAssertEqual(merged.records["extra-e"]?.modified["mark"], 3)
    XCTAssertNil(merged.records["extra-e"]?.modified["checked"])
  }
  func testQuantityEditAndResetMergeAsOneValue() throws {
    let state = fixture(), key = generatedItems(state)[0].key
    let edited = try updateItem(state, key, ItemPatch(amount: .some(.some(2))))
    let base = bootstrapLedger(state: edited, now: 1)
    let reset = try updateItem(edited, key, ItemPatch(resetAmount: true))
    let changed = try updateItem(edited, key, ItemPatch(amount: .some(.some(4))))
    let a = recordLocalChange(base, old: edited, new: reset, now: 2)
    let b = recordLocalChange(base, old: edited, new: changed, now: 3)
    let winner = compose(Array(mergeRemote(a, incoming: Array(b.records.values)).ledger.records.values)).trip.items[key]!
    XCTAssertTrue(winner.edited)
    XCTAssertEqual(winner.amount, 4)
    let laterReset = recordLocalChange(base, old: edited, new: reset, now: 4)
    let resetWinner = compose(Array(mergeRemote(b, incoming: Array(laterReset.records.values)).ledger.records.values))
    XCTAssertNil(resetWinner.trip.items[key]) // Normalization removes the default pair.
    let record = decompose(changed).values.first { $0.type == .item }!
    XCTAssertNotNil(record.fields["quantity"])
    XCTAssertNil(record.fields["edited"])
    XCTAssertNil(record.fields["amount"])
  }
  func testLegacyMarkAndQuantityFieldsMigrate() {
    var record = SyncRecord(type: .item, name: "item-legacy", fields: [
      "checked": .bool(true), "have": .bool(true), "edited": .bool(true), "amount": .double(2)
    ], modified: ["checked": 2, "have": 3, "edited": 4, "amount": 5])
    let result = mergeRemote(SyncLedger(), incoming: [record]).ledger.records[record.name]!
    XCTAssertEqual(result.fields["mark"], .string("have"))
    XCTAssertEqual(result.modified["mark"], 3)
    XCTAssertEqual(result.modified["quantity"], 5)
    XCTAssertNil(result.fields["checked"])
    record.fields = result.fields; record.modified = result.modified
    XCTAssertEqual(mergeRemote(SyncLedger(), incoming: [record]).ledger.records[record.name], result)
  }
}
extension SyncTests {
  func testBootstrapEmptyServerRaceRebasesOnWinningTrip() {
    let first = rebaseBootstrap(local: bootstrapLedger(state: fixture(), now: 10), server: [])
    let second = rebaseBootstrap(local: bootstrapLedger(state: secondDevice(), now: 200), server: [])
    XCTAssertEqual(second.bootstrapTripPending, true)
    // Simulate serverRecordChanged on the second device's first trip save.
    let rebased = rebaseBootstrap(local: second, server: [first.records["trip-current"]!])
    XCTAssertEqual(rebased.bootstrapTripPending, false)
    let onFirst = mergeRemote(first, incoming: Array(rebased.records.values)).ledger
    let onSecond = mergeRemote(rebased, incoming: Array(onFirst.records.values)).ledger
    XCTAssertEqual(Set(compose(Array(onFirst.records.values)).trip.meals.map(\.id)), ["m", "second-meal"])
    XCTAssertEqual(compose(Array(onFirst.records.values)), compose(Array(onSecond.records.values)))
  }
  func testBootstrapStagingSurvivesRestartWithoutPublishingServerTrip() throws {
    let state = secondDevice()
    var local = bootstrapLedger(state: state, now: 200)
    local.bootstrapServer = bootstrapLedger(state: fixture(), now: 10).records
    let restarted = try JSONDecoder().decode(SyncLedger.self, from: JSONEncoder().encode(local))
    XCTAssertTrue(restarted.needsBootstrap)
    XCTAssertEqual(compose(Array(restarted.records.values)), state)
    XCTAssertEqual(restarted.bootstrapServer, local.bootstrapServer)
    let completed = rebaseBootstrap(local: restarted, server: Array(restarted.bootstrapServer!.values))
    XCTAssertFalse(completed.needsBootstrap)
    XCTAssertEqual(compose(Array(completed.records.values)).trip.meals.count, 2)
  }
  func testExtraMarksTieDeterministicallyAndCanBeCleared() {
    var state = fixture(); state.trip.extras[0].checked = false
    let base = bootstrapLedger(state: state, now: 1)
    let checked = updateExtra(state, "e", Marks(checked: true))
    let have = updateExtra(state, "e", Marks(have: true))
    let a = recordLocalChange(base, old: state, new: checked, now: 2)
    let b = recordLocalChange(base, old: state, new: have, now: 2)
    XCTAssertEqual(mergeRemote(a, incoming: Array(b.records.values)).ledger.records,
      mergeRemote(b, incoming: Array(a.records.values)).ledger.records)
    let reset = recordLocalChange(b, old: have, new: state, now: 3)
    let final = compose(Array(mergeRemote(a, incoming: Array(reset.records.values)).ledger.records.values)).trip.extras[0]
    XCTAssertFalse(final.checked)
    XCTAssertFalse(final.have)
  }
}
extension SyncTests {
  func testBootstrapRelocationDoesNotDependOnTimestampOrEncodedTripOrder() {
    for localTime in [2.0, 100.0, 1000.0] {
      for serverTime in [1.0, 3.0, 200.0] {
        var local = secondDevice(), server = fixture()
        local.trip.createdAt = localTime; server.trip.createdAt = serverTime
        let rebased = rebaseBootstrap(local: bootstrapLedger(state: local, now: 10000),
          server: Array(bootstrapLedger(state: server, now: 1).records.values))
        let state = compose(Array(rebased.records.values))
        XCTAssertEqual(state.trip.createdAt, serverTime)
        XCTAssertEqual(Set(state.trip.meals.map(\.id)), ["m", "second-meal"])
        XCTAssertEqual(Set(state.trip.extras.map(\.id)), ["e", "second-extra"])
      }
    }
  }
}

extension SyncTests {
  func testRelocationBeatsPreviouslyUploadedMembershipOnBothDevices() throws {
    var aState = fixture(), bState = secondDevice()
    aState.trip.createdAt = 2; bState.trip.createdAt = 3
    let key = generatedItems(bState)[0].key
    bState = try updateItem(bState, key, ItemPatch(checked: true))
    let a = rebaseBootstrap(local: bootstrapLedger(state: aState, now: 100), server: [], now: 100)
    var b = rebaseBootstrap(local: bootstrapLedger(state: bState, now: 200), server: [], now: 200)
    for record in b.records.values where record.type == .item {
      b.systemFields[record.name] = "existing-server-version"
    }
    // B uploads its meals/items first, but A wins trip-current. A fetches B's
    // old membership before B receives the conflict and relocates those records.
    let earlyUploads = b.records.values.filter { $0.type != .trip }
    let aBeforeRelocation = mergeRemote(a, incoming: Array(earlyUploads)).ledger
    XCTAssertEqual(compose(Array(aBeforeRelocation.records.values)).trip.meals.count, 1)
    // Also exercise a clock behind the already uploaded timestamps.
    let relocated = rebaseBootstrap(local: b, server: [a.records["trip-current"]!], now: 1)
    let movedMeal = relocated.records["meal-second-meal"]!
    XCTAssertGreaterThan(movedMeal.modified["tripCreatedAt"]!, b.records["meal-second-meal"]!.modified.values.max()!)
    let onA = mergeRemote(aBeforeRelocation, incoming: Array(relocated.records.values)).ledger
    let onB = mergeRemote(relocated, incoming: Array(onA.records.values)).ledger
    for ledger in [onA, onB] {
      let state = compose(Array(ledger.records.values))
      XCTAssertEqual(state.trip.createdAt, 2)
      XCTAssertEqual(Set(state.trip.meals.map(\.id)), ["m", "second-meal"])
      XCTAssertEqual(Set(state.trip.extras.map(\.id)), ["e", "second-extra"])
      XCTAssertTrue(readTrip(state).items[0].checked)
    }
    XCTAssertEqual(compose(Array(onA.records.values)), compose(Array(onB.records.values)))
    for old in b.records.values where old.type == .item {
      let tombstone = relocated.records[old.name]!
      XCTAssertNotNil(tombstone.deletedAt)
      XCTAssertGreaterThan(tombstone.deletedAt!, old.modified.values.max()!)
      XCTAssertTrue(relocated.pending.contains(old.name))
      XCTAssertEqual(relocated.systemFields[old.name], "existing-server-version")
    }
  }
  func testRelocationUsesFreshNowAndBeatsObservedServerVersion() {
    var local = secondDevice(), server = fixture()
    local.trip.createdAt = 3; server.trip.createdAt = 2
    let ledger = bootstrapLedger(state: local, now: 100)
    var uploaded = ledger.records["meal-second-meal"]!
    uploaded.modified["tripCreatedAt"] = 500
    var incoming = Array(bootstrapLedger(state: server, now: 10).records.values)
    incoming.append(uploaded)
    for now in [1.0, 1000.0] {
      let relocated = rebaseBootstrap(local: ledger, server: incoming, now: now)
      let record = relocated.records[uploaded.name]!
      XCTAssertGreaterThan(record.modified["tripCreatedAt"]!, 500)
      XCTAssertGreaterThanOrEqual(record.modified["tripCreatedAt"]!, now)
      XCTAssertEqual(record.fields["tripCreatedAt"], .double(2))
      XCTAssertTrue(relocated.pending.contains(record.name))
    }
  }
}

extension SyncTests {
  func testBootstrapServerWinsForExistingDishesAndKeepsLocalAndServerOnlyDishes() {
    var localState = fixture(), serverState = fixture()
    localState.dishes.append(Dish(id: "local-only", name: "Salaatti", ingredients: [], instructions: "Sekoita."))
    serverState.dishes[0].name = "Uusi keitto"
    serverState.dishes[0].instructions = "Uusi ohje."
    serverState.dishes[0].photo = "new.jpg"
    serverState.dishes[0].ingredients = [Ingredient(name: "Porkkana", amount: 3, unit: "kg")]
    serverState.dishes.append(Dish(id: "server-only", name: "Pata", ingredients: []))
    let local = bootstrapLedger(state: localState, now: 1000)
    let server = bootstrapLedger(state: serverState, now: 10)
    let rebased = rebaseBootstrap(local: local, server: Array(server.records.values), now: 1100)
    XCTAssertEqual(rebased.records["dish-d"], server.records["dish-d"])
    XCTAssertFalse(rebased.pending.contains("dish-d"))
    XCTAssertEqual(rebased.records["dish-local-only"]?.fields, local.records["dish-local-only"]?.fields)
    XCTAssertEqual(rebased.records["dish-local-only"]?.modified["name"], 1100)
    XCTAssertTrue(rebased.pending.contains("dish-local-only"))
    XCTAssertEqual(rebased.records["dish-server-only"], server.records["dish-server-only"])
    let onServer = mergeRemote(server, incoming: Array(rebased.records.values)).ledger
    let onLocal = mergeRemote(rebased, incoming: Array(onServer.records.values)).ledger
    let result = compose(Array(onLocal.records.values))
    XCTAssertEqual(Set(result.dishes.map(\.id)), ["d", "local-only", "server-only"])
    XCTAssertEqual(result.dishes.first { $0.id == "d" }, serverState.dishes[0])
    XCTAssertEqual(compose(Array(onServer.records.values)), result)
  }
  func testBootstrapLocalFallbackOnlyFillsAbsentServerFieldsWithZeroTimestamps() {
    let local = bootstrapLedger(state: fixture(), now: 1000)
    var remote = bootstrapLedger(state: fixture(), now: 10).records["dish-d"]!
    remote.fields["name"] = .string("Server name")
    remote.fields["instructions"] = nil; remote.modified["instructions"] = nil
    // Explicit null is a server value, not an absent field.
    remote.fields["photo"] = .null
    let rebased = rebaseBootstrap(local: local, server: [remote], now: 1100)
    let record = rebased.records["dish-d"]!
    XCTAssertEqual(record.fields["name"], .string("Server name"))
    XCTAssertEqual(record.fields["photo"], .null)
    XCTAssertEqual(record.fields["instructions"], local.records["dish-d"]?.fields["instructions"])
    XCTAssertEqual(record.modified["instructions"], 0)
    XCTAssertTrue(rebased.pending.contains("dish-d"))
    remote.fields["instructions"] = .string("Server added instructions")
    remote.modified["instructions"] = 1
    let later = mergeRemote(rebased, incoming: [remote]).ledger
    XCTAssertEqual(later.records["dish-d"]?.fields["instructions"], remote.fields["instructions"])
  }
}
extension SyncTests {
  func testBootstrapFallbackAlsoPreservesAbsentGroupedItemFields() throws {
    var state = fixture()
    let key = generatedItems(state)[0].key
    state = try updateItem(state, key, ItemPatch(amount: .some(.some(4)), checked: true))
    let local = bootstrapLedger(state: state, now: 1000)
    let name = local.records.values.first { $0.type == .item }!.name
    var remote = local.records[name]!
    for field in ["mark", "quantity"] { remote.fields[field] = nil; remote.modified[field] = nil }
    let result = rebaseBootstrap(local: local, server: [remote], now: 1100)
    for field in ["mark", "quantity"] {
      XCTAssertEqual(result.records[name]?.fields[field], local.records[name]?.fields[field])
      XCTAssertEqual(result.records[name]?.modified[field], 0)
    }
    let item = compose(Array(result.records.values)).trip.items[key]!
    XCTAssertTrue(item.checked)
    XCTAssertTrue(item.edited)
    XCTAssertEqual(item.amount, 4)
  }
}
extension SyncTests {
  func testReaddedItemKeepsResetClockAgainstOlderRemoteCheck() throws {
    let initial = fixture()
    let key = generatedItems(initial)[0].key
    let base = bootstrapLedger(state: initial, now: 1)
    let checked = try updateItem(initial, key, ItemPatch(checked: true))
    let checkedLedger = recordLocalChange(base, old: initial, new: checked, now: 20)
    let stale = checkedLedger.records.values.filter { $0.type == .item }
    let removed = removeMeal(checked, "m")
    let removedLedger = recordLocalChange(checkedLedger, old: checked, new: removed, now: 30)
    let readded = try addMeal(removed, "d", "new")
    let readdedLedger = recordLocalChange(removedLedger, old: removed, new: readded, now: 40)
    let merged = mergeRemote(readdedLedger, incoming: Array(stale)).ledger
    XCTAssertFalse(readTrip(compose(Array(merged.records.values))).items[0].checked)
  }
}
