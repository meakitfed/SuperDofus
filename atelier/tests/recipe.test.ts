// A world from a recipe (worlds_src/ascension/recipe.json): floors of Dofus maps linked only inside a floor, a stair
// NPC per floor whose dialogue goes to the other floors' hubs, 0 error; rebuilt on the same id slot with --force.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import sharp from "sharp";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { AtelierError } from "../core/errors";
import { buildRecipe, rebuildMonsters, type Recipe } from "../core/recipe";
import { ringLevels } from "../core/recipe_monsters";
import { WorldStore } from "../core/store";
import { writeFakeI18n } from "./fake_dofus";

let tmp: string, store: WorldStore;

// four Dofus maps in a row (1 - 2 - 3 - 4): the recipe puts 1, 2 on the first floor, 3 on the second; 4 stays out
const RECIPE: Recipe = {
  id: "tour_test", name: "Tour de test", stair_npc: { name: "Gardien", look_npc: 77 },
  floors: [{ name: "Bas", hub: 7001, maps: [7001, 7002] }, { name: "Haut", hub: 7003, maps: [7003] }],
};

beforeAll(async () => {
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), "atelier-recipe-"));
  const content = path.join(tmp, "content", "Content");
  fs.mkdirSync(path.join(content, "Maps", "Gfx"), { recursive: true });
  await sharp({ create: { width: 90, height: 60, channels: 4, background: "#446688" } }).webp().toFile(path.join(content, "Maps", "Gfx", "12.webp"));
  writeFakeI18n(path.join(content, "I18n", "fr.bin"), { 1: "Plaine", 5: "Gardien des clés" });
  fs.mkdirSync(path.join(content, "Characters", "Bones", "2719"), { recursive: true });
  fs.writeFileSync(path.join(content, "Characters", "Bones", "2719", "0.webp"), "");
  const data = path.join(tmp, "data", "tables");
  fs.mkdirSync(data, { recursive: true });
  fs.writeFileSync(path.join(data, "npcs.json"), JSON.stringify({ objectsById: { 77: { nameId: 5, look: "{2719|||100}" } } }));
  // monsters: 1 (grades 2 and 5, one spell the data lacks, a portrait that is not there), 2 (grade 15), 3 (no skeleton),
  // boss 9 (grade 8)
  fs.mkdirSync(path.join(content, "Characters", "Bones", "4907"), { recursive: true });
  fs.mkdirSync(path.join(content, "Picto", "Monsters"), { recursive: true });
  fs.writeFileSync(path.join(content, "Picto", "Monsters", "1.webp"), "");
  fs.writeFileSync(path.join(tmp, "data", "spells.json"), JSON.stringify({ spells: [{ id: 500 }] }));
  const grade = (monster: number, level: number, bone = 4907, portrait = 1) => ({
    monster, level, look: `{${bone}|||100}`, portrait, spells: [500, 501], drops: [{ item: 362, pct: 50 }], kamas: [1, 2], hp: 10,
  });
  fs.mkdirSync(path.join(tmp, "worlds", "dofus"), { recursive: true });
  fs.writeFileSync(path.join(tmp, "worlds", "dofus", "monsters.json"), JSON.stringify({
    subareas: {},
    monsters: { 1: { name_id: 1, grades: [grade(1, 2), grade(1, 5, 4907, 77)] }, 2: { name_id: 1, grades: [grade(2, 15)] }, 3: { name_id: 1, grades: [grade(3, 3, 9999)] } },
    bosses: { 9: { name_id: 1, grades: [grade(9, 8)] } },
  }));
  const dofus = path.join(tmp, "worlds", "dofus", "maps");
  fs.mkdirSync(dofus, { recursive: true });
  const ids = [7001, 7002, 7003, 7004];
  ids.forEach((id, i) => {
    const neighbors: Record<string, number> = {};
    if (i > 0) neighbors.left = ids[i - 1];
    if (i < ids.length - 1) neighbors.right = ids[i + 1];
    fs.writeFileSync(path.join(dofus, `${id}.json`), JSON.stringify({
      id, subarea: 10, subarea_name_id: 1, outdoor: true, coords: [i, 0], visual: id, neighbors, triggers: [], map_change: { 27: 131 },
      blocked: [0, 1, 2], fight_blocked: [0, 1, 2], los_blocked: [], placement: { red: [100, 101], blue: [200, 201] }, monster_spawn: true,
    }));
    fs.writeFileSync(path.join(content, "Maps", `${id}.json`), JSON.stringify({
      id, bg: 4278190080, neighbors, cell_flags: ["mov"], cells: [[0]], animated: [],
      layers: { background: [{ g: 12, c: 4286611584, t: [1, 0, 0, 1, 100, 100] }], sortable: [], foreground: [] },
    }));
  });
  store = new WorldStore(path.join(tmp, "worlds"), path.join(tmp, "r.json"), path.resolve(__dirname, "..", "templates"));
  store.contentRoot = content;
  store.dataRoot = path.join(tmp, "data");
});
afterAll(() => fs.rmSync(tmp, { recursive: true, force: true }));

