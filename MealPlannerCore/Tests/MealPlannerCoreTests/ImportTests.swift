import XCTest
@testable import MealPlannerCore

final class ImportTests: XCTestCase {
  func testPercentagesStayInIngredientNames() throws {
    let cases: [(String, Double?, String, String)] = [
      ("10 % jogurtti", nil, "", "10 % jogurtti"),
      ("10% jogurtti", nil, "", "10% jogurtti"),
      ("200 g 10 % jogurtti", 200, "g", "10 % jogurtti"),
      ("200 g 10% jogurtti", 200, "g", "10% jogurtti"),
      ("2 dl 35 % kermaa", 2, "dl", "35 % kermaa"),
      ("2 dl 35% kermaa", 2, "dl", "35% kermaa"),
      ("200 g 10 %:n jogurtti", 200, "g", "10 %:n jogurtti"),
      ("2 100 % mehu", 2, "", "100 % mehu"),
      ("1 000 g 10 % jogurtti", 1000, "g", "10 % jogurtti"),
      ("1/2 dl 35 % kermaa", 0.5, "dl", "35 % kermaa"),
    ]
    for (line, amount, unit, name) in cases {
      let preview = makeImportPreview("Ruoka\n\(line)", state: emptyState())
      let dish = preview.dishes[0]
      XCTAssertTrue(dish.errors.isEmpty, line)
      XCTAssertEqual(dish.ingredients[0].amount, amount, line)
      XCTAssertEqual(dish.ingredients[0].typedUnit, unit, line)
      XCTAssertEqual(dish.ingredients[0].typedName, name, line)
      let saved = try applyImport(emptyState(), preview, choices: ImportChoices(), newId: { "new" })
      XCTAssertEqual(saved.dishes[0].ingredients, [Ingredient(name: name, amount: amount, unit: unit)], line)
    }
  }
  func testDigitContainingIngredientNamesAfterAmount() throws {
    for name in ["10% jogurtti", "3-juusto", "7up"] {
      let preview = makeImportPreview("Ruoka\n200 g \(name)", state: emptyState())
      let dish = preview.dishes[0]
      XCTAssertTrue(dish.errors.isEmpty, name)
      XCTAssertEqual(dish.ingredients[0].amount, 200)
      XCTAssertEqual(dish.ingredients[0].typedUnit, "g")
      XCTAssertEqual(dish.ingredients[0].typedName, name)
      let saved = try applyImport(emptyState(), preview, choices: ImportChoices(), newId: { "new" })
      XCTAssertEqual(saved.dishes[0].ingredients, [Ingredient(name: name, amount: 200, unit: "g")])
    }
  }
  func testFourCharacterTyposMatchLongerNames() {
    let known = [KnownIngredient(key: "kerma", name: "kerma", unit: "dl", uses: 1)]
    for typed in ["kerm", "kema"] {
      XCTAssertEqual(matchIngredientName(typed, known: known), .close("kerma"))
      let row = makeImportPreview("Ruoka\n1 dl \(typed)", state: state()).dishes[0].ingredients[0]
      XCTAssertEqual(row.nameSuggestion, "kerma")
    }
    let short = [KnownIngredient(key: "kala", name: "kala", unit: "", uses: 1)]
    XCTAssertEqual(matchIngredientName("kana", known: short), .none)
    let reverse = [KnownIngredient(key: "kerm", name: "kerm", unit: "", uses: 1)]
    XCTAssertEqual(matchIngredientName("kerma", known: reverse), .close("kerm"))
  }
  func testFinnishEndingsDoNotReplaceCompoundNames() throws {
    let names = ["kaakao", "kerma", "sipuli", "jauheliha", "maito"]
    var s = emptyState(0)
    s.dishes = [Dish(id: "old", name: "Vanha", ingredients: names.map {
      Ingredient(name: $0, amount: nil, unit: "")
    })]
    let known = knownIngredients(s.dishes)
    XCTAssertEqual(matchIngredientName("kaakaovoi", known: known), .none)
    for (typed, expected) in ["kermaa": "kerma", "sipulit": "sipuli", "jauhelihaa": "jauheliha", "maitoa": "maito"] {
      XCTAssertEqual(matchIngredientName(typed, known: known), .close(expected))
    }
    for ending in ["a", "ä", "t", "n", "ta", "tä", "ja", "jä", "ia", "iä", "it", "in", "ksi"] {
      XCTAssertEqual(matchIngredientName("KAAKAO" + ending.uppercased(), known: known), .close("kaakao"))
    }
    let preview = makeImportPreview("Uusi\nkaakaovoi", state: s)
    XCTAssertNil(preview.dishes[0].ingredients[0].nameSuggestion)
    let result = try applyImport(s, preview, choices: ImportChoices(), newId: { "new" })
    XCTAssertEqual(result.dishes.first { $0.id == "new" }?.ingredients[0].name, "kaakaovoi")
  }
  func testSlashNamesAreOrdinaryText() throws {
    for name in ["suola/pippuri", "a/2"] {
      for amount in ["", "1 "] {
        let preview = makeImportPreview("Ruoka\n\(amount)\(name)", state: emptyState())
        let dish = preview.dishes[0]
        XCTAssertTrue(dish.errors.isEmpty)
        XCTAssertEqual(dish.ingredients[0].typedName, name)
        XCTAssertEqual(dish.ingredients[0].amount, amount.isEmpty ? nil : 1)
        let result = try applyImport(emptyState(), preview, choices: ImportChoices(), newId: { "new" })
        XCTAssertEqual(result.dishes[0].ingredients[0].name, name)
      }
    }
  }
  func testThousandsAndFractions() throws {
    let cases: [(String, Double, String, String)] = [
      ("1 000 g jauheliha", 1000, "g", "jauheliha"),
      ("12 500 g jauheliha", 12500, "g", "jauheliha"),
      ("1 234 567 g jauheliha", 1234567, "g", "jauheliha"),
      ("1 000,5 g jauheliha", 1000.5, "g", "jauheliha"),
      ("12 500.125g jauheliha", 12500.125, "g", "jauheliha"),
      ("1/2 dl kerma", 0.5, "dl", "kerma"),
      ("3/4 dl kerma", 0.75, "dl", "kerma"),
      ("1 1/2 dl kerma", 1.5, "dl", "kerma"),
      ("1 1/3dl kerma", 1.333, "dl", "kerma"),
      ("1 1/3000 dl kerma", 1, "dl", "kerma"),
      ("½ dl kerma", 0.5, "dl", "kerma"),
      ("¼ dl kerma", 0.25, "dl", "kerma"),
      ("¾ dl kerma", 0.75, "dl", "kerma"),
      ("⅓ dl kerma", 0.333, "dl", "kerma"),
      ("⅔ dl kerma", 0.667, "dl", "kerma"),
      ("1½ dl kerma", 1.5, "dl", "kerma"),
      ("1 ½dl kerma", 1.5, "dl", "kerma"),
      ("2 isoa sipulia", 2, "", "isoa sipulia"),
    ]
    for (line, expected, unit, name) in cases {
      let preview = makeImportPreview("Ruoka\n\(line)", state: emptyState())
      let dish = preview.dishes[0]
      // The grouped value is still subject to the normal maximum amount.
      if expected > MAX_AMOUNT {
        XCTAssertFalse(dish.errors.isEmpty, line)
        continue
      }
      XCTAssertTrue(dish.errors.isEmpty, line)
      XCTAssertEqual(dish.ingredients[0].amount, expected, line)
      XCTAssertEqual(dish.ingredients[0].typedUnit, unit, line)
      XCTAssertEqual(dish.ingredients[0].typedName, name, line)
      let saved = try applyImport(emptyState(), preview, choices: ImportChoices(), newId: { "new" })
      XCTAssertEqual(saved.dishes[0].ingredients[0].amount, expected, line)
    }
    let salt = makeImportPreview("Ruoka\nsuola", state: emptyState()).dishes[0]
    XCTAssertTrue(salt.errors.isEmpty)
    XCTAssertNil(salt.ingredients[0].amount)
    XCTAssertEqual(salt.ingredients[0].typedName, "suola")
  }
  func testMalformedQuantitiesUseAmountError() {
    for line in [
      "1/0 dl kerma", "1/ dl kerma", "/2 dl kerma", "1 1/0 dl kerma",
      "1 00 g jauheliha", "1 000 00 g jauheliha", "1 000 0 g jauheliha", "1 dl 2 kerma", "1 dl ½ kerma",
      "1 dl 1½ kerma",
      "1 1/2/3 dl kerma", "1/2/3 dl kerma", "0/2 dl kerma", "1/10000 dl kerma",
      "1 000 001 g jauheliha", "1000001½ dl kerma",
    ] {
      let preview = makeImportPreview("Ruoka\nsuola\n\(line)", state: emptyState())
      XCTAssertEqual(preview.dishes[0].errors, [ImportIssue(line: 3,
        message: "Ainesosa 2: määrän pitää olla positiivinen luku (enintään 1 000 000).")], line)
      XCTAssertThrowsError(try applyImport(emptyState(), preview, choices: ImportChoices(), newId: { "new" }), line)
    }
  }
  func testReplacementBatchPreservesShoppingStateWhenIngredientMoves() throws {
    var s = emptyState(0)
    let salt = Ingredient(name: "suola", amount: 1, unit: "dl")
    s.dishes = [
      Dish(id: "a", name: "A", ingredients: [salt]),
      Dish(id: "b", name: "B", ingredients: []),
    ]
    s.trip.meals = [Meal(id: "meal-a", dishId: "a"), Meal(id: "meal-b", dishId: "b")]
    let key = itemKey("suola", "dl")
    let preview = makeImportPreview("A\n\nB\n2 dl suola", state: s)
    var choices = ImportChoices()
    choices.replace = [1: true, 3: true]
    for marks in [
      ItemState(edited: true, amount: 3.5, removed: false, checked: true, have: false),
      ItemState(edited: true, amount: nil, removed: false, checked: false, have: true),
      ItemState(edited: false, amount: nil, removed: true, checked: false, have: false),
    ] {
      s.trip.items[key] = marks
      let result = try applyImport(s, preview, choices: choices, newId: { XCTFail("Replacement needs no new ID"); return "unused" })
      XCTAssertEqual(result.trip.items[key], marks)
      XCTAssertEqual(result.dishes.map(\.id), ["a", "b"])
      XCTAssertTrue(result.dishes[0].ingredients.isEmpty)
      XCTAssertEqual(result.dishes[1].ingredients, [Ingredient(name: "suola", amount: 2, unit: "dl")])
      XCTAssertEqual(generatedItems(result).map(\.key), [key])
    }
  }
  func testListMarkersAndNegativeAmounts() throws {
    for marker in ["-", "*", "•"] {
      let preview = makeImportPreview("Ruoka\n\(marker) 1 dl kerma", state: state())
      XCTAssertTrue(preview.dishes[0].errors.isEmpty)
      XCTAssertEqual(preview.dishes[0].ingredients[0].amount, 1)
      XCTAssertEqual(parseImport("Ruoka\n\(marker)kerma")[0].ingredients[0].text, "\(marker)kerma")
    }
    for line in ["-1 dl kerma", "-  -1 dl kerma", "-1dl kerma", "-,5 dl kerma"] {
      let preview = makeImportPreview("Ruoka\n\(line)", state: state())
      XCTAssertEqual(preview.dishes[0].errors, [ImportIssue(line: 2,
        message: "Ainesosa 1: määrän pitää olla positiivinen luku (enintään 1 000 000).")])
      XCTAssertThrowsError(try applyImport(state(), preview, choices: ImportChoices(), newId: { "new" }))
    }
  }
  private func state(unit: String = "dl") -> AppState {
    var s = emptyState(0)
    s.dishes = [Dish(id: "old", name: "Keitto", ingredients: ["kerma", "sipuli", "jauheliha", "peruna", "kala"].map {
      Ingredient(name: $0, amount: 1, unit: unit)
    })]
    return s
  }
  func testExample() throws {
    let text = "Makaronilaatikko\n400 g makaroni\n400 g jauheliha\n3 dl kerma\n1 sipuli\nsuola\n\nKanakeitto\n500 g kana\n4 peruna\n1,5 dl kermaa"
    let p = makeImportPreview(text, state: state())
    XCTAssertEqual(p.dishes.count, 2)
    XCTAssertEqual(p.dishes[1].line, 8)
    let rows = p.dishes[1].ingredients
    XCTAssertEqual(rows[2].line, 11)
    XCTAssertEqual(rows[2].amount, 1.5)
    XCTAssertEqual(rows[2].nameSuggestion, "kerma")
    XCTAssertEqual(rows[1].typedUnit, "")
    XCTAssertEqual(p.dishes[0].ingredients.last?.typedName, "suola")
    let saved = try applyImport(state(), p, choices: ImportChoices(), newId: { UUID().uuidString })
    XCTAssertEqual(saved.dishes.first { $0.name == "Kanakeitto" }?.ingredients.last?.name, "kerma")
  }
  func testParsing() {
    XCTAssertEqual(parseImport("\r\n- Keitto\r\n• suola\r\n \r\n* Toinen").map(\.line), [2, 5])
    let rows = makeImportPreview("Ruoka\n400g porkkana\n1,5dl kerma\n2 isoa sipulia\n.5 dl vesi", state: state()).dishes[0].ingredients
    XCTAssertEqual(rows[0].amount, 400)
    XCTAssertEqual(rows[0].typedUnit, "g")
    XCTAssertEqual(rows[1].amount, 1.5)
    XCTAssertEqual(rows[2].typedName, "isoa sipulia")
    XCTAssertEqual(rows[2].typedUnit, "")
    XCTAssertEqual(rows[3].amount, 0.5)
    XCTAssertTrue(makeImportPreview(" \n", state: state()).dishes.isEmpty)
    XCTAssertTrue(makeImportPreview("Ruoka", state: state()).dishes[0].errors.isEmpty)
  }
  func testUnits() {
    let aliases = ["gr": "g", "gramma": "g", "grammaa": "g", "kilo": "kg", "kiloa": "kg", "litra": "l", "litraa": "l", "desi": "dl", "desiä": "dl", "rl": "rkl", "rkl.": "rkl", "tl.": "tl", "kpl.": "kpl", "DL": "dl"]
    for (typed, canonical) in aliases {
      XCTAssertEqual(makeImportPreview("Ruoka\n1 \(typed) aine", state: emptyState()).dishes[0].ingredients[0].unitSuggestion, canonical, typed)
    }
    for unit in ["cl", "mm", "ps", "rs", "plo"] {
      XCTAssertEqual(makeImportPreview("Ruoka\n1 \(unit) aine", state: state()).dishes[0].ingredients[0].typedUnit, unit)
    }
    let row = makeImportPreview("Ruoka\n1 MITTA kerma", state: state(unit: "mitta")).dishes[0].ingredients[0]
    XCTAssertEqual(row.silentUnit, "mitta")
    XCTAssertNil(row.unitSuggestion)
    let typo = makeImportPreview("Ruoka\n1 mitra kerma", state: state(unit: "mitta")).dishes[0].ingredients[0]
    XCTAssertEqual(typo.unitSuggestion, "mitta")
  }
  func testMatching() {
    let known = knownIngredients(state().dishes)
    for (typed, expected) in ["kermaa": "kerma", "sipulit": "sipuli", "jauhelihaa": "jauheliha", "sipul": "sipuli", "peruma": "peruna"] {
      XCTAssertEqual(matchIngredientName(typed, known: known), .close(expected))
    }
    XCTAssertEqual(matchIngredientName("kana", known: known), .none)
    XCTAssertEqual(matchIngredientName(" KERMA ", known: known), .exact("kerma"))
    let row = makeImportPreview("Ruoka\n1 DL KERMA", state: state()).dishes[0].ingredients[0]
    XCTAssertEqual(row.silentName, "kerma")
    XCTAssertEqual(row.silentUnit, "dl")
    XCTAssertNil(row.nameSuggestion)
    XCTAssertNil(row.unitSuggestion)
    let tied = [
      KnownIngredient(key: "peruna", name: "peruna", unit: "", uses: 3),
      KnownIngredient(key: "peruma", name: "peruma", unit: "", uses: 1),
    ]
    XCTAssertEqual(matchIngredientName("perula", known: tied), .close("peruna"))
  }
  func testValidation() {
    let p = makeImportPreview("Ruoka\nsuola\n0 g kerma\n1,2,3 dl vesi", state: state())
    XCTAssertEqual(p.dishes[0].errors.map(\.line), [3, 4])
    XCTAssertEqual(p.dishes[0].errors[0].message, "Ainesosa 2: määrän pitää olla positiivinen luku (enintään 1 000 000).")
    XCTAssertThrowsError(try applyImport(state(), p, choices: ImportChoices(), newId: { "new" }))
    XCTAssertEqual(makeImportPreview(String(repeating: "a", count: 101), state: state()).dishes[0].errors.first?.message, "Nimi on liian pitkä (enintään 100 merkkiä).")
    XCTAssertEqual(makeImportPreview("Ruoka\n" + Array(repeating: "suola", count: 101).joined(separator: "\n"), state: state()).dishes[0].errors.first?.message, "Enintään 100 ainesosaa.")
    XCTAssertEqual(makeImportPreview("Ruoka\n" + String(repeating: "a", count: 101), state: state()).dishes[0].errors.first?.message, "Ainesosa 1: nimi on liian pitkä.")
    let unit = String(repeating: "u", count: 21)
    XCTAssertEqual(makeImportPreview("Ruoka\n1 \(unit) suola", state: state(unit: unit)).dishes[0].errors.first?.message, "Ainesosa 1: yksikkö on liian pitkä.")
  }
  func testChoicesAndDuplicates() throws {
    let s = state()
    let p = makeImportPreview(" KEITTO \nsuola\n\nUusi\n1 gr kermaa", state: s)
    var choices = ImportChoices()
    XCTAssertEqual(p.dishes[0].existingDishId, "old")
    XCTAssertEqual(importCount(p, choices), 1)
    let skipped = try applyImport(s, p, choices: choices, newId: { "new" })
    XCTAssertEqual(skipped.dishes.first { $0.id == "old" }, s.dishes[0])
    choices.replace[1] = true
    choices.keepTypedNames.insert(5)
    choices.keepTypedUnits.insert(5)
    XCTAssertEqual(importCount(p, choices), 2)
    let replaced = try applyImport(s, p, choices: choices, newId: { "new" })
    XCTAssertEqual(replaced.dishes.first { $0.id == "old" }?.ingredients.first?.name, "suola")
    XCTAssertEqual(replaced.dishes.first { $0.id == "new" }?.ingredients.first?.name, "kermaa")
    XCTAssertEqual(replaced.dishes.first { $0.id == "new" }?.ingredients.first?.unit, "gr")
    let duplicate = makeImportPreview("Uusi\n\n uusi ", state: s)
    XCTAssertEqual(duplicate.dishes[1].errors.first?.message, "Sama ruokalaji on liitetty kahdesti.")
    XCTAssertThrowsError(try applyImport(s, duplicate, choices: choices, newId: { "new" }))
    let invalidSkipped = makeImportPreview("Keitto\n0 g kerma", state: s)
    XCTAssertEqual(try applyImport(s, invalidSkipped, choices: ImportChoices(), newId: { "new" }), s)
  }
}

