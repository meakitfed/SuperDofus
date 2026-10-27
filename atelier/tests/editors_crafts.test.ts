// Workshops (craft skills standing on maps) and recipes, through a real store on a temp folder.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import sharp from "sharp";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { AtelierError } from "../core/errors";
import type { RecipeInput, RecipeRow, WorkshopRow } from "../core/editors_crafts";
import { WorldStore } from "../core/store";

let tmp: string, store: WorldStore, map: number, ore: number, bar: number, sword: number, gfx: number, job: number, ic: number;
const W = "monde_artisanat";
const errors = () => store.detail(W).problems.filter((p) => p.severity === "error").map((p) => `${p.code} ${p.message}`);
const workshops = () => store.rowsOf(W, "workshops") as WorkshopRow[];
const recipes = () => store.rowsOf(W, "recipes") as RecipeRow[];
const refuses = (fn: () => void, status: number, re: RegExp) => {
  try { fn(); } catch (e) { expect(e).toBeInstanceOf(AtelierError); expect((e as AtelierError).status).toBe(status); expect((e as Error).message).toMatch(re); return; }
  throw new Error("aucune erreur levée");
};
const raw = (name: string) => JSON.parse(fs.readFileSync(path.join(tmp, "worlds", W, name), "utf-8"));
const item = (name: string, level = 1) => store.dataCreate(W, "items", { name, icon: ic, type: 15, level, effects: [] });
const obtainable = () => store.report(W).find((c) => c.code === "P_ITEM_OBTAINABLE")!;

beforeAll(async () => {
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), "atelier-craft-"));
  fs.mkdirSync(path.join(tmp, "worlds"));
  store = new WorldStore(path.join(tmp, "worlds"), path.join(tmp, "r.json"), path.resolve(__dirname, "..", "templates"));
  store.create(W, "Artisanat");
  map = (store.rowsOf(W, "maps") as { id: number }[])[0].id;
  const png = await sharp({ create: { width: 96, height: 96, channels: 4, background: "#335577" } }).png().toBuffer();
  const file = [{ name: "a.png", data: png }];
  ic = (await store.importAssets(W, "item", { files: file }))[0].id!;
  gfx = (await store.importAssets(W, "tile", { files: file }))[0].id!;
  ore = item("Minerai de fer");
  bar = item("Lingot de fer");
  sword = item("Épée de fer", 5);
  job = store.dataCreate(W, "jobs", { name: "Forgeron" });
  store.dataCreate(W, "resources", { name: "Filon de fer", job, item: ore, level: 1, gfx, places: [{ map, cell: 120 }] });
});
afterAll(() => fs.rmSync(tmp, { recursive: true, force: true }));

