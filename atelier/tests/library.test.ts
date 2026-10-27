// Dofus library: browse a content folder, copy chosen images into a world as ordinary imports.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import sharp from "sharp";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { AtelierError } from "../core/errors";
import { listLibrary } from "../core/library";
import { WorldStore } from "../core/store";
import { fakeGrade, writeFakeI18n } from "./fake_dofus";

let tmp: string, store: WorldStore, content: string;
const W = "monde_biblio";
const refuses = async (fn: () => Promise<unknown> | unknown, status: number, re: RegExp) => {
  try { await fn(); } catch (e) { expect(e).toBeInstanceOf(AtelierError); expect((e as AtelierError).status).toBe(status); expect((e as Error).message).toMatch(re); return; }
  throw new Error("aucune erreur levée");
};

beforeAll(async () => {
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), "atelier-library-"));
  content = path.join(tmp, "content", "Content");
  fs.mkdirSync(path.join(content, "Picto", "Items"), { recursive: true });
  fs.mkdirSync(path.join(content, "Maps", "Gfx"), { recursive: true });
  const img = (c: string) => sharp({ create: { width: 200, height: 120, channels: 4, background: c } });
  for (const [id, c] of [[100001, "#aa3333"], [100003, "#33aa33"], [250, "#3333aa"], [7100001, "#aaaa33"]] as const)
    await img(c).webp().toFile(path.join(content, "Picto", "Items", `${id}.webp`));
  await img("#555555").png().toFile(path.join(content, "Maps", "Gfx", "42.png"));
  fs.writeFileSync(path.join(content, "Picto", "Items", "notes.txt"), "pas une image");
  for (const id of [10, 1000, 7]) {
    fs.mkdirSync(path.join(content, "Characters", "Bones", String(id)), { recursive: true });
    await img("#884422").webp().toFile(path.join(content, "Characters", "Bones", String(id), "0.webp"));
    fs.writeFileSync(path.join(content, "Characters", "Bones", String(id), "bone.json"), "{}");
  }
  fs.mkdirSync(path.join(content, "Characters", "Bones", "1-12-combat"), { recursive: true }); // a split player bundle: not listed
  fs.mkdirSync(path.join(tmp, "worlds"));
  store = new WorldStore(path.join(tmp, "worlds"), path.join(tmp, "r.json"), path.resolve(__dirname, "..", "templates"));
  store.contentRoot = content;
  store.create(W, "Biblio");
});
afterAll(() => fs.rmSync(tmp, { recursive: true, force: true }));

describe("bibliothèque Dofus", () => {
  it("liste les images d'une catégorie par numéro, avec recherche et pages", () => {
    expect(store.library("item", "", 0, 60)).toEqual({ available: true, total: 4, ids: [250, 100001, 100003, 7100001] });
    expect(store.library("item", "1000", 0, 60).ids).toEqual([100001, 100003, 7100001]);
    expect(store.library("item", "", 1, 2).ids).toEqual([100001, 100003]);
    expect(store.library("tile", "", 0, 60).ids).toEqual([42]);
  });

  it("signale une bibliothèque absente, refuse une recherche ou une catégorie invalide", async () => {
    expect(listLibrary(path.join(tmp, "nulle-part"), "item")).toEqual({ available: false, total: 0, ids: [] });
    expect(store.library("spell", "", 0, 60).available).toBe(false); // that folder is not there
    await refuses(() => store.library("item", "a'b", 0, 60), 400, /chiffres/);
    await refuses(() => store.library("bidon", "", 0, 60), 400, /catégorie/);
  });

  it("sert une vignette PNG réduite", async () => {
    const png = await store.libraryPng("item", 100001, 50);
    const m = await sharp(png).metadata();
    expect(m.format).toBe("png");
    expect(Math.max(m.width!, m.height!)).toBeLessThanOrEqual(50);
    await refuses(() => store.libraryPng("item", 999, 50), 404, /absente/);
  });

  it("copie des images dans un monde : elles y deviennent des images ordinaires, une seule fois", async () => {
    const out = await store.importFromLibrary(W, "item", [100001, 100003]);
    expect(out.map((r) => r.status)).toEqual(["imported", "imported"]);
    const assets = await store.assets(W, "item");
    expect(assets).toHaveLength(2);
    expect(assets[0].name).toBe("dofus-100001");
    const again = await store.importFromLibrary(W, "item", [100001]);
    expect(again[0].status).toBe("duplicate");
    expect(await store.assets(W, "item")).toHaveLength(2);
    expect(store.detail(W).problems.filter((p) => p.severity === "error")).toEqual([]);
  });

  it("refuse une liste vide ou trop longue, un monde inconnu, une image absente", async () => {
    await refuses(() => store.importFromLibrary(W, "item", []), 400, /1 à 100/);
    await refuses(() => store.importFromLibrary(W, "item", Array.from({ length: 101 }, (_, i) => i)), 400, /1 à 100/);
    await refuses(() => store.importFromLibrary("inconnu", "item", [100001]), 404, /inconnu/);
    await refuses(() => store.importFromLibrary(W, "item", [999999]), 404, /absente/);
    expect(await store.assets(W, "item")).toHaveLength(2);
  });

  it("squelettes : liste les dossiers numériques, sert l'atlas, copie le dossier dans le monde", async () => {
    expect(store.library("bone", "", 0, 60).ids).toEqual([7, 10, 1000]);
    expect(store.library("bone", "10", 0, 60).ids).toEqual([10, 1000]);
    const m = await sharp(await store.libraryPng("bone", 10, 64)).metadata();
    expect(Math.max(m.width!, m.height!)).toBeLessThanOrEqual(64);
    expect(store.bones(W).own).toEqual([]);
    store.importBone(W, "dofus", 10);
    expect(store.bones(W).own).toEqual([10]);
    expect(fs.existsSync(path.join(tmp, "worlds", W, "Content", "Characters", "Bones", "10", "bone.json"))).toBe(true);
    await refuses(() => store.importBone(W, "dofus", 10), 409, /déjà présent/);
    await refuses(() => store.importBone(W, "dofus", 99999), 404, /absent/);
  });
});

