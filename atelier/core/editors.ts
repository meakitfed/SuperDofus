// Edits of the data files, as pure functions on a World: texts, items and sets. The store wraps each call in
// `edit` (atomic save + one undo step) and the validator then re-checks the whole world.
// Rules of the house: no text is ever written inline (every name goes through an i18n id), ids come from the
// world's own range, and a deletion that would leave a dangling reference is refused.
import { AtelierError } from "./errors";
import type { World } from "./io";
import { nextId, type RangeMap } from "./ranges";
import { itemUsages, textUsages, type Ref } from "./usage";

const bad = (msg: string) => new AtelierError(400, msg);
const conflict = (msg: string) => new AtelierError(409, msg);
const clean = (s: unknown, what: string, max = 200): string => {
  const t = typeof s === "string" ? s.trim() : "";
  if (!t) throw bad(`${what} : valeur vide`);
  if (t.length > max) throw bad(`${what} : ${max} caractères au maximum`);
  return t;
};
const refLabel = (refs: Ref[]) => refs.slice(0, 3).map((r) => `${r.kind} ${r.id}`).join(", ") + (refs.length > 3 ? "…" : "");

// ---- texts ----
export interface TextRow { id: number; text: string; usedBy: Ref[] }

export function listTexts(w: World): TextRow[] {
  const used = textUsages(w);
  return Object.entries(w.files.texts)
    .map(([k, text]) => ({ id: Number(k), text, usedBy: used.get(Number(k)) ?? [] }))
    .sort((a, b) => a.id - b.id);
}

export function addText(w: World, ranges: RangeMap, text: string): number {
  const t = clean(text, "texte", 2000);
  const id = nextTextId(w, ranges);
  w.files.texts[String(id)] = t;
  return id;
}

/** Next free text id: the highest in the world's range + 1 (a deleted id is not reused by accident). */
function nextTextId(w: World, ranges: RangeMap): number {
  const [lo, hi] = ranges.text;
  const used = Object.keys(w.files.texts).map(Number).filter((i) => i >= lo && i <= hi);
  const next = used.length ? Math.max(...used) + 1 : lo;
  if (next > hi) throw conflict("plage d'ids de textes épuisée");
  return next;
}

export function setText(w: World, id: number, text: string): void {
  if (!(String(id) in w.files.texts)) throw new AtelierError(404, `texte ${id} inconnu`);
  w.files.texts[String(id)] = clean(text, "texte", 2000);
}

export function deleteText(w: World, id: number): void {
  if (!(String(id) in w.files.texts)) throw new AtelierError(404, `texte ${id} inconnu`);
  const refs = textUsages(w).get(id) ?? [];
  if (refs.length) throw conflict(`texte ${id} utilisé par ${refLabel(refs)} : modifie-le plutôt que de le supprimer`);
  delete w.files.texts[String(id)];
}

// ---- items ----
export interface ItemInput {
  name: string;
  description?: string;
  icon: number;
  type: number;
  level: number;
  price?: number;
  weight?: number;
  /** [effectId, min, max, 0] rows, same layout as the game's item effects */
  effects: number[][];
  set?: number | null;
}

export interface ItemRow {
  id: number;
  name: string;
  description: string;
  icon: number;
  type: number;
  level: number;
  price: number;
  weight: number;
  effects: number[][];
  set: number | null;
  usedBy: Ref[];
}

type RawItem = World["files"]["items"]["items"][number] & { name?: string; price?: number; weight?: number };

const text = (w: World, id: number | undefined | null) => (id ? w.files.texts[String(id)] ?? "" : "");

export function listItems(w: World): ItemRow[] {
  const used = itemUsages(w);
  return w.files.items.items.map((raw) => {
    const it = raw as RawItem;
    return {
      id: it.id, name: text(w, it.name_id) || it.name || "", description: text(w, it.description_id), icon: it.icon, type: it.type,
      level: it.level, price: it.price ?? 0, weight: it.weight ?? 1, effects: it.effects ?? [], set: it.set ?? null, usedBy: used.get(it.id) ?? [],
    };
  });
}

function checkItem(w: World, i: ItemInput): ItemInput & { name: string } {
  const name = clean(i.name, "nom", 80);
  const description = i.description?.trim() ? clean(i.description, "description", 1000) : undefined;
  const int = (n: unknown, what: string, min: number, max: number) => {
    if (!Number.isInteger(n) || (n as number) < min || (n as number) > max) throw bad(`${what} : entier entre ${min} et ${max} attendu`);
    return n as number;
  };
  const effects = (i.effects ?? []).map((e) => {
    if (!Array.isArray(e) || e.length < 2 || e.length > 4 || !e.every((n) => Number.isInteger(n))) throw bad("effet : [id, min, max, 0] attendu");
    const [id, a, b = 0, c = 0] = e;
    if (id <= 0) throw bad("effet : identifiant invalide");
    return [id, a, b, c];
  });
  if (effects.length > 24) throw bad("24 effets au maximum");
  const set = i.set ?? null;
  if (set !== null && !w.files.items.sets.some((s) => s.id === set)) throw bad(`panoplie ${set} inconnue`);
  return {
    name, description, effects, set,
    icon: int(i.icon, "icône", 1, 2_147_483_647),
    type: int(i.type, "type", 1, 1000),
    level: int(i.level, "niveau", 1, 200),
    price: int(i.price ?? 0, "prix", 0, 100_000_000),
    weight: int(i.weight ?? 1, "poids", 0, 100_000),
  };
}

