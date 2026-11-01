// A world from a recipe (worlds_src/ascension/recipe.json): floors of Dofus maps linked only inside a floor, a stair
// NPC per floor whose dialogue goes to the other floors' hubs, 0 error; rebuilt on the same id slot with --force.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import sharp from "sharp";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { AtelierError } from "../core/errors";
import { buildRecipe, type Recipe } from "../core/recipe";
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
});
