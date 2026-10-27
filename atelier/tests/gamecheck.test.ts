// "Vérifier avec le jeu": the judgement of the game output, the missing-Godot case, and one real boot.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import sharp from "sharp";
import { afterAll, describe, expect, it } from "vitest";
import { DEFAULT_GODOT, judgeFightOutput, judgeGameOutput, runGameCheck } from "../core/gamecheck";
import { WorldStore } from "../core/store";

const ROOT = path.resolve(__dirname, "..", "..");
const GODOT = process.env.GODOT_EXE ?? DEFAULT_GODOT;
const ID = "atelier_gamecheck";
const FIGHT = "atelier_gamecheck_fight";
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

describe("jugement du combat d'essai", () => {
  const START = '{"ev":{"fight":5.0,"t":"fight_start"}}\n';
  const END = '{"ev":{"duration":23200.0,"result":"lose","t":"fight_end"}}\n';
  it("accepte un combat qui démarre et se termine, quelle que soit l'issue", () => {
    expect(judgeFightOutput(START + END, "", false)).toMatchObject({ status: "ok", result: "lose" });
    expect(judgeFightOutput(START + END.replace("lose", "win"), "", false).summary).toMatch(/victoire/);
  });
  it("refuse un combat qui ne démarre pas, ne finit pas, plante ou dépasse le temps", () => {
    expect(judgeFightOutput('{"ev":{"code":"no_target","t":"error"}}\n', "", false).summary).toMatch(/Aucun groupe/);
    expect(judgeFightOutput("", "", false).summary).toMatch(/pas démarré/);
    expect(judgeFightOutput(START, "", false).summary).toMatch(/jamais terminé/);
    expect(judgeFightOutput(START + END + "SCRIPT ERROR: boom\n", "", false)).toMatchObject({ status: "failed", lines: ["SCRIPT ERROR: boom"] });
    expect(judgeFightOutput(START, "", true).summary).toMatch(/temps imparti/);
  });
  it("ignore le bruit que le moteur écrit toujours à la sortie", () => {
    const noise = "WARNING: 83 ObjectDB instances were leaked at exit (run with `--verbose` for details).\nERROR: 41 resources still in use at exit (run with --verbose for details).";
    expect(judgeFightOutput(START + END, noise, false).status).toBe("ok");
    expect(judgeGameOutput(ID, GOOD, noise, false)).toMatchObject({ status: "ok", lines: [] });
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
      expect(ok.fight?.status).toBe("skipped"); // no monsters in a new world
      await expect(store.gameCheck("n_existe_pas")).rejects.toThrow();
    } finally {
      fs.rmSync(tmp, { recursive: true, force: true });
    }
  }, 180_000);
  it.skipIf(!fs.existsSync(GODOT))("un monde avec une classe, un sort et un monstre joue un combat complet", async () => {
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "atelier-gc-"));
    try {
      const store = new WorldStore(path.join(ROOT, "game", "worlds"), path.join(tmp, "r.json"), path.resolve(__dirname, "..", "templates"));
      store.create(FIGHT, "Combat d'essai");
      const png = await sharp({ create: { width: 96, height: 96, channels: 4, background: "#884422" } }).png().toBuffer();
      const file = [{ name: "i.png", data: png }];
      const [icon] = await store.importAssets(FIGHT, "spell", { files: file });
      const [portrait] = await store.importAssets(FIGHT, "monster", { files: file });
      store.importBone(FIGHT, "vertebre", 950001);
      const spell = store.dataCreate(FIGHT, "spells", {
        name: "Coup", icon: icon.id, level: 1, ap: 3, range: [1, 3], los: true, inLine: false, perTurn: 2, cooldown: 0, crit: 5, color: "#aa3322",
        area: { shape: "point", size: 0 }, effects: [{ kind: "damage", target: "enemies", min: 5, max: 8, element: "fire" }],
      });
      const fam = (store.rowsOf(FIGHT, "spells") as any[]).find((s) => s.id === spell).family;
      store.dataCreate(FIGHT, "classes", { name: "Test", tagline: "Pour voir", description: "Une classe.", bone: 950001, size: 100, spells: [fam] });
      const zone = store.dataCreate(FIGHT, "zones", { level: 1 });
      const g = { level: 1, hp: 20, ap: 6, mp: 3, xp: 10, stats: { strength: 0, intelligence: 0, chance: 0, agility: 0, wisdom: 0, ap_dodge: 0, mp_dodge: 0 }, res: { earth: 0, fire: 0, water: 0, air: 0, neutral: 0 }, spells: [spell], drops: [], kamas: [1, 3], aggro: { zone: 2, level_diff: 60, delay: 8000 } };
      store.dataCreate(FIGHT, "monsters", { name: "Rat", bone: 950001, size: 100, portrait: portrait.id, grades: [g], zones: [String(zone)] });
      expect(store.fightMap(FIGHT)).toBeUndefined(); // the zone exists but no map uses it yet
      const m0 = (store.rowsOf(FIGHT, "maps") as any[])[0];
      store.dataUpdate(FIGHT, "maps", m0.id, { ...m0, zone: String(zone), monsterSpawn: true });
      expect(store.fightMap(FIGHT)).toBe(m0.id);
      const r = await store.gameCheck(FIGHT);
      expect(r.status, JSON.stringify(r)).toBe("ok");
      expect(r.fight, JSON.stringify(r)).toMatchObject({ status: "ok" });
      expect(["win", "lose"]).toContain(r.fight?.result);
    } finally {
      fs.rmSync(tmp, { recursive: true, force: true });
      fs.rmSync(path.join(ROOT, "game", "worlds", FIGHT), { recursive: true, force: true });
    }
  }, 300_000);
});
