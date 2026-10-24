// "Vérifier avec le jeu": the judgement of the game output, the missing-Godot case, and one real boot.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterAll, describe, expect, it } from "vitest";
import { DEFAULT_GODOT, judgeGameOutput, runGameCheck } from "../core/gamecheck";
import { WorldStore } from "../core/store";

const ROOT = path.resolve(__dirname, "..", "..");
const GODOT = process.env.GODOT_EXE ?? DEFAULT_GODOT;
const ID = "atelier_gamecheck";
const GOOD = `{"t":"welcome","world":{"id":"${ID}"}}\n{"t":"map_enter"}\n`;

afterAll(() => fs.rmSync(path.join(ROOT, "game", "worlds", ID), { recursive: true, force: true }));

describe("jugement de la sortie du jeu", () => {
  it("accepte un monde qui accueille puis fait entrer sur une map", () => {
    expect(judgeGameOutput(ID, GOOD, "", false).status).toBe("ok");
  });
  it("refuse une erreur de script, un monde inconnu, une absence de map et un dépassement de temps", () => {
    expect(judgeGameOutput(ID, GOOD + "SCRIPT ERROR: boom\n", "", false)).toMatchObject({ status: "failed", lines: ["SCRIPT ERROR: boom"] });
    expect(judgeGameOutput(ID, '{"t":"welcome","world":{"id":"autre"}}\n{"t":"map_enter"}', "", false).status).toBe("failed");
    expect(judgeGameOutput(ID, `{"t":"welcome","world":{"id":"${ID}"}}`, "", false).summary).toMatch(/aucune map/);
    expect(judgeGameOutput(ID, GOOD, "", true).summary).toMatch(/temps imparti/);
  });
});

describe("lancement", () => {
  it("sans Godot : indisponible, jamais une fausse réussite", async () => {
    const r = await runGameCheck(path.join(ROOT, "game"), ID, path.join(os.tmpdir(), "pas-de-godot.exe"));
    expect(r.status).toBe("unavailable");
  });
  it.skipIf(!fs.existsSync(GODOT))("un monde neuf passe, un monde inconnu est refusé", async () => {
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "atelier-gc-"));
    try {
      const store = new WorldStore(path.join(ROOT, "game", "worlds"), path.join(tmp, "r.json"), path.resolve(__dirname, "..", "templates"));
      store.create(ID, "Vérif jeu");
      const ok = await store.gameCheck(ID);
      expect(ok.status, JSON.stringify(ok)).toBe("ok");
      await expect(store.gameCheck("n_existe_pas")).rejects.toThrow();
    } finally {
      fs.rmSync(tmp, { recursive: true, force: true });
    }
  }, 180_000);
});
