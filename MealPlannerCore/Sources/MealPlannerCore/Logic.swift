import Foundation

public let MIN_AMOUNT = 0.001
public let MAX_AMOUNT = 1_000_000.0
public let UNITS = [
  "g", "kg", "dl", "l", "ml", "rkl", "tl", "kpl", "pkt", "prk", "pss", "tlk", "nippu",
]
public func fold(_ s: String) -> String {
  s.precomposedStringWithCanonicalMapping.lowercased(with: Locale(identifier: "fi"))
}
public func itemKey(_ name: String, _ unit: String) -> String {
  let data = try! JSONSerialization.data(
    withJSONObject: [fold(name), fold(unit)], options: [.fragmentsAllowed, .withoutEscapingSlashes])
  return String(decoding: data, as: UTF8.self)
}
public func tidy(_ s: String) -> String {
  s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
}
public enum AmountResult: Equatable, Sendable {
  case value(Double?)
  case invalid
}
public func parseAmount(_ text: String?) -> AmountResult {
  var s = (text ?? "").filter { !$0.isWhitespace }
  if let comma = s.firstIndex(of: ",") { s.replaceSubrange(comma...comma, with: ".") }
  if s.isEmpty { return .value(nil) }
  guard s.range(of: #"^(\d+(\.\d{0,3})?|\.\d{1,3})$"#, options: .regularExpression) != nil,
    let n = Double(s), n >= MIN_AMOUNT, n <= MAX_AMOUNT
  else { return .invalid }
  return .value(n)
}
public func formatAmount(_ n: Double?) -> String {
  guard let n else { return "" }
  let s = n.rounded() == n ? String(format: "%.0f", n) : String(n)
  return s.replacingOccurrences(of: ".", with: ",")
}
// Intl.Collator('fi', { sensitivity: 'base' }): ignore secondary accents while
// preserving Finnish primary letters (å, ä, ö) and their equivalent spellings.
private func finnishPrimary(_ text: String) -> String {
  let equivalent: [Character: String] = [
    "ü": "y", "ø": "ö", "æ": "ä", "œ": "oe", "ß": "ss", "ð": "d", "ł": "l",
  ]
  return fold(text).map { character in
    if let value = equivalent[character] { return value }
    if "åäöçþı".contains(character) { return String(character) }
    return String(character).folding(
      options: .diacriticInsensitive, locale: Locale(identifier: "fi"))
  }.joined()
}
public func finnishLess(_ a: String, _ b: String) -> Bool {
  finnishPrimary(a).compare(
    finnishPrimary(b), options: .caseInsensitive, locale: Locale(identifier: "fi"))
    == .orderedAscending
}
public struct IngredientRow: Equatable, Sendable {
  public var ingredient: Ingredient
  public var dishId: String
  public var dish: String
  public init(_ ingredient: Ingredient, dishId: String, dish: String) {
    self.ingredient = ingredient
    self.dishId = dishId
    self.dish = dish
  }
}
public func aggregateIngredients(_ rows: [IngredientRow]) -> [Generated] {
  var items: [String: Generated] = [:]
  var order: [String] = []
  var seen: [String: Set<String>] = [:]
  for row in rows {
    let i = row.ingredient
    let key = itemKey(row.ingredient.name, row.ingredient.unit)
    if items[key] == nil { order.append(key) }
    var item =
      items[key] ?? Generated(name: i.name, amount: nil, unit: i.unit, key: key, dishes: [])
    if let amount = i.amount {
      item.amount = (((item.amount ?? 0) + amount) * 1000).rounded() / 1000
    }
    if !(seen[key] ?? []).contains(row.dishId) {
      item.dishes.append(row.dish)
      seen[key, default: []].insert(row.dishId)
    }
    items[key] = item
  }
  return order.compactMap { items[$0] }.sorted {
    if finnishLess($0.name, $1.name) { return true }
    if finnishLess($1.name, $0.name) { return false }
    return finnishLess($0.unit, $1.unit)
  }
}
public func applyItemState(_ generated: [Generated], _ states: [String: ItemState]) -> (
  items: [ShopItem], removed: [ShopItem]
) {
  var items: [ShopItem] = []
  var removed: [ShopItem] = []
  for i in generated {
    let s = states[i.key]
    let out = ShopItem(
      name: i.name, amount: s?.edited == true ? s?.amount : i.amount, unit: i.unit, key: i.key,
      dishes: i.dishes, recipeAmount: i.amount, edited: s?.edited ?? false,
      checked: s?.checked ?? false, have: s?.have ?? false)
    if s?.removed == true { removed.append(out) } else { items.append(out) }
  }
  return (items, removed)
}
public func markClause<T: Marked>(_ before: T, _ patch: Marks) -> T {
  var next = before
  if let checked = patch.checked {
    next.checked = checked
    if checked { next.have = false }
  }
  if let have = patch.have {
    next.have = have
    if have { next.checked = false }
  }
  return next
}
public func uncheckedFirst<T: Marked>(_ list: [T]) -> [T] {
  list.filter { !$0.checked } + list.filter { $0.checked }
}
public func historyOrder<T: Marked>(_ list: [T]) -> [T] {
  list.filter { !$0.have && !$0.checked } + list.filter { !$0.have && $0.checked }
    + list.filter { $0.have }
}
public func tripCounts<I: Marked, E: Marked>(_ items: [I], _ extras: [E]) -> Counts {
  let all = items.map { ($0.checked, $0.have) } + extras.map { ($0.checked, $0.have) }
  let have = all.filter { $0.1 }.count
  let bought = all.filter { $0.0 && !$0.1 }.count
  let toBuy = all.count - have
  return Counts(left: toBuy - bought, bought: bought, have: have, toBuy: toBuy)
}
public func statusText(_ c: Counts) -> String? {
  if c.toBuy == 0 && c.have == 0 { return nil }
  let home = c.have > 0 ? " · kotona \(c.have)" : ""
  return c.toBuy == 0
    ? "Kaikki on jo kotona"
    : c.left == 0 ? "Kaikki ostettu! 🎉" + home : "\(c.left) / \(c.toBuy) jäljellä" + home
}
public func ingredientSummary(_ ingredients: [Ingredient]) -> String {
  ingredients.map {
    [formatAmount($0.amount), $0.unit, $0.name].filter { !$0.isEmpty }.joined(separator: " ")
  }.joined(separator: ", ")
}
public func toDishBody(_ name: String, _ rows: [FormRow], instructions: String? = nil,
                       photo: String? = nil) throws -> DishBody {
  if tidy(name).isEmpty { throw CoreError("Anna ruokalajille nimi.") }
  if tidy(name).utf16.count > 100 { throw CoreError("Nimi on liian pitkä (enintään 100 merkkiä).") }
  func blank(_ r: FormRow) -> Bool {
    tidy(r.name).isEmpty && tidy(r.amount).isEmpty && tidy(r.unit).isEmpty
  }
  if rows.filter({ !blank($0) }).count > 100 { throw CoreError("Enintään 100 ainesosaa.") }
  var ingredients: [Ingredient] = []
  for (i, r) in rows.enumerated() where !blank(r) {
    let prefix = "Ainesosa \(i + 1): "
    if tidy(r.name).isEmpty { throw CoreError(prefix + "anna nimi.") }
    if tidy(r.name).utf16.count > 100 { throw CoreError(prefix + "nimi on liian pitkä.") }
    guard case .value(let amount) = parseAmount(r.amount) else {
      throw CoreError(prefix + "määrän pitää olla positiivinen luku (enintään 1 000 000).")
    }
    if tidy(r.unit).utf16.count > 20 { throw CoreError(prefix + "yksikkö on liian pitkä.") }
    ingredients.append(Ingredient(name: tidy(r.name), amount: amount, unit: tidy(r.unit)))
  }
  return DishBody(name: tidy(name), ingredients: ingredients,
                  photo: validPhotoFileName(photo), instructions: try normalizedInstructions(instructions))
}
public func knownIngredients(_ dishes: [Dish]) -> [KnownIngredient] {
  var order: [String] = []
  var groups: [String: [Ingredient]] = [:]
  for i in dishes.flatMap(\.ingredients) {
    let key = fold(tidy(i.name))
    if key.isEmpty { continue }
    if groups[key] == nil { order.append(key) }
    groups[key, default: []].append(i)
  }
  func common(_ values: [String]) -> String {
    var order: [String] = []
    var counts: [String: Int] = [:]
    for v in values where !v.isEmpty {
      if counts[v] == nil { order.append(v) }
      counts[v, default: 0] += 1
    }
    return order.enumerated().sorted {
      counts[$0.element]! == counts[$1.element]!
        ? $0.offset < $1.offset : counts[$0.element]! > counts[$1.element]!
    }.first?.element ?? ""
  }
  return order.map { key in
    let g = groups[key]!
    return KnownIngredient(
      key: key, name: common(g.map { tidy($0.name).precomposedStringWithCanonicalMapping }),
      unit: common(g.map { fold(tidy($0.unit)) }), uses: g.count)
  }
}
public func suggestIngredients(_ dishes: [Dish], _ query: String, limit: Int = 8) -> [Suggestion] {
  let q = fold(tidy(query))
  return knownIngredients(dishes).filter { $0.key.contains(q) || q.isEmpty }.sorted {
    let a = $0.key.hasPrefix(q)
    let b = $1.key.hasPrefix(q)
    if a != b { return a }
    if $0.uses != $1.uses { return $0.uses > $1.uses }
    return finnishLess($0.name, $1.name)
  }.prefix(max(0, limit)).map { Suggestion(name: $0.name, unit: $0.unit, uses: $0.uses) }
}
public func visibleSuggestions(_ answer: (query: String, items: [Suggestion])?, _ query: String)
  -> [Suggestion]
{
  guard let answer, answer.query == query else { return [] }
  return answer.items.count == 1 && answer.items[0].name == query ? [] : answer.items
}
public func formatDay(_ ms: Double, timeZone: TimeZone = .current) -> String {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = timeZone
  let c = calendar.dateComponents(
    [.day, .month, .year], from: Date(timeIntervalSince1970: ms / 1000))
  return "\(c.day!).\(c.month!).\(c.year!)"
}


public func validPhotoFileName(_ name: String?) -> String? {
  guard let name, name != ".", name != "..", (1...100).contains(name.utf8.count),
    name.utf8.allSatisfy({
      (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0)
        || $0 == 46 || $0 == 95 || $0 == 45
    }) else { return nil }
  return name
}

public func normalizedInstructions(_ value: String?) throws -> String? {
  var lines = (value ?? "").replacingOccurrences(of: "\r\n", with: "\n")
    .components(separatedBy: "\n")
  while let first = lines.first, first.allSatisfy({ $0.isWhitespace }) { lines.removeFirst() }
  while let last = lines.last, last.allSatisfy({ $0.isWhitespace }) { lines.removeLast() }
  let text = lines.joined(separator: "\n")
  guard text.count <= 5000 else {
    throw CoreError("Ohjeet ovat liian pitkät (enintään 5000 merkkiä).")
  }
  return text.isEmpty ? nil : text
}

public func photoFileToDelete(old: Dish?, new: Dish?) -> String? {
  guard let photo = validPhotoFileName(old?.photo), photo != new?.photo else { return nil }
  return photo
}

public func orphanedPhotos(state: AppState, files: [String], backups: [String] = []) -> [String] {
  let referenced = Set(state.dishes.compactMap { validPhotoFileName($0.photo) })
  // Search raw text conservatively, including malformed documents and non-photo fields.
  return files.filter { file in
    validPhotoFileName(file) != nil && !referenced.contains(file)
      && !backups.contains { $0.contains(file) }
  }
}
