// Guided workflows: their state is read from the data, and breaking the data un-does the right step.
import { describe, expect, it } from "vitest";
import { WORKFLOW_IDS, workflows } from "../core/workflows";
import { makeMini } from "./mini";

type Files = any;
function playable() {
  const w = makeMini();
  const f: Files = w.files;
  for (const s of f.spells.spells) s.level = 1;
  Object.assign(w.maps.get(1) as any, { subarea: 1, monster_spawn: true });
  f.monsters.subareas["1"].level = 1;
  f.dialogs.dialogs["920001"].nodes["0"].replies.push({ id: 4, text: "Voir la boutique", action: { type: "shop" } });
  return w;
}
const FACTS: { ownBones: number; images: Record<string, number> } = { ownBones: 1, images: { monster: 1, item: 1, spell: 1, tile: 0 } };
const states = (w: ReturnType<typeof makeMini>, facts = FACTS) =>
  Object.fromEntries(workflows(w, facts).map((x) => [x.id, x.steps.map((s) => s.done)]));

describe("assistants guidés", () => {
  it("garde : les sept assistants existent, chacun avec ses étapes et une destination", () => {
    const list = workflows(playable(), FACTS);
    expect(list.map((x) => x.id)).toEqual([...WORKFLOW_IDS]);
    for (const x of list) {
      expect(x.steps.length).toBeGreaterThan(1);
      for (const s of x.steps) { expect(s.label).toBeTruthy(); expect(s.tab.startsWith("/")).toBe(true); }
    }
  });

  it("un monde jouable complet termine les assistants classe, monstre, quête et marchand", () => {
    const s = states(playable());
    for (const id of ["class", "monster", "quest", "merchant"]) expect(s[id], id).toEqual(s[id].map(() => true));
  });

  it("l'assistant ressource se coche avec un objet, une tuile, un métier, une ressource, posée sur une map atteignable", () => {
    const w = playable();
    const f: Files = w.files;
    const facts = { ownBones: 1, images: { tile: 1 } };
    expect(states(w, facts).resource).toEqual([true, true, false, true, true]); // everything but the job: the mini world has a skill and a placed element
    f.jobs = { objectsById: { "9001": { id: 9001, nameId: 9000546 } } };
    expect(states(w, facts).resource).toEqual([true, true, true, true, true]);
    expect(states(w, { ownBones: 1, images: {} }).resource[1]).toBe(false); // no tile image
    f.interactives.maps = {}; // the resource stands nowhere
    expect(states(w, facts).resource[4]).toBe(false);
  });

  it("sans squelette ni image, les étapes concernées restent à faire", () => {
    const s = states(playable(), { ownBones: 0, images: {} });
    expect(s.class[1]).toBe(false);
    expect(s.monster[0]).toBe(false);
  });

  it("casser les données défait l'étape correspondante", () => {
    const noLevel1 = playable();
    for (const sp of (noLevel1.files as Files).spells.spells) sp.level = 5;
    expect(states(noLevel1).class[3]).toBe(false);

    const noSpawn = playable();
    (noSpawn.maps.get(1) as Files).monster_spawn = false;
    (noSpawn.maps.get(2) as Files).monster_spawn = false;
    expect(states(noSpawn).monster[4]).toBe(false);

    const noGiver = playable();
    (noGiver.files as Files).quests.quests["930001"].start.npc = 777;
    expect(states(noGiver).quest[3]).toBe(false);

    const noShop = playable();
    const node = (noShop.files as Files).dialogs.dialogs["920001"].nodes["0"];
    node.replies = node.replies.filter((r: any) => r.action?.type !== "shop");
    expect(states(noShop).merchant[2]).toBe(false);
  });

  it("deux maps non reliées : l'assistant « relier » n'est pas terminé", () => {
    const w = playable();
    for (const m of w.maps.values()) { delete (m as Files).neighbors; (m as Files).triggers = []; }
    for (const t of Object.values((w.files as Files).dialogs.dialogs) as Files[]) for (const n of Object.values(t.nodes) as Files[]) n.replies = n.replies.filter((r: any) => r.action?.type !== "teleport");
    expect(w.maps.size).toBeGreaterThanOrEqual(2);
    expect(states(w).link.every(Boolean)).toBe(false);
  });
});
