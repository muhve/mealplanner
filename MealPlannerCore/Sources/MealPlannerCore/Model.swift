import Foundation

public struct Ingredient: Codable, Equatable, Sendable {
  public var name: String
  public var amount: Double?
  public var unit: String
  public init(name: String, amount: Double?, unit: String) {
    self.name = name
    self.amount = amount
    self.unit = unit
  }
  enum CodingKeys: String, CodingKey { case name, amount, unit }
  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(name, forKey: .name)
    try c.encode(amount, forKey: .amount)
    try c.encode(unit, forKey: .unit)
  }
}
public struct Dish: Codable, Equatable, Sendable {
  public var id: String
  public var name: String
  public var ingredients: [Ingredient]
  public init(id: String, name: String, ingredients: [Ingredient]) {
    self.id = id
    self.name = name
    self.ingredients = ingredients
  }
}
public struct ItemState: Codable, Equatable, Sendable {
  public var edited: Bool
  public var amount: Double?
  public var removed: Bool
  public var checked: Bool
  public var have: Bool
  public init(edited: Bool, amount: Double?, removed: Bool, checked: Bool, have: Bool) {
    self.edited = edited
    self.amount = amount
    self.removed = removed
    self.checked = checked
    self.have = have
  }
  enum CodingKeys: String, CodingKey { case edited, amount, removed, checked, have }
  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(edited, forKey: .edited)
    try c.encode(amount, forKey: .amount)
    try c.encode(removed, forKey: .removed)
    try c.encode(checked, forKey: .checked)
    try c.encode(have, forKey: .have)
  }
}
public struct Extra: Codable, Equatable, Sendable {
  public var id: String
  public var name: String
  public var checked: Bool
  public var have: Bool
  public init(id: String, name: String, checked: Bool, have: Bool) {
    self.id = id
    self.name = name
    self.checked = checked
    self.have = have
  }
}
public struct Meal: Codable, Equatable, Sendable {
  public var id: String
  public var dishId: String
  public init(id: String, dishId: String) {
    self.id = id
    self.dishId = dishId
  }
}
public struct Trip: Codable, Equatable, Sendable {
  public var createdAt: Double
  public var meals: [Meal]
  public var items: [String: ItemState]
  public var extras: [Extra]
  public init(createdAt: Double, meals: [Meal], items: [String: ItemState], extras: [Extra]) {
    self.createdAt = createdAt
    self.meals = meals
    self.items = items
    self.extras = extras
  }
}
public struct ArchivedItem: Codable, Equatable, Sendable {
  public var name: String
  public var amount: Double?
  public var unit: String
  public var checked: Bool
  public var have: Bool
  public init(name: String, amount: Double?, unit: String, checked: Bool, have: Bool) {
    self.name = name
    self.amount = amount
    self.unit = unit
    self.checked = checked
    self.have = have
  }
  enum CodingKeys: String, CodingKey { case name, amount, unit, checked, have }
  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(name, forKey: .name)
    try c.encode(amount, forKey: .amount)
    try c.encode(unit, forKey: .unit)
    try c.encode(checked, forKey: .checked)
    try c.encode(have, forKey: .have)
  }
}
public struct ArchivedExtra: Codable, Equatable, Sendable {
  public var name: String
  public var checked: Bool
  public var have: Bool
  public init(name: String, checked: Bool, have: Bool) {
    self.name = name
    self.checked = checked
    self.have = have
  }
}
public struct ArchivedTrip: Codable, Equatable, Sendable {
  public var id: String
  public var createdAt: Double
  public var archivedAt: Double
  public var meals: [String]
  public var items: [ArchivedItem]
  public var extras: [ArchivedExtra]
  public init(
    id: String, createdAt: Double, archivedAt: Double, meals: [String], items: [ArchivedItem],
    extras: [ArchivedExtra]
  ) {
    self.id = id
    self.createdAt = createdAt
    self.archivedAt = archivedAt
    self.meals = meals
    self.items = items
    self.extras = extras
  }
}
public struct AppState: Codable, Equatable, Sendable {
  public var version: Int
  public var dishes: [Dish]
  public var trip: Trip
  public var history: [ArchivedTrip]
  public init(version: Int, dishes: [Dish], trip: Trip, history: [ArchivedTrip]) {
    self.version = version
    self.dishes = dishes
    self.trip = trip
    self.history = history
  }
}
public struct Generated: Codable, Equatable, Sendable {
  public var name: String
  public var amount: Double?
  public var unit: String
  public var key: String
  public var dishes: [String]
  public init(name: String, amount: Double?, unit: String, key: String, dishes: [String]) {
    self.name = name
    self.amount = amount
    self.unit = unit
    self.key = key
    self.dishes = dishes
  }
  enum CodingKeys: String, CodingKey { case name, amount, unit, key, dishes }
  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(name, forKey: .name)
    try c.encode(amount, forKey: .amount)
    try c.encode(unit, forKey: .unit)
    try c.encode(key, forKey: .key)
    try c.encode(dishes, forKey: .dishes)
  }
}
public struct ShopItem: Codable, Equatable, Sendable {
  public var name: String
  public var amount: Double?
  public var unit: String
  public var key: String
  public var dishes: [String]
  public var recipeAmount: Double?
  public var edited: Bool
  public var checked: Bool
  public var have: Bool
  public init(
    name: String, amount: Double?, unit: String, key: String, dishes: [String],
    recipeAmount: Double?, edited: Bool, checked: Bool, have: Bool
  ) {
    self.name = name
    self.amount = amount
    self.unit = unit
    self.key = key
    self.dishes = dishes
    self.recipeAmount = recipeAmount
    self.edited = edited
    self.checked = checked
    self.have = have
  }
  enum CodingKeys: String, CodingKey {
    case name, amount, unit, key, dishes, recipeAmount, edited, checked, have
  }
  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(name, forKey: .name)
    try c.encode(amount, forKey: .amount)
    try c.encode(unit, forKey: .unit)
    try c.encode(key, forKey: .key)
    try c.encode(dishes, forKey: .dishes)
    try c.encode(recipeAmount, forKey: .recipeAmount)
    try c.encode(edited, forKey: .edited)
    try c.encode(checked, forKey: .checked)
    try c.encode(have, forKey: .have)
  }
}
public struct Marks: Codable, Equatable, Sendable {
  public var checked: Bool?
  public var have: Bool?
  public init(checked: Bool? = nil, have: Bool? = nil) {
    self.checked = checked
    self.have = have
  }
}
public struct FormRow: Codable, Equatable, Sendable {
  public var name: String
  public var amount: String
  public var unit: String
  public init(name: String, amount: String, unit: String) {
    self.name = name
    self.amount = amount
    self.unit = unit
  }
}
public struct DishBody: Codable, Equatable, Sendable {
  public var name: String
  public var ingredients: [Ingredient]
  public init(name: String, ingredients: [Ingredient]) {
    self.name = name
    self.ingredients = ingredients
  }
}
public struct Suggestion: Codable, Equatable, Sendable {
  public var name: String
  public var unit: String
  public var uses: Int
  public init(name: String, unit: String, uses: Int) {
    self.name = name
    self.unit = unit
    self.uses = uses
  }
}
public struct KnownIngredient: Codable, Equatable, Sendable {
  public var key: String
  public var name: String
  public var unit: String
  public var uses: Int
  public init(key: String, name: String, unit: String, uses: Int) {
    self.key = key
    self.name = name
    self.unit = unit
    self.uses = uses
  }
}
public struct Counts: Codable, Equatable, Sendable {
  public var left: Int
  public var bought: Int
  public var have: Int
  public var toBuy: Int
  public init(left: Int, bought: Int, have: Int, toBuy: Int) {
    self.left = left
    self.bought = bought
    self.have = have
    self.toBuy = toBuy
  }
}
public protocol Marked {
  var checked: Bool { get set }
  var have: Bool { get set }
}
extension ItemState: Marked {}
extension Extra: Marked {}
extension ShopItem: Marked {}
extension ArchivedItem: Marked {}
extension ArchivedExtra: Marked {}
public struct CoreError: LocalizedError, Equatable {
  public let message: String
  public init(_ message: String) { self.message = message }
  public var errorDescription: String? { message }
}
extension ArchivedExtra {
  enum CodingKeys: String, CodingKey { case name, checked, have }
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    name = try c.decode(String.self, forKey: .name)
    checked = try c.decodeIfPresent(Bool.self, forKey: .checked) ?? false
    have = try c.decodeIfPresent(Bool.self, forKey: .have) ?? false
  }
}
extension ArchivedItem {
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    name = try c.decode(String.self, forKey: .name)
    amount = try c.decodeIfPresent(Double.self, forKey: .amount)
    unit = try c.decode(String.self, forKey: .unit)
    checked = try c.decodeIfPresent(Bool.self, forKey: .checked) ?? false
    have = try c.decodeIfPresent(Bool.self, forKey: .have) ?? false
  }
}

// Earlier snapshots may omit false marks. The JS readers used boolean defaults.
extension ItemState {
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    edited = try c.decodeIfPresent(Bool.self, forKey: .edited) ?? false
    amount = try c.decodeIfPresent(Double.self, forKey: .amount)
    removed = try c.decodeIfPresent(Bool.self, forKey: .removed) ?? false
    checked = try c.decodeIfPresent(Bool.self, forKey: .checked) ?? false
    have = try c.decodeIfPresent(Bool.self, forKey: .have) ?? false
  }
}
extension Extra {
  enum CodingKeys: String, CodingKey { case id, name, checked, have }
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(String.self, forKey: .id)
    name = try c.decode(String.self, forKey: .name)
    checked = try c.decodeIfPresent(Bool.self, forKey: .checked) ?? false
    have = try c.decodeIfPresent(Bool.self, forKey: .have) ?? false
  }
}
