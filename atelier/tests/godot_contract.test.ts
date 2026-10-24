// Contract with the game: a world that went through the atelier (load -> save) must boot in the real sim.
// Skipped when the Godot executable is not there (set GODOT_EXE to override the default location).
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { afterAll, describe, expect, it } from "vitest";
import { loadWorld, saveWorld } from "../core/io";
import { validateDir } from "../core/validate";

const ROOT = path.resolve(__dirname, "..", "..");
const GODOT = process.env.GODOT_EXE ?? "C:\\Users\\natha\\Documents\\Godot\\Godot_v4.7-stable_win64_console.exe";
const ID = "atelier_contract";
const DIR = path.join(ROOT, "game", "worlds", ID); // game/worlds/* is git-ignored; removed after the test

afterAll(() => fs.rmSync(DIR, { recursive: true, force: true }));

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
});
