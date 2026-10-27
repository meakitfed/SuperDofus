// Jobs, resources (gathering skills) and their places on maps, through a real store on a temp folder.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import sharp from "sharp";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { AtelierError } from "../core/errors";
import type { JobRow, ResourceInput, ResourceRow } from "../core/editors_resources";
import { WorldStore } from "../core/store";

let tmp: string, store: WorldStore, map: number, item: number, gfx: number, job: number;
const W = "monde_ressources";
const errors = () => store.detail(W).problems.filter((p) => p.severity === "error").map((p) => `${p.code} ${p.message}`);
const resources = () => store.rowsOf(W, "resources") as ResourceRow[];
const jobs = () => store.rowsOf(W, "jobs") as JobRow[];
const refuses = (fn: () => void, status: number, re: RegExp) => {
  try { fn(); } catch (e) { expect(e).toBeInstanceOf(AtelierError); expect((e as AtelierError).status).toBe(status); expect((e as Error).message).toMatch(re); return; }
  throw new Error("aucune erreur levée");
};
const base = (): ResourceInput => ({ name: "Frêne", job, item, level: 1, gfx, places: [{ map, cell: 150 }, { map, cell: 180 }] });
const raw = (name: string) => JSON.parse(fs.readFileSync(path.join(tmp, "worlds", W, name), "utf-8"));

beforeAll(async () => {
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), "atelier-res-"));
  fs.mkdirSync(path.join(tmp, "worlds"));
  store = new WorldStore(path.join(tmp, "worlds"), path.join(tmp, "r.json"), path.resolve(__dirname, "..", "templates"));
  store.create(W, "Ressources");
  map = (store.rowsOf(W, "maps") as { id: number }[])[0].id;
  const png = await sharp({ create: { width: 96, height: 96, channels: 4, background: "#335577" } }).png().toBuffer();
  const [ic] = await store.importAssets(W, "item", { files: [{ name: "a.png", data: png }] });
  const [tile] = await store.importAssets(W, "tile", { files: [{ name: "t.png", data: png }] });
  gfx = tile.id!;
  item = store.dataCreate(W, "items", { name: "Bois de frêne", icon: ic.id, type: 15, level: 1, effects: [] });
  job = store.dataCreate(W, "jobs", { name: "Bûcheron" });
});
afterAll(() => fs.rmSync(tmp, { recursive: true, force: true }));

describe("métiers", () => {
  it("crée un métier dans la plage du monde, avec son nom en texte ; un monde neuf n'a pas de fichier de métiers avant", () => {
    expect(job).toBeGreaterThanOrEqual(store.registry()[W].ranges.interactive[0]);
    expect(jobs()).toEqual([{ id: job, name: "Bûcheron", resources: 0 }]);
    expect(raw("data/tables/jobs.json").objectsById[String(job)]).toMatchObject({ id: job, iconId: 0 });
    expect(errors()).toEqual([]);
  });
  it("renomme un métier, refuse un nom vide", () => {
    store.dataUpdate(W, "jobs", job, { name: "Bûcheronne" });
    expect(jobs()[0].name).toBe("Bûcheronne");
    refuses(() => store.dataUpdate(W, "jobs", job, { name: " " }), 400, /vide/);
    store.dataUpdate(W, "jobs", job, { name: "Bûcheron" });
  });
});

