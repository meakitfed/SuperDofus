// The monsters of a recipe world (L'Ascension): every Dofus monster (same id, same stats and spells, no drops: the loot
// is the world's bonus equipment, world.json "rates") placed by level band on the floors. Each floor is cut in rings
// around its hub (breadth-first over the floor's links): the hub has no monster, the first ring the bottom of the band,
// the farthest ring its top. Each ring is a monster zone with `levels` (only the grades in range are drawn), the dungeon
// bosses of that range (`bosses`) and `boss_pct` (each member's chance to be one of them; game/src/sim/monster_spawner.gd).
// Re-run alone (npm run recipe -- <recette> --monsters) it rewrites monsters.json and the maps' zones, nothing else.
import fs from "node:fs";
import path from "node:path";
import { AtelierError } from "./errors";
import type { WorldStore } from "./store";

export interface RecipeMonsters {
  /** [lo, hi] level band of each floor, in floor order */
  bands: [number, number][];
  /** width of a ring's level range (default 15) */
  window?: number;
  /** % chance for each group member to be a dungeon boss of the range (default 5) */
  boss_pct?: number;
  /** the world's own rates (world.json "rates", same keys as the server options) */
  rates?: Record<string, unknown>;
}
export interface MonstersResult {
  /** per floor: its zones, in ring order */
  floors: { zones: { key: string; ring: number; levels: [number, number]; maps: number[]; monsters: number; bosses: number }[] }[];
  monsters: number;
  bosses: number;
  /** Dofus monsters left out: their skeleton is not in the content */
  left_out: number[];
}

type Raw = Record<string, any>;
const bad = (m: string) => new AtelierError(400, m);
/** a monster has a grade in [lo, hi] */
const hasGrade = (mo: Raw, lo: number, hi: number) => (mo.grades as Raw[]).some((g) => g.level >= lo && g.level <= hi);
/** how far a monster's closest grade is from [lo, hi] */
const gap = (mo: Raw, lo: number, hi: number) => Math.min(...(mo.grades as Raw[]).map((g) => (g.level < lo ? lo - g.level : g.level > hi ? g.level - hi : 0)));
const BOSS_FALLBACK = 3;

export function checkMonsters(m: RecipeMonsters, floors: number): void {
  if (!Array.isArray(m.bands) || m.bands.length !== floors) throw bad(`monstres : une tranche de niveaux par étage attendue (${floors})`);
  for (const [lo, hi] of m.bands) if (!Number.isInteger(lo) || !Number.isInteger(hi) || lo < 1 || hi < lo) throw bad(`monstres : tranche ${lo}-${hi} invalide`);
  if (m.window !== undefined && (!Number.isInteger(m.window) || m.window < 1)) throw bad("monstres : window entier ≥ 1");
  if (m.boss_pct !== undefined && (typeof m.boss_pct !== "number" || m.boss_pct < 0 || m.boss_pct > 100)) throw bad("monstres : boss_pct entre 0 et 100");
}

/** The level range of ring r (1..rings) of a band: the bottom of the band at ring 1, its top at the last ring. */
export function ringLevels(lo: number, hi: number, r: number, rings: number, window: number): [number, number] {
  const w = Math.min(window, hi - lo);
  const start = rings <= 1 ? lo : Math.round(lo + ((hi - lo - w) * (r - 1)) / (rings - 1));
  return [start, start + w];
}

