import type { Dish, Generated, Ingredient, ItemState, Marks, ShopItem } from './model.ts';
export const fold = (s: string) => s.normalize('NFC').toLocaleLowerCase('fi');
export const itemKey = (name: string, unit: string) => JSON.stringify([fold(name), fold(unit)]);
export const MIN_AMOUNT = .001;
export const MAX_AMOUNT = 1000000;
export function parseAmount(text: unknown): number | null {
  const s = String(text ?? '').trim().replace(/\s/g, '').replace(',', '.');
  if (!s)
    return null;
  if (!/^(\d+(\.\d{0,3})?|\.\d{1,3})$/.test(s))
    return NaN;
  const n = Number(s);
  return n >= MIN_AMOUNT && n <= MAX_AMOUNT ? n : NaN;
}
export const formatAmount = (n: number | null) => n == null ? '' : String(n).replace('.', ',');
export const tidy = (s: string) => s.trim().replace(/\s+/g, ' ');
const collator = new Intl.Collator('fi', { sensitivity: 'base' });
export function aggregateIngredients(rows: (Ingredient & {
  dishId: string;
  dish: string;
})[]): Generated[] {
  const items = new Map<string, Generated>();
  const seen = new Map<string, Set<string>>();
  for (const { dishId, dish, name, amount, unit } of rows) {
    const key = itemKey(name, unit);
    let item = items.get(key);
    if (!item) {
      item = { key, name, unit, amount: null, dishes: [] };
      items.set(key, item);
      seen.set(key, new Set());
    }
    if (amount != null)
      item.amount = Math.round(((item.amount ?? 0) + amount) * 1000) / 1000;
    if (!seen.get(key)!.has(dishId)) {
      seen.get(key)!.add(dishId);
      item.dishes.push(dish);
    }
  }
  return [...items.values()].sort((a, b) => collator.compare(a.name, b.name) || collator.compare(a.unit, b.unit));
}
export function applyItemState(generated: Generated[], states: Record<string, ItemState>) {
  const items: ShopItem[] = [], removed: ShopItem[] = [];
  for (const item of generated) {
    const s = states[item.key];
    const out = { ...item, recipeAmount: item.amount, amount: s?.edited ? s.amount : item.amount, edited: !!s?.edited, checked: !!s?.checked, have: !!s?.have };
    (s?.removed ? removed : items).push(out);
  }
  return { items, removed };
}
export function markClause<T extends Marks>(before: T, patch: Marks): T {
  const next = { ...before };
  if ('checked' in patch) {
    next.checked = patch.checked;
    if (patch.checked)
      next.have = false;
  }
  if ('have' in patch) {
    next.have = patch.have;
    if (patch.have)
      next.checked = false;
  }
  return next;
}
export const uncheckedFirst = <T extends Marks>(list: T[]) => [...list.filter(i => !i.checked), ...list.filter(i => i.checked)];
export const historyOrder = <T extends Marks>(list: T[]) => [...list.filter(i => !i.have && !i.checked), ...list.filter(i => !i.have && i.checked), ...list.filter(i => i.have)];
export function tripCounts(items: Marks[], extras: Marks[]) { const all = [...items, ...extras], have = all.filter(i => i.have).length, bought = all.filter(i => i.checked && !i.have).length, toBuy = all.length - have; return { left: toBuy - bought, bought, have, toBuy }; }
export function statusText({ left, have, toBuy }: {
  left: number;
  have: number;
  toBuy: number;
}) {
  if (!toBuy && !have)
    return null; const home = have ? ` · kotona ${have}` : ''; return !toBuy ? 'Kaikki on jo kotona' : !left ? 'Kaikki ostettu! 🎉' + home : `${left} / ${toBuy} jäljellä${home}`;
}
export const ingredientSummary = (ingredients: Ingredient[]) => ingredients.map(i => [formatAmount(i.amount), i.unit, i.name].filter(Boolean).join(' ')).join(', ');
export type FormRow = {
  name: string;
  amount: string;
  unit: string;
};
export function toDishBody(name: string, rows: FormRow[]): {
  error: string;
  body?: never;
} | {
  body: Omit<Dish, 'id'>;
  error?: never;
} {
  if (!name.trim())
    return { error: 'Anna ruokalajille nimi.' };
  if (tidy(name).length > 100)
    return { error: 'Nimi on liian pitkä (enintään 100 merkkiä).' };
  const blank = (r: FormRow) => !r.name.trim() && !r.amount.trim() && !r.unit.trim();
  const ingredients: Ingredient[] = [];
  if (rows.filter(r => !blank(r)).length > 100)
    return { error: 'Enintään 100 ainesosaa.' };
  for (const [i, r] of rows.entries()) {
    if (blank(r))
      continue;
    const prefix = `Ainesosa ${i + 1}: `;
    if (!r.name.trim())
      return { error: prefix + 'anna nimi.' };
    if (tidy(r.name).length > 100)
      return { error: prefix + 'nimi on liian pitkä.' };
    const amount = parseAmount(r.amount);
    if (Number.isNaN(amount))
      return { error: prefix + 'määrän pitää olla positiivinen luku (enintään 1 000 000).' };
    if (tidy(r.unit).length > 20)
      return { error: prefix + 'yksikkö on liian pitkä.' };
    ingredients.push({ name: tidy(r.name), amount, unit: tidy(r.unit) });
  }
  return { body: { name: tidy(name), ingredients } };
}
export type Suggestion = {
  name: string;
  unit: string;
  uses: number;
};
export function knownIngredients(dishes: Dish[]) {
  const groups = new Map<string, {
    key: string;
    uses: number;
    names: Map<string, {
      n: number;
      first: number;
    }>;
    units: Map<string, {
      n: number;
      first: number;
    }>;
  }>();
  const bump = (m: Map<string, {
    n: number;
    first: number;
  }>, v: string, o: number) => {
    const c = m.get(v); if (c)
      c.n++;
    else
      m.set(v, { n: 1, first: o });
  };
  const common = (m: Map<string, {
    n: number;
    first: number;
  }>) => [...m].sort((a, b) => b[1].n - a[1].n || a[1].first - b[1].first)[0]?.[0] ?? '';
  dishes.flatMap(d => d.ingredients).forEach((i, o) => {
    const name = tidy(i.name).normalize('NFC'), key = fold(name); if (!key)
      return; let g = groups.get(key); if (!g) {
        g = { key, uses: 0, names: new Map(), units: new Map() };
        groups.set(key, g);
      } g.uses++; bump(g.names, name, o); const u = fold(tidy(i.unit)); if (u)
      bump(g.units, u, o);
  });
  return [...groups.values()].map(g => ({ key: g.key, name: common(g.names), unit: common(g.units), uses: g.uses }));
}
export function suggestIngredients(dishes: Dish[], q: string, limit = 8): Suggestion[] { const needle = fold(tidy(q)); return knownIngredients(dishes).filter(i => i.key.includes(needle)).sort((a, b) => Number(!a.key.startsWith(needle)) - Number(!b.key.startsWith(needle)) || b.uses - a.uses || collator.compare(a.name, b.name)).slice(0, limit).map(({ name, unit, uses }) => ({ name, unit, uses })); }
export function visibleSuggestions<T extends {
  name: string;
}>(answer: {
  query: string;
  items: T[];
} | null, query: string): T[] {
  if (!answer || answer.query !== query)
    return []; return answer.items.length === 1 && answer.items[0].name === query ? [] : answer.items;
}
export const UNITS = ['g', 'kg', 'dl', 'l', 'ml', 'rkl', 'tl', 'kpl', 'pkt', 'prk', 'pss', 'tlk', 'nippu'];
export const formatDay = (ms: number) => new Intl.DateTimeFormat('fi-FI', { day: 'numeric', month: 'numeric', year: 'numeric', timeZone: 'Europe/Helsinki' }).format(new Date(ms));