describe("ateliers et recettes", () => {
  let shop = 0;
  it("crée un atelier posé sur une map : dans la plage, sans objet récolté, cellule occupée, monde sans erreur", () => {
    shop = store.dataCreate(W, "workshops", { name: "Forge", job, gfx, places: [{ map, cell: 150 }] });
    expect(shop).toBeGreaterThanOrEqual(store.registry()[W].ranges.interactive[0]);
    expect(workshops()).toHaveLength(1);
    expect(workshops()[0]).toMatchObject({ name: "Forge", jobName: "Forgeron", recipes: 0 });
    expect(raw("data/tables/skills.json").objectsById[String(shop)].gatheredRessourceItem).toBe(-1);
    expect((store.rowsOf(W, "resources") as any[]).map((r) => r.name)).toEqual(["Filon de fer"]); // a workshop is not a resource
    expect((store.rowsOf(W, "maps") as any[])[0].blocked).toContain(150);
    expect(errors()).toEqual([]);
  });

  it("crée une recette : clé = objet fabriqué, niveau de l'objet, métier de l'atelier ; le résultat devient obtenable", () => {
    expect(obtainable().items.map((i: any) => i.ref?.id)).toEqual(expect.arrayContaining([bar, sword])); // nothing makes them yet
    store.dataCreate(W, "recipes", { result: bar, skill: shop, ingredients: [{ item: ore, qty: 2 }] });
    expect(raw("data/tables/recipes.json").objectsById[String(bar)]).toEqual({ id: bar, resultId: bar, resultLevel: 1, ingredientIds: [ore], quantities: [2], jobId: job, skillId: shop });
    store.dataCreate(W, "recipes", { result: sword, skill: shop, ingredients: [{ item: bar, qty: 3 }, { item: ore, qty: 1 }] });
    expect(raw("data/tables/recipes.json").objectsById[String(sword)]).toMatchObject({ resultLevel: 5, ingredientIds: [bar, ore], quantities: [3, 1] });
    expect(recipes().find((r) => r.id === sword)).toMatchObject({ resultName: "Épée de fer", skillName: "Forge", jobName: "Forgeron", level: 5 });
    expect(workshops()[0].recipes).toBe(2);
    expect(errors()).toEqual([]);
    // the ore is gathered, the bar is made from ore, the sword from bars: the whole chain is obtainable
    expect(obtainable().items).toEqual([]);
  });

  it("une recette dont l'atelier n'est posé nulle part ne rend rien obtenable", () => {
    const flag = (store.rowsOf(W, "workshops") as WorkshopRow[])[0];
    store.dataUpdate(W, "workshops", shop, { name: "Forge", job, gfx, places: [] });
    expect(obtainable().items.length).toBe(2);
    store.dataUpdate(W, "workshops", shop, { name: "Forge", job, gfx, places: flag.places.map((p) => ({ map: p.map, cell: p.cell })) });
    expect(obtainable().items).toEqual([]);
  });

  it("refuse des recettes invalides", () => {
    const ok = (): RecipeInput => ({ result: item("Dague de fer"), skill: shop, ingredients: [{ item: ore, qty: 5 }] });
    refuses(() => store.dataCreate(W, "recipes", { ...ok(), result: 424242 }), 400, /fabriqué/);
    refuses(() => store.dataCreate(W, "recipes", { ...ok(), result: bar }), 409, /déjà une recette/);
    refuses(() => store.dataCreate(W, "recipes", { ...ok(), skill: 424242 }), 400, /atelier/);
    refuses(() => store.dataCreate(W, "recipes", { ...ok(), skill: (store.rowsOf(W, "resources") as any[])[0].id }), 400, /atelier/); // a resource is not a workshop
    refuses(() => store.dataCreate(W, "recipes", { ...ok(), ingredients: [] }), 400, /1 à 8/);
    refuses(() => store.dataCreate(W, "recipes", { ...ok(), ingredients: Array.from({ length: 9 }, (_, i) => ({ item: ore + i, qty: 1 })) }), 400, /1 à 8/);
    refuses(() => store.dataCreate(W, "recipes", { ...ok(), ingredients: [{ item: 424242, qty: 1 }] }), 400, /inconnu/);
    refuses(() => store.dataCreate(W, "recipes", { ...ok(), ingredients: [{ item: ore, qty: 0 }] }), 400, /quantité/);
    refuses(() => store.dataCreate(W, "recipes", { ...ok(), ingredients: [{ item: ore, qty: 1 }, { item: ore, qty: 2 }] }), 400, /deux fois/);
    const r = ok();
    refuses(() => store.dataCreate(W, "recipes", { ...r, ingredients: [{ item: r.result, qty: 1 }] }), 400, /propre ingrédient/);
    refuses(() => store.dataCreate(W, "recipes", { ...r, ingredients: [{ item: ore, qty: 2 }] }), 409, /exactement ces ingrédients/); // same as the bar's recipe
    expect(recipes()).toHaveLength(2);
  });

  it("modifier une recette change ses ingrédients ; l'objet fabriqué ne change pas", () => {
    store.dataUpdate(W, "recipes", bar, { result: bar, skill: shop, ingredients: [{ item: ore, qty: 3 }] });
    expect(recipes().find((r) => r.id === bar)!.ingredients).toEqual([{ item: ore, name: "Minerai de fer", qty: 3 }]);
    refuses(() => store.dataUpdate(W, "recipes", bar, { result: sword, skill: shop, ingredients: [{ item: ore, qty: 3 }] }), 400, /ne change pas/);
    expect(errors()).toEqual([]);
  });

  it("protège ce que les recettes utilisent : objets, atelier, métier", () => {
    refuses(() => store.dataDelete(W, "items", ore), 409, /recipe/);
    refuses(() => store.dataDelete(W, "items", sword), 409, /recipe/);
    refuses(() => store.dataDelete(W, "workshops", shop), 409, /recette/);
    refuses(() => store.dataDelete(W, "jobs", job), 409, /utilisé/);
  });

  it("annuler, supprimer, et dupliquer le monde", () => {
    store.dataDelete(W, "recipes", sword);
    expect(recipes().map((r) => r.id)).toEqual([bar]);
    expect(store.undo(W)).toBe(true);
    expect(recipes()).toHaveLength(2);
    store.clone(W, "monde_artisanat_copie", "Copie");
    const copy = "monde_artisanat_copie";
    const lo = store.registry()[copy].ranges.item[0];
    const rs = store.rowsOf(copy, "recipes") as RecipeRow[];
    expect(rs).toHaveLength(2);
    for (const r of rs) { expect(r.id).toBeGreaterThanOrEqual(lo); for (const g of r.ingredients) expect(g.item).toBeGreaterThanOrEqual(lo); }
    expect((store.rowsOf(copy, "workshops") as WorkshopRow[])[0]).toMatchObject({ name: "Forge", recipes: 2 });
    expect(store.detail(copy).problems.filter((p) => p.severity === "error")).toEqual([]);
    store.remove(copy, copy);
    store.dataDelete(W, "recipes", sword);
    store.dataDelete(W, "recipes", bar);
    store.dataDelete(W, "workshops", shop);
    expect(workshops()).toEqual([]);
    expect(errors()).toEqual([]);
  });
});
