// Contract with the game: a world that went through the atelier (load -> save) must boot in the real sim.
// Skipped when the Godot executable is not there (set GODOT_EXE to override the default location).
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
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
afterAll(() => {
  fs.rmSync(DIR, { recursive: true, force: true });
  fs.rmSync(path.join(ROOT, "game", "worlds", NEW), { recursive: true, force: true });
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
});
