// World cloning: every id moves to the new slot, nothing of the old slot is left, the copy is as coherent as the original.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import sharp from "sharp";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { AtelierError } from "../core/errors";
import { makeRemap } from "../core/clone";
import { loadWorld } from "../core/io";
import { collectIds, KINDS, rangesForSlot } from "../core/ranges";
import { WorldStore } from "../core/store";

let tmp: string, store: WorldStore, npc: number, quest: number;
const SRC = "monde_source";
const ROOT = path.resolve(__dirname, "..", "..");
const wdir = (id: string) => path.join(tmp, "worlds", id);
const refuses = (fn: () => void, status: number, re: RegExp) => {
  try { fn(); } catch (e) { expect(e).toBeInstanceOf(AtelierError); expect((e as AtelierError).status).toBe(status); expect((e as Error).message).toMatch(re); return; }
  throw new Error("aucune erreur levée");
};
function walk(dir: string): string[] {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((e) => (e.isDirectory() ? walk(path.join(dir, e.name)) : [path.join(dir, e.name)]));
}

beforeAll(async () => {
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), "atelier-clone-"));
  fs.mkdirSync(path.join(tmp, "worlds"));
  store = new WorldStore(path.join(tmp, "worlds"), path.join(tmp, "r.json"), path.resolve(__dirname, "..", "templates"));
  store.create(SRC, "Monde source");
  const map = (store.rowsOf(SRC, "maps") as { id: number }[])[0].id;
  fs.cpSync(path.join(ROOT, "game", "worlds", "vertebre", "Content", "Characters", "Bones", "950001"), path.join(wdir(SRC), "Content", "Characters", "Bones", "950001"), { recursive: true });
  const png = (w: number, h: number) => sharp({ create: { width: w, height: h, channels: 4, background: "#335577" } }).png().toBuffer();
  const file = async (w = 96, h = 96) => [{ name: "a.png", data: await png(w, h) }];
  const [ic] = await store.importAssets(SRC, "item", { files: await file() });
  const [por] = await store.importAssets(SRC, "monster", { files: await file() });
  const [spi] = await store.importAssets(SRC, "spell", { files: await file() });
  const [til] = await store.importAssets(SRC, "tile", { files: await file(64, 64) });
  const item = store.dataCreate(SRC, "items", { name: "Croix d'os", icon: ic.id, type: 12, level: 1, effects: [] });
  npc = store.dataCreate(SRC, "npcs", { map, cell: 150, dir: 3, name: "Gardien", bone: 950001, size: 100, banker: false, shop: null });
  const spell = store.dataCreate(SRC, "spells", { name: "Griffe", icon: spi.id, level: 1, ap: 3, range: [1, 1], los: true, inLine: false, perTurn: 2, cooldown: 0, crit: 5, color: "#aa3322", area: { shape: "point", size: 0 }, effects: [{ kind: "damage", target: "enemies", min: 3, max: 5, element: "earth" }] });
  const fam = (store.rowsOf(SRC, "spells") as any[]).find((s) => s.id === spell).family;
  store.dataCreate(SRC, "classes", { name: "Os", tagline: "Solide", description: "Une classe.", bone: 950001, size: 100, spells: [fam] });
  const zone = store.dataCreate(SRC, "zones", { level: 1 });
  const g = { level: 1, hp: 10, ap: 6, mp: 3, xp: 5, stats: { strength: 0, intelligence: 0, chance: 0, agility: 0, wisdom: 0, ap_dodge: 0, mp_dodge: 0 }, res: { earth: 0, fire: 0, water: 0, air: 0, neutral: 0 }, spells: [spell], drops: [{ item, pct: 50 }], kamas: [0, 1], aggro: { zone: 2, level_diff: 60, delay: 8000 } };
  const monster = store.dataCreate(SRC, "monsters", { name: "Rat", bone: 950001, size: 100, portrait: por.id, grades: [g], zones: [String(zone)] });
  quest = store.dataCreate(SRC, "quests", {
    name: "Les rats", giver: npc, levelMin: 1, repeat: 0,
    steps: [{ name: "Chasse", desc: "Chasse les rats.", level: 1, objectives: [{ type: 14, monster, qty: 3 }, { type: 3, npc, item, qty: 1 }], reward: { xp: 1, kamas: 1, items: [[item, 1]] } }],
  });
  store.dataUpdate(SRC, "dialogs", npc, { start: "0", nodes: { "0": { text: "Salut.", replies: [{ text: "Merci", criteria: `Qf=${quest}` }, { text: "Un cadeau", action: { type: "give_item", item, qty: 1 } }] } } });
  store.dataUpdate(SRC, "visuals", map, { bg: 0xff202030, background: [{ g: til.id!, x: 100, y: 100 }], sortable: [{ g: til.id!, x: 50, y: 60, cell: 30 }], foreground: [] });
});
afterAll(() => fs.rmSync(tmp, { recursive: true, force: true }));

