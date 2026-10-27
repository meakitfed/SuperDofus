// Dungeons: rooms chained from an entrance, keys, a level, boss monsters copied to the bosses table.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import sharp from "sharp";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { AtelierError } from "../core/errors";
import type { DungeonInput, DungeonRow } from "../core/editors_dungeons";
import { newGrade } from "../core/editors_monsters";
import { WorldStore } from "../core/store";

let tmp: string, store: WorldStore, entrance: number, rooms: number[], key: number, mob: number, zone: number;
const W = "monde_donjons";
const errors = () => store.detail(W).problems.filter((p) => p.severity === "error").map((p) => `${p.code} ${p.message}`);
const warnings = () => store.detail(W).problems.filter((p) => p.severity === "warning").map((p) => p.code);
const dungeons = () => store.rowsOf(W, "dungeons") as DungeonRow[];
const refuses = (fn: () => void, status: number, re: RegExp) => {
  try { fn(); } catch (e) { expect(e).toBeInstanceOf(AtelierError); expect((e as AtelierError).status).toBe(status); expect((e as Error).message).toMatch(re); return; }
  throw new Error("aucune erreur levée");
};
const base = (): DungeonInput => ({ name: "Cave du Rat", level: 10, minLevel: 5, difficulty: 2, entrance, exit: entrance, rooms: [rooms[0], rooms[1]], keys: [{ item: key, qty: 1 }], bosses: [] });
const raw = (name: string) => JSON.parse(fs.readFileSync(path.join(tmp, "worlds", W, name), "utf-8"));

beforeAll(async () => {
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), "atelier-dun-"));
  fs.mkdirSync(path.join(tmp, "worlds"));
  store = new WorldStore(path.join(tmp, "worlds"), path.join(tmp, "r.json"), path.resolve(__dirname, "..", "templates"));
  store.create(W, "Donjons");
  entrance = (store.rowsOf(W, "maps") as { id: number }[])[0].id;
  rooms = [store.dataCreate(W, "maps", { name: "Salle 1" }), store.dataCreate(W, "maps", { name: "Salle 2" })];
  const png = await sharp({ create: { width: 96, height: 96, channels: 4, background: "#335577" } }).png().toBuffer();
  const file = [{ name: "a.png", data: png }];
  const [ic] = await store.importAssets(W, "item", { files: file });
  const [portrait] = await store.importAssets(W, "monster", { files: file });
  key = store.dataCreate(W, "items", { name: "Clé de la cave", icon: ic.id, type: 84, level: 1, effects: [] });
  fs.cpSync(path.resolve(__dirname, "..", "..", "game", "worlds", "vertebre", "Content", "Characters", "Bones", "950001"), path.join(tmp, "worlds", W, "Content", "Characters", "Bones", "950001"), { recursive: true });
  zone = store.dataCreate(W, "zones", { level: 5 });
  mob = store.dataCreate(W, "monsters", { name: "Rat", bone: 950001, size: 100, portrait: portrait.id, grades: [{ ...newGrade(), level: 5 }], zones: [String(zone)] });
  for (const r of rooms) {
    const m = (store.rowsOf(W, "maps") as any[]).find((x) => x.id === r);
    store.dataUpdate(W, "maps", r, { ...m, zone: String(zone), monsterSpawn: true });
  }
});
afterAll(() => fs.rmSync(tmp, { recursive: true, force: true }));

