import Foundation

/// An open form owns only the fields it changed relative to its opening snapshot.
/// Untouched fields come from the latest local document, including remote edits.
public func applyDishEdits(current: Dish?, original: Dish, edited: Dish) throws -> Dish {
  guard var result = current else {
    throw CoreError("Ruokalaji on poistettu toisella laitteella.")
  }
  if edited.name != original.name { result.name = edited.name }
  if edited.instructions != original.instructions { result.instructions = edited.instructions }
  if edited.photo != original.photo { result.photo = edited.photo }
  if edited.ingredients != original.ingredients { result.ingredients = edited.ingredients }
  return result
}