final class ImportReviewFixTests: XCTestCase {
  func testDigitLeadingNamesWithoutAmountStayNames() {
    let preview = makeImportPreview("Ruoka\n10% jogurtti\n7up\n2 7up", state: emptyState(0))
    let rows = preview.dishes[0].ingredients
    XCTAssertEqual(rows.map(\.typedName), ["10% jogurtti", "7up", "7up"])
    XCTAssertEqual(rows.map(\.amount), [nil, nil, 2])
    XCTAssertTrue(importIssues(preview.dishes[0], choices: ImportChoices()).isEmpty)
    let glued = makeImportPreview("Ruoka\n400g makaroni\n-1 dl kerma", state: emptyState(0))
    XCTAssertEqual(glued.dishes[0].ingredients[0].amount, 400)
    XCTAssertEqual(glued.dishes[0].ingredients[0].typedUnit, "g")
    XCTAssertFalse(importIssues(glued.dishes[0], choices: ImportChoices()).isEmpty)
  }

  func testChoicesSurviveEditingAnotherLine() {
    var state = emptyState(0)
    state.dishes = [
      Dish(id: "d1", name: "Keitto", ingredients: [Ingredient(name: "kerma", amount: 1, unit: "dl")])
    ]
    let before = makeImportPreview("Keitto\n1 dl kermaa\n\nPasta\n1 dl kermaa", state: state)
    var choices = ImportChoices()
    choices.replace[before.dishes[0].line] = true
    choices.keepTypedNames.insert(before.dishes[1].ingredients[0].line)
    let after = makeImportPreview("Uusi\n\nKeitto\n1 dl kermaa\n\nPasta\n2 kpl muna\n1 dl kermaa", state: state)
    let carried = carryChoices(choices, from: before, to: after)
    let keitto = after.dishes.first { $0.name == "Keitto" }!
    let pasta = after.dishes.first { $0.name == "Pasta" }!
    XCTAssertEqual(carried.replace[keitto.line], true)
    XCTAssertEqual(carried.keepTypedNames, [pasta.ingredients[1].line])
    XCTAssertFalse(carried.keepTypedNames.contains(keitto.ingredients[0].line))
  }
}

final class ImportClosingReviewTests: XCTestCase {
  func testNegativeFractionCharacterIsAnAmountError() {
    let preview = makeImportPreview("Ruoka\n-½ dl kerma", state: emptyState(0))
    XCTAssertFalse(importIssues(preview.dishes[0], choices: ImportChoices()).isEmpty)
  }

  func testRepeatedRowsDoNotShareCarriedChoices() {
    var state = emptyState(0)
    state.dishes = [Dish(id: "d1", name: "Keitto", ingredients: [Ingredient(name: "kerma", amount: 1, unit: "dl")])]
    let before = makeImportPreview("Ruoka\n1 dl kermaa\n1 dl kermaa", state: state)
    var choices = ImportChoices()
    choices.keepTypedNames.insert(before.dishes[0].ingredients[0].line)
    let after = makeImportPreview("Ruoka\n1 dl kermaa\n2 dl kermaa", state: state)
    XCTAssertTrue(carryChoices(choices, from: before, to: after).keepTypedNames.isEmpty)
  }
}