describe("donjons", () => {
  let id = 0;
  it("crée un donjon : id dans la plage, fichier au format du jeu, salles atteignables depuis l'entrée, monde sans erreur", () => {
    id = store.dataCreate(W, "dungeons", base());
    expect(id).toBeGreaterThanOrEqual(store.registry()[W].ranges.interactive[0]);
    expect(raw("dungeons.json").dungeons[String(id)]).toEqual({
      id, name: "Cave du Rat", level: 10, min_level: 5, difficulty: 2, maps: rooms, entrance_map: entrance, exit_map: entrance, keys: [{ item: key, qty: 1 }], bosses: [],
    });
    expect(dungeons()[0]).toMatchObject({ name: "Cave du Rat", entranceName: "Départ", roomNames: ["Salle 1", "Salle 2"] });
    expect(errors()).toEqual([]);
    expect(warnings()).not.toContain("W_WORLD_MAP_UNREACHABLE"); // the rooms hang from the entrance
  });

  it("un boss est copié dans la table des boss, listé une seule fois, protège le monstre, et suit ses modifications", () => {
    store.dataUpdate(W, "dungeons", id, { ...base(), bosses: [mob] });
    expect(Object.keys(raw("monsters.json").bosses)).toEqual([String(mob)]);
    expect((store.rowsOf(W, "monsters") as any[]).filter((m) => m.id === mob)).toHaveLength(1);
    expect(errors()).toEqual([]);
    refuses(() => store.dataDelete(W, "monsters", mob), 409, /dungeon/);
    const row = (store.rowsOf(W, "monsters") as any[]).find((m) => m.id === mob);
    store.dataUpdate(W, "monsters", mob, { ...row, name: "Rat géant" });
    expect(Object.keys(raw("monsters.json").bosses)).toEqual([String(mob)]);
    store.dataUpdate(W, "monsters", mob, { ...row, name: "Rat géant", grades: [{ ...row.grades[0], hp: 77 }] });
    expect(raw("monsters.json").bosses[String(mob)].grades[0].hp).toBe(77);
  });

  it("retirer le boss retire sa copie, le monstre reste", () => {
    store.dataUpdate(W, "dungeons", id, base());
    expect(raw("monsters.json").bosses).toEqual({});
    expect(raw("monsters.json").monsters[String(mob)]).toBeTruthy();
  });

  it("refuse des données invalides sans rien laisser", () => {
    refuses(() => store.dataCreate(W, "dungeons", { ...base(), name: " " }), 400, /vide/);
    refuses(() => store.dataCreate(W, "dungeons", { ...base(), level: 0 }), 400, /niveau/);
    refuses(() => store.dataCreate(W, "dungeons", { ...base(), minLevel: 11 }), 400, /niveau minimum/);
    refuses(() => store.dataCreate(W, "dungeons", { ...base(), difficulty: 6 }), 400, /difficulté/);
    refuses(() => store.dataCreate(W, "dungeons", { ...base(), rooms: [] }), 400, /salles/);
    refuses(() => store.dataCreate(W, "dungeons", { ...base(), rooms: [rooms[0], rooms[0]] }), 400, /deux fois/);
    refuses(() => store.dataCreate(W, "dungeons", { ...base(), rooms: [424242] }), 400, /inconnue/);
    refuses(() => store.dataCreate(W, "dungeons", { ...base(), rooms: [entrance] }), 400, /à la fois/);
    refuses(() => store.dataCreate(W, "dungeons", { ...base(), entrance: 424242 }), 400, /entrée/);
    refuses(() => store.dataCreate(W, "dungeons", { ...base(), keys: [{ item: 424242, qty: 1 }] }), 400, /clé/);
    refuses(() => store.dataCreate(W, "dungeons", { ...base(), keys: [{ item: key, qty: 0 }] }), 400, /quantité/);
    refuses(() => store.dataCreate(W, "dungeons", { ...base(), bosses: [424242] }), 400, /boss/);
    expect(dungeons()).toHaveLength(1);
    expect(raw("monsters.json").bosses).toEqual({});
  });

  it("une salle sans monstre ni boss est signalée, pas refusée", () => {
    const r = (store.rowsOf(W, "maps") as any[]).find((x) => x.id === rooms[1]);
    store.dataUpdate(W, "maps", rooms[1], { ...r, zone: null, monsterSpawn: false });
    store.dataUpdate(W, "maps", rooms[0], { ...(store.rowsOf(W, "maps") as any[]).find((x) => x.id === rooms[0]), zone: null, monsterSpawn: false });
    expect(warnings()).toContain("W_DUNGEON_NO_MONSTERS");
    expect(errors()).toEqual([]);
  });

  it("annuler rend le donjon et sa copie de boss d'un coup ; dupliquer le monde décale ses numéros", () => {
    store.dataUpdate(W, "dungeons", id, { ...base(), bosses: [mob] });
    expect(store.undo(W)).toBe(true);
    expect(raw("monsters.json").bosses).toEqual({});
    expect(store.redo(W)).toBe(true);
    expect(Object.keys(raw("monsters.json").bosses)).toEqual([String(mob)]);
    store.clone(W, "monde_donjons_copie", "Copie");
    const copy = "monde_donjons_copie";
    const lo = store.registry()[copy].ranges.interactive[0];
    const d = (store.rowsOf(copy, "dungeons") as DungeonRow[])[0];
    expect(d.id).toBeGreaterThanOrEqual(lo);
    expect(d.rooms.every((r) => r >= store.registry()[copy].ranges.map[0])).toBe(true);
    expect(d.bosses[0]).toBeGreaterThanOrEqual(store.registry()[copy].ranges.monster[0]);
    expect(store.detail(copy).problems.filter((p) => p.severity === "error")).toEqual([]);
    store.remove(copy, copy);
  });

  it("supprimer le donjon retire aussi la copie de boss", () => {
    store.dataDelete(W, "dungeons", id);
    expect(dungeons()).toEqual([]);
    expect(raw("monsters.json").bosses).toEqual({});
    expect(errors()).toEqual([]);
  });
});
