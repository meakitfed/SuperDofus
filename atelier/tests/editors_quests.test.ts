// Quest editor through a real store: a quest built from the form is playable data the validator accepts.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import sharp from "sharp";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { AtelierError } from "../core/errors";
import type { QuestInput, QuestRow } from "../core/editors_quests";
import { WorldStore } from "../core/store";

let tmp: string, store: WorldStore, map: number, npc: number, item: number, monster: number;
const W = "monde_quetes";
const ROOT = path.resolve(__dirname, "..", "..");
const errors = () => store.detail(W).problems.filter((p) => p.severity === "error").map((p) => `${p.code} ${p.message}`);
const quests = () => store.rowsOf(W, "quests") as QuestRow[];
const refuses = (fn: () => void, status: number, re: RegExp) => {
  try { fn(); } catch (e) { expect(e).toBeInstanceOf(AtelierError); expect((e as AtelierError).status).toBe(status); expect((e as Error).message).toMatch(re); return; }
  throw new Error("aucune erreur levée");
};
const base = (): QuestInput => ({
  name: "Les os du pont", giver: npc, levelMin: 1, repeat: 0,
  steps: [
    { name: "Parler au gardien", desc: "Va voir le gardien du pont.", level: 1, objectives: [{ type: 1, npc }], reward: { xp: 1, kamas: 1, items: [] } },
    { name: "Chasse", desc: "Chasse trois rats.", level: 2, objectives: [{ type: 14, monster, qty: 3 }, { type: 4, map }], reward: { xp: 2, kamas: 2, items: [[item, 2]] } },
    { name: "Rapport", desc: "Rapporte-lui des croix.", level: 3, objectives: [{ type: 3, npc, item, qty: 2 }, { type: 9, npc }], reward: { xp: 3, kamas: 0, items: [] } },
  ],
});

beforeAll(async () => {
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), "atelier-quests-"));
  fs.mkdirSync(path.join(tmp, "worlds"));
  store = new WorldStore(path.join(tmp, "worlds"), path.join(tmp, "r.json"), path.resolve(__dirname, "..", "templates"));
  store.create(W, "Quêtes");
  map = (store.rowsOf(W, "maps") as { id: number }[])[0].id;
  fs.cpSync(path.join(ROOT, "game", "worlds", "vertebre", "Content", "Characters", "Bones", "950001"), path.join(tmp, "worlds", W, "Content", "Characters", "Bones", "950001"), { recursive: true });
  const png = await sharp({ create: { width: 96, height: 96, channels: 4, background: "#335577" } }).png().toBuffer();
  const file = [{ name: "a.png", data: png }];
  const [ic] = await store.importAssets(W, "item", { files: file });
  const [por] = await store.importAssets(W, "monster", { files: file });
  const [spi] = await store.importAssets(W, "spell", { files: file });
  item = store.dataCreate(W, "items", { name: "Croix d'os", icon: ic.id, type: 12, level: 1, effects: [] });
  npc = store.dataCreate(W, "npcs", { map, cell: 150, dir: 3, name: "Gardien", bone: 950001, size: 100, banker: false, shop: null });
  const spell = store.dataCreate(W, "spells", { name: "Griffe", icon: spi.id, level: 1, ap: 3, range: [1, 1], los: true, inLine: false, perTurn: 2, cooldown: 0, crit: 5, color: "#aa3322", area: { shape: "point", size: 0 }, effects: [{ kind: "damage", target: "enemies", min: 3, max: 5, element: "earth" }] });
  const zone = store.dataCreate(W, "zones", { level: 1 });
  const g = { level: 1, hp: 10, ap: 6, mp: 3, xp: 5, stats: { strength: 0, intelligence: 0, chance: 0, agility: 0, wisdom: 0, ap_dodge: 0, mp_dodge: 0 }, res: { earth: 0, fire: 0, water: 0, air: 0, neutral: 0 }, spells: [spell], drops: [], kamas: [0, 1], aggro: { zone: 2, level_diff: 60, delay: 8000 } };
  monster = store.dataCreate(W, "monsters", { name: "Rat", bone: 950001, size: 100, portrait: por.id, grades: [g], zones: [String(zone)] });
});
afterAll(() => fs.rmSync(tmp, { recursive: true, force: true }));