/** `hubs`: the world map id of each floor's hub, in floor order (the floors are the maps linked to them). */
export function applyMonsters(store: WorldStore, id: string, m: RecipeMonsters, hubs: number[]): MonstersResult {
  checkMonsters(m, hubs.length);
  const window = m.window ?? 15;
  const bossPct = m.boss_pct ?? 5;
  const dofus = JSON.parse(fs.readFileSync(path.join(store.worldsDir, "dofus", "monsters.json"), "utf-8")) as Raw;
  const { entry } = store.place(id);
  const out: MonstersResult = { floors: [], monsters: 0, bosses: 0, left_out: [] };
  // what the game itself does with a Dofus monster: the spells the data lacks are dropped (WorldFights.monster_fighter),
  // a missing portrait shows nothing; a monster whose skeleton is missing would be invisible: it is left out
  const spellIds = new Set(((JSON.parse(fs.readFileSync(path.join(store.dataRoot, "spells.json"), "utf-8")).spells ?? []) as Raw[]).map((x) => x.id as number));
  const has = (rel: string) => fs.existsSync(path.join(store.contentRoot, rel));
  const visible = (mo: Raw) => (mo.grades as Raw[]).every((g) => has(`Characters/Bones/${String(g.look).replace(/[{}]/g, "").split("|")[0]}`));
  const usable = (all: Raw) => Object.fromEntries(Object.entries(all ?? {}).filter(([k, mo]) => visible(mo as Raw) || (out.left_out.push(Number(k)), false)));
  dofus.monsters = usable(dofus.monsters);
  dofus.bosses = usable(dofus.bosses);
  const copy = (mo: Raw): Raw => {
    const c = structuredClone(mo);
    for (const g of c.grades as Raw[]) {
      g.drops = []; // the loot is the world's bonus equipment
      g.spells = (g.spells as number[]).filter((x) => spellIds.has(x));
      if (g.portrait !== undefined && !has(`Picto/Monsters/${g.portrait}.webp`) && !has(`Picto/Monsters/${g.portrait}.png`)) delete g.portrait;
    }
    return c;
  };

  store.edit(id, `recette ${id} : monstres`, (w) => {
    const maps = w.maps as Map<number, Raw>;
    const monsters: Raw = {};
    const bosses: Raw = {};
    const subareas: Raw = {};
    let key = entry.ranges.monster[1]; // the atelier's zone keys: down from the top of the monster range
    // the maps of each floor by ring (breadth-first from the hub over the floor's links)
    hubs.forEach((hub, f) => {
      if (!maps.has(hub)) throw bad(`étage ${f + 1} : map d'arrivée ${hub} absente du monde`);
      const ring = new Map<number, number>([[hub, 0]]);
      const queue = [hub];
      while (queue.length) {
        const cur = queue.shift()!;
        for (const to of Object.values(maps.get(cur)!.neighbors ?? {}) as number[])
          if (maps.has(to) && !ring.has(to)) { ring.set(to, ring.get(cur)! + 1); queue.push(to); }
      }
      const rings = Math.max(0, ...ring.values());
      const [lo, hi] = m.bands[f];
      const floor: MonstersResult["floors"][number] = { zones: [] };
      const hubMap = maps.get(hub)!;
      hubMap.monster_spawn = false;
      delete hubMap.subarea;
      delete hubMap.area;
      for (let r = 1; r <= rings; r++) {
        const levels = ringLevels(lo, hi, r, rings, window);
        const mobs = Object.keys(dofus.monsters).filter((k) => hasGrade(dofus.monsters[k], ...levels)).map(Number);
        let bossIds = Object.keys(dofus.bosses ?? {}).filter((k) => hasGrade(dofus.bosses[k], ...levels)).map(Number);
        if (!bossIds.length) // no boss of that range: the closest ones of the band, at their nearest grade
          bossIds = Object.keys(dofus.bosses ?? {}).filter((k) => hasGrade(dofus.bosses[k], lo, hi) || gap(dofus.bosses[k], lo, hi) <= window)
            .sort((a, b) => gap(dofus.bosses[a], ...levels) - gap(dofus.bosses[b], ...levels) || Number(a) - Number(b))
            .slice(0, BOSS_FALLBACK).map(Number);
        const z = String(key--);
        subareas[z] = { level: levels[1], area: Number(z), monsters: mobs, levels, bosses: bossIds, boss_pct: bossPct };
        for (const k of mobs) monsters[k] ??= copy(dofus.monsters[k]);
        for (const k of bossIds) bosses[k] ??= copy(dofus.bosses[k]);
        const inRing = [...ring].filter(([, d]) => d === r).map(([mid]) => mid);
        for (const mid of inRing) Object.assign(maps.get(mid)!, { subarea: Number(z), area: Number(z), monster_spawn: true });
        floor.zones.push({ key: z, ring: r, levels, maps: inRing, monsters: mobs.length, bosses: bossIds.length });
      }
      out.floors.push(floor);
    });
    w.files.monsters.monsters = monsters;
    w.files.monsters.bosses = bosses;
    w.files.monsters.subareas = subareas;
    const world = w.files.world as Raw;
    world.base = "dofus"; // uses the Dofus spells, monsters and images without holding them (validation: Options.base)
    if (m.rates) world.rates = m.rates;
    out.monsters = Object.keys(monsters).length;
    out.bosses = Object.keys(bosses).length;
  });
  return out;
}
