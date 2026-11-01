// A world built from a recipe: floors made of real Dofus maps (grid + decor + tile images, copied the way the map
// library does), linked only to each other inside a floor, with one NPC per floor whose dialogue goes up and down.
// The result is an ordinary atelier world (0 error), edited afterwards in the atelier. Rebuilding it (--force)
// starts again from the recipe on the same id slot: whatever was edited in the atelier is lost.
import fs from "node:fs";
import path from "node:path";
import { AtelierError } from "./errors";
import { readI18n } from "./dofus_text";
import * as mp from "./editors_maps";
import * as np from "./editors_npcs";
import { CELLS, neighbors, reachableFromFirstFree } from "./grid";
import { copyGfx, loadDofusMap } from "./library_maps";
import { searchDofusNpcs } from "./library_npcs";
import type { Problem } from "./problems";
import type { WorldStore } from "./store";

export interface RecipeFloor {
  name: string;
  /** Dofus map ids; links between them are kept, every other link is closed */
  maps: number[];
  /** the Dofus map where the stair NPC stands and players arrive */
  hub: number;
  /** NPC cell, and the cell players arrive on; picked near the middle of the hub when absent */
  npc_cell?: number;
  arrive_cell?: number;
}
export interface Recipe {
  id: string;
  name: string;
  /** the stair NPC: its name and the Dofus NPC whose look it wears */
  stair_npc: { name: string; look_npc: number };
  floors: RecipeFloor[];
}
export interface RecipeResult {
  /** Dofus map id -> world map id */
  maps: Record<number, number>;
  /** per floor: hub map, NPC id, NPC cell, arrival cell */
  floors: { hub: number; npc: number; npc_cell: number; arrive_cell: number; maps: number[] }[];
  problems: Problem[];
}

type Raw = Record<string, any>;
const SIDES = ["top", "bottom", "left", "right"] as const;
const OPPOSITE: Record<string, string> = { top: "bottom", bottom: "top", left: "right", right: "left" };
const bad = (m: string) => new AtelierError(400, m);

export function checkRecipe(r: Recipe): void {
  if (!r || typeof r.id !== "string" || typeof r.name !== "string") throw bad("recette : id et name attendus");
  if (!Array.isArray(r.floors) || r.floors.length < 1) throw bad("recette : au moins un étage");
  const all = new Set<number>();
  r.floors.forEach((f, i) => {
    if (!Array.isArray(f.maps) || f.maps.length < 1) throw bad(`étage ${i + 1} : aucune map`);
    if (!f.maps.includes(f.hub)) throw bad(`étage ${i + 1} : la map d'arrivée ${f.hub} n'est pas dans l'étage`);
    for (const m of f.maps) {
      if (all.has(m)) throw bad(`map ${m} dans deux étages`);
      all.add(m);
    }
  });
}

/** Cells reachable on a map (the same convention as the atelier's checks), nearest the middle first. */
function freeCellsByCenter(blocked: Set<number>): number[] {
  const seen = reachableFromFirstFree(blocked);
  const mid = (c: number) => Math.abs((c % 14) - 7) * 2 + Math.abs(Math.floor(c / 14) - 20);
  return [...seen].sort((a, b) => mid(a) - mid(b) || a - b);
}

/** A NPC cell and an arrival cell next to it: both free and reachable, the NPC keeping a free neighbour once placed. */
function pickCells(m: Raw, f: RecipeFloor): { npc: number; arrive: number } {
  const blocked = new Set<number>(m.blocked);
  const free = freeCellsByCenter(blocked);
  const ok = new Set(free);
  if (f.npc_cell !== undefined && f.arrive_cell !== undefined) {
    if (!ok.has(f.npc_cell) || !ok.has(f.arrive_cell)) throw bad(`map ${f.hub} : cellule du PNJ ou d'arrivée bloquée ou inatteignable`);
    return { npc: f.npc_cell, arrive: f.arrive_cell };
  }
  for (const c of free) {
    if (c === m.phoenix || c < 3 * 14 || c >= CELLS - 3 * 14) continue;
    // once the NPC blocks c, the arrival cell must stay reachable from the rest of the map
    const after = reachableFromFirstFree(new Set([...blocked, c]));
    const arrive = neighbors(c).find((n) => after.has(n) && n !== m.phoenix);
    if (arrive !== undefined && after.size >= ok.size - 1) return { npc: c, arrive };
  }
  throw bad(`map ${f.hub} : aucune cellule libre pour le PNJ`);
}