describe("objets du jeu comme modèles", () => {
  beforeAll(() => {
    fs.mkdirSync(path.join(tmp, "data"), { recursive: true });
    store.dataRoot = path.join(tmp, "data");
    const weapon = { ap: 4, min_range: 1, range: 2, crit: 25, crit_bonus: 8, in_line: 1, los: 1, per_turn: 1 };
    fs.writeFileSync(path.join(tmp, "data", "items.json"), JSON.stringify({ items: [
      { id: 44, name: "Épée de Boisaille", icon: 6007, type: 6, level: 7, price: 700, weight: 1, effects: [[100, 8, 10, 0], [118, 7, 10, 0]], weapon },
      { id: 45, name: "Épée d'Argent", icon: 6008, type: 6, level: 40, price: 9000, weight: 2, effects: [[100, 30, 40, 0]], weapon },
      { id: 46, name: "Anneau de Boisaille", icon: 6009, type: 9, level: 3, effects: [[125, 5, 0, 0]] },
      { id: 47, name: "Clé de la Cave", icon: 6010, type: 84, level: 1, effects: [] },
    ] }));
  });

  it("cherche par nom sans accent ni majuscule, par numéro, et donne un objet prêt à créer", () => {
    const r = store.libraryItems("epee");
    expect(r.map((x) => x.source)).toEqual([44, 45]); // lower level first
    expect(r[0]).toMatchObject({ name: "Épée de Boisaille", icon: 6007, type: 6, level: 7, price: 700 });
    expect(r[0].weapon).toEqual({ ap: 4, min_range: 1, range: 2, crit: 25, crit_bonus: 8, in_line: 1, los: 1, per_turn: 1 });
    expect(r[0].effects).toEqual([[100, 8, 10, 0], [118, 7, 10, 0]]);
    expect(store.libraryItems("boisaille").map((x) => x.source).sort()).toEqual([44, 46]);
    expect(store.libraryItems("46")[0].name).toBe("Anneau de Boisaille");
  });

  it("ignore les types que l'éditeur ne connaît pas, refuse une recherche trop courte", async () => {
    expect(store.libraryItems("cave")).toEqual([]);
    await refuses(() => store.libraryItems("a"), 400, /2 caractères/);
  });

  it("un modèle devient un objet du monde, arme comprise, sans incohérence", async () => {
    const [tpl] = store.libraryItems("Boisaille").filter((x) => x.type === 6);
    const [icon] = await store.importFromLibrary(W, "item", [100001]);
    const id = store.dataCreate(W, "items", { ...tpl, icon: icon.id! });
    const row = (store.rowsOf(W, "items") as any[]).find((i) => i.id === id);
    expect(row).toMatchObject({ name: "Épée de Boisaille", type: 6, level: 7 });
    expect(row.weapon.range).toBe(2);
    expect(store.detail(W).problems.filter((p) => p.severity === "error")).toEqual([]);
  });
});