describe("ressources", () => {
  let id = 0;
  it("crée une ressource posée à deux endroits : ids distincts dans la plage, cellules occupées, monde sans erreur", () => {
    id = store.dataCreate(W, "resources", base());
    const r = resources().find((x) => x.id === id)!;
    expect(r).toMatchObject({ name: "Frêne", job, jobName: "Bûcheron", item, itemName: "Bois de frêne", level: 1, gfx });
    expect(r.places.map((p) => p.cell)).toEqual([150, 180]);
    const ids = [job, id, ...r.places.map((p) => p.element)];
    expect(new Set(ids).size).toBe(ids.length); // jobs, skills and elements share one numbering
    for (const n of ids) expect(n).toBeGreaterThanOrEqual(store.registry()[W].ranges.interactive[0]);
    const blocked = (store.rowsOf(W, "maps") as any[])[0].blocked;
    expect(blocked).toEqual(expect.arrayContaining([150, 180]));
    expect(raw("data/tables/skills.json").objectsById[String(id)]).toMatchObject({ parentJobId: job, gatheredRessourceItem: item, levelMin: 1 });
    expect(raw("interactives.json").maps[String(map)]).toHaveLength(2);
    expect(errors()).toEqual([]);
    expect(jobs()[0].resources).toBe(1);
  });

  it("modifier garde l'identifiant d'un élément qui reste, retire ceux qui partent, ajoute les nouveaux", () => {
    const before = resources().find((x) => x.id === id)!;
    const keep = before.places.find((p) => p.cell === 150)!.element;
    store.dataUpdate(W, "resources", id, { ...base(), name: "Frêne ancien", level: 20, places: [{ map, cell: 150 }, { map, cell: 210 }] });
    const after = resources().find((x) => x.id === id)!;
    expect(after).toMatchObject({ name: "Frêne ancien", level: 20 });
    expect(after.places.map((p) => p.cell).sort()).toEqual([150, 210]);
    expect(after.places.find((p) => p.cell === 150)!.element).toBe(keep);
    expect(errors()).toEqual([]);
  });

  it("refuse un métier ou un objet inconnu, un niveau ou une image invalides, une cellule prise ou en double ou de départ", () => {
    refuses(() => store.dataCreate(W, "resources", { ...base(), job: 424242 }), 400, /métier/);
    refuses(() => store.dataCreate(W, "resources", { ...base(), item: 424242 }), 400, /objet/);
    refuses(() => store.dataCreate(W, "resources", { ...base(), level: 0 }), 400, /niveau/);
    refuses(() => store.dataCreate(W, "resources", { ...base(), level: 201 }), 400, /niveau/);
    refuses(() => store.dataCreate(W, "resources", { ...base(), gfx: 424242 }), 400, /introuvable/);
    refuses(() => store.dataCreate(W, "resources", { ...base(), name: "" }), 400, /vide/);
    refuses(() => store.dataCreate(W, "resources", { ...base(), places: [{ map: 424242, cell: 100 }] }), 400, /map/);
    refuses(() => store.dataCreate(W, "resources", { ...base(), places: [{ map, cell: 900 }] }), 400, /hors de la grille/);
    refuses(() => store.dataCreate(W, "resources", { ...base(), places: [{ map, cell: 100 }, { map, cell: 100 }] }), 400, /deux fois/);
    refuses(() => store.dataCreate(W, "resources", { ...base(), places: [{ map, cell: 150 }] }), 409, /occupée/); // 150 is taken by the first resource
    refuses(() => store.dataCreate(W, "resources", { ...base(), places: [{ map, cell: 300 }] }), 409, /départ/);
    expect(resources()).toHaveLength(1); // nothing was left by the refused attempts
  });

  it("un métier utilisé ne peut pas être supprimé ; supprimer la ressource retire ses éléments et son texte", () => {
    refuses(() => store.dataDelete(W, "jobs", job), 409, /utilisé/);
    const textsBefore = Object.keys(raw("Content/I18n/extra_fr.json")).length;
    store.dataDelete(W, "resources", id);
    expect(resources()).toEqual([]);
    expect(raw("interactives.json").maps).toEqual({});
    expect(Object.keys(raw("Content/I18n/extra_fr.json")).length).toBe(textsBefore - 1);
    expect(errors()).toEqual([]);
    store.dataDelete(W, "jobs", job);
    expect(jobs()).toEqual([]);
  });

  it("annuler rétablit le métier, la ressource et ses éléments d'un coup", () => {
    expect(store.undo(W)).toBe(true); // the job comes back
    expect(jobs()).toHaveLength(1);
    expect(store.undo(W)).toBe(true); // the resource comes back with its elements
    expect(resources()[0].places).toHaveLength(2);
    expect(errors()).toEqual([]);
  });

  it("dupliquer le monde décale aussi les métiers, ressources et éléments, sans incohérence", () => {
    store.clone(W, "monde_ressources_copie", "Copie");
    const copy = "monde_ressources_copie";
    const lo = store.registry()[copy].ranges.interactive[0];
    const rows = store.rowsOf(copy, "resources") as ResourceRow[];
    expect(rows).toHaveLength(1);
    const ids = [rows[0].id, rows[0].job, ...rows[0].places.map((p) => p.element)];
    for (const n of ids) expect(n).toBeGreaterThanOrEqual(lo);
    expect(rows[0]).toMatchObject({ name: "Frêne ancien", jobName: "Bûcheron", level: 20 });
    expect(store.detail(copy).problems.filter((p) => p.severity === "error")).toEqual([]);
    // a new resource in the copy never reuses a number
    const again = store.dataCreate(copy, "resources", { ...base(), name: "Chêne", places: [{ map: (store.rowsOf(copy, "maps") as any[])[0].id, cell: 260 }], job: rows[0].job, item: rows[0].item, gfx: rows[0].gfx });
    expect(ids).not.toContain(again);
    store.remove(copy, copy);
  });
});