describe("duplication de monde", () => {
  it("le décalage d'ids suit chaque plage et laisse le reste intact", () => {
    const r = makeRemap(rangesForSlot(1), rangesForSlot(2));
    expect(r(rangesForSlot(1).item[0] + 5)).toBe(rangesForSlot(2).item[0] + 5);
    expect(r(rangesForSlot(1).map[1])).toBe(rangesForSlot(2).map[1]);
    for (const n of [0, 559, 123456789, 4286611584]) expect(r(n)).toBe(n);
  });

  it("copie tout le monde dans un nouvel emplacement, sans reste de l'ancien, aussi cohérent que l'original", () => {
    const srcProblems = store.detail(SRC).problems;
    const out = store.clone(SRC, "monde_copie", "Monde copie");
    expect(out).toMatchObject({ id: "monde_copie", name: "Monde copie", managed: true, created: true });
    const reg = store.registry();
    expect(reg.monde_copie.slot).not.toBe(reg[SRC].slot);

    const copy = store.detail("monde_copie");
    expect(copy.problems.map((p) => p.code).sort()).toEqual(srcProblems.map((p) => p.code).sort());

    // every id the copy defines sits in its own ranges, and none in the original's
    const ids = collectIds(loadWorld(wdir("monde_copie")).world!);
    for (const k of KINDS) for (const n of ids[k]) expect(n >= reg.monde_copie.ranges[k][0] && n <= reg.monde_copie.ranges[k][1], `${k} ${n}`).toBe(true);
    const old = reg[SRC].ranges;
    const inOld = (n: number) => KINDS.some((k) => n >= old[k][0] && n <= old[k][1]);
    for (const f of walk(wdir("monde_copie"))) {
      const text = f.endsWith(".json") ? fs.readFileSync(f, "utf-8") : f.replace(wdir("monde_copie"), "");
      for (const m of text.matchAll(/\d{10}/g)) expect(inOld(Number(m[0])), `${path.basename(f)} ${m[0]}`).toBe(false);
    }
    // names of the world and its text entry follow
    const w = loadWorld(wdir("monde_copie")).world!;
    expect(w.files.world.name).toBe("Monde copie");
    expect(Object.values(w.files.texts)).toContain("Monde copie");
    expect(Object.values(w.files.texts)).not.toContain("Monde source");
  });

  it("l'original n'a pas bougé, et la copie s'édite à part", () => {
    const rows = (id: string) => (store.rowsOf(id, "quests") as { id: number; name: string }[]);
    expect(rows(SRC)[0].id).toBe(quest);
    store.dataCreate("monde_copie", "zones", { level: 3 });
    expect((store.rowsOf("monde_copie", "zones") as unknown[]).length).toBe((store.rowsOf(SRC, "zones") as unknown[]).length + 1);
    expect(store.detail(SRC).problems.filter((p) => p.severity === "error")).toEqual([]);
    expect(store.detail("monde_copie").problems.filter((p) => p.severity === "error")).toEqual([]);
  });

  it("refuse La Vertèbre, un identifiant pris ou invalide, un nom vide", () => {
    refuses(() => store.clone("vertebre", "autre_monde", "Autre"), 400, /propres numéros|inconnu/);
    refuses(() => store.clone(SRC, "monde_copie", "Encore"), 409, /existe déjà/);
    refuses(() => store.clone(SRC, "Mauvais Id", "Nom"), 400, /identifiant/);
    refuses(() => store.clone(SRC, "monde_vide", "  "), 400, /nom/);
    expect(fs.existsSync(wdir("monde_vide"))).toBe(false);
  });
});
