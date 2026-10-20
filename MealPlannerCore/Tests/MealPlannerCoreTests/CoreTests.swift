import XCTest

@testable import MealPlannerCore

final class MemoryStore: DocumentStore {
  var values: [String: String] = [:]
  var failSave = false
  func load(_ key: String) throws -> String? { values[key] }
  func exists(_ key: String) throws -> Bool { values[key] != nil }
  func save(_ key: String, _ value: String) throws {
    if failSave { throw CoreError("disk") }
    values[key] = value
  }
}
final class CoreTests: XCTestCase {
  let dish = Dish(
    id: "dish", name: "Puuro", ingredients: [Ingredient(name: "kaura", amount: 2, unit: "dl")])
  let key = "[\"kaura\",\"dl\"]"
  func setup() throws -> AppState { try addMeal(saveDish(emptyState(1), dish), "dish", "meal") }
  func r(_ n: String, _ a: String = "", _ u: String = "") -> FormRow {
    FormRow(name: n, amount: a, unit: u)
  }
  func m(_ c: Bool, _ h: Bool = false) -> Extra { Extra(id: "", name: "", checked: c, have: h) }
  func testReadsDecimalsAndSpaces() {
    for (s, n) in [
      ("1,5", 1.5), (" 2.25 ", 2.25), ("400", 400), (",5", 0.5), ("0,125", 0.125), ("1 000", 1000),
      ("1000000", 1_000_000), ("0.001", 0.001),
    ] { XCTAssertEqual(parseAmount(s), .value(n)) }
  }
  func testEmptyAmount() {
    for s in [nil, "", "  "] { XCTAssertEqual(parseAmount(s), .value(nil)) }
  }
  func testInvalidAmounts() {
    for s in [
      "abc", "0", "-1", "1,2,3", "1e5", "2kg", ".", "1000001", "0,0004", "0,0000001", "1.0000",
      "Infinity",
    ] { XCTAssertEqual(parseAmount(s), .invalid, s) }
  }
  func testFormatsAmounts() {
    XCTAssertEqual(formatAmount(1.5), "1,5")
    XCTAssertEqual(formatAmount(400), "400")
    XCTAssertEqual(formatAmount(0.001), "0,001")
    XCTAssertEqual(formatAmount(nil), "")
  }
  func testDropsBlankRows() throws {
    XCTAssertEqual(
      try toDishBody(" Puuro ", [r(" kaura ", "2,5", " dl "), r(""), r("suola")]),
      DishBody(
        name: "Puuro",
        ingredients: [
          Ingredient(name: "kaura", amount: 2.5, unit: "dl"),
          Ingredient(name: "suola", amount: nil, unit: ""),
        ]))
  }
  func testFirstBadRowNumber() {
    XCTAssertThrowsError(try toDishBody("X", [r("a"), r(""), r("", "2", "dl")])) {
      XCTAssertEqual($0.localizedDescription, "Ainesosa 3: anna nimi.")
    }
    XCTAssertThrowsError(try toDishBody("X", [r("a", "paljon")])) {
      XCTAssertTrue($0.localizedDescription.hasPrefix("Ainesosa 1: määrän"))
    }
  }
  func testWhitespaceAndRowCap() throws {
    XCTAssertEqual(try toDishBody("Kana  curry", [r("kookos  maito")]).name, "Kana curry")
    XCTAssertEqual(try toDishBody("X", [r("kookos  maito")]).ingredients[0].name, "kookos maito")
    let rows = (0...100).map { r("a\($0)") }
    XCTAssertThrowsError(try toDishBody("X", rows))
    XCTAssertEqual(try toDishBody("X", Array(rows.dropFirst()) + [r("")]).ingredients.count, 100)
  }
  func testTextValidation() throws {
    XCTAssertThrowsError(try toDishBody("  ", [r("a", "x")])) {
      XCTAssertEqual($0.localizedDescription, "Anna ruokalajille nimi.")
    }
    XCTAssertThrowsError(try toDishBody(String(repeating: "a", count: 101), []))
    XCTAssertThrowsError(try toDishBody("X", [r(String(repeating: "a", count: 101))]))
    XCTAssertThrowsError(try toDishBody("X", [r("a", "", String(repeating: "u", count: 21))]))
    XCTAssertNoThrow(
      try toDishBody(
        "X", [r(String(repeating: "a", count: 100), "", String(repeating: "u", count: 20))]))
  }
  func testIngredientSummary() {
    XCTAssertEqual(
      ingredientSummary([
        Ingredient(name: "lohi", amount: 0.4, unit: "kg"),
        Ingredient(name: "suola", amount: nil, unit: ""),
      ]), "0,4 kg lohi, suola")
  }
  func testCounts() {
    XCTAssertEqual(
      tripCounts([m(false), m(true), m(false, true)], [m(false), m(true), m(false, true)]),
      Counts(left: 2, bought: 2, have: 2, toBuy: 4))
  }
  func testEmptyCounts() {
    XCTAssertEqual(tripCounts([Extra](), [Extra]()), Counts(left: 0, bought: 0, have: 0, toBuy: 0))
  }
  func testStatusVariants() {
    for (l, h, t, s) in [
      (2, 0, 3, "2 / 3 jäljellä"), (2, 4, 3, "2 / 3 jäljellä · kotona 4"),
      (0, 1, 3, "Kaikki ostettu! 🎉 · kotona 1"), (0, 2, 0, "Kaikki on jo kotona"),
    ] { XCTAssertEqual(statusText(Counts(left: l, bought: 0, have: h, toBuy: t)), s) }
    XCTAssertNil(statusText(Counts(left: 0, bought: 0, have: 0, toBuy: 0)))
  }
  func testStableOrderingAndOldSnapshot() throws {
    var a = m(true)
    var b = m(false, true)
    var c = m(false)
    var d = m(false)
    a.name = "a"
    b.name = "b"
    c.name = "c"
    d.name = "d"
    XCTAssertEqual(historyOrder([a, b, c, d]).map(\.name), ["c", "d", "a", "b"])
    XCTAssertEqual(uncheckedFirst([a, b, c, d]).map(\.name), ["b", "c", "d", "a"])
    let old = try JSONDecoder().decode(
      ArchivedExtra.self, from: Data(#"{"name":"old","checked":true}"#.utf8))
    XCTAssertEqual(historyOrder([old]).first?.name, "old")
  }
  func testHaveWins() {
    XCTAssertEqual(markClause(m(false), Marks(checked: true, have: true)), m(false, true))
    XCTAssertEqual(markClause(m(false, true), Marks(checked: false)), m(false, true))
    XCTAssertEqual(markClause(m(true), Marks(checked: false)), m(false))
  }
  func testHelsinkiDateBoundary() {
    XCTAssertEqual(
      formatDay(1_792_360_800_000, timeZone: TimeZone(identifier: "Europe/Helsinki")!), "19.10.2026"
    )
  }
  func testFoldAndKeys() {
    XCTAssertEqual(fold("ÄITI"), "äiti")
    XCTAssertEqual(itemKey("Ma\u{0308}ito", "DL"), itemKey("Mäito", "dl"))
    XCTAssertNotEqual(itemKey("a,b", "c"), itemKey("a", "b,c"))
  }
  func testAggregation() {
    let rows = [
      IngredientRow(Ingredient(name: "Kerma", amount: 0.1, unit: "dl"), dishId: "1", dish: "A"),
      IngredientRow(Ingredient(name: "kerma", amount: 0.2, unit: "DL"), dishId: "1", dish: "A"),
      IngredientRow(Ingredient(name: "kerma", amount: nil, unit: "dl"), dishId: "2", dish: "B"),
      IngredientRow(Ingredient(name: "kerma", amount: 1, unit: "l"), dishId: "1", dish: "A"),
      IngredientRow(Ingredient(name: "suola", amount: nil, unit: ""), dishId: "1", dish: "A"),
    ]
    let items = aggregateIngredients(rows)
    XCTAssertEqual(items.count, 3)
    XCTAssertEqual(items[0].amount, 0.3)
    XCTAssertEqual(items[0].dishes, ["A", "B"])
    XCTAssertEqual(items[1].amount, 1)
    XCTAssertNil(items[2].amount)
  }
  func testApplyStatePinsNull() {
    let g = aggregateIngredients([
      IngredientRow(Ingredient(name: "kerma", amount: 2, unit: "dl"), dishId: "d", dish: "A")
    ])
    let result = applyItemState(
      g,
      [
        g[0].key: ItemState(edited: true, amount: nil, removed: true, checked: false, have: false),
        "stale": ItemState(edited: false, amount: nil, removed: false, checked: true, have: false),
      ])
    XCTAssertTrue(result.items.isEmpty)
    XCTAssertNil(result.removed[0].amount)
    XCTAssertEqual(result.removed[0].recipeAmount, 2)
    XCTAssertFalse(applyItemState(g, [:]).items[0].checked)
  }
  var suggestions: [Dish] {
    [
      Dish(
        id: "a", name: "A",
        ingredients: [
          Ingredient(name: " Peruna ", amount: nil, unit: " KPL "),
          Ingredient(name: "peruna", amount: 1, unit: "kg"),
          Ingredient(name: "peruna", amount: 2, unit: "kpl"),
          Ingredient(name: "perunajauho", amount: 1, unit: "dl"),
          Ingredient(name: "bataattiperuna", amount: nil, unit: ""),
        ])
    ]
  }
  func testVisibleSuggestions() {
    let p = Suggestion(name: "peruna", unit: "kpl", uses: 3)
    let j = Suggestion(name: "perunajauho", unit: "dl", uses: 1)
    XCTAssertEqual(visibleSuggestions(("per", [p, j]), "per"), [p, j])
    XCTAssertTrue(visibleSuggestions(("pe", [p]), "per").isEmpty)
    XCTAssertTrue(visibleSuggestions(nil, "per").isEmpty)
    XCTAssertTrue(visibleSuggestions(("peruna", [p]), "peruna").isEmpty)
    XCTAssertEqual(visibleSuggestions(("Peruna", [p]), "Peruna"), [p])
    XCTAssertEqual(visibleSuggestions(("perun", [p]), "perun"), [p])
  }
  func testCommonIngredientNameAndUnit() {
    XCTAssertEqual(
      knownIngredients(suggestions)[0],
      KnownIngredient(key: "peruna", name: "peruna", unit: "kpl", uses: 3))
    XCTAssertEqual(
      suggestIngredients(suggestions, " PER ")[0], Suggestion(name: "peruna", unit: "kpl", uses: 3))
  }
  func testSuggestionOrderingAndLimit() {
    XCTAssertEqual(
      suggestIngredients(suggestions, "per").map(\.name),
      ["peruna", "perunajauho", "bataattiperuna"])
    XCTAssertEqual(suggestIngredients(suggestions, "", limit: 1).count, 1)
    XCTAssertTrue(suggestIngredients(suggestions, "zz").isEmpty)
    let ties = [
      Dish(
        id: "b", name: "B",
        ingredients: [
          Ingredient(name: "Äiti", amount: nil, unit: "DL"),
          Ingredient(name: "A\u{0308}iti", amount: nil, unit: "l"),
        ])
    ]
    XCTAssertEqual(knownIngredients(ties)[0].uses, 2)
    XCTAssertEqual(knownIngredients(ties)[0].unit, "dl")
  }
  func testUnitSuggestions() {
    func units(_ q: String) -> [Suggestion] {
      visibleSuggestions(
        (
          q,
          UNITS.filter { $0.contains(q) || q.isEmpty }.map {
            Suggestion(name: $0, unit: "", uses: 0)
          }
        ), q)
    }
    XCTAssertTrue(units("dl").isEmpty)
    XCTAssertTrue(units("kg").isEmpty)
    XCTAssertEqual(units("nip").map(\.name), ["nippu"])
    XCTAssertGreaterThan(units("").count, 1)
  }
  func testRepeatedMeals() throws {
    let s = try setup()
    let next = try addMeal(s, "dish", "second")
    XCTAssertEqual(readTrip(next).items[0].amount, 4)
    XCTAssertEqual(readTrip(removeMeal(next, "second")).items[0].amount, 2)
    XCTAssertEqual(readTrip(s).items[0].amount, 2)
    XCTAssertEqual(try addMeal(s, "missing", "x"), s)
  }
  func testMutuallyExclusiveMarks() throws {
    var s = try updateItem(setup(), key, ItemPatch(checked: true))
    s = try updateItem(s, key, ItemPatch(have: true))
    XCTAssertFalse(readTrip(s).items[0].checked)
    XCTAssertTrue(readTrip(s).items[0].have)
    s = try updateItem(s, key, ItemPatch(checked: true))
    XCTAssertFalse(readTrip(s).items[0].have)
    s = try updateItem(s, key, ItemPatch(checked: false))
    XCTAssertTrue(s.trip.items.isEmpty)
    s = try addExtra(s, "kahvi", "e")
    s = updateExtra(s, "e", Marks(checked: true, have: true))
    XCTAssertEqual(s.trip.extras[0], Extra(id: "e", name: "kahvi", checked: false, have: true))
    s = updateExtra(s, "e", Marks(checked: true))
    XCTAssertFalse(s.trip.extras[0].have)
    XCTAssertTrue(removeExtra(s, "e").trip.extras.isEmpty)
  }
  func testEditResetRemoveRestore() throws {
    var s = try updateItem(setup(), key, ItemPatch(amount: .some(3)))
    s = try addMeal(s, "dish", "2")
    XCTAssertEqual(readTrip(s).items[0].amount, 3)
    XCTAssertEqual(readTrip(s).items[0].recipeAmount, 4)
    s = try updateItem(s, key, ItemPatch(resetAmount: true))
    XCTAssertEqual(readTrip(s).items[0].amount, 4)
    XCTAssertTrue(s.trip.items.isEmpty)
    s = try updateItem(s, key, ItemPatch(have: true))
    s = try updateItem(s, key, ItemPatch(removed: true))
    XCTAssertTrue(readTrip(s).items.isEmpty)
    XCTAssertFalse(readTrip(s).removed[0].have)
    s = try updateItem(s, key, ItemPatch(removed: false))
    XCTAssertEqual(readTrip(s).items.count, 1)
    XCTAssertTrue(s.trip.items.isEmpty)
    s = try updateItem(s, key, ItemPatch(amount: .some(nil)))
    XCTAssertNil(readTrip(s).items[0].amount)
    XCTAssertThrowsError(try updateItem(s, key, ItemPatch(amount: .some(0))))
  }
  func testStaleStateCleanup() throws {
    var s = try updateItem(setup(), key, ItemPatch(checked: true))
    s = removeMeal(s, "meal")
    XCTAssertTrue(s.trip.items.isEmpty)
    s = try addMeal(s, "dish", "2")
    XCTAssertFalse(readTrip(s).items[0].checked)
    s = try updateItem(s, key, ItemPatch(checked: true))
    s = try saveDish(s, Dish(id: "dish", name: "Puuro", ingredients: []))
    XCTAssertTrue(s.trip.items.isEmpty)
  }
  func testDeletePreservesHistory() throws {
    var s = try archiveTrip(setup(), 10, "old")
    s = try addMeal(s, "dish", "new")
    s = deleteDish(s, "dish")
    XCTAssertTrue(s.dishes.isEmpty)
    XCTAssertTrue(s.trip.meals.isEmpty)
    XCTAssertEqual(s.history[0].meals, ["Puuro"])
  }
  func testArchiveSnapshotAndCap() throws {
    var s = try setup()
    s = try addExtra(s, " kahvi ", "e")
    s = updateExtra(s, "e", Marks(have: true))
    s = try updateItem(s, key, ItemPatch(amount: .some(3), checked: true))
    s = try archiveTrip(s, 10, "archive")
    XCTAssertEqual(
      s.history[0],
      ArchivedTrip(
        id: "archive", createdAt: 1, archivedAt: 10, meals: ["Puuro"],
        items: [ArchivedItem(name: "kaura", amount: 3, unit: "dl", checked: true, have: false)],
        extras: [ArchivedExtra(name: "kahvi", checked: false, have: true)]))
    XCTAssertEqual(s.trip, emptyTrip(10))
    s = try saveDish(s, Dish(id: "dish", name: "Changed", ingredients: dish.ingredients))
    XCTAssertEqual(s.history[0].meals, ["Puuro"])
    for n in 11..<215 {
      s = try addExtra(s, "x", "e\(n)")
      s = try archiveTrip(s, Double(n), "h\(n)")
    }
    XCTAssertEqual(s.history.count, 200)
    XCTAssertEqual(s.history.first?.archivedAt, 214)
    XCTAssertEqual(s.history.last?.archivedAt, 15)
    let removed = try archiveTrip(updateItem(setup(), key, ItemPatch(removed: true)), 2, "r")
    XCTAssertTrue(removed.history[0].items.isEmpty)
  }
  func testLimitsAndEmptyArchive() throws {
    XCTAssertThrowsError(try archiveTrip(emptyState(0), 1, "x"))
    var s = emptyState(0)
    for i in 0..<200 { s = try addExtra(s, "x", "\(i)") }
    XCTAssertThrowsError(try addExtra(s, "x", "extra"))
    XCTAssertThrowsError(try addExtra(emptyState(0), String(repeating: "x", count: 101), "x"))
    XCTAssertThrowsError(try addExtra(emptyState(0), "  ", "x"))
    s = try saveDish(emptyState(0), dish)
    for i in 0..<100 { s = try addMeal(s, "dish", "\(i)") }
    XCTAssertThrowsError(try addMeal(s, "dish", "extra"))
  }
  func testDecodeRoundTripAndBroken() throws {
    let s = try setup()
    XCTAssertEqual(decodeState(try encodeState(s), now: 1).state, s)
    for raw in [nil, "", "{broken", "{}", "null", #"{"version":2}"#] {
      XCTAssertTrue(decodeState(raw, now: 1).state.dishes.isEmpty)
    }
  }
  func testRecoveryNotRequestedForValidOrMissing() throws {
    XCTAssertNil(decodeState(nil, now: 1).unreadableRaw)
    XCTAssertNil(decodeState(try encodeState(setup()), now: 1).unreadableRaw)
  }
  func testExactUnreadableBytes() throws {
    var json = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(encodeState(setup()).utf8)) as? [String: Any])
    var trip = json["trip"] as! [String: Any]
    trip["items"] = [key: NSNull()]
    json["trip"] = trip
    let bad = String(decoding: try JSONSerialization.data(withJSONObject: json), as: UTF8.self)
    for raw in ["", "  {broken\n", "{}", "null", #"{"version":2}"#, bad] {
      let d = decodeState(raw, now: 1)
      XCTAssertEqual(d.unreadableRaw, raw)
      XCTAssertTrue(d.state.dishes.isEmpty)
      XCTAssertTrue(d.state.trip.items.isEmpty)
    }
  }
  func testBackupCollision() throws {
    let store = MemoryStore()
    let raw = "  {unreadable\n"
    try store.save(documentKey, raw)
    try backupDocument(store: store, raw: try XCTUnwrap(store.load(documentKey)), now: 12345)
    try backupDocument(store: store, raw: "another broken document", now: 12345)
    try store.save(documentKey, #"{"replacement":true}"#)
    XCTAssertEqual(store.values["ruokalista-v1-backup-12345"], raw)
    XCTAssertEqual(store.values["ruokalista-v1-backup-12346"], "another broken document")
    XCTAssertEqual(try store.load(documentKey), #"{"replacement":true}"#)
  }
  func testExactTypeScriptJSONShape() throws {
    let raw =
      #"{"version":1,"dishes":[{"id":"d","name":"Suola","ingredients":[{"name":"suola","amount":null,"unit":""}]}],"trip":{"createdAt":1792360800000,"meals":[{"id":"m","dishId":"d"}],"items":{"[\"suola\",\"\"]":{"edited":true,"amount":null,"removed":false,"checked":false,"have":true}},"extras":[{"id":"e","name":"kahvi","checked":true,"have":false}]},"history":[{"id":"h","createdAt":1,"archivedAt":2,"meals":["Suola"],"items":[{"name":"suola","amount":null,"unit":"","checked":false,"have":false}],"extras":[{"name":"kahvi","checked":true,"have":false}]}]}"#
    let decoded = decodeState(raw, now: 0)
    XCTAssertNil(decoded.unreadableRaw)
    let before = try JSONSerialization.jsonObject(with: Data(raw.utf8)) as! NSDictionary
    let after =
      try JSONSerialization.jsonObject(with: Data(encodeState(decoded.state).utf8)) as! NSDictionary
    XCTAssertEqual(before, after)
  }
  func testMigrationOnceAndExistingWins() throws {
    let store = MemoryStore()
    let raw = try encodeState(setup())
    XCTAssertTrue(try legacyMigration(store: store, now: 5) { raw })
    XCTAssertEqual(try loadState(store: store, now: 5), try setup())
    let saved = try store.load(documentKey)
    XCTAssertFalse(
      try legacyMigration(store: store, now: 6) {
        XCTFail("must not read legacy")
        return nil
      })
    XCTAssertEqual(try store.load(documentKey), saved)
  }
  func testThrowingLegacyReaderLeavesStoreUntouchedAndCanRetry() throws {
    let store = MemoryStore()
    store.values["ruokalista-v1-backup-1"] = "previous backup"
    let before = store.values
    let failure = CoreError("SQLite read failed")
    XCTAssertThrowsError(
      try legacyMigration(store: store, now: 10) { throw failure }
    ) { error in
      XCTAssertEqual(error as? CoreError, failure)
    }
    XCTAssertEqual(store.values, before)
    XCTAssertFalse(try store.exists(documentKey))

    let raw = try encodeState(setup())
    XCTAssertTrue(try legacyMigration(store: store, now: 11) { raw })
    XCTAssertEqual(try loadState(store: store, now: 11), try setup())
    XCTAssertEqual(store.values["ruokalista-v1-backup-1"], "previous backup")
  }
  func testMigrationCorruptionAndMissing() throws {
    let store = MemoryStore()
    XCTAssertFalse(try legacyMigration(store: store, now: 10) { nil })
    XCTAssertFalse(try store.exists(documentKey))
    XCTAssertTrue(try legacyMigration(store: store, now: 10) { "bad bytes" })
    XCTAssertEqual(store.values["ruokalista-v1-backup-10"], "bad bytes")
    XCTAssertEqual(try loadState(store: store, now: 11), emptyState(10))
  }
  func testBackupFailureDoesNotOverwrite() throws {
    let store = MemoryStore()
    store.values[documentKey] = "broken"
    store.failSave = true
    XCTAssertThrowsError(try loadState(store: store, now: 1))
    XCTAssertEqual(store.values[documentKey], "broken")
    store.values.removeValue(forKey: documentKey)
    XCTAssertThrowsError(try legacyMigration(store: store, now: 1) { "legacy" })
  }
  func testRecoveryOnlyOnce() throws {
    let store = MemoryStore()
    store.values[documentKey] = "broken"
    _ = try loadState(store: store, now: 1)
    _ = try loadState(store: store, now: 2)
    XCTAssertEqual(store.values.count, 2)
  }

  func testNormalizeDropsMalformedStaleItemsAndDefaultsOldMarks() throws {
    var root = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(encodeState(setup()).utf8)) as? [String: Any])
    var trip = root["trip"] as! [String: Any]
    trip["items"] = ["stale": NSNull(), key: ["checked": true]] as [String: Any]
    trip["extras"] = [["id": "e", "name": "kahvi", "checked": true]]
    root["trip"] = trip
    let raw = String(decoding: try JSONSerialization.data(withJSONObject: root), as: UTF8.self)
    let decoded = decodeState(raw, now: 1)
    XCTAssertNil(decoded.unreadableRaw)
    XCTAssertEqual(decoded.state.trip.items.count, 1)
    XCTAssertTrue(readTrip(decoded.state).items[0].checked)
    XCTAssertFalse(decoded.state.trip.extras[0].have)
    root["dishes"] = "invalid"
    let bad = String(decoding: try JSONSerialization.data(withJSONObject: root), as: UTF8.self)
    XCTAssertEqual(decodeState(bad, now: 1).unreadableRaw, bad)
  }
  func testSavedIngredientSpellingExcludesEditedRecipe() throws {
    var s = try saveDish(
      emptyState(1),
      Dish(id: "a", name: "A", ingredients: [Ingredient(name: "Peruna", amount: nil, unit: "kpl")]))
    s = try saveDish(
      s, Dish(id: "b", name: "B", ingredients: [Ingredient(name: "peruna", amount: 1, unit: "kg")]))
    XCTAssertEqual(s.dishes[1].ingredients[0].name, "Peruna")
    s = try saveDish(
      s, Dish(id: "a", name: "A", ingredients: [Ingredient(name: "PERUNA", amount: nil, unit: "")]))
    XCTAssertEqual(s.dishes[0].ingredients[0].name, "Peruna")
    let only = try saveDish(
      emptyState(1),
      Dish(id: "a", name: "A", ingredients: [Ingredient(name: "peruna", amount: nil, unit: "")]))
    let renamed = try saveDish(
      only,
      Dish(id: "a", name: "A", ingredients: [Ingredient(name: "PERUNA", amount: nil, unit: "")]))
    XCTAssertEqual(renamed.dishes[0].ingredients[0].name, "PERUNA")
  }
  func testFinnishCollationAndTrailingDecimal() {
    XCTAssertEqual(
      ["Öljy", "Äiti", "Åland", "Zebra", "Ananas"].sorted(by: finnishLess),
      ["Ananas", "Zebra", "Åland", "Äiti", "Öljy"])
    XCTAssertFalse(finnishLess("é", "e"))
    XCTAssertFalse(finnishLess("e", "é"))
    XCTAssertEqual(parseAmount("1."), .value(1))
  }

