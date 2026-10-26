// World archives: export, import into a free slot, and the refusals (foreign zip, path traversal, La Vertèbre).
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import sharp from "sharp";
import { unzipSync, zipSync } from "fflate";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { AtelierError } from "../core/errors";
import { MANIFEST } from "../core/exchange";
import { loadWorld } from "../core/io";
import { collectIds, KINDS } from "../core/ranges";
import { WorldStore } from "../core/store";

let tmp: string, store: WorldStore;
const SRC = "monde_export";
const wdir = (id: string) => path.join(tmp, "worlds", id);
const refuses = (fn: () => unknown, status: number, re: RegExp) => {
  try { fn(); } catch (e) { expect(e).toBeInstanceOf(AtelierError); expect((e as AtelierError).status).toBe(status); expect((e as Error).message).toMatch(re); return; }
  throw new Error("aucune erreur levée");
};
const enc = (s: string) => new TextEncoder().encode(s);

beforeAll(async () => {
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), "atelier-exchange-"));
  fs.mkdirSync(path.join(tmp, "worlds"));
  store = new WorldStore(path.join(tmp, "worlds"), path.join(tmp, "r.json"), path.resolve(__dirname, "..", "templates"));
  store.create(SRC, "Monde exporté");
  const map = (store.rowsOf(SRC, "maps") as { id: number }[])[0].id;
  const png = await sharp({ create: { width: 96, height: 96, channels: 4, background: "#335577" } }).png().toBuffer();
  const [ic] = await store.importAssets(SRC, "item", { files: [{ name: "a.png", data: png }] });
  const [til] = await store.importAssets(SRC, "tile", { files: [{ name: "t.png", data: png }] });
  store.dataCreate(SRC, "items", { name: "Croix d'os", icon: ic.id, type: 12, level: 1, effects: [] });
  store.dataCreate(SRC, "zones", { level: 2 });
  store.dataUpdate(SRC, "visuals", map, { bg: 0xff101010, background: [], sortable: [{ g: til.id!, x: 10, y: 20, cell: 40 }], foreground: [] });
  fs.writeFileSync(path.join(wdir(SRC), "items.json.bak"), "ancien");
});
afterAll(() => fs.rmSync(tmp, { recursive: true, force: true }));

describe("archives de monde", () => {
  it("exporte un ZIP avec manifeste, sans fichiers .bak", () => {
    const files = unzipSync(new Uint8Array(store.exportWorld(SRC)));
    expect(Object.keys(files)).toContain(MANIFEST);
    expect(Object.keys(files)).toContain("world.json");
    expect(Object.keys(files).some((f) => f.endsWith(".bak"))).toBe(false);
    expect(JSON.parse(new TextDecoder().decode(files[MANIFEST])).ranges.item).toEqual(store.registry()[SRC].ranges.item);
  });

  it("réimporte le monde dans un nouvel emplacement, aussi cohérent, avec ses images", () => {
    const out = store.importWorld(store.exportWorld(SRC), "monde_importe", "Monde importé");
    expect(out).toMatchObject({ id: "monde_importe", name: "Monde importé", created: true });
    expect(store.registry().monde_importe.slot).not.toBe(store.registry()[SRC].slot);
    expect(store.detail("monde_importe").problems.map((p) => p.code).sort()).toEqual(store.detail(SRC).problems.map((p) => p.code).sort());
    const ids = collectIds(loadWorld(wdir("monde_importe")).world!);
    const r = store.registry().monde_importe.ranges;
    for (const k of KINDS) for (const n of ids[k]) expect(n >= r[k][0] && n <= r[k][1], `${k} ${n}`).toBe(true);
    expect((store.rowsOf("monde_importe", "items") as unknown[]).length).toBe((store.rowsOf(SRC, "items") as unknown[]).length);
  });

  it("n'importe pas une archive étrangère, piégée ou incomplète", () => {
    refuses(() => store.importWorld(Buffer.from("pas un zip"), "x_monde", "X"), 400, /ZIP invalide/);
    refuses(() => store.importWorld(Buffer.from(zipSync({ "world.json": enc("{}") })), "x_monde", "X"), 400, /atelier/);
    const good = unzipSync(new Uint8Array(store.exportWorld(SRC)));
    refuses(() => store.importWorld(Buffer.from(zipSync({ ...good, "../evil.txt": enc("x") })), "x_monde", "X"), 400, /chemin refusé/);
    expect(fs.existsSync(path.join(tmp, "evil.txt"))).toBe(false);
    const noRange = JSON.stringify({ format: 1, id: "a", ranges: {} });
    refuses(() => store.importWorld(Buffer.from(zipSync({ ...good, [MANIFEST]: enc(noRange) })), "x_monde", "X"), 400, /plage/);
    refuses(() => store.importWorld(Buffer.from(zipSync({ ...good, "world.json": enc("pas du json") })), "x_monde", "X"), 400, /lisible/);
    expect(fs.existsSync(wdir("x_monde"))).toBe(false);
    expect(store.registry().x_monde).toBeUndefined();
  });

  it("refuse un identifiant pris et l'export de La Vertèbre", () => {
    refuses(() => store.importWorld(store.exportWorld(SRC), SRC, "Doublon"), 409, /existe déjà/);
    refuses(() => store.exportWorld("vertebre"), 400, /propres numéros|inconnu/);
  });
});
