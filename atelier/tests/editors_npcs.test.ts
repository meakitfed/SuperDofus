// NPC, shop, bank and dialogue editors, through a real store on a temp folder.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import sharp from "sharp";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { AtelierError } from "../core/errors";
import type { DialogInput, NpcInput, NpcRow } from "../core/editors_npcs";
import { WorldStore } from "../core/store";

let tmp: string, store: WorldStore, map: number, item: number;
const W = "monde_pnj";
const errors = () => store.detail(W).problems.filter((p) => p.severity === "error").map((p) => `${p.code} ${p.message}`);
const npcs = () => store.rowsOf(W, "npcs") as NpcRow[];
const refuses = (fn: () => void, status: number, re: RegExp) => {
  try { fn(); } catch (e) { expect(e).toBeInstanceOf(AtelierError); expect((e as AtelierError).status).toBe(status); expect((e as Error).message).toMatch(re); return; }
  throw new Error("aucune erreur levée");
};
const base = (): NpcInput => ({ map, cell: 150, dir: 3, name: "Marchande", bone: 950001, size: 100, banker: false, shop: null });

beforeAll(async () => {
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), "atelier-npcs-"));
  fs.mkdirSync(path.join(tmp, "worlds"));
  store = new WorldStore(path.join(tmp, "worlds"), path.join(tmp, "r.json"), path.resolve(__dirname, "..", "templates"));
  store.create(W, "PNJ");
  map = (store.rowsOf(W, "maps") as { id: number }[])[0].id;
  const png = await sharp({ create: { width: 96, height: 96, channels: 4, background: "#335577" } }).png().toBuffer();
  const [it] = await store.importAssets(W, "item", { files: [{ name: "a.png", data: png }] });
  item = store.dataCreate(W, "items", { name: "Pain", icon: it.id, type: 12, level: 1, effects: [] });
  // the skeleton normally comes from another world (importBone); here it is copied by hand
  fs.cpSync(path.resolve(__dirname, "..", "..", "game", "worlds", "vertebre", "Content", "Characters", "Bones", "950001"), path.join(tmp, "worlds", W, "Content", "Characters", "Bones", "950001"), { recursive: true });
});
afterAll(() => fs.rmSync(tmp, { recursive: true, force: true }));

describe("npcs", () => {
  it("places an NPC: in range, named, on a blocked cell, world coherent", () => {
    const id = store.dataCreate(W, "npcs", base());
    const n = npcs().find((x) => x.id === id)!;
    expect(id).toBeGreaterThanOrEqual(store.registry()[W].ranges.npc[0]);
    expect(n).toMatchObject({ map, cell: 150, name: "Marchande", bone: 950001, hasDialog: false });
    expect((store.rowsOf(W, "maps") as any[])[0].blocked).toContain(150);
    expect(errors()).toEqual([]);
  });
  it("refuses an occupied cell, a door cell, the start cell, bad input", () => {
    refuses(() => store.dataCreate(W, "npcs", base()), 409, /occupée/);
    refuses(() => store.dataCreate(W, "npcs", { ...base(), cell: 300 }), 409, /départ|renaissance/);
    refuses(() => store.dataCreate(W, "npcs", { ...base(), cell: 999 }), 400, /grille/);
    refuses(() => store.dataCreate(W, "npcs", { ...base(), cell: 151, name: " " }), 400, /nom/);
    refuses(() => store.dataCreate(W, "npcs", { ...base(), cell: 151, map: 4242 }), 400, /inconnue/);
    refuses(() => store.dataCreate(W, "npcs", { ...base(), cell: 151, shop: [424242] }), 400, /objet 424242/);
  });
  it("gives an NPC a shop and a bank; a dialogue may only offer what the NPC does", () => {
    const id = npcs()[0].id;
    const dlg = (action: any): DialogInput => ({ start: "0", nodes: { "0": { text: "Bonjour.", replies: [{ text: "Voir", action }, { text: "Au revoir" }] } } });
    refuses(() => store.dataUpdate(W, "dialogs", id, dlg({ type: "shop" })), 400, /boutique/);
    store.dataUpdate(W, "npcs", id, { ...base(), shop: [item], banker: true });
    store.dataUpdate(W, "dialogs", id, dlg({ type: "shop" }));
    store.dataUpdate(W, "dialogs", id, dlg({ type: "bank" }));
    store.dataUpdate(W, "dialogs", id, dlg({ type: "shop" }));
    refuses(() => store.dataUpdate(W, "npcs", id, { ...base(), shop: null }), 409, /boutique/);
    expect(errors()).toEqual([]);
  });
  it("validates dialogue nodes, targets, criteria and actions; numbers replies", () => {
    const id = npcs()[0].id;
    const ok: DialogInput = {
      start: "0", nodes: {
        "0": { text: "Salut.", replies: [{ text: "Parle", next: "suite", criteria: `PO=${item}` }, { text: "Un cadeau", action: { type: "give_item", item, qty: 2 } }, { text: "Fin" }] },
        suite: { text: "Voilà.", replies: [{ text: "Retour", next: "0" }] },
      },
    };
    store.dataUpdate(W, "dialogs", id, ok);
    const d: any = store.dialogOf(W, id);
    expect(d.nodes["0"].replies.map((r: any) => r.id)).toEqual([1, 2, 3]);
    expect(errors()).toEqual([]);
    const bad = (mut: (d: DialogInput) => void, re: RegExp) => { const c = structuredClone(ok); mut(c); refuses(() => store.dataUpdate(W, "dialogs", id, c), 400, re); };
    bad((c) => { c.start = "nope"; }, /départ/);
    bad((c) => { c.nodes["0"].replies[0].next = "ghost"; }, /ghost/);
    bad((c) => { c.nodes["0"].replies[0].criteria = "Qf=999"; }, /quête 999/);
    bad((c) => { c.nodes["0"].replies[0].criteria = "n'importe quoi"; }, /invalide/);
    bad((c) => { c.nodes["0"].replies[1].action = { type: "give_item", item: 1, qty: 1 }; }, /objet 1 inconnu/);
    bad((c) => { c.nodes["0"].replies[1].action = { type: "teleport", map: 4242, cell: 1 }; }, /map 4242/);
    bad((c) => { c.nodes["0"].replies[0].text = ""; }, /réponse/);
    bad((c) => { c.nodes["Bad Key"] = { text: "x", replies: [] }; }, /minuscules/);
  });
  it("moves an NPC, then removes it with its dialogue, shop and bank entry", () => {
    const id = npcs()[0].id;
    store.dataUpdate(W, "npcs", id, { ...base(), cell: 160, shop: [item], banker: true });
    expect(npcs()[0].cell).toBe(160);
    store.dataUpdate(W, "dialogs", id, { start: "0", nodes: { "0": { text: "Salut.", replies: [] } } });
    store.dataDelete(W, "npcs", id);
    expect(npcs()).toHaveLength(0);
    expect(store.dialogOf(W, id)).toBeNull();
    const shops = JSON.parse(fs.readFileSync(path.join(tmp, "worlds", W, "shops.json"), "utf-8"));
    expect(shops.shops[String(id)]).toBeUndefined();
    expect(errors()).toEqual([]);
  });
  it("keeps NPC cells blocked when a map is edited", () => {
    const id = store.dataCreate(W, "npcs", { ...base(), cell: 170 });
    const m = (store.rowsOf(W, "maps") as any[])[0];
    refuses(() => store.dataUpdate(W, "maps", map, { ...m, blocked: m.blocked.filter((c: number) => c !== 170) }), 400, /PNJ en 170/);
    store.dataDelete(W, "npcs", id);
  });
});
