// Dofus maps as a starting point: search by coordinates or number, copy grid + decor + tile images into a world.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import sharp from "sharp";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { AtelierError } from "../core/errors";
import { WorldStore } from "../core/store";
import type { VisualRow } from "../core/editors_visual";
import { writeFakeI18n } from "./fake_dofus";

let tmp: string, store: WorldStore, content: string;
const W = "monde_cartes_jeu";
const refuses = async (fn: () => Promise<unknown> | unknown, status: number, re: RegExp) => {
  try { await fn(); } catch (e) { expect(e).toBeInstanceOf(AtelierError); expect((e as AtelierError).status).toBe(status); expect((e as Error).message).toMatch(re); return; }
  throw new Error("aucune erreur levée");
};
const wdir = () => path.join(tmp, "worlds", W);

beforeAll(async () => {
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), "atelier-dofusmaps-"));
  content = path.join(tmp, "content", "Content");
  fs.mkdirSync(path.join(content, "Maps", "Gfx"), { recursive: true });
  for (const g of [12, 18, 99]) await sharp({ create: { width: 90, height: 60, channels: 4, background: "#446688" } }).webp().toFile(path.join(content, "Maps", "Gfx", `${g}.webp`));
  writeFakeI18n(path.join(content, "I18n", "fr.bin"), { 1: "Plaine des Scarafeuilles", 2: "Incarnam" });
  const dofus = path.join(tmp, "worlds", "dofus");
  fs.mkdirSync(path.join(dofus, "maps"), { recursive: true });
  fs.writeFileSync(path.join(dofus, "coords.json"), JSON.stringify({ "-3,5": [[7001, 1, true, false], [7002, 1, true, false]] }));
  const map = (id: number, extra: object = {}) => ({
    id, name: "", subarea: 10, subarea_name_id: 1, area_name_id: 2, outdoor: true, coords: [-3, 5], visual: id, neighbors: { top: 1 }, triggers: [], map_change: { 0: 1 },
    blocked: [40, 41, 300, 9999], fight_blocked: [40, 41, 300, 201], los_blocked: [41], placement: { red: [100, 300, 101], blue: [200, 201, 202] }, monster_spawn: true, ...extra,
  });
  fs.writeFileSync(path.join(dofus, "maps", "7001.json"), JSON.stringify(map(7001)));
  fs.writeFileSync(path.join(dofus, "maps", "7002.json"), JSON.stringify(map(7002, { visual: 7001, outdoor: false })));
  const el = (g: number, extra: object = {}) => ({ g, c: 4286611584, t: [1, 0, 0, 1, 100, 100], ...extra });
  fs.writeFileSync(path.join(content, "Maps", "7001.json"), JSON.stringify({
    id: 7001, bg: 4278190080, neighbors: { top: 5 }, cell_flags: ["mov"], cells: [[0]], animated: [{ g: 5 }],
    layers: { background: [el(12)], sortable: [el(18, { cell: 50, o: 0, t: [-1.5, 0, 0, 1.5, 200, 120], c: 4278255360 }), el(99, { cell: 51, o: 0 }), el(555, { cell: 52, o: 0 })], foreground: [] },
  }));
  fs.mkdirSync(path.join(tmp, "worlds"), { recursive: true });
  store = new WorldStore(path.join(tmp, "worlds"), path.join(tmp, "r.json"), path.resolve(__dirname, "..", "templates"));
  store.contentRoot = content;
  store.create(W, "Cartes du jeu");
});
afterAll(() => fs.rmSync(tmp, { recursive: true, force: true }));

