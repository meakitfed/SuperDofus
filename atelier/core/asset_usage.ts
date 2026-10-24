// Where each kind of image lives in a world, and who references it (no image library needed: used by the rules).
import type { World } from "./io";

export const CATEGORIES = {
  item: { label: "Icônes d'objets", dir: "Picto/Items", size: 96 },
  spell: { label: "Icônes de sorts", dir: "Picto/Spells", size: 96 },
  monster: { label: "Portraits de monstres", dir: "Picto/Monsters", size: 96 },
  tile: { label: "Tuiles de map", dir: "Maps/Gfx", size: 0 }, // 0 = keep the size
} as const;
export type Category = keyof typeof CATEGORIES;
export const isCategory = (c: string): c is Category => c in CATEGORIES;

/** Who points at each asset id of a category. */
export function usages(w: World, cat: Category): Map<number, { kind: string; id: string | number }[]> {
  const out = new Map<number, { kind: string; id: string | number }[]>();
  const add = (asset: number | undefined, kind: string, id: string | number) => {
    if (asset === undefined) return;
    const l = out.get(asset) ?? [];
    if (!l.some((u) => u.kind === kind && u.id === id)) l.push({ kind, id });
    out.set(asset, l);
  };
  const f = w.files;
  if (cat === "item") for (const i of f.items.items) add(i.icon, "item", i.id);
  if (cat === "spell") {
    // the engine looks an icon up by the spell's `icon` field, but also by the grade id itself (spell bar, variants)
    for (const s of f.spells.spells) {
      add((s as { icon?: number }).icon, "spell", s.id);
      add(s.id, "spell", s.id);
    }
  }
  if (cat === "monster") {
    for (const [id, m] of [...Object.entries(f.monsters.monsters), ...Object.entries(f.monsters.bosses)])
      for (const g of m.grades) add(g.portrait, "monster", id);
  }
  if (cat === "tile") {
    for (const [mid, m] of w.maps) {
      const v = w.visuals.get(m.visual);
      if (v) for (const e of [...v.layers.background, ...v.layers.sortable]) add(e.g, "map", mid);
    }
  }
  return out;
}

