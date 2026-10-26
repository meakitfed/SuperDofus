// Dofus library: browse a content folder, copy chosen images into a world as ordinary imports.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import sharp from "sharp";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { AtelierError } from "../core/errors";
import { listLibrary } from "../core/library";
import { WorldStore } from "../core/store";

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
