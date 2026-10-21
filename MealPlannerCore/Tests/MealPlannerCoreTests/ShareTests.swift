import XCTest
@testable import MealPlannerCore

final class ShareTests: XCTestCase {
  private func roundTrip(_ dishes: [Dish], file: StaticString = #filePath, line: UInt = #line) throws {
    var sender = emptyState(0)
    sender.dishes = dishes
    let text = shareText(dishes, state: sender)
    for recipient in [emptyState(0), sender] {
      let preview = makeImportPreview(text, state: recipient)
      var choices = ImportChoices()
      for dish in preview.dishes { choices.replace[dish.line] = true }
      let result = try applyImport(recipient, preview, choices: choices, newId: { UUID().uuidString })
      XCTAssertEqual(result.dishes.count, dishes.count, file: file, line: line)
      for expected in dishes {
        let actual = result.dishes.first { $0.name == expected.name }
        XCTAssertNotNil(actual, file: file, line: line)
        XCTAssertEqual(actual?.ingredients, expected.ingredients, text, file: file, line: line)
      }
    }
  }

  func testTypicalTextAndMultipleDishes() throws {
    let dish = Dish(id: "a", name: "Makaronilaatikko", ingredients: [
      Ingredient(name: "makaroni", amount: 400, unit: "g"),
      Ingredient(name: "kerma", amount: 3, unit: "dl"),
      Ingredient(name: "sipuli", amount: 1, unit: ""),
      Ingredient(name: "suola", amount: nil, unit: ""),
    ])
    let expected = "Makaronilaatikko\n400 g makaroni\n3 dl kerma\n1 sipuli\nsuola"
    let other = Dish(id: "b", name: "Pasta", ingredients: [])
    XCTAssertEqual(shareText([dish], state: emptyState(0)), expected)
    XCTAssertEqual(shareText([dish, other], state: emptyState(0)), expected + "\n\nPasta")
    XCTAssertEqual(shareText([], state: emptyState(0)), "")
    try roundTrip([dish, other])
  }

  func testDecimalsAndUnitWithoutAmount() throws {
    let dish = Dish(id: "a", name: "Määrät", ingredients: [
      Ingredient(name: "kerma", amount: 1.5, unit: "dl"),
      Ingredient(name: "suola", amount: 0.25, unit: "tl"),
      Ingredient(name: "jauho", amount: 0.001, unit: "kg"),
      Ingredient(name: "vesi", amount: 1000000, unit: "g"),
      Ingredient(name: "muna", amount: 2, unit: ""),
      Ingredient(name: "maito", amount: nil, unit: "dl"),
    ])
    XCTAssertEqual(shareText([dish], state: emptyState(0)),
      "Määrät\n1,5 dl kerma\n0,25 tl suola\n0,001 kg jauho\n1000000 g vesi\n2 muna\n\"dl\" \"maito\"")
    try roundTrip([dish])
  }

  func testAmbiguousNames() throws {
    let names = ["7up", "10% jogurtti", "1/2 kuppia", "123", "kg", "dl kerma",
      "kilo", "desi", "pkt", "- suola", "* suola", "• suola",
      "\"Valio\"", "\"alku", "loppu\"", "juusto \"Valio\""]
    // Separate dishes keep unrelated spelling suggestions out of these syntax tests.
    for name in names {
      for amount: Double? in [nil, 2] {
        for unit in ["", "g"] {
          try roundTrip([Dish(id: "a", name: "Ruoka", ingredients: [
            Ingredient(name: name, amount: amount, unit: unit)
          ])])
        }
      }
    }
    for name in ["- Pasta", "* Pasta", "• Pasta", "\"Pasta\""] {
      try roundTrip([Dish(id: "a", name: name, ingredients: [])])
    }
  }

  func testCustomUnitsAndSenderAmbiguity() throws {
    try roundTrip([
      Dish(id: "a", name: "A", ingredients: [Ingredient(name: "tomaattia", amount: 1, unit: "purkki"),
        Ingredient(name: "peruna", amount: 1, unit: "iso")]),
      Dish(id: "b", name: "B", ingredients: [Ingredient(name: "iso sipuli", amount: 2, unit: "")]),
    ])
  }

