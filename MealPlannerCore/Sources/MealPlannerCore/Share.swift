import Foundation

/// Importable dish text, preserving the supplied dish order.
public func shareText(_ dishes: [Dish], state: AppState) -> String {
  let used = state.dishes.flatMap(\.ingredients).map(\.unit).filter { !$0.isEmpty }
  func quoted(_ text: String) -> String { "\"" + text + "\"" }
  func ingredientLine(_ ingredient: Ingredient) -> String {
    let amount = formatAmount(ingredient.amount)
    let plain = [amount, ingredient.unit, ingredient.name].filter { !$0.isEmpty }.joined(separator: " ")
    func roundTrips(_ text: String) -> Bool {
      [[], used].allSatisfy { units in
        let parsed = parseIngredientLine(stripImportListMarker(text), usedUnits: units)
        return parseAmount(parsed.amountText) == .value(ingredient.amount)
          && parsed.unit == ingredient.unit && parsed.name == ingredient.name
      }
    }
    // A recipient may recognize a custom unit in the first word of the name.
    let needsQuotedName = ingredient.amount != nil && ingredient.unit.isEmpty
      && ingredient.name.split(separator: " ").count >= 2
    if !needsQuotedName && roundTrips(plain) { return plain }
    // Always parses back, except a unit containing `" "` (the unit/name delimiter).
    return [
      amount, ingredient.unit.isEmpty ? "" : quoted(ingredient.unit), quoted(ingredient.name),
    ].filter { !$0.isEmpty }.joined(separator: " ")
  }
  return dishes.map { dish in
    let name = stripImportListMarker(dish.name) != dish.name
      || (dish.name.hasPrefix("\"") && dish.name.hasSuffix("\""))
      ? quoted(dish.name) : dish.name
    return ([name] + dish.ingredients.map(ingredientLine)).joined(separator: "\n")
  }.joined(separator: "\n\n")
}
