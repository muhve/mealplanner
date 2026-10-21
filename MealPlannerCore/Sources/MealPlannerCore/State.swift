import Foundation

public func emptyTrip(_ now: Double) -> Trip {
  Trip(createdAt: now, meals: [], items: [:], extras: [])
}
public func emptyState(_ now: Double = Date().timeIntervalSince1970 * 1000) -> AppState {
  AppState(version: 1, dishes: [], trip: emptyTrip(now), history: [])
}
public func generatedItems(_ state: AppState) -> [Generated] {
  aggregateIngredients(
    state.trip.meals.flatMap { meal -> [IngredientRow] in
      guard let dish = state.dishes.first(where: { $0.id == meal.dishId }) else { return [] }
      return dish.ingredients.map { IngredientRow($0, dishId: dish.id, dish: dish.name) }
    })
}
public struct ReadMeal: Equatable, Sendable {
  public var id: String
  public var dishId: String
  public var name: String
}
public struct ReadTrip: Equatable, Sendable {
  public var createdAt: Double
  public var meals: [ReadMeal]
  public var items: [ShopItem]
  public var removed: [ShopItem]
  public var extras: [Extra]
}
public func readTrip(_ s: AppState) -> ReadTrip {
  let applied = applyItemState(generatedItems(s), s.trip.items)
  return ReadTrip(
    createdAt: s.trip.createdAt,
    meals: s.trip.meals.compactMap { meal in
      s.dishes.first(where: { $0.id == meal.dishId }).map {
        ReadMeal(id: meal.id, dishId: meal.dishId, name: $0.name)
      }
    }, items: applied.items, removed: applied.removed, extras: s.trip.extras)
}
public func normalize(_ state: AppState) -> AppState {
  var s = state
  let live = Set(generatedItems(s).map(\.key))
  s.trip.items = s.trip.items.filter {
    live.contains($0.key)
      && ($0.value.edited || $0.value.removed || $0.value.checked || $0.value.have)
  }
  return s
}
public func saveDish(_ state: AppState, _ dish: Dish) throws -> AppState {
  normalize(try saveDishWithoutNormalization(state, dish))
}
// Batch callers defer shopping-list cleanup until all dishes have been saved.
func saveDishWithoutNormalization(_ state: AppState, _ dish: Dish) throws -> AppState {
  let body = try toDishBody(
    dish.name,
    dish.ingredients.map { FormRow(name: $0.name, amount: formatAmount($0.amount), unit: $0.unit) },
    instructions: dish.instructions, photo: dish.photo)
  var known = Dictionary(
    uniqueKeysWithValues: knownIngredients(state.dishes.filter { $0.id != dish.id }).map {
      ($0.key, $0.name)
    })
  let ingredients = body.ingredients.map { i -> Ingredient in
    var i = i
    let name = i.name.precomposedStringWithCanonicalMapping
    let key = fold(name)
    if known[key] == nil { known[key] = name }
    i.name = known[key]!
    return i
  }
  let saved = Dish(id: dish.id, name: body.name, ingredients: ingredients,
                   photo: body.photo, instructions: body.instructions)
  var s = state
  if let i = s.dishes.firstIndex(where: { $0.id == dish.id }) {
    s.dishes[i] = saved
  } else {
    s.dishes.append(saved)
  }
  s.dishes.sort { $0.name.compare($1.name, locale: Locale(identifier: "fi")) == .orderedAscending }
  return s
}
public func deleteDish(_ state: AppState, _ id: String) -> AppState {
  var s = state
  s.dishes.removeAll { $0.id == id }
  s.trip.meals.removeAll { $0.dishId == id }
  return normalize(s)
}
public func addMeal(_ state: AppState, _ dishId: String, _ id: String) throws -> AppState {
  if state.trip.meals.count >= 100 { throw CoreError("Enintään 100 ruokaa listalla.") }
  guard state.dishes.contains(where: { $0.id == dishId }) else { return state }
  var s = state
  s.trip.meals.append(Meal(id: id, dishId: dishId))
  return normalize(s)
}
public func removeMeal(_ state: AppState, _ id: String) -> AppState {
  var s = state
  s.trip.meals.removeAll { $0.id == id }
  return normalize(s)
}
public struct ItemPatch: Sendable {
  public var amount: Double??
  public var removed: Bool?
  public var checked: Bool?
  public var have: Bool?
  public var resetAmount: Bool
  public init(
    amount: Double?? = nil, removed: Bool? = nil, checked: Bool? = nil, have: Bool? = nil,
    resetAmount: Bool = false
  ) {
    self.amount = amount
    self.removed = removed
    self.checked = checked
    self.have = have
    self.resetAmount = resetAmount
  }
}
public func updateItem(_ state: AppState, _ key: String, _ patch: ItemPatch) throws -> AppState {
  guard generatedItems(state).contains(where: { $0.key == key }) else { return state }
  var s = state
  var i =
    state.trip.items[key]
    ?? ItemState(edited: false, amount: nil, removed: false, checked: false, have: false)
  if let amount = patch.amount {
    if let amount, parseAmount(formatAmount(amount)) == .invalid {
      throw CoreError("Määrän pitää olla positiivinen luku, esim. 1,5.")
    }
    i.amount = amount
    i.edited = true
  }
  if patch.resetAmount {
    i.amount = nil
    i.edited = false
  }
  if let removed = patch.removed {
    i.removed = removed
    if removed {
      i.checked = false
      i.have = false
    }
  }
  i = markClause(i, Marks(checked: patch.checked, have: patch.have))
  s.trip.items[key] = i
  return normalize(s)
}
public func addExtra(_ state: AppState, _ name: String, _ id: String) throws -> AppState {
  let name = tidy(name)
  if name.isEmpty { throw CoreError("Anna tuotteelle nimi.") }
  if name.utf16.count > 100 { throw CoreError("Nimi on liian pitkä.") }
  if state.trip.extras.count >= 200 { throw CoreError("Enintään 200 muuta ostosta listalla.") }
  var s = state
  s.trip.extras.append(Extra(id: id, name: name, checked: false, have: false))
  return s
}
public func updateExtra(_ state: AppState, _ id: String, _ patch: Marks) -> AppState {
  var s = state
  s.trip.extras = s.trip.extras.map { $0.id == id ? markClause($0, patch) : $0 }
  return s
}
public func removeExtra(_ state: AppState, _ id: String) -> AppState {
  var s = state
  s.trip.extras.removeAll { $0.id == id }
  return s
}
public func archiveTrip(_ state: AppState, _ now: Double, _ id: String) throws -> AppState {
  let trip = readTrip(state)
  if trip.meals.isEmpty && trip.extras.isEmpty { throw CoreError("Lista on tyhjä.") }
  let snapshot = ArchivedTrip(
    id: id, createdAt: trip.createdAt, archivedAt: now, meals: trip.meals.map(\.name),
    items: trip.items.map {
      ArchivedItem(
        name: $0.name, amount: $0.amount, unit: $0.unit, checked: $0.checked, have: $0.have)
    }, extras: trip.extras.map { ArchivedExtra(name: $0.name, checked: $0.checked, have: $0.have) })
  var s = state
  s.trip = emptyTrip(now)
  s.history = Array(([snapshot] + s.history).sorted { $0.archivedAt > $1.archivedAt }.prefix(200))
  return s
}
public func decodeState(_ raw: String?, now: Double) -> (state: AppState, unreadableRaw: String?) {
  guard let raw else { return (emptyState(now), nil) }
  do {
    let decoder = JSONDecoder()
    guard var root = try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any],
      var trip = root["trip"] as? [String: Any],
      let rawItems = trip["items"] as? [String: Any],
      let rawDishes = root["dishes"] as? [Any], let rawMeals = trip["meals"] as? [Any]
    else { throw CoreError("Invalid stored document") }
    let dishes = try decoder.decode(
      [Dish].self, from: JSONSerialization.data(withJSONObject: rawDishes))
    let meals = try decoder.decode(
      [Meal].self, from: JSONSerialization.data(withJSONObject: rawMeals))
    let probe = AppState(
      version: 1, dishes: dishes, trip: Trip(createdAt: now, meals: meals, items: [:], extras: []),
      history: [])
    let live = Set(generatedItems(probe).map(\.key))
    // JS normalize short-circuits stale entries before reading their fields, even nulls.
    trip["items"] = rawItems.filter { live.contains($0.key) }
    root["trip"] = trip
    let s = try decoder.decode(AppState.self, from: JSONSerialization.data(withJSONObject: root))
    guard s.version == 1 else { throw CoreError("Invalid stored document") }
    return (normalize(s), nil)
  } catch { return (emptyState(now), raw) }
}
