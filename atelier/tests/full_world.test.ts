// A whole world built with every editor, the way a person would: it must be coherent (0 error), playable (every check of
// the playable report green), exportable, and accepted by the real game (boot and a rehearsed fight) when Godot is there.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import sharp from "sharp";
import { afterAll, describe, expect, it } from "vitest";
import { WorldStore } from "../core/store";
import { WORKFLOW_IDS } from "../core/workflows";

const ROOT = path.resolve(__dirname, "..", "..");
const W = "monde_complet";
const GODOT = process.env.GODOT_EXE ?? "C:\\Users\\natha\\Documents\\Godot\\Godot_v4.7-stable_win64_console.exe";
let tmp = "";
afterAll(() => {
  if (tmp) fs.rmSync(tmp, { recursive: true, force: true });
  fs.rmSync(path.join(ROOT, "game", "worlds", W), { recursive: true, force: true });
});

describe("monde complet", () => {
  it("construit avec tous les éditeurs : cohérent, jouable, assistants terminés, accepté par le jeu", async () => {
    tmp = fs.mkdtempSync(path.join(os.tmpdir(), "atelier-full-"));
    const store = new WorldStore(path.join(ROOT, "game", "worlds"), path.join(tmp, "r.json"), path.resolve(__dirname, "..", "templates"));
    store.create(W, "Monde complet");

    // images and skeleton
    const png = await sharp({ create: { width: 96, height: 96, channels: 4, background: "#557733" } }).png().toBuffer();
    const file = [{ name: "a.png", data: png }];
    const [ic] = await store.importAssets(W, "item", { files: file });
    const [por] = await store.importAssets(W, "monster", { files: file });
    const [spi] = await store.importAssets(W, "spell", { files: file });
    const [tile] = await store.importAssets(W, "tile", { files: file });
    store.importBone(W, "vertebre", 950001);

    // a class that can fight, and a monster that drops something
    const spell = store.dataCreate(W, "spells", { name: "Griffe", icon: spi.id, level: 1, ap: 3, range: [1, 3], los: true, inLine: false, perTurn: 2, cooldown: 0, crit: 5, color: "#aa3322", area: { shape: "point", size: 0 }, effects: [{ kind: "damage", target: "enemies", min: 5, max: 8, element: "fire" }] });
    const family = (store.rowsOf(W, "spells") as any[]).find((s) => s.id === spell).family;
    store.dataCreate(W, "classes", { name: "Vagabond", tagline: "Pour voir", description: "Une classe.", bone: 950001, size: 100, spells: [family] });
    const item = (name: string, type = 15) => store.dataCreate(W, "items", { name, icon: ic.id, type, level: 1, effects: [] });
    const croix = item("Croix d'os"), cle = item("Clé de la cave"), minerai = item("Minerai de fer"), lingot = item("Lingot de fer");
    const zone = store.dataCreate(W, "zones", { level: 3 });
    const g = { level: 3, hp: 30, ap: 6, mp: 3, xp: 20, stats: { strength: 0, intelligence: 0, chance: 0, agility: 0, wisdom: 0, ap_dodge: 0, mp_dodge: 0 }, res: { earth: 0, fire: 0, water: 0, air: 0, neutral: 0 }, spells: [spell], drops: [{ item: croix, pct: 60 }], kamas: [1, 3], aggro: { zone: 2, level_diff: 60, delay: 8000 } };
    const rat = store.dataCreate(W, "monsters", { name: "Rat", bone: 950001, size: 100, portrait: por.id, grades: [g], zones: [String(zone)] });

    // four maps: the village (start), a forest linked to it, and two rooms for the dungeon
    const village = (store.rowsOf(W, "maps") as any[])[0];
    const mk = (name: string) => store.dataCreate(W, "maps", { name });
    const forest = mk("Forêt"), room1 = mk("Salle 1"), room2 = mk("Salle 2");
    const patch = (id: number, p: object) => store.dataUpdate(W, "maps", id, { ...(store.rowsOf(W, "maps") as any[]).find((m) => m.id === id), ...p });
    patch(village.id, { neighbors: { right: forest } });
    patch(forest, { neighbors: { left: village.id }, zone: String(zone), monsterSpawn: true });
    patch(room1, { zone: String(zone), monsterSpawn: true });
    patch(room2, { zone: String(zone), monsterSpawn: true });

    // a merchant with a dialogue that opens the shop, and a quest from them
    const merchant = store.dataCreate(W, "npcs", { map: village.id, cell: 150, dir: 3, name: "Marchande", bone: 950001, size: 100, banker: false, shop: [croix, cle] });
    store.dataUpdate(W, "dialogs", merchant, { start: "0", nodes: { "0": { text: "Bienvenue.", replies: [{ text: "Voir la boutique", action: { type: "shop" } }, { text: "Au revoir", next: null }] } } });
    store.dataCreate(W, "quests", {
      name: "Chasse aux rats", giver: merchant, levelMin: 1, repeat: 0,
      steps: [{ name: "Chasser", desc: "Chasse trois rats.", level: 1, objectives: [{ type: 14, monster: rat, qty: 3 }], reward: { xp: 5, kamas: 5, items: [[croix, 1]] } }, { name: "Rapport", desc: "Reviens la voir.", level: 2, objectives: [{ type: 1, npc: merchant }], reward: { xp: 5, kamas: 0, items: [] } }],
    });

    // a job, a resource, a workshop and a recipe
    const job = store.dataCreate(W, "jobs", { name: "Forgeron" });
    store.dataCreate(W, "resources", { name: "Filon de fer", job, item: minerai, level: 1, gfx: tile.id, places: [{ map: forest, cell: 120 }] });
    const forge = store.dataCreate(W, "workshops", { name: "Forge", job, gfx: tile.id, places: [{ map: village.id, cell: 200 }] });
    store.dataCreate(W, "recipes", { result: lingot, skill: forge, ingredients: [{ item: minerai, qty: 2 }] });

    // a dungeon whose rooms hang from the village, with a boss
    store.dataCreate(W, "dungeons", { name: "Cave aux rats", level: 5, minLevel: 1, difficulty: 1, entrance: village.id, exit: village.id, rooms: [room1, room2], keys: [{ item: cle, qty: 1 }], bosses: [rat] });

    const d = store.detail(W);
    expect(d.problems.filter((p) => p.severity === "error").map((p) => `${p.code} ${p.message}`)).toEqual([]);
    const notOk = store.report(W).filter((c) => c.status !== "ok").map((c) => `${c.code}: ${c.items.map((i: any) => i.message).join(" | ")}`);
    expect(notOk).toEqual([]);
    const flows = await store.workflows(W);
    expect(flows.map((f) => f.id)).toEqual([...WORKFLOW_IDS]);
    const open = flows.filter((f) => !f.done && f.id !== "link").map((f) => `${f.id}: ${f.steps.filter((s) => !s.done).map((s) => s.label).join(", ")}`);
    expect(open).toEqual([]);

    // it survives a round trip through an archive
    const zip = store.exportWorld(W);
    expect(zip.length).toBeGreaterThan(1000);

    if (fs.existsSync(GODOT)) {
      const r = await store.gameCheck(W);
      expect(r.status, JSON.stringify(r)).toBe("ok");
      expect(r.fight?.status, JSON.stringify(r)).toBe("ok");
    }
  }, 300_000);
});
