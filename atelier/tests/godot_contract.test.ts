// Contract with the game: a world that went through the atelier (load -> save) must boot in the real sim.
// Skipped when the Godot executable is not there (set GODOT_EXE to override the default location).
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import sharp from "sharp";
import { afterAll, describe, expect, it } from "vitest";
import os from "node:os";
import { loadWorld, saveWorld } from "../core/io";
import { WorldStore } from "../core/store";
import { validateDir } from "../core/validate";

const ROOT = path.resolve(__dirname, "..", "..");
const GODOT = process.env.GODOT_EXE ?? "C:\\Users\\natha\\Documents\\Godot\\Godot_v4.7-stable_win64_console.exe";
const ID = "atelier_contract";
const DIR = path.join(ROOT, "game", "worlds", ID); // game/worlds/* is git-ignored; removed after the test

const NEW = "atelier_contract_new";
const EDITED = "atelier_contract_edit";
afterAll(() => {
  fs.rmSync(DIR, { recursive: true, force: true });
  fs.rmSync(path.join(ROOT, "game", "worlds", NEW), { recursive: true, force: true });
  fs.rmSync(path.join(ROOT, "game", "worlds", EDITED), { recursive: true, force: true });
});

describe.skipIf(!fs.existsSync(GODOT))("contrat avec le jeu", () => {
  it("un monde relu et réécrit par l'atelier démarre dans la simulation", () => {
    fs.rmSync(DIR, { recursive: true, force: true });
    fs.cpSync(path.join(ROOT, "game", "worlds", "vertebre"), DIR, { recursive: true });
    const { world } = loadWorld(DIR);
    world!.files.world.id = ID;
    world!.files.world.name = "Contrat atelier";
    saveWorld(world!);
    expect(validateDir(DIR).filter((p) => p.severity === "error")).toEqual([]);

    const r = spawnSync(GODOT, ["--headless", "--path", path.join(ROOT, "game"), "-s", "res://tools/sim_cli.gd", "--", `--world=${ID}`, "--seconds=2"], {
      encoding: "utf-8",
      timeout: 120_000,
    });
    const out = r.stdout ?? "";
    expect(out, r.stderr).toContain(`"id":"${ID}"`); // welcome event names the world
    expect(out).toContain('"t":"map_enter"');
    expect(out).not.toMatch(/SCRIPT ERROR|Parse Error/);
  });

  it("un monde neuf créé par l'atelier démarre dans la simulation", () => {
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "atelier-contract-"));
    try {
      const store = new WorldStore(path.join(ROOT, "game", "worlds"), path.join(tmp, "r.json"), path.resolve(__dirname, "..", "templates"));
      store.create(NEW, "Monde neuf");
      expect(store.detail(NEW).problems).toEqual([]);
      const r = spawnSync(GODOT, ["--headless", "--path", path.join(ROOT, "game"), "-s", "res://tools/sim_cli.gd", "--", `--world=${NEW}`, "--seconds=2"], {
        encoding: "utf-8",
        timeout: 120_000,
      });
      const out = r.stdout ?? "";
      expect(out, r.stderr).toContain(`"id":"${NEW}"`);
      expect(out).toContain('"t":"map_enter"');
      expect(out).not.toMatch(/SCRIPT ERROR|Parse Error/);
    } finally {
      fs.rmSync(tmp, { recursive: true, force: true });
    }
  });

  it("un monde rempli avec les éditeurs (objet, sort, classe, monstre, zone) démarre dans la simulation", async () => {
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "atelier-contract-"));
    try {
      const store = new WorldStore(path.join(ROOT, "game", "worlds"), path.join(tmp, "r.json"), path.resolve(__dirname, "..", "templates"));
      store.create(EDITED, "Monde édité");
      const png = await sharp({ create: { width: 96, height: 96, channels: 4, background: "#884422" } }).png().toBuffer();
      const file = [{ name: "i.png", data: png }];
      const [item] = await store.importAssets(EDITED, "item", { files: file });
      const [icon] = await store.importAssets(EDITED, "spell", { files: file });
      const [portrait] = await store.importAssets(EDITED, "monster", { files: file });
      store.importBone(EDITED, "vertebre", 950001);
      const spell = store.dataCreate(EDITED, "spells", {
        name: "Coup", icon: icon.id, level: 1, ap: 3, range: [1, 3], los: true, inLine: false, perTurn: 2, cooldown: 0, crit: 5, color: "#aa3322",
        area: { shape: "point", size: 0 }, effects: [{ kind: "damage", target: "enemies", min: 5, max: 8, element: "fire" }],
      });
      const fam = (store.rowsOf(EDITED, "spells") as any[]).find((s) => s.id === spell).family;
      store.dataCreate(EDITED, "classes", { name: "Test", tagline: "Pour voir", description: "Une classe.", bone: 950001, size: 100, spells: [fam] });
      const zone = store.dataCreate(EDITED, "zones", { level: 1 });
      const it = store.dataCreate(EDITED, "items", { name: "Dent", icon: item.id, type: 9, level: 1, effects: [[125, 5, 0, 0]] });
      const g = { level: 1, hp: 20, ap: 6, mp: 3, xp: 10, stats: { strength: 0, intelligence: 0, chance: 0, agility: 0, wisdom: 0, ap_dodge: 0, mp_dodge: 0 }, res: { earth: 0, fire: 0, water: 0, air: 0, neutral: 0 }, spells: [spell], drops: [{ item: it, pct: 50 }], kamas: [1, 3], aggro: { zone: 2, level_diff: 60, delay: 8000 } };
      store.dataCreate(EDITED, "monsters", { name: "Rat", bone: 950001, size: 100, portrait: portrait.id, grades: [g], zones: [String(zone)] });
      expect(store.detail(EDITED).problems.filter((p) => p.severity === "error")).toEqual([]);
      const r = spawnSync(GODOT, ["--headless", "--path", path.join(ROOT, "game"), "-s", "res://tools/sim_cli.gd", "--", `--world=${EDITED}`, "--seconds=2"], { encoding: "utf-8", timeout: 120_000 });
      const out = r.stdout ?? "";
      expect(out, r.stderr).toContain(`"id":"${EDITED}"`);
      expect(out).toContain('"t":"map_enter"');
      expect(out).not.toMatch(/SCRIPT ERROR|Parse Error/);
    } finally {
      fs.rmSync(tmp, { recursive: true, force: true });
    }
  }, 180_000);
});