function stairDialog(r: Recipe, i: number, built: RecipeResult["floors"]): np.DialogInput {
  const replies: np.ReplyInput[] = [];
  if (i + 1 < r.floors.length) replies.push({ text: `Monter à l'étage ${i + 2} : ${r.floors[i + 1].name}.`, action: { type: "teleport", map: built[i + 1].hub, cell: built[i + 1].arrive_cell } });
  if (i > 0) replies.push({ text: `Descendre à l'étage ${i} : ${r.floors[i - 1].name}.`, action: { type: "teleport", map: built[i - 1].hub, cell: built[i - 1].arrive_cell } });
  return { start: "start", nodes: { start: { text: `Étage ${i + 1} de la tour : ${r.floors[i].name}. L'escalier monte et descend d'ici.`, replies } } };
}

export function buildRecipe(store: WorldStore, r: Recipe, opts: { force?: boolean } = {}): RecipeResult {
  checkRecipe(r);
  const dir = path.join(store.worldsDir, r.id);
  const prior = store.registry()[r.id];
  if (fs.existsSync(dir)) {
    if (!opts.force) throw new AtelierError(409, `le monde « ${r.id} » existe déjà : --force le reconstruit depuis la recette (les modifications faites dans l'atelier seront perdues)`);
    if (prior && !prior.created) throw new AtelierError(409, `« ${r.id} » n'est pas un monde de l'atelier : pas de reconstruction`);
    fs.rmSync(dir, { recursive: true, force: true });
  }
  store.create(r.id, r.name, prior?.slot);
  const { entry } = store.place(r.id);
  const dofusDir = path.join(store.worldsDir, "dofus");
  const text = readI18n(path.join(store.contentRoot, "I18n", "fr.bin"));
  const look = searchDofusNpcs(path.join(store.dataRoot, "tables", "npcs.json"), path.join(store.contentRoot, "I18n", "fr.bin"), String(r.stair_npc.look_npc))[0];
  if (!look) throw bad(`PNJ Dofus ${r.stair_npc.look_npc} introuvable (apparence du gardien)`);
  store.importBone(r.id, "dofus", look.bone);
  const out: RecipeResult = { maps: {}, floors: [], problems: [] };

  store.edit(r.id, `recette ${r.id}`, (w) => {
    const skeleton = w.files.world.start_map;
    const maps = w.maps as Map<number, Raw>;
    // 1. maps: grid, decor and tile images of each Dofus map, with its exits and coordinates
    r.floors.forEach((f, i) => {
      for (const src of f.maps) {
        const d = loadDofusMap(dofusDir, store.contentRoot, src);
        const missing = new Set(copyGfx(store.contentRoot, dir, d.gfx));
        const place = text(Number(d.map.subarea_name_id)) || f.name;
        const { id } = mp.createMapFromDofus(w, entry.ranges, `Étage ${i + 1} — ${place}`.slice(0, 60), d.map, d.visual, missing);
        Object.assign(maps.get(id)!, { coords: d.map.coords ?? [0, 0], map_change: d.map.map_change ?? {}, source: src });
        out.maps[src] = id;
      }
    });
    // 2. links: the Dofus neighbours inside the same floor, both ways; nothing leads out of a floor
    for (const f of r.floors) {
      const inFloor = new Set(f.maps);
      for (const src of f.maps) {
        const d = JSON.parse(fs.readFileSync(path.join(dofusDir, "maps", `${src}.json`), "utf-8")) as Raw;
        const m = maps.get(out.maps[src])!;
        for (const side of SIDES) {
          const to = Number(d.neighbors?.[side] ?? 0);
          if (!inFloor.has(to)) continue;
          m.neighbors[side] = out.maps[to];
          maps.get(out.maps[to])!.neighbors[OPPOSITE[side]] ??= out.maps[src];
        }
      }
    }
    // 3. start and rebirth on the hubs, then the empty map of the skeleton goes
    const cells = r.floors.map((f) => pickCells(maps.get(out.maps[f.hub])!, f));
    w.files.world.phoenixes = r.floors.map((f) => out.maps[f.hub]);
    mp.setStart(w, out.maps[r.floors[0].hub], cells[0].arrive);
    mp.deleteMap(w, skeleton);
    // 4. one stair NPC per floor, then the dialogues (they point at the other floors' hubs)
    r.floors.forEach((f, i) => {
      const hub = out.maps[f.hub];
      const npc = np.createNpc(w, entry.ranges, { map: hub, cell: cells[i].npc, dir: 1, name: r.stair_npc.name, bone: look.bone, size: look.size, banker: false, shop: null });
      out.floors.push({ hub, npc, npc_cell: cells[i].npc, arrive_cell: cells[i].arrive, maps: f.maps.map((s) => out.maps[s]) });
    });
    r.floors.forEach((_, i) => np.setDialog(w, out.floors[i].npc, stairDialog(r, i, out.floors)));
  });
  out.problems = store.check(r.id);
  return out;
}
