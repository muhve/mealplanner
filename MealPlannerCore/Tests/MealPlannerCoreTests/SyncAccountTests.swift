import XCTest
@testable import MealPlannerCore

final class SyncAccountTests: XCTestCase {
  private func fixture() -> AppState {
    var state = emptyState(1)
    state.dishes = [Dish(id: "d", name: "Keitto", ingredients: [], photo: "old.jpg", instructions: "Vanha ohje")]
    return state
  }
  private func synced(_ state: AppState, account: String = "A", now: Double = 10) -> SyncLedger {
    var ledger = rebaseBootstrap(local: bootstrapLedger(state: state, now: now), server: [], now: now)
    ledger.accountIdentifier = account
    ledger.bootstrapTripPending = false
    ledger.pending = []
    ledger.lastSync = now
    ledger.serverState = "saved-engine-state"
    ledger.systemFields["dish-d"] = "saved-system-fields"
    return ledger
  }
  func testSameAccountResumesAndUploadsEditsMadeWhileSignedOut() throws {
    let state = fixture(), server = synced(state)
    let signedOut = prepareSyncAccount(server, accountIdentifier: nil, now: 20)
    XCTAssertEqual(signedOut, server)
    var edited = state; edited.dishes[0].instructions = "Muokattu ilman iCloudia"
    let offline = recordLocalChange(signedOut, old: state, new: edited, now: 30)
    let resumed = prepareSyncAccount(offline, accountIdentifier: "A", now: 40)
    XCTAssertEqual(resumed, offline)
    XCTAssertFalse(resumed.needsBootstrap)
    let merged = mergeRemote(resumed, incoming: Array(server.records.values)).ledger
    XCTAssertEqual(compose(Array(merged.records.values)), edited)
    XCTAssertTrue(merged.pending.contains("dish-d"))
    let onServer = mergeRemote(server, incoming: Array(merged.records.values)).ledger
    XCTAssertEqual(compose(Array(onServer.records.values)), edited)
    XCTAssertFalse(acknowledgeUploaded(merged, saved: Array(onServer.records.values)).pending.contains("dish-d"))
    // Even a full rebase must respect real field clocks rather than force server values.
    var forcedBootstrap = resumed; forcedBootstrap.bootstrapCompleted = false
    let rebased = rebaseBootstrap(local: forcedBootstrap, server: Array(server.records.values), now: 50)
    XCTAssertEqual(rebased.records["dish-d"]?.modified["instructions"], 30)
    XCTAssertEqual(compose(Array(rebased.records.values)), edited)
    XCTAssertTrue(rebased.pending.contains("dish-d"))
    XCTAssertEqual(try JSONDecoder().decode(SyncLedger.self, from: JSONEncoder().encode(resumed)), resumed)
  }
  func testInitialFetchKeepsRealLocalEditsAndDefersUntouchedFields() {
    let state = fixture()
    let initial = bootstrapLedger(state: state, now: 1000)
    XCTAssertTrue(initial.records["dish-d"]!.modified.isEmpty)
    var edited = state; edited.dishes[0].name = "Oma nimi"
    let duringFetch = recordLocalChange(initial, old: state, new: edited, now: 1001)
    var serverState = state
    serverState.dishes[0].instructions = "Uusi palvelimen ohje"
    serverState.dishes[0].photo = "remote.jpg"
    let server = synced(serverState, now: 20)
    let rebased = rebaseBootstrap(local: duringFetch, server: Array(server.records.values), now: 1100)
    let result = compose(Array(rebased.records.values)).dishes[0]
    XCTAssertEqual(result.name, "Oma nimi")
    XCTAssertEqual(result.instructions, "Uusi palvelimen ohje")
    XCTAssertEqual(result.photo, "remote.jpg")
    XCTAssertEqual(rebased.records["dish-d"]?.modified["name"], 1001)
    XCTAssertEqual(rebased.records["dish-d"]?.modified["instructions"], 20)
    XCTAssertTrue(rebased.pending.contains("dish-d"))
    let onServer = mergeRemote(server, incoming: Array(rebased.records.values)).ledger
    XCTAssertEqual(compose(Array(onServer.records.values)).dishes[0], result)
    // Clearing pending is safe only if every local winning value has been superseded.
    var newerServer = server
    newerServer.records["dish-d"]?.fields["name"] = .string("Uudempi palvelimen nimi")
    newerServer.records["dish-d"]?.modified["name"] = 2000
    let superseded = rebaseBootstrap(local: duringFetch, server: Array(newerServer.records.values), now: 2100)
    XCTAssertEqual(superseded.records["dish-d"], newerServer.records["dish-d"])
    XCTAssertFalse(superseded.pending.contains("dish-d"))
  }
  func testDifferentOrFirstKnownAccountClearsOldClocksAndBootstrapsRetainedData() {
    for oldAccount: String? in ["A", nil] {
      let state = fixture()
      var local = synced(state)
      local.accountIdentifier = oldAccount
      var edited = state; edited.dishes[0].instructions = "Vanhan tilin muutos"
      edited.dishes.append(Dish(id: "local-only", name: "Salaatti", ingredients: []))
      local = recordLocalChange(local, old: state, new: edited, now: 1000)
      local.records["dish-deleted"] = SyncRecord(type: .dish, name: "dish-deleted", deletedAt: 1001)
      local.pending.insert("dish-deleted")
      let switched = prepareSyncAccount(local, accountIdentifier: "B", now: 2000)
      XCTAssertTrue(switched.needsBootstrap)
      XCTAssertEqual(switched.accountIdentifier, "B")
      XCTAssertNil(switched.serverState)
      XCTAssertNil(switched.lastSync)
      XCTAssertTrue(switched.systemFields.isEmpty)
      XCTAssertTrue(switched.records.values.allSatisfy { $0.modified.isEmpty && $0.deletedAt == nil })
      XCTAssertNil(switched.records["dish-deleted"])
      XCTAssertEqual(compose(Array(switched.records.values)), edited)
      XCTAssertEqual(switched.pending, Set(switched.records.keys))
      var serverState = state; serverState.dishes[0].instructions = "Uuden tilin ohje"
      serverState.dishes.append(Dish(id: "deleted", name: "Uuden tilin ruoka", ingredients: []))
      let server = synced(serverState, account: "B", now: 10)
      let rebased = rebaseBootstrap(local: switched, server: Array(server.records.values), now: 2100)
      XCTAssertEqual(rebased.records["dish-d"], server.records["dish-d"])
      XCTAssertFalse(rebased.pending.contains("dish-d"))
      XCTAssertTrue(rebased.pending.contains("dish-local-only"))
      XCTAssertEqual(rebased.records["dish-local-only"]?.modified["name"], 2100)
      XCTAssertEqual(rebased.records["dish-deleted"], server.records["dish-deleted"])
    }
  }
  func testTimestampedFallbackFieldKeepsItsClockDuringBootstrap() {
    let state = fixture()
    var edited = state; edited.dishes[0].instructions = "Oma uusi ohje"
    let local = recordLocalChange(bootstrapLedger(state: state, now: 1), old: state, new: edited, now: 30)
    var remote = synced(state).records["dish-d"]!
    remote.fields["instructions"] = nil; remote.modified["instructions"] = nil
    let result = rebaseBootstrap(local: local, server: [remote], now: 100)
    XCTAssertEqual(result.records["dish-d"]?.fields["instructions"], .string("Oma uusi ohje"))
    XCTAssertEqual(result.records["dish-d"]?.modified["instructions"], 30)
    XCTAssertTrue(result.pending.contains("dish-d"))
  }
}
extension SyncAccountTests {
  func testTimestampedTripChangeDuringInitialFetchUsesLWWAndStaysPending() throws {
    var state = fixture()
    state.trip.extras = [Extra(id: "e", name: "Leipä", checked: false, have: false)]
    let initial = bootstrapLedger(state: state, now: 10)
    let archived = try archiveTrip(state, 30, "archive")
    let local = recordLocalChange(initial, old: state, new: archived, now: 30)
    let server = synced(state, now: 20)
    let result = rebaseBootstrap(local: local, server: Array(server.records.values), now: 40)
    XCTAssertEqual(result.records["trip-current"]?.modified["createdAt"], 30)
    XCTAssertEqual(compose(Array(result.records.values)).trip.createdAt, 30)
    XCTAssertTrue(result.pending.contains("trip-current"))
    XCTAssertEqual(compose(Array(result.records.values)).history.count, 1)
    XCTAssertNotNil(result.records["extra-e"]?.deletedAt)
  }
}
extension SyncAccountTests {
  func testRealTripEditAfterEmptyServerFetchIsNotMistakenForInitialTripRace() throws {
    var state = fixture()
    state.trip.extras = [Extra(id: "e", name: "Leipä", checked: false, have: false)]
    let importing = rebaseBootstrap(local: bootstrapLedger(state: state, now: 10), server: [], now: 10)
    XCTAssertEqual(importing.bootstrapTripPending, true)
    let archived = try archiveTrip(state, 30, "archive")
    let edited = recordLocalChange(importing, old: state, new: archived, now: 30)
    var serverTrip = importing.records["trip-current"]!
    serverTrip.fields["createdAt"] = .double(2)
    serverTrip.modified["createdAt"] = 20
    let result = rebaseBootstrap(local: edited, server: [serverTrip], now: 40)
    XCTAssertEqual(result.records["trip-current"]?.fields["createdAt"], .double(30))
    XCTAssertEqual(result.records["trip-current"]?.modified["createdAt"], 30)
    XCTAssertTrue(result.pending.contains("trip-current"))
    XCTAssertEqual(compose(Array(result.records.values)).history.count, 1)
  }
}