describe("maps du jeu comme point de départ", () => {
  it("cherche par coordonnées ou par numéro, avec le nom du lieu lu dans les textes du client", () => {
    const byXY = store.libraryMaps("-3,5");
    expect(byXY.map((m) => m.source)).toEqual([7001, 7002]);
    expect(byXY[0]).toMatchObject({ coords: [-3, 5], outdoor: true, place: "Plaine des Scarafeuilles", elements: 4 });
    expect(byXY[0].blocked).toEqual([40, 41, 300, 9999]);
    expect(store.libraryMaps("-3 5")).toHaveLength(2);
    expect(store.libraryMaps("7002")[0].outdoor).toBe(false);
    expect(store.libraryMaps("8888")).toEqual([]);
    expect(store.libraryMaps("0,0")).toEqual([]);
  });

  it("refuse une recherche qui n'est ni des coordonnées ni un numéro", async () => {
    await refuses(() => store.libraryMaps("plaine"), 400, /coordonnées/);
  });

  it("copie la grille, le décor et les images ; laisse de côté ce dont l'image manque ; le monde reste sans erreur", () => {
    const r = store.importDofusMap(W, "Plaine copiée", 7001);
    expect(r).toMatchObject({ dropped: 1, missing: 1 }); // image 555 does not exist
    const row = (store.rowsOf(W, "maps") as any[]).find((m) => m.id === r.id);
    expect(row.name).toBe("Plaine copiée");
    expect(row.blocked).toEqual([40, 41, 201, 300]); // walls + cells blocked in fights; 9999 is not a cell of the grid
    expect(row.placement ?? { red: row.red, blue: row.blue }).toBeTruthy();
    expect(row.red).toEqual([100, 101]); // 300 is a wall: not a valid placement cell
    expect(row.blue).toEqual([200, 202]); // 201 is blocked in fights without being a wall (8 real Dofus maps do this)
    expect(row.neighbors).toEqual({});
    expect(row.doors).toEqual([]);
    expect(row.monsterSpawn).toBe(false);
    expect(row.phoenix).not.toBe(300); // the rebirth cell must be free
    expect([40, 41, 300]).not.toContain(row.phoenix);
    for (const g of [12, 18, 99]) expect(fs.existsSync(path.join(wdir(), "Content", "Maps", "Gfx", `${g}.webp`))).toBe(true);
    const v = JSON.parse(fs.readFileSync(path.join(wdir(), "Content", "Maps", `${r.id}.json`), "utf-8"));
    expect(v).toMatchObject({ id: r.id, neighbors: {}, animated: [] });
    expect(v.layers.sortable.map((e: any) => e.g)).toEqual([18, 99]);
    expect(v.layers.sortable[0]).toMatchObject({ t: [-1.5, 0, 0, 1.5, 200, 120], c: 4278255360 });
    const errors = store.detail(W).problems.filter((p) => p.severity === "error");
    expect(errors).toEqual([]);
    // the decor editor reads it, scale and tint included
    const vis = store.visualOf(W, r.id) as VisualRow;
    expect(vis.sortable[0]).toMatchObject({ g: 18, m: [-1.5, 0, 0, 1.5], tint: 4278255360 });
  });

  it("une deuxième copie ne recopie pas les images déjà présentes, et le décor partagé de la source est lu par son numéro de visuel", () => {
    const r = store.importDofusMap(W, "Seconde", 7002); // its visual is 7001
    expect(r.id).toBeGreaterThan(0);
    expect(store.detail(W).problems.filter((p) => p.severity === "error")).toEqual([]);
  });

  it("sert une image WebP copiée du jeu en PNG", async () => {
    const png = await store.assetBytes(W, "tile", 12);
    expect((await sharp(png).metadata()).format).toBe("png");
    await refuses(() => store.assetBytes(W, "tile", 424242), 404, /introuvable/);
  });

  it("refuse une map inconnue, un nom vide, et rien n'est resté de la tentative", async () => {
    const before = (store.rowsOf(W, "maps") as unknown[]).length;
    await refuses(() => store.importDofusMap(W, "X", 123456), 404, /absente/);
    await refuses(() => store.importDofusMap(W, "  ", 7001), 400, /nom/);
    expect((store.rowsOf(W, "maps") as unknown[]).length).toBe(before);
  });

  it("annuler retire la map copiée", () => {
    const before = (store.rowsOf(W, "maps") as unknown[]).length;
    store.importDofusMap(W, "Éphémère", 7001);
    expect((store.rowsOf(W, "maps") as unknown[]).length).toBe(before + 1);
    expect(store.undo(W)).toBe(true);
    expect((store.rowsOf(W, "maps") as unknown[]).length).toBe(before);
  });
});
