// Image library: import (single files and ZIP), normalisation, deduplication, usage tracking, safe deletion.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { zipSync } from "fflate";
import sharp from "sharp";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { AtelierError, WorldStore } from "../core/store";

let tmp: string;
let store: WorldStore;
beforeEach(() => {
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), "atelier-assets-"));
  store = new WorldStore(tmp, path.join(tmp, "r.json"), path.resolve(__dirname, "..", "templates"));
  store.create("monde_a", "A");
});
afterEach(() => fs.rmSync(tmp, { recursive: true, force: true }));

const solid = (w: number, h: number, rgb: [number, number, number], fmt: "png" | "jpeg" | "webp" = "png") =>
  sharp({ create: { width: w, height: h, channels: 3, background: { r: rgb[0], g: rgb[1], b: rgb[2] } } })[fmt]().toBuffer();

const range = () => store.detail("monde_a").ranges.asset;

describe("import d'images", () => {
  it("redimensionne une icône en 96×96 PNG, l'enregistre sous un id de la tranche du monde", async () => {
    const [r] = await store.importAssets("monde_a", "item", { files: [{ name: "Épée rouillée.png", data: await solid(200, 100, [200, 30, 30]) }] });
    expect(r).toMatchObject({ status: "imported", name: "Épée rouillée" });
    expect(r.id).toBe(range()[0]);
    const file = path.join(tmp, "monde_a", "Content", "Picto", "Items", `${r.id}.png`);
    const meta = await sharp(file).metadata();
    expect([meta.format, meta.width, meta.height, meta.hasAlpha]).toEqual(["png", 96, 96, true]);
    const list = await store.assets("monde_a", "item");
    expect(list).toEqual([expect.objectContaining({ id: r.id, name: "Épée rouillée", width: 96, height: 96, usedBy: [] })]);
  });

  it("accepte JPEG et WebP, garde la taille d'une tuile, et donne des ids consécutifs", async () => {
    const res = await store.importAssets("monde_a", "tile", {
      files: [{ name: "herbe.jpg", data: await solid(300, 150, [10, 160, 20], "jpeg") }, { name: "eau.webp", data: await solid(64, 64, [10, 20, 160], "webp") }],
    });
    expect(res.map((r) => r.status)).toEqual(["imported", "imported"]);
    expect(res[1].id).toBe(res[0].id! + 1);
    const list = await store.assets("monde_a", "tile");
    expect(list.map((a) => [a.width, a.height])).toEqual([[300, 150], [64, 64]]);
  });

  it("repère un doublon (même image) et ne le réimporte pas", async () => {
    const data = await solid(50, 50, [1, 2, 3]);
    const [a] = await store.importAssets("monde_a", "spell", { files: [{ name: "a.png", data }] });
    const [b] = await store.importAssets("monde_a", "spell", { files: [{ name: "copie.png", data }] });
    expect(b).toMatchObject({ status: "duplicate", id: a.id });
    expect(await store.assets("monde_a", "spell")).toHaveLength(1);
  });

  it("rejette ce qui n'est pas une image sans arrêter le reste du lot", async () => {
    const good = await solid(40, 40, [9, 9, 9]);
    const res = await store.importAssets("monde_a", "monster", {
      files: [
        { name: "notes.txt", data: Buffer.from("coucou") },
        { name: "faux.png", data: Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47]), Buffer.from("pas vraiment")]) },
        { name: "ok.png", data: good },
        { name: "gros.png", data: Buffer.alloc(9 * 1024 * 1024, 1) },
      ],
    });
    expect(res.map((r) => r.status)).toEqual(["rejected", "rejected", "imported", "rejected"]);
    expect(res[0].reason).toMatch(/image lisible/);
    expect(res[3].reason).toMatch(/trop gros/);
    expect(await store.assets("monde_a", "monster")).toHaveLength(1);
  });

  it("refuse une tuile démesurée", async () => {
    const huge = await sharp({ create: { width: 5000, height: 10, channels: 3, background: "#fff" } }).png().toBuffer();
    const [r] = await store.importAssets("monde_a", "tile", { files: [{ name: "large.png", data: huge }] });
    expect(r.status).toBe("rejected");
  });

  it("refuse une catégorie inconnue (aucun accès hors du dossier du monde)", async () => {
    await expect(store.importAssets("monde_a", "../../x", { files: [{ name: "a.png", data: await solid(8, 8, [0, 0, 0]) }] })).rejects.toThrow(AtelierError);
    expect(() => store.assetPath("monde_a", "item", 1)).toThrow(/introuvable/);
  });
});

