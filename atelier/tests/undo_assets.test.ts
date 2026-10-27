// Undo / redo and deleted images: going back to a state that points at an image deleted since must bring the image back.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import sharp from "sharp";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { WorldStore } from "../core/store";

let tmp: string, store: WorldStore;
const W = "monde_images_annuler";
const png = (color: string) => sharp({ create: { width: 64, height: 64, channels: 4, background: color } }).png().toBuffer();
const file = async (cat: string, color: string) => (await store.importAssets(W, cat, { files: [{ name: `${color}.png`, data: await png(color) }] }))[0].id!;
const ids = async () => (await store.assets(W, "item")).map((a) => a.id);
const errors = () => store.detail(W).problems.filter((p) => p.severity === "error");

beforeAll(() => {
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), "atelier-undoimg-"));
  fs.mkdirSync(path.join(tmp, "worlds"), { recursive: true });
  store = new WorldStore(path.join(tmp, "worlds"), path.join(tmp, "r.json"), path.resolve(__dirname, "..", "templates"));
  store.create(W, "Images annulables");
});
afterAll(() => fs.rmSync(tmp, { recursive: true, force: true }));

describe("annuler après la suppression d'une image", () => {
  it("l'image réapparaît quand l'état retrouvé la référence de nouveau, et disparaît quand on rétablit", async () => {
    const a = await file("item", "#aa0000");
    const b = await file("item", "#00aa00");
    const item = store.dataCreate(W, "items", { name: "Dent", icon: a, type: 9, level: 1, effects: [[125, 5, 0, 0]] });
    const row = (store.rowsOf(W, "items") as any[]).find((r) => r.id === item);
    store.dataUpdate(W, "items", item, { ...row, icon: b });
    store.removeAsset(W, "item", a); // a is now unused
    expect(await ids()).toEqual([b]);

    expect(store.undo(W)).toBe(true); // back to the item with icon a
    expect(await ids()).toEqual([a, b]);
    expect(errors()).toEqual([]);
    expect(((await store.assets(W, "item")).find((x) => x.id === a)?.name)).toBe("aa0000"); // its name came back too

    expect(store.redo(W)).toBe(true); // forward: the item uses b again, a is unused (it stays, restored images are not re-deleted)
    expect(errors()).toEqual([]);
    expect(await ids()).toContain(b);
  });

  it("une image supprimée et jamais redemandée reste supprimée après un annuler qui ne la concerne pas", async () => {
    const c = await file("item", "#0000aa");
    store.removeAsset(W, "item", c);
    store.dataCreate(W, "items", { name: "Autre", icon: (await ids())[0], type: 9, level: 1, effects: [[125, 5, 0, 0]] });
    store.undo(W); // undoes the item creation, not the deletion
    expect(await ids()).not.toContain(c);
  });

  it("un nouvel import ne reprend pas le numéro d'une image supprimée qui pourrait revenir", async () => {
    const d = await file("item", "#aaaa00");
    store.removeAsset(W, "item", d);
    const e = await file("item", "#00aaaa");
    expect(e).not.toBe(d);
  });
});
