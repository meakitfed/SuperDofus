// Id ranges: every world owns a slice of each kind of id, so worlds never collide with each other nor with the
// Dofus data (whose ids stay below 4e8; map ids reach 1.6e8). Slice of kind k for slot n:
//   [BASE + idx(k) * KIND_SPAN + n * SLOT, BASE + idx(k) * KIND_SPAN + (n + 1) * SLOT - 1]
import type { World } from "./io";

export const KINDS = ["text", "item", "set", "spell", "monster", "npc", "quest", "step", "objective", "interactive", "map", "asset", "breed"] as const;
export type Kind = (typeof KINDS)[number];
export type RangeMap = Record<Kind, [number, number]>;

const BASE = 1_000_000_000;
export const SLOT = 100_000;
const KIND_SPAN = 90_000_000;
// ids stay below 2^31 (the last kind, `breed`, sits at BASE + 12 * KIND_SPAN): 600 slots keep every range inside
export const MAX_SLOT = 600;

export function rangesForSlot(slot: number): RangeMap {
  if (!Number.isInteger(slot) || slot < 1 || slot > MAX_SLOT) throw new Error(`emplacement d'ids invalide : ${slot}`);
  const out = {} as RangeMap;
  KINDS.forEach((k, idx) => {
    const lo = BASE + idx * KIND_SPAN + slot * SLOT;
    out[k] = [lo, lo + SLOT - 1];
  });
  return out;
}

/** La Vertèbre predates the allocator: its real ranges (worlds_src/vertebre/gen/common.py). */
export const VERTEBRE_RANGES: RangeMap = {
  text: [9_000_000, 9_099_999],
  item: [9_100_000, 9_199_999],
  set: [9_100, 9_199],
  spell: [9_200_000, 9_299_999],
  monster: [910_000, 919_999],
  npc: [920_000, 929_999],
  quest: [930_000, 930_999],
  step: [931_000, 931_999],
  objective: [932_000, 932_999],
  interactive: [933_000, 933_999],
  map: [9_000, 9_399],
  asset: [9_300_000, 9_399_999], // icon ids of imported images (the Vertebre keeps its own numbering)
  breed: [901, 999],
};

export interface WorldEntry {
  /** Allocator slot, or 0 for a legacy world with hand-set ranges. */
  slot: number;
  ranges: RangeMap;
  /** Created by the atelier: the only worlds it may delete. */
  created: boolean;
}
export type Registry = Record<string, WorldEntry>;

export function defaultRegistry(): Registry {
  return { vertebre: { slot: 0, ranges: VERTEBRE_RANGES, created: false } };
}

export function nextSlot(reg: Registry): number {
  const used = new Set(Object.values(reg).map((e) => e.slot));
  for (let s = 1; s <= MAX_SLOT; s++) if (!used.has(s)) return s;
  throw new Error("plus d'emplacement d'ids libre");
}

/** Every id a world defines, by kind (steps, objectives and interactives included). */
export function collectIds(w: World): Record<Kind, number[]> {
  const f = w.files;
  const quests = Object.values(f.quests.quests);
  const mobs = [...Object.keys(f.monsters.monsters), ...Object.keys(f.monsters.bosses)].map(Number);
  return {
    text: Object.keys(f.texts).map(Number),
    item: f.items.items.map((i) => i.id),
    set: f.items.sets.map((s) => s.id),
    spell: f.spells.spells.map((s) => s.id),
    monster: mobs,
    npc: [...new Set(Object.values(f.npcs.maps).flatMap((l) => l.map((n) => n.npc)))],
    quest: quests.map((q) => q.id),
    step: quests.flatMap((q) => q.steps.map((s) => s.id)),
    objective: quests.flatMap((q) => q.steps.flatMap((s) => s.objectives.map((o) => o.id))),
    // elements placed on maps, and the jobs and skills they use: one numbering. A world with hand-set ranges
    // (La Vertèbre) keeps its own skill numbers, which are not ids of a slot.
    interactive: [
      ...Object.values(f.interactives.maps).flatMap((l) => l.map((e) => e.e)),
      ...[...Object.keys(f.skills.objectsById), ...Object.keys(f.jobs?.objectsById ?? {}), ...Object.keys(f.dungeons?.dungeons ?? {})].map(Number).filter((n) => n >= BASE),
    ],
    map: [...w.maps.keys()],
    asset: [], // images live on disk: see assets.ts
    breed: [...new Set([...f.world.breeds, ...Object.keys(f.breeds.objectsById).map(Number)])],
  };
}

/** Next free id of a kind in the world's range (never reuses a deleted id's number below the highest in use). */
export function nextId(w: World, kind: Kind, range: [number, number]): number {
  const used = collectIds(w)[kind].filter((i) => i >= range[0] && i <= range[1]);
  const next = used.length ? Math.max(...used) + 1 : range[0];
  if (next > range[1]) throw new Error(`plage d'ids épuisée pour « ${kind} »`);
  return next;
}
