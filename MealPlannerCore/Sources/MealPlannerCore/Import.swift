import Foundation

public enum NameMatch: Equatable, Sendable {
  case exact(String), close(String), none
}
public struct ImportIssue: Equatable, Sendable {
  public var line: Int
  public var message: String
}
public struct ImportLine: Equatable, Sendable {
  public var line: Int
  public var text: String
}
public struct ImportBlock: Equatable, Sendable {
  public var line: Int
  public var name: String
  public var ingredients: [ImportLine]
}
public struct ImportIngredient: Equatable, Sendable {
  public var line: Int
  public var amount: Double?
  public var typedName: String
  public var typedUnit: String
  public var nameSuggestion: String?
  public var unitSuggestion: String?
  public var silentName: String
  public var silentUnit: String
  public var amountText: String
}
public struct ImportDish: Equatable, Sendable {
  public var line: Int
  public var name: String
  public var ingredients: [ImportIngredient]
  public var errors: [ImportIssue]
  public var existingDishId: String?
}
public struct ImportPreview: Equatable, Sendable {
  public var dishes: [ImportDish]
}
// Source lines are stable identifiers until the pasted text changes.
public struct ImportChoices: Equatable, Sendable {
  public var replace: [Int: Bool] = [:]
  public var keepTypedNames: Set<Int> = []
  public var keepTypedUnits: Set<Int> = []
  public init() {}
}
private let aliases = [
  "gr": "g", "gramma": "g", "grammaa": "g", "kilo": "kg", "kiloa": "kg",
  "litra": "l", "litraa": "l", "desi": "dl", "desiä": "dl", "rl": "rkl",
]
private let importUnits = UNITS + ["cl", "mm", "ps", "rs", "plo"]
private func unitKey(_ s: String) -> String {
  let s = fold(tidy(s))
  return s.hasSuffix(".") ? String(s.dropLast()) : s
}
public func parseImport(_ text: String) -> [ImportBlock] {
  var blocks: [ImportBlock] = []
  var current: ImportBlock?
  for (index, raw) in text.replacingOccurrences(of: "\r\n", with: "\n")
    .replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n").enumerated() {
    var text = tidy(raw)
    if text.isEmpty {
      if let block = current { blocks.append(block) }
      current = nil
      continue
    }
    if let first = text.first, "-*•".contains(first), text.dropFirst().first?.isWhitespace == true {
      text = tidy(String(text.dropFirst()))
    }
    if current == nil { current = ImportBlock(line: index + 1, name: text, ingredients: []) }
    else { current?.ingredients.append(ImportLine(line: index + 1, text: text)) }
  }
  if let current { blocks.append(current) }
  return blocks
}
private func distance(_ a: String, _ b: String) -> Int {
  let b = Array(b)
  var previous = Array(0...b.count)
  for (i, x) in a.enumerated() {
    var row = [i + 1]
    for (j, y) in b.enumerated() {
      row.append(min(row[j] + 1, previous[j + 1] + 1, previous[j] + (x == y ? 0 : 1)))
    }
    previous = row
  }
  return previous[b.count]
}
public func matchIngredientName(_ typed: String, known: [KnownIngredient]) -> NameMatch {
  let key = fold(tidy(typed))
  let endings: Set<String> = ["a", "ä", "t", "n", "ta", "tä", "ja", "jä", "ia", "iä", "it", "in", "ksi"]
  if let exact = known.first(where: { fold(tidy($0.name)) == key }) { return .exact(exact.name) }
  var best: (String, Int)?
  for candidate in known {
    let name = fold(tidy(candidate.name))
    guard abs(key.count - name.count) <= 3 else { continue }
    let inflection = (name.count >= 4 && key.hasPrefix(name)
      && endings.contains(String(key.dropFirst(name.count))))
      || (key.count >= 5 && name.hasPrefix(key) && name.count - key.count <= 1)
    let d = distance(key, name)
    if inflection || (max(key.count, name.count) >= 5 && min(key.count, name.count) >= 4 && d == 1) {
      if best == nil || d < best!.1 { best = (candidate.name, d) }
    }
  }
  return best.map { .close($0.0) } ?? .none
}
private func spellings(_ typed: String, _ match: NameMatch) -> (String, String?) {
  switch match {
  case .exact(let name): return (name, nil)
  case .close(let name): return (typed, name)
  case .none: return (typed, nil)
  }
}
private let fractionValues: [Character: Double] = [
  "½": 0.5, "¼": 0.25, "¾": 0.75, "⅓": 1.0 / 3, "⅔": 2.0 / 3,
]
private func startsQuantity(_ text: String) -> Bool {
  text.first.map { $0.isNumber || fractionValues[$0] != nil } == true
    || text.range(of: #"^-?(\d|[.,]\d|/\d|[½¼¾⅓⅔])"#, options: .regularExpression) != nil
}
private func isLeftoverQuantity(_ text: String) -> Bool {
  // Numeric slash sequences include malformed fractions such as 1/2/3.
  text.range(of: #"^(\d+|[\d/]*\/[\d/]*|\d*[½¼¾⅓⅔])$"#,
    options: .regularExpression) != nil
}
private func startsPercentage(_ tokens: ArraySlice<String>) -> Bool {
  guard let first = tokens.first else { return false }
  if first.hasSuffix("%") { return true }
  return first.range(of: #"^-?(\d+([.,]\d+)?|[.,]\d+)$"#, options: .regularExpression) != nil
    && tokens.dropFirst().first?.hasPrefix("%") == true
}
private func fractionNumber(_ text: String) -> Double? {
  let value: Double
  if text.range(of: #"^\d+/\d+$"#, options: .regularExpression) != nil {
    let parts = text.split(separator: "/")
    guard let numerator = Double(parts[0]), let denominator = Double(parts[1]), denominator > 0 else {
      return nil
    }
    value = numerator / denominator
  } else if let last = text.last, let fraction = fractionValues[last] {
    let whole = String(text.dropLast())
    guard whole.isEmpty || whole.range(of: #"^\d+$"#, options: .regularExpression) != nil,
      let integer = whole.isEmpty ? 0 : Double(whole) else { return nil }
    value = integer + fraction
  } else { return nil }
  return value.isFinite ? value : nil
}
// Leave invalid text intact so the dish form supplies the standard amount error.
private func decimalFraction(_ text: String) -> String {
  guard let value = fractionNumber(text) else { return text }
  return formatAmount((value * 1000).rounded() / 1000)
}
private func formRows(_ dish: ImportDish, _ choices: ImportChoices) -> [FormRow] {
  dish.ingredients.map { i in
    FormRow(name: choices.keepTypedNames.contains(i.line) ? i.typedName : i.nameSuggestion ?? i.silentName,
      amount: i.amountText,
      unit: choices.keepTypedUnits.contains(i.line) ? i.typedUnit : i.unitSuggestion ?? i.silentUnit)
  }
}
private func validation(_ dish: ImportDish, _ choices: ImportChoices) -> [ImportIssue] {
  var issues: [ImportIssue] = []
  do { _ = try toDishBody(dish.name, []) }
  catch { issues.append(ImportIssue(line: dish.line, message: error.localizedDescription)) }
  let rows = formRows(dish, choices)
  if rows.count > 100 { issues.append(ImportIssue(line: dish.ingredients[100].line, message: "Enintään 100 ainesosaa.")) }
  for (index, row) in rows.enumerated() {
    do { _ = try toDishBody("Ruoka", [row]) }
    catch {
      issues.append(ImportIssue(line: dish.ingredients[index].line,
        message: error.localizedDescription.replacingOccurrences(of: "Ainesosa 1:", with: "Ainesosa \(index + 1):")))
    }
  }
  return issues
}
public func makeImportPreview(_ text: String, state: AppState) -> ImportPreview {
  let known = knownIngredients(state.dishes).sorted { $0.uses > $1.uses }
  var used: [String] = []
  for i in state.dishes.flatMap(\.ingredients) where !tidy(i.unit).isEmpty {
    if !used.contains(where: { fold(tidy($0)) == fold(tidy(i.unit)) }) { used.append(tidy(i.unit)) }
  }
  func unitMatch(_ text: String) -> NameMatch {
    guard !text.isEmpty else { return .none }
    if let exact = used.first(where: { fold(tidy($0)) == fold(tidy(text)) }) {
      return .exact(exact)
    }
    let key = aliases[unitKey(text)] ?? unitKey(text)
    let candidates = used + importUnits.filter { canonical in
      !used.contains { fold(tidy($0)) == canonical }
    }
    if let canonical = candidates.first(where: { unitKey($0) == key }) {
      return canonical == text ? .exact(canonical) : .close(canonical)
    }
    let knownUnits = candidates.map { KnownIngredient(key: fold($0), name: $0, unit: "", uses: 0) }
    return matchIngredientName(text, known: knownUnits)
  }
  func recognized(_ text: String) -> Bool {
    unitMatch(text) != .none
  }
  var seen: Set<String> = []
  let dishes = parseImport(text).map { block in
    let ingredients = block.ingredients.map { source in
      var tokens = source.text.split(separator: " ").map(String.init)
      var amountText = ""
      var unit = ""
      func splitUnit(_ token: String) -> (number: String, unit: String) {
        if let range = token.range(of: #"[\p{L}]+\.?$"#, options: .regularExpression) {
          let suffix = String(token[range])
          if recognized(suffix) { return (String(token[..<range.lowerBound]), suffix) }
        }
        return (token, "")
      }
      if let first = tokens.first, startsQuantity(first), !startsPercentage(tokens[...]),
        splitUnit(first).number.range(of: #"^-?[\d.,/½¼¾⅓⅔]+$"#, options: .regularExpression) != nil {
        let initial = splitUnit(tokens.removeFirst())
        amountText = initial.number
        unit = initial.unit
        if unit.isEmpty, amountText.range(of: #"^\d+$"#, options: .regularExpression) != nil,
          !startsPercentage(tokens[...]),
          let next = tokens.first, fractionNumber(splitUnit(next).number) != nil
            || splitUnit(next).number.range(of: #"^\d+/\d+$"#, options: .regularExpression) != nil {
          let fraction = splitUnit(tokens.removeFirst())
          if let part = fractionNumber(fraction.number),
            let whole = Double(amountText) {
            amountText = formatAmount(((whole + part) * 1000).rounded() / 1000)
          } else { amountText = "?" }
          unit = fraction.unit
        } else if unit.isEmpty,
          amountText.range(of: #"^\d{1,3}$"#, options: .regularExpression) != nil {
          while let next = tokens.first {
            if startsPercentage(tokens[...]) { break }
            let group = splitUnit(next)
            guard group.number.range(of: #"^\d{3}([.,]\d+)?$"#, options: .regularExpression) != nil else { break }
            tokens.removeFirst()
            amountText += group.number
            unit = group.unit
            if !unit.isEmpty || group.number.contains(",") || group.number.contains(".") { break }
          }
        }
        amountText = decimalFraction(amountText)
        if unit.isEmpty, let next = tokens.first, recognized(next) { unit = tokens.removeFirst() }
        if let next = tokens.first, isLeftoverQuantity(next), !startsPercentage(tokens[...]) {
          amountText = "?"
        }
      }
      let name = tokens.joined(separator: " ")
      let (silentName, nameSuggestion) = spellings(name, matchIngredientName(name, known: known))
      let (silentUnit, unitSuggestion) = spellings(unit, unitMatch(unit))
      let amount: Double?
      if case .value(let value) = parseAmount(amountText) { amount = value } else { amount = nil }
      return ImportIngredient(line: source.line, amount: amount, typedName: name, typedUnit: unit,
        nameSuggestion: nameSuggestion, unitSuggestion: unitSuggestion, silentName: silentName,
        silentUnit: silentUnit, amountText: amountText)
    }
    let key = fold(tidy(block.name))
    var dish = ImportDish(line: block.line, name: block.name, ingredients: ingredients, errors: [],
      existingDishId: state.dishes.first { fold(tidy($0.name)) == key }?.id)
    dish.errors = validation(dish, ImportChoices())
    if !seen.insert(key).inserted {
      dish.errors.append(ImportIssue(line: block.line, message: "Sama ruokalaji on liitetty kahdesti."))
    }
    return dish
  }
  return ImportPreview(dishes: dishes)
}
/// Carries skip/replace and keep-typed choices over to a re-parsed preview, matching dishes by name and
/// ingredients by dish name + typed name + typed unit, so editing one line doesn't reset the others.
public func carryChoices(_ choices: ImportChoices, from old: ImportPreview, to new: ImportPreview)
  -> ImportChoices
{
  func dishKey(_ dish: ImportDish) -> String { fold(tidy(dish.name)) }
  func ingredientKeys(_ preview: ImportPreview) -> [Int: String] {
    var keys: [Int: String] = [:]
    for dish in preview.dishes {
      for i in dish.ingredients {
        keys[i.line] = [dishKey(dish), fold(tidy(i.typedName)), fold(tidy(i.typedUnit))]
          .joined(separator: "\u{1}")
      }
    }
    return keys
  }
  // Only rows whose key is unique on both sides carry over; repeated rows would otherwise share one choice.
  func unique(_ keys: [Int: String]) -> [Int: String] {
    let counts = Dictionary(keys.values.map { ($0, 1) }, uniquingKeysWith: +)
    return keys.filter { counts[$0.value] == 1 }
  }
  let oldKeys = unique(ingredientKeys(old))
  let newKeys = unique(ingredientKeys(new))
  let replaced = Set(old.dishes.filter { choices.replace[$0.line] == true }.map(dishKey))
  let keptNames = Set(choices.keepTypedNames.compactMap { oldKeys[$0] })
  let keptUnits = Set(choices.keepTypedUnits.compactMap { oldKeys[$0] })
  var next = ImportChoices()
  for dish in new.dishes where replaced.contains(dishKey(dish)) { next.replace[dish.line] = true }
  for (line, key) in newKeys {
    if keptNames.contains(key) { next.keepTypedNames.insert(line) }
    if keptUnits.contains(key) { next.keepTypedUnits.insert(line) }
  }
  return next
}
public func importCount(_ preview: ImportPreview, _ choices: ImportChoices) -> Int {
  preview.dishes.filter { $0.existingDishId == nil || choices.replace[$0.line] == true }.count
}
public func importIssues(_ dish: ImportDish, choices: ImportChoices) -> [ImportIssue] {
  var issues = dish.errors
  for issue in validation(dish, choices) where !issues.contains(issue) { issues.append(issue) }
  return issues
}
public func applyImport(_ state: AppState, _ preview: ImportPreview, choices: ImportChoices,
  newId: () -> String) throws -> AppState {
  let selected = preview.dishes.filter { $0.existingDishId == nil || choices.replace[$0.line] == true }
  for dish in selected {
    if let issue = importIssues(dish, choices: choices).first { throw CoreError(issue.message) }
  }
  var next = state
  for dish in selected {
    let body = try toDishBody(dish.name, formRows(dish, choices))
    next = try saveDishWithoutNormalization(next,
      Dish(id: dish.existingDishId ?? newId(), name: body.name, ingredients: body.ingredients))
  }
  return normalize(next)
}
