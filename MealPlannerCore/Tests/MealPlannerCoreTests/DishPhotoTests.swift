import Foundation
import XCTest
@testable import MealPlannerCore

final class DishPhotoTests: XCTestCase {
  func testOldShapeHasExactlyTheSameEncodedBytes() throws {
    // Sorted keys isolate the shape from JSONEncoder's unspecified key ordering.
    let raw = #"{"dishes":[{"id":"d","ingredients":[],"name":"A"}],"history":[],"trip":{"createdAt":1,"extras":[],"items":{},"meals":[]},"version":1}"#
    let decoded = decodeState(raw, now: 0)
    XCTAssertNil(decoded.unreadableRaw)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    XCTAssertEqual(String(decoding: try encoder.encode(decoded.state), as: UTF8.self), raw)
  }

  func testRoundTripAndSavePreserveOptionalFields() throws {
    let dish = Dish(id: "d", name: "A", ingredients: [], photo: "abc.jpg",
                    instructions: "  Sekoita.\n\nPaista.  ")
    let state = try saveDish(emptyState(1), dish)
    XCTAssertEqual(state.dishes, [dish])
    let decoded = decodeState(try encodeState(state), now: 0)
    XCTAssertNil(decoded.unreadableRaw)
    XCTAssertEqual(decoded.state, state)
    let updated = try saveDish(state, Dish(id: "d", name: "B", ingredients: [],
                                          photo: "other.jpg", instructions: "\r\nPaista.\r\n"))
    XCTAssertEqual(updated.dishes[0].photo, "other.jpg")
    XCTAssertEqual(updated.dishes[0].instructions, "Paista.")
  }

  func testInvalidOptionalFieldsDoNotDiscardDocument() throws {
    for photo: Any in ["../x.jpg", "a/b.jpg", "", 12, ".", "..", "x.jpg\n",
                       String(repeating: "x", count: 101), NSNull()] {
      let root: [String: Any] = [
        "version": 1, "dishes": [["id": "d", "name": "A", "ingredients": [],
                                   "photo": photo, "instructions": 12]],
        "trip": ["createdAt": 1, "meals": [], "items": [:], "extras": []],
        "history": []
      ]
      let raw = String(decoding: try JSONSerialization.data(withJSONObject: root), as: UTF8.self)
      let decoded = decodeState(raw, now: 0)
      XCTAssertNil(decoded.unreadableRaw)
      XCTAssertEqual(decoded.state.dishes.count, 1)
      XCTAssertNil(decoded.state.dishes.first?.photo)
      XCTAssertNil(decoded.state.dishes.first?.instructions)
    }
    XCTAssertEqual(validPhotoFileName("A_1.-jpg"), "A_1.-jpg")
    XCTAssertNotNil(validPhotoFileName(String(repeating: "a", count: 100)))
  }

  func testInstructionsValidationAndWhitespace() throws {
    XCTAssertNil(try toDishBody("A", [], instructions: " \r\n\t\n ").instructions)
    XCTAssertEqual(try toDishBody("A", [], instructions: "\r\n  A  \r\n\r\n B\r\n \t").instructions,
                   "  A  \n\n B")
    XCTAssertEqual(try toDishBody("A", [], instructions: String(repeating: "ä", count: 5000))
      .instructions?.count, 5000)
    let long = String(repeating: "a", count: 5001)
    XCTAssertThrowsError(try toDishBody("A", [], instructions: long)) {
      XCTAssertEqual($0.localizedDescription, "Ohjeet ovat liian pitkät (enintään 5000 merkkiä).")
    }
    XCTAssertThrowsError(try saveDish(emptyState(1),
      Dish(id: "d", name: "A", ingredients: [], instructions: long)))
  }

  func testDeletionAndOrphans() {
    let old = Dish(id: "d", name: "A", ingredients: [], photo: "old.jpg")
    var next = old
    XCTAssertNil(photoFileToDelete(old: nil, new: old))
    XCTAssertNil(photoFileToDelete(old: nil, new: nil))
    XCTAssertNil(photoFileToDelete(old: old, new: next))
    next.photo = "new.jpg"
    XCTAssertEqual(photoFileToDelete(old: old, new: next), "old.jpg")
    next.photo = nil
    XCTAssertEqual(photoFileToDelete(old: old, new: next), "old.jpg")
    XCTAssertEqual(photoFileToDelete(old: old, new: nil), "old.jpg")
    XCTAssertNil(photoFileToDelete(old: next, new: nil))
    var state = emptyState(1)
    state.dishes = [old, old, next]
    XCTAssertEqual(orphanedPhotos(state: state, files: ["old.jpg", "new.jpg", "../unsafe"]),
                   ["new.jpg"])
    XCTAssertEqual(orphanedPhotos(state: emptyState(1), files: ["a.jpg"]), ["a.jpg"])
    XCTAssertEqual(orphanedPhotos(state: state, files: []), [])
  }
}
