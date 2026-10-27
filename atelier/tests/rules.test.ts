// Mutation tests: start from the valid mini world, break exactly one thing, expect exactly that rule to fire.
// The coverage guard fails if a rule of RULES has no mutation here (same idea as the Godot harness guards).
import { describe, expect, it } from "vitest";
import type { World } from "../core/io";
import type { Options } from "../core/problems";
import { RULES, validate } from "../core/validate";
import { makeMini, miniList, miniProbe } from "./mini";

type Files = any; // the mutations poke at raw JSON
interface Mutation { mutate: (w: World, f: Files) => void; opts?: Options; also?: string[]; probe?: (rel: string) => boolean }

const m1 = (w: World) => w.maps.get(1)!;

const MUTATIONS: Record<string, Mutation> = {
  E_TEXT_MISSING: { mutate: (_, f) => { delete f.texts["9000004"]; } },
  E_SPELL_SUBSPELL: { mutate: (_, f) => { f.spells.spells[1].effects[1].spell = 424242; } },
  E_SPELL_SUMMON: { mutate: (_, f) => { f.spells.spells[1].effects[0].monster = 424242; } },
  E_GRADE_MISSING: { mutate: (_, f) => { f.spells.grades["900001"].push(424242); } },
  E_CLASS_SPELL_NO_GRADES: { mutate: (_, f) => { f.spells.classes["901"].pairs.push([424242, 424242]); } },
  E_CLASS_NOT_OFFERED: { mutate: (_, f) => { f.spells.classes["902"] = { pairs: [] }; } },
  E_BREED_NO_ROW: { mutate: (_, f) => { f.world.breeds.push(777); } },
  E_SUMMON_SPELL: { mutate: (_, f) => { f.spells.summons["5"].grades[0].spells.push(424242); } },
  W_WEAPON_NO_STATS: { mutate: (_, f) => { f.items.items[0].type = 6; } },
  E_ITEM_SET: { mutate: (_, f) => { f.items.items[0].set = 424242; } },
  E_ITEM_ICON: { mutate: (_, f) => { f.items.items[0].icon = 424242; }, also: ["W_ASSET_UNUSED"] },
  E_SET_ITEM: { mutate: (_, f) => { f.items.sets[0].items.push(424242); } },
  E_SKILL_ITEM: { mutate: (_, f) => { f.skills.objectsById["9501"].gatheredRessourceItem = 424242; } },
  E_MONSTER_SPELL: { mutate: (_, f) => { f.monsters.monsters["910001"].grades[0].spells.push(424242); } },
  E_MONSTER_DROP: { mutate: (_, f) => { f.monsters.monsters["910001"].grades[0].drops.push({ item: 424242, pct: 1 }); } },
  E_MONSTER_BONE: { mutate: (_, f) => { f.monsters.monsters["910001"].grades[0].look = "{424242|||100}"; } },
  E_MONSTER_PORTRAIT: { mutate: (_, f) => { f.monsters.monsters["910001"].grades[0].portrait = 424242; }, also: ["W_ASSET_UNUSED"] },
  W_MONSTER_NO_ZONE: { mutate: (_, f) => { f.monsters.subareas["1"].monsters = []; }, also: ["W_DUNGEON_NO_MONSTERS"] },
  E_SUBAREA_MONSTER: { mutate: (_, f) => { f.monsters.subareas["1"].monsters.push(424242); } },
  E_START_MAP: { mutate: (_, f) => { f.world.start_map = 99; } },
  E_START_CELL: { mutate: (w) => { m1(w).blocked.push(100); } },
  E_PHOENIX_MAP: { mutate: (_, f) => { f.world.phoenixes.push(99); } },
  E_MAP_ID_MISMATCH: { mutate: (w) => { m1(w).id = 55; } },
  E_MAP_CELL_RANGE: { mutate: (w) => { m1(w).blocked.push(560); } },
  E_MAP_TRIGGER_TARGET: { mutate: (w) => { m1(w).triggers![0].to_map = 99; } },
  E_MAP_TRIGGER_ARRIVAL: { mutate: (w) => { m1(w).triggers![0].to_cell = 35; w.maps.get(2)!.blocked.push(35); } },
  E_MAP_NEIGHBOR_TARGET: { mutate: (w) => { m1(w).neighbors!.top = 99; } },
  W_MAP_NEIGHBOR_RECIPROCAL: { mutate: (w) => { delete w.maps.get(2)!.neighbors!.left; } },
  E_PLACEMENT_BLOCKED: { mutate: (w) => { m1(w).fight_blocked!.push(60); } },
  E_MAP_VISUAL: { mutate: (w) => { m1(w).visual = 3; }, probe: (r) => r !== "Maps/1.json" && miniProbe(r) },
  E_MAP_GFX: { mutate: (w) => { w.visuals.get(1)!.layers.sortable.push({ g: 424242 }); } },
  E_INTERACTIVE_SKILL: { mutate: (_, f) => { f.interactives.maps["1"][0].skill = 424242; } },
  E_RECIPE_ITEM: { mutate: (_, f) => { f.recipes = { objectsById: { "9100001": { id: 9100001, resultId: 9100001, resultLevel: 1, ingredientIds: [424242], quantities: [1], jobId: 1, skillId: 9501 } } }; } },
  E_RECIPE_SKILL: { mutate: (_, f) => { f.recipes = { objectsById: { "9100001": { id: 9100001, resultId: 9100001, resultLevel: 1, ingredientIds: [9100001], quantities: [1], jobId: 1, skillId: 424242 } } }; } },
  E_DUNGEON_MAP: { mutate: (_, f) => { f.dungeons.dungeons["933500"].maps = [2, 99]; } },
  E_DUNGEON_KEY: { mutate: (_, f) => { f.dungeons.dungeons["933500"].keys[0].item = 424242; } },
  E_DUNGEON_BOSS: { mutate: (_, f) => { f.dungeons.dungeons["933500"].bosses = [910001]; } }, // a monster, but not in the bosses table
  W_DUNGEON_NO_MONSTERS: { mutate: (w, f) => { f.monsters.subareas["1"].monsters = []; delete (w.maps.get(2) as any).subarea; }, also: ["W_MONSTER_NO_ZONE"] },
  E_INTERACTIVE_GFX: { mutate: (_, f) => { f.interactives.maps["1"][0].gfx = 424242; } },
  E_INTERACTIVE_CELL: { mutate: (_, f) => { f.interactives.maps["1"][0].cell = 36; } },
  E_MAP_UNREACHABLE_CELL: {
    // wall off the NPC cell (202) with all its neighbours
    mutate: (w) => { m1(w).blocked.push(187, 188, 215, 216); },
  },
  E_MAP_TRIGGER_CUTOFF: {
    // seal the door at 150 inside a ring of blocked cells; the rest of the map stays open
    mutate: (w) => { m1(w).blocked.push(135, 136, 163, 164); },
  },
  W_WORLD_MAP_UNREACHABLE: {
    mutate: (w, f) => { w.maps.get(1)!.triggers = []; delete w.maps.get(1)!.neighbors!.right; w.maps.get(2)!.triggers = []; f.dialogs.dialogs["920001"].nodes["0"].replies.splice(1, 1); f.dungeons.dungeons = {}; },
    also: ["W_MAP_NEIGHBOR_RECIPROCAL"],
  },
  E_DIALOG_NPC: { mutate: (_, f) => { f.dialogs.dialogs["999"] = { start: "0", nodes: { "0": { text: "x", replies: [] } } }; } },
  E_DIALOG_START: { mutate: (_, f) => { f.dialogs.dialogs["920001"].start = "zzz"; }, also: ["W_DIALOG_ORPHAN"] },
  E_DIALOG_NODE: { mutate: (_, f) => { f.dialogs.dialogs["920001"].nodes.a.replies.push({ text: "x", next: "zzz" }); } },
  W_DIALOG_ORPHAN: { mutate: (_, f) => { f.dialogs.dialogs["920001"].nodes.lost = { text: "x", replies: [] }; } },
  E_DIALOG_TELEPORT: { mutate: (_, f) => { f.dialogs.dialogs["920001"].nodes["0"].replies[1].action.map = 99; } },
  E_DIALOG_GIVE_ITEM: { mutate: (_, f) => { f.dialogs.dialogs["920001"].nodes["0"].replies[2].action.item = 424242; } },
  E_DIALOG_CRIT_QUEST: { mutate: (_, f) => { f.dialogs.dialogs["920001"].nodes["0"].replies[0].criteria = "Qf=424242"; } },
  E_DIALOG_CRIT_ITEM: { mutate: (_, f) => { f.dialogs.dialogs["920001"].nodes["0"].replies[0].criteria = "PO=424242"; } },
  E_NPC_BONE: { mutate: (_, f) => { f.npcs.maps["1"][0].look = "{424242|||100}"; } },
  E_SHOP_NPC: { mutate: (_, f) => { f.shops.shops["999"] = { items: [] }; } },
  E_SHOP_ITEM: { mutate: (_, f) => { f.shops.shops["920001"].items.push(424242); } },
  E_QUEST_GIVER: { mutate: (_, f) => { f.quests.quests["930001"].start.map = 2; } },
  E_QUEST_NO_STEPS: { mutate: (_, f) => { f.quests.quests["930001"].steps[0].objectives = []; } },
  E_QUEST_OBJ_NPC: { mutate: (_, f) => { f.quests.quests["930001"].steps[0].objectives[0] = { id: 932001, type: 1, map: 0, params: [424242], args: [] }; } },
  E_QUEST_OBJ_ITEM: { mutate: (_, f) => { f.quests.quests["930001"].steps[0].objectives[0] = { id: 932001, type: 3, map: 0, params: [920001, 424242], args: [] }; } },
  E_QUEST_OBJ_MONSTER: { mutate: (_, f) => { f.quests.quests["930001"].steps[0].objectives[0].params[0] = 424242; } },
  E_QUEST_OBJ_MAP: { mutate: (_, f) => { f.quests.quests["930001"].steps[0].objectives[0] = { id: 932001, type: 4, map: 99, params: [], args: [] }; } },
  E_QUEST_REWARD_ITEM: { mutate: (_, f) => { f.quests.quests["930001"].steps[0].rewards[0].items.push([424242, 1]); } },
  E_ID_DUPLICATE: { mutate: (_, f) => { f.items.items.push({ ...f.items.items[0] }); } },
  E_ID_RANGE: { mutate: (_, f) => { f.items.items[0].id = 5; f.items.sets[0].items = [5]; f.shops.shops["920001"].items = [5]; f.monsters.monsters["910001"].grades[0].drops[0].item = 5; f.quests.quests["930001"].steps[0].rewards[0].items = [[5, 1]]; f.skills.objectsById["9501"].gatheredRessourceItem = 5; f.dialogs.dialogs["920001"].nodes["0"].replies[2].action.item = 5; f.dialogs.dialogs["920001"].nodes["0"].replies[0].criteria = "Qf=930001&PO=5"; f.dungeons.dungeons["933500"].keys[0].item = 5; },
    opts: { ranges: { item: [9100000, 9199999] } } },
  W_ASSET_UNUSED: { mutate: () => {}, opts: { list: (d) => (d === "Picto/Items" ? ["9100001.png", "777.png"] : miniList(d)) } },
  E_ID_COLLISION: { mutate: () => {}, opts: { reserved: { item: new Set([9100001]) } } },
};