/** Item id <-> set membership is stored on both sides: keep them equal. */
function syncSet(w: World, itemId: number, set: number | null): void {
  for (const s of w.files.items.sets) s.items = s.items.filter((i) => i !== itemId);
  if (set !== null) {
    const target = w.files.items.sets.find((s) => s.id === set)!;
    target.items.push(itemId);
    // bonus table: one row per number of pieces worn; a new piece gets an (empty) row to fill
    const eff = ((target as { effects?: unknown[] }).effects ??= []);
    while (eff.length < target.items.length) eff.push([]);
  }
}

export function createItem(w: World, ranges: RangeMap, input: ItemInput): number {
  const v = checkItem(w, input);
  const id = nextId(w, "item", ranges.item);
  const nameId = addText(w, ranges, v.name);
  const descId = v.description ? addText(w, ranges, v.description) : undefined;
  const item: RawItem & Record<string, unknown> = {
    id, name_id: nameId, name: v.name, icon: v.icon, type: v.type, level: v.level, weight: v.weight, price: v.price,
    ...(descId ? { description_id: descId } : {}), usable: false, criteria: "", effects: v.effects, set: v.set,
  };
  w.files.items.items.push(item);
  syncSet(w, id, v.set ?? null);
  return id;
}

export function updateItem(w: World, ranges: RangeMap, id: number, input: ItemInput): void {
  const raw = w.files.items.items.find((i) => i.id === id) as (RawItem & Record<string, unknown>) | undefined;
  if (!raw) throw new AtelierError(404, `objet ${id} inconnu`);
  const v = checkItem(w, input);
  // the name text is rewritten in place (same id); a description is created or removed as needed
  if (raw.name_id && String(raw.name_id) in w.files.texts) w.files.texts[String(raw.name_id)] = v.name;
  else raw.name_id = addText(w, ranges, v.name);
  if (v.description) {
    if (raw.description_id && String(raw.description_id) in w.files.texts) w.files.texts[String(raw.description_id)] = v.description;
    else raw.description_id = addText(w, ranges, v.description);
  } else if (raw.description_id) {
    const d = raw.description_id;
    delete raw.description_id;
    if (!(textUsages(w).get(d)?.length)) delete w.files.texts[String(d)];
  }
  Object.assign(raw, { name: v.name, icon: v.icon, type: v.type, level: v.level, price: v.price, weight: v.weight, effects: v.effects, set: v.set });
  syncSet(w, id, v.set ?? null);
}

export function deleteItem(w: World, id: number): void {
  const idx = w.files.items.items.findIndex((i) => i.id === id);
  if (idx < 0) throw new AtelierError(404, `objet ${id} inconnu`);
  const refs = itemUsages(w).get(id) ?? [];
  if (refs.length) throw conflict(`objet ${id} utilisé par ${refLabel(refs)} : retire d'abord ces références`);
  const [gone] = w.files.items.items.splice(idx, 1);
  syncSet(w, id, null);
  for (const t of [gone.name_id, gone.description_id]) if (t && !(textUsages(w).get(t)?.length)) delete w.files.texts[String(t)];
}

// ---- sets ----
export interface SetRow { id: number; name: string; items: number[] }

export function listSets(w: World): SetRow[] {
  return w.files.items.sets.map((s) => ({ id: s.id, name: text(w, s.name_id), items: s.items }));
}

export function createSet(w: World, ranges: RangeMap, name: string): number {
  const n = clean(name, "nom", 80);
  const id = nextId(w, "set", ranges.set);
  const nameId = addText(w, ranges, n);
  w.files.items.sets.push({ id, name_id: nameId, items: [], effects: [] } as never);
  return id;
}

export function renameSet(w: World, id: number, name: string): void {
  const s = w.files.items.sets.find((x) => x.id === id);
  if (!s) throw new AtelierError(404, `panoplie ${id} inconnue`);
  if (s.name_id && String(s.name_id) in w.files.texts) w.files.texts[String(s.name_id)] = clean(name, "nom", 80);
  else throw bad(`panoplie ${id} sans nom`);
}

export function deleteSet(w: World, id: number): void {
  const idx = w.files.items.sets.findIndex((s) => s.id === id);
  if (idx < 0) throw new AtelierError(404, `panoplie ${id} inconnue`);
  if (w.files.items.sets[idx].items.length) throw conflict("panoplie non vide : retire d'abord ses objets");
  const [gone] = w.files.items.sets.splice(idx, 1);
  if (gone.name_id && !(textUsages(w).get(gone.name_id)?.length)) delete w.files.texts[String(gone.name_id)];
}
