import XCTest
@testable import MealPlannerCore

final class DishEditsTests: XCTestCase {
  private func dish() -> Dish {
    Dish(id: "d", name: "Keitto", ingredients: [Ingredient(name: "Peruna", amount: 2, unit: "kg")],
         photo: "old.jpg", instructions: "Keitä.")
  }
  func testUntouchedFieldsKeepRemoteEditsIncludingReplacedPhoto() throws {
    let original = dish()
    var remote = original
    remote.instructions = "Paista."
    remote.photo = "remote.jpg"
    remote.ingredients = [Ingredient(name: "Porkkana", amount: 3, unit: "kg")]
    var edited = original; edited.name = "Uusi nimi"
    let merged = try applyDishEdits(current: remote, original: original, edited: edited)
    XCTAssertEqual(merged.name, "Uusi nimi")
    XCTAssertEqual(merged.instructions, remote.instructions)
    XCTAssertEqual(merged.photo, "remote.jpg")
    XCTAssertEqual(merged.ingredients, remote.ingredients)
    XCTAssertEqual(try applyDishEdits(current: remote, original: original, edited: original), remote)
  }
  func testEachChangedFieldIsAppliedAsAUnit() throws {
    let original = dish()
    var remote = original
    remote.name = "Toinen nimi"; remote.photo = "remote.jpg"; remote.instructions = "Toinen ohje"
    var edited = original
    edited.ingredients = [Ingredient(name: "Suola", amount: nil, unit: "")]
    var merged = try applyDishEdits(current: remote, original: original, edited: edited)
    XCTAssertEqual(merged.ingredients, edited.ingredients)
    XCTAssertEqual(merged.name, remote.name)
    XCTAssertEqual(merged.instructions, remote.instructions)
    XCTAssertEqual(merged.photo, remote.photo)
    edited.instructions = nil; edited.photo = nil
    merged = try applyDishEdits(current: remote, original: original, edited: edited)
    XCTAssertNil(merged.instructions)
    XCTAssertNil(merged.photo)
    XCTAssertEqual(merged.name, remote.name)
  }
  func testDeletedDishCannotBeRecreatedByStaleForm() throws {
    let original = dish()
    var edited = original; edited.name = "Muokattu"
    XCTAssertThrowsError(try applyDishEdits(current: nil, original: original, edited: edited)) {
      XCTAssertEqual($0.localizedDescription, "Ruokalaji on poistettu toisella laitteella.")
    }
    let state = emptyState(1)
    XCTAssertThrowsError(try saveDish(state, edited, original: original)) {
      XCTAssertEqual($0.localizedDescription, "Ruokalaji on poistettu toisella laitteella.")
    }
    XCTAssertTrue(state.dishes.isEmpty)
  }
  func testSavingFormOnlyTimestampsChangedFields() throws {
    let original = dish()
    var remote = original
    remote.photo = "remote.jpg"
    // Remote fields must survive even when normal validation would trim them.
    remote.instructions = "  Uusi ohje.\n "
    var state = emptyState(1); state.dishes = [remote]
    let before = bootstrapLedger(state: state, now: 10)
    var edited = original; edited.name = "Muokattu"
    let saved = try saveDish(state, edited, original: original)
    XCTAssertEqual(saved.dishes[0].instructions, remote.instructions)
    XCTAssertEqual(saved.dishes[0].photo, remote.photo)
    let after = recordLocalChange(before, old: state, new: saved, now: 20)
    XCTAssertEqual(after.records["dish-d"]?.modified["name"], 20)
    for field in ["ingredients", "instructions", "photo"] {
      XCTAssertEqual(after.records["dish-d"]?.modified[field], before.records["dish-d"]?.modified[field])
    }
    // New dishes still use the regular creation/validation path.
    XCTAssertEqual(try saveDish(emptyState(1), original).dishes[0], original)
  }
}