describe("règles de cohérence", () => {
  it("le mini-monde est valide", () => {
    expect(validate(makeMini(), miniProbe, { list: miniList })).toEqual([]);
  });

  it("garde de couverture : chaque règle a son test de mutation (et inversement)", () => {
    const codes = RULES.map((r) => r.code);
    expect(new Set(codes).size, "codes de règle en double").toBe(codes.length);
    expect(codes.filter((c) => !(c in MUTATIONS)), "règles sans test de mutation").toEqual([]);
    expect(Object.keys(MUTATIONS).filter((c) => !codes.includes(c)), "mutations sans règle").toEqual([]);
    for (const r of RULES) expect(r.doc.length, `${r.code} sans doc`).toBeGreaterThan(10);
    for (const r of RULES) expect(r.code.startsWith(r.severity === "error" ? "E_" : "W_"), `${r.code} : préfixe vs sévérité`).toBe(true);
  });

  for (const rule of RULES) {
    it(`${rule.code}`, () => {
      const mut = MUTATIONS[rule.code];
      const w = makeMini();
      mut.mutate(w, w.files);
      const problems = validate(w, mut.probe ?? miniProbe, { list: miniList, ...mut.opts });
      const codes = new Set(problems.map((p) => p.code));
      expect(codes.has(rule.code), `${rule.code} ne s'est pas déclenchée ; obtenu ${[...codes]}`).toBe(true);
      const extra = [...codes].filter((c) => c !== rule.code && !(mut.also ?? []).includes(c));
      expect(extra, "la mutation déclenche d'autres règles").toEqual([]);
      expect(problems.find((p) => p.code === rule.code)!.severity).toBe(rule.severity);
    });
  }
});