describe("monde construit depuis une recette", () => {
  it("fait des étages fermés, un gardien par étage qui monte et descend, sans erreur", () => {
    const r = buildRecipe(store, RECIPE);
    expect(r.problems.filter((p) => p.severity === "error")).toEqual([]);
    const w = JSON.parse(fs.readFileSync(path.join(tmp, "worlds", "tour_test", "world.json"), "utf-8"));
    expect(w.maps.sort()).toEqual(Object.values(r.maps).sort());
    expect(w.start_map).toBe(r.maps[7001]);
    const map = (src: number) => JSON.parse(fs.readFileSync(path.join(tmp, "worlds", "tour_test", "maps", `${r.maps[src]}.json`), "utf-8"));
    // 1 - 2 stay linked both ways, 2 - 3 is cut (another floor), 4 is not imported
    expect(map(7001).neighbors).toEqual({ right: r.maps[7002] });
    expect(map(7002).neighbors).toEqual({ left: r.maps[7001] });
    expect(map(7003).neighbors).toEqual({});
    expect(r.maps[7004]).toBeUndefined();
    expect(map(7001)).toMatchObject({ coords: [0, 0], map_change: { 27: 131 }, source: 7001, name: "Étage 1 — Plaine" });
    const dialogs = JSON.parse(fs.readFileSync(path.join(tmp, "worlds", "tour_test", "dialogs.json"), "utf-8")).dialogs;
    const replies = (i: number) => dialogs[String(r.floors[i].npc)].nodes.start.replies;
    expect(replies(0).map((x: { action: unknown }) => x.action)).toEqual([{ type: "teleport", map: r.floors[1].hub, cell: r.floors[1].arrive_cell }]);
    expect(replies(1).map((x: { action: unknown }) => x.action)).toEqual([{ type: "teleport", map: r.floors[0].hub, cell: r.floors[0].arrive_cell }]);
    expect(fs.existsSync(path.join(tmp, "worlds", "tour_test", "Content", "Characters", "Bones", "2719"))).toBe(true);
  });

  it("refuse d'écraser un monde existant sans --force, et le reconstruit sur le même emplacement d'ids", () => {
    expect(() => buildRecipe(store, RECIPE)).toThrow(AtelierError);
    const slot = store.registry().tour_test.slot;
    const r = buildRecipe(store, RECIPE, { force: true });
    expect(store.registry().tour_test.slot).toBe(slot);
    expect(r.problems.filter((p) => p.severity === "error")).toEqual([]);
  });

  it("refuse une recette incohérente", () => {
    expect(() => buildRecipe(store, { ...RECIPE, id: "autre", floors: [{ name: "x", hub: 7003, maps: [7001] }] })).toThrow(/n'est pas dans l'étage/);
    expect(() => buildRecipe(store, { ...RECIPE, id: "autre", floors: [{ name: "x", hub: 7001, maps: [7001] }, { name: "y", hub: 7001, maps: [7001] }] })).toThrow(/deux étages/);
  });

  it("place les monstres Dofus par tranche, en anneaux autour du gardien, sans butin, avec les boss et les taux du monde", () => {
    const recipe: Recipe = {
      ...RECIPE, id: "tour_mobs",
      floors: [{ name: "Bas", hub: 7001, maps: [7001, 7002, 7003] }],
      monsters: { bands: [[1, 20]], window: 6, boss_pct: 5, rates: { "bonus-drops": true } },
    };
    const r = buildRecipe(store, recipe);
    expect(r.problems.filter((p) => p.severity === "error")).toEqual([]);
    const read = (f: string) => JSON.parse(fs.readFileSync(path.join(tmp, "worlds", "tour_mobs", f), "utf-8"));
    const mons = read("monsters.json");
    // two rings (7002, then 7003): 1-7, then 14-20
    expect(r.monsters!.floors[0].zones.map((z) => z.levels)).toEqual([[1, 7], [14, 20]]);
    expect(ringLevels(1, 20, 1, 2, 6)).toEqual([1, 7]);
    const [z1, z2] = r.monsters!.floors[0].zones;
    expect(mons.subareas[z1.key]).toMatchObject({ monsters: [1], levels: [1, 7], bosses: [9], boss_pct: 5 });
    expect(mons.subareas[z2.key].monsters).toEqual([2]);
    expect(mons.subareas[z2.key].bosses).toEqual([9]); // none in 14-20: the closest of the band
    expect(r.monsters!.left_out).toEqual([3]);
    const g = mons.monsters["1"].grades;
    expect(g.map((x: { drops: unknown[] }) => x.drops)).toEqual([[], []]);
    expect(g[0].spells).toEqual([500]);
    expect(g[0].portrait).toBe(1);
    expect(g[1].portrait).toBeUndefined();
    expect(Object.keys(mons.bosses)).toEqual(["9"]);
    const map = (src: number) => read(`maps/${r.maps[src]}.json`);
    expect(map(7001).monster_spawn).toBe(false);
    expect(map(7002)).toMatchObject({ monster_spawn: true, subarea: Number(z1.key) });
    expect(map(7003)).toMatchObject({ monster_spawn: true, subarea: Number(z2.key) });
    expect(read("world.json")).toMatchObject({ base: "dofus", rates: { "bonus-drops": true } });
    // only the monsters again: the NPC stays, the zones are rewritten the same
    const again = rebuildMonsters(store, recipe);
    expect(again.problems.filter((p) => p.severity === "error")).toEqual([]);
    expect(Object.keys(read("npcs.json").maps)).toEqual([String(r.maps[7001])]);
    expect(read("monsters.json").subareas).toEqual(mons.subareas);
  });

  it("sans « base: dofus », un monstre aux ids Dofus reste une erreur de plage", () => {
    const w = JSON.parse(fs.readFileSync(path.join(tmp, "worlds", "tour_mobs", "world.json"), "utf-8"));
    delete w.base;
    fs.writeFileSync(path.join(tmp, "worlds", "tour_mobs", "world.json"), JSON.stringify(w));
    const s2 = new WorldStore(path.join(tmp, "worlds"), path.join(tmp, "r.json"), path.resolve(__dirname, "..", "templates"));
    s2.contentRoot = store.contentRoot;
    s2.dataRoot = store.dataRoot;
    expect(s2.check("tour_mobs").map((p) => p.code)).toContain("E_ID_RANGE");
  });
});
