import type { AppState, Dish, ItemState, Marks, Trip } from '../lib/model.ts';
import {
  aggregateIngredients, applyItemState, markClause, parseAmount, tidy,
  toDishBody, formatAmount, knownIngredients, fold,
} from '../lib/logic.ts';

export const emptyTrip = (now: number): Trip => ({ createdAt: now, meals: [], items: {}, extras: [] });
export const emptyState = (now = Date.now()): AppState => ({ version: 1, dishes: [], trip: emptyTrip(now), history: [] });
export const newId = () => Date.now().toString(36) + Math.random().toString(36).slice(2);

export function generatedItems(state: AppState) {
  const dishes = new Map(state.dishes.map(dish => [dish.id, dish]));
  return aggregateIngredients(state.trip.meals.flatMap(meal => {
    const dish = dishes.get(meal.dishId);
    return dish ? dish.ingredients.map(ingredient => ({ ...ingredient, dishId: dish.id, dish: dish.name })) : [];
  }));
}

export function readTrip(state: AppState) {
  return {
    ...state.trip,
    ...applyItemState(generatedItems(state), state.trip.items),
    meals: state.trip.meals.flatMap(meal => {
      const dish = state.dishes.find(d => d.id === meal.dishId);
      return dish ? [{ ...meal, name: dish.name }] : [];
    }),
  };
}

// Forget state when an ingredient leaves the generated list, including after recipe edits.
function normalize(state: AppState): AppState {
  const live = new Set(generatedItems(state).map(item => item.key));
  const items = Object.fromEntries(Object.entries(state.trip.items).filter(([key, item]) =>
    live.has(key) && (item.edited || item.removed || item.checked || item.have)));
  return { ...state, trip: { ...state.trip, items } };
}

export function saveDish(state: AppState, dish: Dish): AppState {
  const result = toDishBody(dish.name, dish.ingredients.map(i => ({ ...i, amount: formatAmount(i.amount) })));
  if (result.error) throw Error(result.error);
  // Match the original's saved ingredient spelling, excluding the recipe being edited.
  const known = new Map(knownIngredients(state.dishes.filter(d => d.id !== dish.id)).map(i => [i.key, i.name]));
  const body = result.body!;
  const ingredients = body.ingredients.map(ingredient => {
    const name = ingredient.name.normalize('NFC');
    const key = fold(name);
    if (!known.has(key)) known.set(key, name);
    return { ...ingredient, name: known.get(key)! };
  });
  const saved = { id: dish.id, ...body, ingredients };
  const dishes = state.dishes.some(d => d.id === dish.id)
    ? state.dishes.map(d => d.id === dish.id ? saved : d) : [...state.dishes, saved];
  return normalize({ ...state, dishes: dishes.sort((a, b) => a.name.localeCompare(b.name, 'fi')) });
}

export function deleteDish(state: AppState, id: string): AppState {
  return normalize({
    ...state, dishes: state.dishes.filter(d => d.id !== id),
    trip: { ...state.trip, meals: state.trip.meals.filter(m => m.dishId !== id) },
  });
}

export function addMeal(state: AppState, dishId: string, id: string): AppState {
  if (state.trip.meals.length >= 100) throw Error('Enintään 100 ruokaa listalla.');
  if (!state.dishes.some(d => d.id === dishId)) return state;
  return normalize({ ...state, trip: { ...state.trip, meals: [...state.trip.meals, { id, dishId }] } });
}

export function removeMeal(state: AppState, id: string): AppState {
  return normalize({ ...state, trip: { ...state.trip, meals: state.trip.meals.filter(m => m.id !== id) } });
}

export type ItemPatch = Pick<Partial<ItemState>, 'amount' | 'removed' | 'checked' | 'have'> & { resetAmount?: boolean };

export function updateItem(state: AppState, key: string, patch: ItemPatch): AppState {
  if (!generatedItems(state).some(i => i.key === key)) return state;
  let item: ItemState = { ...(state.trip.items[key] ?? { edited: false, amount: null, removed: false, checked: false, have: false }) };
  if ('amount' in patch) {
    if (Number.isNaN(parseAmount(patch.amount))) throw Error('Määrän pitää olla positiivinen luku, esim. 1,5.');
    item.amount = patch.amount ?? null;
    item.edited = true;
  }
  if (patch.resetAmount) { item.amount = null; item.edited = false; }
  if ('removed' in patch) {
    item.removed = !!patch.removed;
    if (patch.removed) { item.checked = false; item.have = false; }
  }
  item = markClause(item, patch);
  return normalize({ ...state, trip: { ...state.trip, items: { ...state.trip.items, [key]: item } } });
}

export function addExtra(state: AppState, name: string, id: string): AppState {
  name = tidy(name);
  if (!name) throw Error('Anna tuotteelle nimi.');
  if (name.length > 100) throw Error('Nimi on liian pitkä.');
  if (state.trip.extras.length >= 200) throw Error('Enintään 200 muuta ostosta listalla.');
  return { ...state, trip: { ...state.trip, extras: [...state.trip.extras, { id, name, checked: false, have: false }] } };
}

export function updateExtra(state: AppState, id: string, patch: Marks): AppState {
  return { ...state, trip: { ...state.trip, extras: state.trip.extras.map(extra => extra.id === id ? markClause(extra, patch) : extra) } };
}

export function removeExtra(state: AppState, id: string): AppState {
  return { ...state, trip: { ...state.trip, extras: state.trip.extras.filter(extra => extra.id !== id) } };
}

export function archiveTrip(state: AppState, now: number, id: string): AppState {
  const trip = readTrip(state);
  if (!trip.meals.length && !trip.extras.length) throw Error('Lista on tyhjä.');
  const snapshot = {
    id, createdAt: trip.createdAt, archivedAt: now,
    meals: trip.meals.map(meal => meal.name),
    items: trip.items.map(({ name, unit, amount, checked, have }) => ({ name, unit, amount, checked, have })),
    extras: trip.extras.map(({ name, checked, have }) => ({ name, checked, have })),
  };
  return {
    ...state, trip: emptyTrip(now),
    history: [snapshot, ...state.history].sort((a, b) => b.archivedAt - a.archivedAt).slice(0, 200),
  };
}

// Report recovery separately so the storage layer can preserve the exact original bytes.
export function decodeState(raw: string | null): { state: AppState; unreadableRaw: string | null } {
  if (raw === null) return { state: emptyState(), unreadableRaw: null };
  try {
    const state = JSON.parse(raw);
    if (state.version !== 1 || !Array.isArray(state.dishes) || !Array.isArray(state.history)
      || !Array.isArray(state.trip?.meals) || !Array.isArray(state.trip?.extras) || !state.trip.items) {
      throw Error('Invalid stored document');
    }
    return { state: normalize(state), unreadableRaw: null };
  } catch { return { state: emptyState(), unreadableRaw: raw }; }
}