describe("archives ZIP", () => {
  it("importe les images d'un ZIP et ignore dossiers, fichiers cachés et autres formats", async () => {
    const zip = zipSync({
      "icones/a.png": new Uint8Array(await solid(30, 30, [1, 1, 1])),
      "icones/sous/b.jpg": new Uint8Array(await solid(30, 30, [2, 2, 2], "jpeg")),
      "__MACOSX/icones/._a.png": new Uint8Array([1, 2, 3]),
      "leseci.txt": new Uint8Array([1]),
      ".cache.png": new Uint8Array([1]),
    });
    const res = await store.importAssets("monde_a", "item", { zip: Buffer.from(zip) });
    expect(res.filter((r) => r.status === "imported").map((r) => r.name).sort()).toEqual(["a", "b"]);
    expect(res.filter((r) => r.status === "rejected")).toHaveLength(3);
    expect(await store.assets("monde_a", "item")).toHaveLength(2);
  });

  it("refuse un ZIP corrompu ou une archive qui explose (trop d'images)", async () => {
    await expect(store.importAssets("monde_a", "item", { zip: Buffer.from("PK pas un zip") })).rejects.toThrow(/ZIP invalide/);
    const tiny = new Uint8Array(await solid(2, 2, [5, 5, 5]));
    const many: Record<string, Uint8Array> = {};
    for (let i = 0; i < 301; i++) many[`i${i}.png`] = tiny;
    await expect(store.importAssets("monde_a", "item", { zip: Buffer.from(zipSync(many)) })).rejects.toThrow(/plus de 300/);
    expect(await store.assets("monde_a", "item")).toHaveLength(0);
  });
});

describe("usage et suppression", () => {
  it("indique qui utilise une image, refuse de la supprimer, puis la supprime une fois libre", async () => {
    const [r] = await store.importAssets("monde_a", "item", { files: [{ name: "x.png", data: await solid(20, 20, [7, 7, 7]) }] });
    store.edit("monde_a", "objet de test", (w) => {
      const ids = store.detail("monde_a").ranges;
      w.files.items.items.push({ id: ids.item[0], name_id: ids.text[0], icon: r.id!, type: 1, level: 1 } as any);
    });
    expect((await store.assets("monde_a", "item"))[0].usedBy).toEqual([{ kind: "item", id: store.detail("monde_a").ranges.item[0] }]);
    expect(() => store.removeAsset("monde_a", "item", r.id!)).toThrow(/utilisée par/);
    store.edit("monde_a", "retire l'objet", (w) => { w.files.items.items.length = 0; });
    store.removeAsset("monde_a", "item", r.id!);
    expect(await store.assets("monde_a", "item")).toEqual([]);
    expect(() => store.assetPath("monde_a", "item", r.id!)).toThrow(/introuvable/);
  });

  it("la règle W_ASSET_UNUSED signale une image que rien n'utilise", async () => {
    const [r] = await store.importAssets("monde_a", "item", { files: [{ name: "x.png", data: await solid(20, 20, [7, 7, 7]) }] });
    const p = store.detail("monde_a").problems;
    expect(p.map((x) => x.code)).toEqual(["W_ASSET_UNUSED"]);
    expect(p[0].ref).toEqual({ kind: "asset", id: `item/${r.id}` });
  });

  it("une image qui reste dans la bibliothèque après suppression de l'objet n'est pas une erreur, seulement un avertissement", async () => {
    await store.importAssets("monde_a", "spell", { files: [{ name: "s.png", data: await solid(20, 20, [3, 3, 3]) }] });
    expect(store.detail("monde_a").problems.every((p) => p.severity === "warning")).toBe(true);
  });
});