  func testLegacySQLiteClassification() {
    for code: Int32 in [11, 26, 11 | (1 << 8), 26 | (2 << 8)] {
      XCTAssertEqual(LegacyReadFailure.sqlite(code: code, message: "broken"), .unreadableDatabase)
    }
    for code: Int32 in [5, 6, 10, 14, 10 | (3 << 8)] {
      XCTAssertEqual(LegacyReadFailure.sqlite(code: code, message: "retry"), .retryable("retry"))
    }
  }
  func testCorruptLegacyDatabaseStartsEmptyAndDoesNotRetry() throws {
    let store = MemoryStore()
    store.values["unrelated"] = "keep"
    XCTAssertTrue(
      try legacyMigration(store: store, now: 10) { throw LegacyReadFailure.unreadableDatabase })
    XCTAssertEqual(try loadState(store: store, now: 11), emptyState(10))
    XCTAssertEqual(store.values.count, 2)
    XCTAssertEqual(store.values["unrelated"], "keep")
    XCTAssertFalse(
      try legacyMigration(store: store, now: 12) {
        XCTFail("must not retry")
        return nil
      })
  }
  func testRetryableLegacyFailureDoesNotSave() throws {
    let store = MemoryStore()
    XCTAssertThrowsError(
      try legacyMigration(store: store, now: 10) { throw LegacyReadFailure.retryable("busy") }
    ) {
      XCTAssertEqual($0 as? LegacyReadFailure, .retryable("busy"))
    }
    XCTAssertTrue(store.values.isEmpty)
  }
  func testSkipLegacyEstablishesEmptyDocumentAndPreservesExistingSwiftState() throws {
    let store = MemoryStore()
    XCTAssertEqual(try startWithoutLegacyData(store: store, now: 10), emptyState(10))
    XCTAssertFalse(
      try legacyMigration(store: store, now: 11) {
        XCTFail("import skipped permanently")
        return nil
      })
    try store.save(documentKey, encodeState(setup()))
    XCTAssertEqual(try startWithoutLegacyData(store: store, now: 12), try setup())
    store.values[documentKey] = "bad Swift JSON"
    XCTAssertEqual(try startWithoutLegacyData(store: store, now: 13), emptyState(13))
    XCTAssertEqual(store.values["ruokalista-v1-backup-13"], "bad Swift JSON")
  }
  func testSkipAndCorruptRecoveryDoNotPublishWhenSaveFails() {
    let store = MemoryStore()
    store.failSave = true
    XCTAssertThrowsError(try startWithoutLegacyData(store: store, now: 1))
    XCTAssertThrowsError(
      try legacyMigration(store: store, now: 1) { throw LegacyReadFailure.unreadableDatabase })
    XCTAssertTrue(store.values.isEmpty)
  }
}
