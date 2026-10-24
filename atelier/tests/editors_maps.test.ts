// Map editor through a real store on a temp folder: grid, neighbours, doors, deletion, undo of a deletion.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { AtelierError } from "../core/errors";
import type { MapInput, MapRow } from "../core/editors_maps";
import { WorldStore } from "../core/store";

let tmp: string, store: WorldStore, first: number, second: number;
const W = "monde_cartes";
const errors = () => store.detail(W).problems.filter((p) => p.severity === "error").map((p) => p.code);
const row = (id: number) => (store.rowsOf(W, "maps") as MapRow[]).find((m) => m.id === id)!;
const asInput = (r: MapRow, over: Partial<MapInput> = {}): MapInput => ({
  name: r.name, coords: r.coords, outdoor: r.outdoor, monsterSpawn: r.monsterSpawn, zone: r.zone, blocked: r.blocked, los: r.los, red: r.red, blue: r.blue,
  phoenix: r.phoenix, isPhoenix: r.isPhoenix, neighbors: r.neighbors, doors: r.doors, ...over,
});
const refuses = (fn: () => void, status: number, re: RegExp) => {
  try { fn(); } catch (e) { expect(e).toBeInstanceOf(AtelierError); expect((e as AtelierError).status).toBe(status); expect((e as Error).message).toMatch(re); return; }
  throw new Error("aucune erreur levée");
};

beforeAll(() => {
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), "atelier-maps-"));
  fs.mkdirSync(path.join(tmp, "worlds"));
  store = new WorldStore(path.join(tmp, "worlds"), path.join(tmp, "r.json"), path.resolve(__dirname, "..", "templates"));
  store.create(W, "Cartes");
  first = (store.rowsOf(W, "maps") as MapRow[])[0].id;
  second = store.dataCreate(W, "maps", { name: "Clairière" });
});
afterAll(() => fs.rmSync(tmp, { recursive: true, force: true }));

describe("maps", () => {
  it("creates a map in range with its own visual, and the world stays coherent", () => {
    expect(second).toBeGreaterThan(first);
    expect(fs.existsSync(path.join(tmp, "worlds", W, "maps", `${second}.json`))).toBe(true);
    expect(fs.existsSync(path.join(tmp, "worlds", W, "Content", "Maps", `${second}.json`))).toBe(true);
    expect(errors()).toEqual([]);
  });
  it("paints the grid; blocked cells are written to blocked and fight_blocked", () => {
    const r = row(first);
    store.dataUpdate(W, "maps", first, asInput(r, { blocked: [40, 41, 42], los: [41], red: [100, 101], blue: [200] }));
    const after = row(first);
    expect(after.blocked).toEqual([40, 41, 42]);
    expect(after.red).toEqual([100, 101]);
    const disk = JSON.parse(fs.readFileSync(path.join(tmp, "worlds", W, "maps", `${first}.json`), "utf-8"));
    expect(disk.fight_blocked).toEqual([40, 41, 42]);
    expect(errors()).toEqual([]);
  });
  it("refuses cells off the grid, a placement on a wall, and blocking the world's start cell", () => {
    const r = row(first);
    refuses(() => store.dataUpdate(W, "maps", first, asInput(r, { blocked: [560] })), 400, /hors de la grille/);
    refuses(() => store.dataUpdate(W, "maps", first, asInput(r, { blocked: [100], red: [100] })), 400, /bloquée/);
    refuses(() => store.dataUpdate(W, "maps", first, asInput(r, { blocked: [r.startCell] })), 400, /renaissance|départ/);
    refuses(() => store.dataUpdate(W, "maps", first, asInput(r, { name: " " })), 400, /nom/);
  });
  it("links neighbours both ways and doors with a valid arrival", () => {
    store.dataUpdate(W, "maps", first, asInput(row(first), { neighbors: { right: second }, doors: [{ cell: 300, to_map: second, to_cell: 301 }] }));
    expect(row(second).neighbors).toEqual({ left: first });
    expect(errors()).toEqual([]);
    refuses(() => store.dataUpdate(W, "maps", second, asInput(row(second), { blocked: [301] })), 400, /porte de la map/);
    refuses(() => store.dataUpdate(W, "maps", first, asInput(row(first), { doors: [{ cell: 300, to_map: 999, to_cell: 1 }] })), 400, /inconnue/);
    refuses(() => store.dataUpdate(W, "maps", first, asInput(row(first), { neighbors: { right: first } })), 400, /propre voisine/);
    store.dataUpdate(W, "maps", first, asInput(row(first), { neighbors: {}, doors: [] }));
    expect(row(second).neighbors).toEqual({}); // the other end is cleared with it
  });
  it("sets the start, refuses to delete a used map, then deletes a free one, removing its files, and undo brings them back", () => {
    store.dataUpdate(W, "maps", second, { start: 120 });
    expect(row(second).isStart).toBe(true);
    refuses(() => store.dataDelete(W, "maps", second), 409, /utilisée par world départ/);
    store.dataUpdate(W, "maps", first, { start: 300 });
    store.dataUpdate(W, "maps", second, asInput(row(second), { isPhoenix: false }));
    const file = path.join(tmp, "worlds", W, "maps", `${second}.json`);
    store.dataDelete(W, "maps", second);
    expect(fs.existsSync(file)).toBe(false);
    expect(fs.existsSync(path.join(tmp, "worlds", W, "Content", "Maps", `${second}.json`))).toBe(false);
    expect(errors()).toEqual([]);
    store.undo(W);
    expect(fs.existsSync(file)).toBe(true);
    store.redo(W);
    expect(fs.existsSync(file)).toBe(false);
    refuses(() => store.dataDelete(W, "maps", first), 409, /au moins une map|utilisée/);
  });
});
