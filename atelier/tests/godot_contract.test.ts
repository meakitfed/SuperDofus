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
const COPY = "atelier_contract_copy";
const COPY_SRC = "atelier_contract_src";
const DOFUS = "atelier_contract_dofus";
const DOFUS_MAP = "atelier_contract_dmap";
const REAL_MAP = 100139008;
const DOFUS_CONTENT = path.join(ROOT, "game", "content", "Content");
afterAll(() => {
  fs.rmSync(DIR, { recursive: true, force: true });
  fs.rmSync(path.join(ROOT, "game", "worlds", NEW), { recursive: true, force: true });
  fs.rmSync(path.join(ROOT, "game", "worlds", EDITED), { recursive: true, force: true });
  fs.rmSync(path.join(ROOT, "game", "worlds", COPY), { recursive: true, force: true });
  fs.rmSync(path.join(ROOT, "game", "worlds", COPY_SRC), { recursive: true, force: true });
  fs.rmSync(path.join(ROOT, "game", "worlds", DOFUS), { recursive: true, force: true });
  fs.rmSync(path.join(ROOT, "game", "worlds", DOFUS_MAP), { recursive: true, force: true });
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
  it("une copie de monde (ids décalés) démarre dans la simulation", async () => {
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "atelier-contract-"));
    try {
      const store = new WorldStore(path.join(ROOT, "game", "worlds"), path.join(tmp, "r.json"), path.resolve(__dirname, "..", "templates"));
      store.create(COPY_SRC, "Monde édité");
      const png = await sharp({ create: { width: 96, height: 96, channels: 4, background: "#884422" } }).png().toBuffer();
      const [item] = await store.importAssets(COPY_SRC, "item", { files: [{ name: "i.png", data: png }] });
      store.dataCreate(COPY_SRC, "items", { name: "Dent", icon: item.id, type: 9, level: 1, effects: [[125, 5, 0, 0]] });
      store.clone(COPY_SRC, COPY, "Monde copie");
      expect(store.detail(COPY).problems).toEqual(store.detail(COPY_SRC).problems);
      const r = spawnSync(GODOT, ["--headless", "--path", path.join(ROOT, "game"), "-s", "res://tools/sim_cli.gd", "--", `--world=${COPY}`, "--seconds=2"], { encoding: "utf-8", timeout: 120_000 });
      const out = r.stdout ?? "";
      expect(out, r.stderr).toContain(`"id":"${COPY}"`);
      expect(out).toContain('"t":"map_enter"');
      expect(out).not.toMatch(/SCRIPT ERROR|Parse Error/);
    } finally {
      fs.rmSync(tmp, { recursive: true, force: true });
    }
  }, 180_000);
  it.skipIf(!fs.existsSync(path.join(DOFUS_CONTENT, "Characters", "Bones", "1000")))("un monde avec un squelette et des icônes pris dans le jeu Dofus démarre dans la simulation", async () => {
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "atelier-contract-"));
    try {
      const store = new WorldStore(path.join(ROOT, "game", "worlds"), path.join(tmp, "r.json"), path.resolve(__dirname, "..", "templates"));
      store.create(DOFUS, "Monde Dofus");
      const [ic] = await store.importFromLibrary(DOFUS, "item", [Number(fs.readdirSync(path.join(DOFUS_CONTENT, "Picto", "Items"))[0].replace(/\..*/, ""))]);
      const [spi] = await store.importFromLibrary(DOFUS, "spell", [Number(fs.readdirSync(path.join(DOFUS_CONTENT, "Picto", "Spells"))[0].replace(/\..*/, ""))]);
      const [por] = await store.importFromLibrary(DOFUS, "monster", [Number(fs.readdirSync(path.join(DOFUS_CONTENT, "Picto", "Monsters"))[0].replace(/\..*/, ""))]);
      store.importBone(DOFUS, "dofus", 1000);
      const spell = store.dataCreate(DOFUS, "spells", { name: "Coup", icon: spi.id, level: 1, ap: 3, range: [1, 3], los: true, inLine: false, perTurn: 2, cooldown: 0, crit: 5, color: "#aa3322", area: { shape: "point", size: 0 }, effects: [{ kind: "damage", target: "enemies", min: 5, max: 8, element: "fire" }] });
      const fam = (store.rowsOf(DOFUS, "spells") as any[]).find((s) => s.id === spell).family;
      store.dataCreate(DOFUS, "classes", { name: "Test", tagline: "Pour voir", description: "Une classe.", bone: 1000, size: 100, spells: [fam] });
      const zone = store.dataCreate(DOFUS, "zones", { level: 1 });
      const it2 = store.dataCreate(DOFUS, "items", { name: "Dent", icon: ic.id!, type: 9, level: 1, effects: [[125, 5, 0, 0]] });
      const g = { level: 1, hp: 20, ap: 6, mp: 3, xp: 10, stats: { strength: 0, intelligence: 0, chance: 0, agility: 0, wisdom: 0, ap_dodge: 0, mp_dodge: 0 }, res: { earth: 0, fire: 0, water: 0, air: 0, neutral: 0 }, spells: [spell], drops: [{ item: it2, pct: 50 }], kamas: [1, 3], aggro: { zone: 2, level_diff: 60, delay: 8000 } };
      store.dataCreate(DOFUS, "monsters", { name: "Rat", bone: 1000, size: 100, portrait: por.id, grades: [g], zones: [String(zone)] });
      expect(store.detail(DOFUS).problems.filter((p) => p.severity === "error")).toEqual([]);
      const r = spawnSync(GODOT, ["--headless", "--path", path.join(ROOT, "game"), "-s", "res://tools/sim_cli.gd", "--", `--world=${DOFUS}`, "--seconds=2"], { encoding: "utf-8", timeout: 120_000 });
      const out = r.stdout ?? "";
      expect(out, r.stderr).toContain(`"id":"${DOFUS}"`);
      expect(out).toContain('"t":"map_enter"');
      expect(out).not.toMatch(/SCRIPT ERROR|Parse Error/);
    } finally {
      fs.rmSync(tmp, { recursive: true, force: true });
    }
  }, 180_000);
  it.skipIf(!fs.existsSync(path.join(DOFUS_CONTENT, "Maps", `${REAL_MAP}.json`)) || !fs.existsSync(path.join(ROOT, "game", "worlds", "dofus", "maps", `${REAL_MAP}.json`)))("un monde dont la map de départ est une vraie map du jeu Dofus démarre dans la simulation", () => {
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "atelier-contract-"));
    try {
      const store = new WorldStore(path.join(ROOT, "game", "worlds"), path.join(tmp, "r.json"), path.resolve(__dirname, "..", "templates"));
      store.create(DOFUS_MAP, "Monde map Dofus");
      const made = store.importDofusMap(DOFUS_MAP, "Plaine du jeu", REAL_MAP);
      const row = (store.rowsOf(DOFUS_MAP, "maps") as any[]).find((m) => m.id === made.id);
      store.dataUpdate(DOFUS_MAP, "maps", made.id, { start: row.phoenix });
      const errors = store.detail(DOFUS_MAP).problems.filter((p) => p.severity === "error");
      expect(errors).toEqual([]);
      const r = spawnSync(GODOT, ["--headless", "--path", path.join(ROOT, "game"), "-s", "res://tools/sim_cli.gd", "--", `--world=${DOFUS_MAP}`, "--seconds=2"], { encoding: "utf-8", timeout: 120_000 });
      const out = r.stdout ?? "";
      expect(out, r.stderr).toContain(`"id":"${DOFUS_MAP}"`);
      expect(out).toContain('"t":"map_enter"');
      expect(out).toContain(String(made.id));
      expect(out).not.toMatch(/SCRIPT ERROR|Parse Error/);
    } finally {
      fs.rmSync(tmp, { recursive: true, force: true });
    }
  }, 180_000);
});