describe("monstres du jeu comme modèles", () => {
  beforeAll(() => {
    writeFakeI18n(path.join(content, "I18n", "fr.bin"), { 6522: "Bouftou", 6523: "Bouftou Royal", 7000: "Piou Rouge", 8223: "Amine", 8453: "Rish Claymore", 8680: "Amine Bis", 8681: "Sans squelette" });
    fs.mkdirSync(path.join(tmp, "worlds", "dofus"), { recursive: true });
    const grade = fakeGrade;
    fs.writeFileSync(path.join(tmp, "worlds", "dofus", "monsters.json"), JSON.stringify({ subareas: {}, bosses: {}, monsters: {
      "31": { name_id: 6522, grades: [grade(16), grade(17), grade(18), grade(19), grade(20), grade(21)] },
      "32": { name_id: 6523, grades: [grade(30)] },
      "33": { name_id: 7000, grades: [grade(2)] },
    } }));
  });

  it("lit les noms du client, cherche sans accent, donne stats et apparence sans sorts ni butin", () => {
    const r = store.libraryMonsters("boufTOU");
    expect(r.map((m) => m.name)).toEqual(["Bouftou", "Bouftou Royal"]);
    const m = r[0];
    expect(m).toMatchObject({ source: 31, bone: 4907, size: 130, portrait: 1 });
    expect(m.grades).toHaveLength(5); // the editor takes at most 5 grades
    expect(m.grades[0]).toMatchObject({ level: 16, hp: 106, ap: 5, mp: 2, xp: 2000, kamas: [32, 70], spells: [], drops: [] });
    expect(m.grades[0].aggro).toEqual({ zone: 3, level_diff: 50, delay: 10000 });
    expect(m.grades[0].res.water).toBe(-9);
    expect(store.libraryMonsters("33")[0].name).toBe("Piou Rouge");
  });

  it("un modèle de monstre devient un monstre du monde, une fois ses sorts choisis", async () => {
    const [tpl] = store.libraryMonsters("Piou");
    const [por] = await store.importFromLibrary(W, "item", [100003]); // any image as a portrait
    const { source: _s, ...rest } = tpl;
    const id = store.dataCreate(W, "monsters", { ...rest, bone: 10, portrait: por.id });
    expect((store.rowsOf(W, "monsters") as any[]).find((x) => x.id === id).grades[0].level).toBe(2);
  });

  it("refuse une recherche trop courte", async () => {
    await refuses(() => store.libraryMonsters("b"), 400, /2 caractères/);
  });
});

describe("PNJ du jeu comme modèles", () => {
  beforeAll(() => {
    fs.mkdirSync(path.join(store.dataRoot, "tables"), { recursive: true });
    fs.writeFileSync(path.join(store.dataRoot, "tables", "npcs.json"), JSON.stringify({ objectsById: {
      "37": { id: 37, nameId: 8223, look: "{10}" },
      "38": { id: 38, nameId: 8453, look: "{10|||120}" },
      "40": { id: 40, nameId: 8680, look: "{10}" },
      "41": { id: 41, nameId: 8681, look: "" }, // no look: not a usable template
      "42": { id: 42, nameId: 999999, look: "{10}" }, // no text: not a usable template
    } }));
  });

  it("cherche sans accent par nom ou par numéro, donne nom et apparence, écarte les PNJ sans apparence ni nom", () => {
    expect(store.libraryNpcs("amine").map((n) => n.name)).toEqual(["Amine", "Amine Bis"]);
    expect(store.libraryNpcs("claymore")[0]).toEqual({ source: 38, name: "Rish Claymore", bone: 10, size: 120 });
    expect(store.libraryNpcs("40")[0].name).toBe("Amine Bis");
    expect(store.libraryNpcs("squelette")).toEqual([]);
    expect(store.libraryNpcs("42")).toEqual([]);
  });

  it("refuse une recherche trop courte", async () => {
    await refuses(() => store.libraryNpcs("a"), 400, /2 caractères/);
  });

  it("un modèle devient un PNJ du monde, squelette copié, sans incohérence", () => {
    const [tpl] = store.libraryNpcs("Rish");
    try { store.importBone(W, "dofus", tpl.bone); } catch (e) { if (!/déjà présent/.test((e as Error).message)) throw e; } // an earlier test may have copied it
    const errors = () => store.detail(W).problems.filter((p) => p.severity === "error").map((p) => p.code + " " + p.message);
    const before = errors(); // earlier tests of this file may leave their own
    const map = (store.rowsOf(W, "maps") as any[])[0];
    const id = store.dataCreate(W, "npcs", { map: map.id, cell: 150, dir: 3, name: tpl.name, bone: tpl.bone, size: tpl.size, banker: false, shop: null });
    expect((store.rowsOf(W, "npcs") as any[]).find((n) => n.id === id)).toMatchObject({ name: "Rish Claymore", bone: 10, size: 120 });
    expect(errors()).toEqual(before); // the NPC adds no problem
  });
});