  func testQuotedParserForms() {
    let cases: [(String, String, String, String)] = [
      ("\"1/2 kuppia\"", "", "", "1/2 kuppia"),
      ("\"purkki\" \"tomaattia\"", "", "purkki", "tomaattia"),
      ("1,5 \"purkki\" \"tomaattia\"", "1,5", "purkki", "tomaattia"),
      ("2 \"dl kerma\"", "2", "", "dl kerma"),
      ("juusto \"Valio\"", "", "", "juusto \"Valio\""),
      ("\"\"Valio\"\"", "", "", "\"Valio\""),
    ]
    for (text, amount, unit, name) in cases {
      let parsed = parseIngredientLine(text, usedUnits: [])
      XCTAssertEqual(parsed.amountText, amount, text)
      XCTAssertEqual(parsed.unit, unit, text)
      XCTAssertEqual(parsed.name, name, text)
      let row = makeImportPreview("Ruoka\n• " + text, state: emptyState(0)).dishes[0].ingredients[0]
      XCTAssertEqual(row.typedName, name, text)
      XCTAssertEqual(row.typedUnit, unit, text)
    }
    XCTAssertEqual(parseImport("\"- Pasta\"")[0].name, "- Pasta")
  }

  func testQuotedFormsStillOfferSpellingFixes() {
    var state = emptyState(0)
    state.dishes = [Dish(id: "a", name: "A", ingredients: [
      Ingredient(name: "kerma", amount: 1, unit: "dl")
    ])]
    let row = makeImportPreview("B\n1 \"DL\" \"kermaa\"", state: state).dishes[0].ingredients[0]
    XCTAssertEqual(row.nameSuggestion, "kerma")
    XCTAssertEqual(row.silentUnit, "dl")
  }

  func testQuoteInUnitRoundTrips() throws {
    for amount: Double? in [nil, 2] {
      let dish = Dish(id: "a", name: "A", ingredients: [
        Ingredient(name: "suola", amount: amount, unit: "oma\"mitta")
      ])
      let prefix = amount == nil ? "" : "2 "
      XCTAssertEqual(shareText([dish], state: emptyState(0)),
        "A\n" + prefix + "\"oma\"mitta\" \"suola\"")
      try roundTrip([dish])
    }
  }

  func testOrdinaryQuotedBrandsKeepTheirNames() {
    for (text, amount, unit, name) in [
      ("1 tlk tomaatteja \"Mutti\"", 1.0, "tlk", "tomaatteja \"Mutti\""),
      ("2 dl kermaa \"Valio\"", 2.0, "dl", "kermaa \"Valio\""),
    ] {
      let row = makeImportPreview("Ruoka\n" + text, state: emptyState(0)).dishes[0].ingredients[0]
      XCTAssertEqual(row.amount, amount)
      XCTAssertEqual(row.typedUnit, unit)
      XCTAssertEqual(row.typedName, name)
    }
  }

  func testRecipientCustomUnitCannotConsumeName() throws {
    let dish = Dish(id: "a", name: "A", ingredients: [
      Ingredient(name: "purkkia tomaattia", amount: 2, unit: "")
    ])
    let text = shareText([dish], state: emptyState(0))
    XCTAssertEqual(text, "A\n2 \"purkkia tomaattia\"")
    var recipient = emptyState(0)
    recipient.dishes = [Dish(id: "b", name: "B", ingredients: [
      Ingredient(name: "papu", amount: 1, unit: "purkki")
    ])]
    let plain = makeImportPreview("A\n2 purkkia tomaattia", state: recipient)
    XCTAssertEqual(plain.dishes[0].ingredients[0].typedUnit, "purkkia")
    let preview = makeImportPreview(text, state: recipient)
    let result = try applyImport(recipient, preview, choices: ImportChoices(), newId: { "new" })
    XCTAssertEqual(result.dishes.first { $0.name == "A" }?.ingredients, dish.ingredients)
  }

  func testAmbiguousQuoteDelimiterStillEmitsEscapedForm() {
    let dish = Dish(id: "a", name: "A", ingredients: [
      Ingredient(name: "suola", amount: 2, unit: "oma\" \"mitta")
    ])
    XCTAssertEqual(shareText([dish], state: emptyState(0)),
      "A\n2 \"oma\" \"mitta\" \"suola\"")
  }
}