describe("quests", () => {
  it("creates a quest with 3 steps; ids in range, args built from existing names, world coherent", () => {
    const id = store.dataCreate(W, "quests", base());
    const r = store.registry()[W].ranges;
    expect(id).toBeGreaterThanOrEqual(r.quest[0]);
    const q = quests().find((x) => x.id === id)!;
    expect(q.steps).toHaveLength(3);
    expect(q.locked).toBe(false);
    const raw = JSON.parse(fs.readFileSync(path.join(tmp, "worlds", W, "quests.json"), "utf-8")).quests[String(id)];
    expect(raw.start).toEqual({ npc, map });
    expect(raw.steps[0].id).toBeGreaterThanOrEqual(r.step[0]);
    expect(raw.steps[1].objectives.map((o: any) => o.type)).toEqual([14, 4]);
    expect(raw.steps[1].objectives[0].args).toHaveLength(2);
    expect(raw.steps[2].objectives[0].params).toEqual([npc, item, 2]);
    expect(raw.steps[1].rewards[0].items).toEqual([[item, 2]]);
    expect(errors()).toEqual([]);
  });
  it("edits in place: ids and texts kept, a step added", () => {
    const id = quests()[0].id;
    const before = quests()[0];
    const input: QuestInput = { ...base(), name: "Les os du pont (v2)", steps: before.steps.map((s) => ({ ...s })) };
    input.steps.push({ name: "Épilogue", desc: "Fin.", level: 4, objectives: [{ type: 1, npc }], reward: { xp: 1, kamas: 1, items: [] } });
    store.dataUpdate(W, "quests", id, input);
    const after = quests()[0];
    expect(after.name).toBe("Les os du pont (v2)");
    expect(after.steps.slice(0, 3).map((s) => s.id)).toEqual(before.steps.map((s) => s.id));
    expect(after.steps).toHaveLength(4);
    expect(new Set(after.steps.map((s) => s.id)).size).toBe(4);
    expect(errors()).toEqual([]);
  });
  it("validates giver, steps, objectives and rewards", () => {
    const bad = (mut: (q: QuestInput) => void, re: RegExp) => { const q = base(); mut(q); refuses(() => store.dataCreate(W, "quests", q), 400, re); };
    bad((q) => { q.giver = 4242; }, /aucune map/);
    bad((q) => { q.name = ""; }, /nom/);
    bad((q) => { q.steps = []; }, /étapes/);
    bad((q) => { q.steps[0].objectives = []; }, /objectifs/);
    bad((q) => { q.steps[0].objectives = [{ type: 7, monster: 1 }]; }, /monstre 1 inconnu/);
    bad((q) => { q.steps[0].objectives = [{ type: 4, map: 1 }]; }, /map 1 inconnue/);
    bad((q) => { q.steps[0].objectives = [{ type: 3, npc, item: 1, qty: 1 }]; }, /objet 1 inconnu/);
    bad((q) => { q.steps[0].reward.items = [[item, 0]]; }, /quantité/);
    bad((q) => { q.steps[0].reward.xp = 500; }, /ratios/);
    bad((q) => { q.steps[0].level = 0; }, /niveau/);
  });
  it("is protected by a dialogue criterion; the NPC, monster and item it uses are protected too", () => {
    const id = quests()[0].id;
    store.dataUpdate(W, "dialogs", npc, { start: "0", nodes: { "0": { text: "Salut.", replies: [{ text: "Merci", criteria: `Qf=${id}` }] } } });
    refuses(() => store.dataDelete(W, "quests", id), 409, /dialog/);
    refuses(() => store.dataDelete(W, "npcs", npc), 409, /quest/);
    refuses(() => store.dataDelete(W, "monsters", monster), 409, /quest/);
    refuses(() => store.dataDelete(W, "items", item), 409, /quest/);
    store.dataDelete(W, "dialogs", npc);
    store.dataDelete(W, "quests", id);
    expect(quests()).toHaveLength(0);
    expect(errors()).toEqual([]);
  });
});
