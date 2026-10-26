// The Dofus items (game/data/items.json) as templates: search by name or number, get a ready-to-edit item.
import fs from "node:fs";
import { AtelierError } from "./errors";
import { WEAPON_TYPES, type ItemInput } from "./editors";

/** Types the item editor knows (the same list as the form). */
export const EDITABLE_TYPES = [...WEAPON_TYPES, 1, 9, 10, 11, 12, 16, 17, 82];
export const TEMPLATE_LIMIT = 30;

export interface ItemTemplate extends ItemInput { source: number; weapon: ItemInput["weapon"] }

const fold = (s: string) => s.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();
let cache: { file: string; rows: { raw: Record<string, any>; key: string }[] } | null = null;

function rowsOf(file: string) {
  if (cache?.file === file) return cache.rows;
  if (!fs.existsSync(file)) throw new AtelierError(404, "les objets du jeu ne sont pas sur cet ordinateur (game/data/items.json)");
  const data = JSON.parse(fs.readFileSync(file, "utf-8")) as { items: Record<string, any>[] };
  const rows = data.items.filter((i) => EDITABLE_TYPES.includes(i.type) && typeof i.name === "string" && i.name).map((raw) => ({ raw, key: fold(raw.name) }));
  cache = { file, rows };
  return rows;
}

export function searchDofusItems(file: string, query: string): ItemTemplate[] {
  const q = fold(query.trim());
  if (q.length < 2) throw new AtelierError(400, "recherche : au moins 2 caractères (un nom d'objet, ou un numéro)");
  const byNumber = /^\d+$/.test(q);
  const hits = rowsOf(file).filter((r) => (byNumber ? String(r.raw.id) === q || r.key.includes(q) : r.key.includes(q)));
  hits.sort((a, b) => (a.key.startsWith(q) === b.key.startsWith(q) ? a.raw.level - b.raw.level : a.key.startsWith(q) ? -1 : 1));
  return hits.slice(0, TEMPLATE_LIMIT).map(({ raw }) => ({
    source: raw.id, name: raw.name, description: "", icon: raw.icon, type: raw.type, level: Math.max(1, Math.min(200, raw.level ?? 1)),
    price: raw.price ?? 0, weight: raw.weight ?? 1,
    effects: ((raw.effects ?? []) as number[][]).slice(0, 24).map((e) => [e[0], e[1] ?? 0, e[2] ?? 0, 0]),
    weapon: raw.weapon ? { ap: raw.weapon.ap, min_range: raw.weapon.min_range, range: raw.weapon.range, crit: raw.weapon.crit, crit_bonus: raw.weapon.crit_bonus, in_line: raw.weapon.in_line ? 1 : 0, los: raw.weapon.los ? 1 : 0, per_turn: raw.weapon.per_turn } : null,
    set: null,
  }));
}
