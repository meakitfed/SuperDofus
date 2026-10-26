// Visual layers editor through a real store: tiles from the library, props on cells, validation, undo.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import sharp from "sharp";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { AtelierError } from "../core/errors";
import { cellXY, type VisualInput, type VisualRow } from "../core/editors_visual";
import { WorldStore } from "../core/store";

let tmp: string, store: WorldStore, map: number, tile: number, tile2: number;
const W = "monde_decor";
const errors = () => store.detail(W).problems.filter((p) => p.severity === "error").map((p) => `${p.code} ${p.message}`);
const row = () => store.visualOf(W, map) as VisualRow;
const raw = () => JSON.parse(fs.readFileSync(path.join(tmp, "worlds", W, "Content", "Maps", `${map}.json`), "utf-8"));
const refuses = (fn: () => void, re: RegExp) => {
  try { fn(); } catch (e) { expect(e).toBeInstanceOf(AtelierError); expect((e as AtelierError).status).toBe(400); expect((e as Error).message).toMatch(re); return; }
  throw new Error("aucune erreur levée");
};
const base = (): VisualInput => ({ bg: 0xff202030, background: [{ g: tile, x: 623.5, y: 419 }], sortable: [{ g: tile2, x: 100, y: 200, cell: 20 }, { g: tile2, x: 102, y: 204, cell: 20 }], foreground: [] });

beforeAll(async () => {
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), "atelier-visual-"));
  fs.mkdirSync(path.join(tmp, "worlds"));
  store = new WorldStore(path.join(tmp, "worlds"), path.join(tmp, "r.json"), path.resolve(__dirname, "..", "templates"));
  store.create(W, "Décor");
  map = (store.rowsOf(W, "maps") as { id: number }[])[0].id;
  const png = await sharp({ create: { width: 64, height: 64, channels: 4, background: "#557733" } }).png().toBuffer();
  const a = await store.importAssets(W, "tile", { files: [{ name: "sol.png", data: png }] });
  const b = await store.importAssets(W, "tile", { files: [{ name: "rocher.png", data: await sharp({ create: { width: 32, height: 48, channels: 4, background: "#775533" } }).png().toBuffer() }] });
  tile = a[0].id!;
  tile2 = b[0].id!;
});
afterAll(() => fs.rmSync(tmp, { recursive: true, force: true }));

describe("décor de map", () => {
  it("un monde neuf a un décor vide", () => {
    const r = row();
    expect(r.background).toEqual([]);
    expect(r.sortable).toEqual([]);
    expect(r.shared).toBe(false);
  });

  it("enregistre les trois couches : position, cellule, ordre sur la même cellule", () => {
    store.dataUpdate(W, "visuals", map, base());
    const v = raw();
    expect(v.bg).toBe(0xff202030);
    expect(v.layers.background[0]).toMatchObject({ g: tile, t: [1, 0, 0, 1, 623.5, 419] });
    expect(v.layers.sortable.map((e: any) => [e.cell, e.o])).toEqual([[20, 0], [20, 1]]);
    expect(row().sortable[1]).toEqual({ g: tile2, x: 102, y: 204, cell: 20 });
    expect(errors()).toEqual([]);
  });

  it("garde les champs inconnus d'un élément à son rang (teinte)", () => {
    const v = raw();
    v.layers.sortable[0].c = 0xff112233;
    fs.writeFileSync(path.join(tmp, "worlds", W, "Content", "Maps", `${map}.json`), JSON.stringify(v));
    store.reload(W);
    const b = base();
    b.sortable[0].x = 130;
    store.dataUpdate(W, "visuals", map, b);
    expect(raw().layers.sortable[0]).toMatchObject({ c: 0xff112233, t: [1, 0, 0, 1, 130, 200] });
  });

  it("refuse une image absente, une cellule ou une position hors de la map, une liste trop longue", () => {
    const bad = (mut: (v: VisualInput) => void, re: RegExp) => { const v = base(); mut(v); refuses(() => store.dataUpdate(W, "visuals", map, v), re); };
    bad((v) => { v.sortable[0].g = 123456; }, /n'existe pas/);
    bad((v) => { v.sortable[0].cell = 560; }, /cellule/);
    bad((v) => { v.background[0].x = 99999; }, /hors de la map/);
    bad((v) => { v.background[0].y = Number.NaN; }, /hors de la map/);
    bad((v) => { v.bg = -1; }, /couleur/);
    bad((v) => { v.foreground = Array.from({ length: 401 }, () => ({ g: tile, x: 0, y: 0 })); }, /400/);
    expect(errors()).toEqual([]);
  });

  it("annuler rend le décor précédent ; supprimer l'image utilisée est refusé", async () => {
    const before = row();
    const b = base();
    b.sortable = [];
    store.dataUpdate(W, "visuals", map, b);
    expect(row().sortable).toEqual([]);
    expect(store.undo(W)).toBe(true);
    expect(row()).toEqual(before);
    const assets = await store.assets(W, "tile");
    expect(assets.find((a) => a.id === tile)!.usedBy.length).toBeGreaterThan(0);
  });

  it("cellXY suit la convention du jeu (lignes impaires décalées d'une demi-cellule)", () => {
    expect(cellXY(0)).toEqual([0, 0]);
    expect(cellXY(14)).toEqual([43, 21.5]);
    expect(cellXY(15)).toEqual([129, 21.5]);
  });
});
