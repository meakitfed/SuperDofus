// "Verify with the game": boots the world in the real headless simulation (the same entry point as the contract test)
// and reports whether it loads, then, when a map has monsters, plays one fight with the game's own scripted player.
// The atelier never links Godot code: it only runs the executable and reads its output.
import { spawn } from "node:child_process";
import fs from "node:fs";
import path from "node:path";

/** The fight rehearsal: the game's scripted player attacks the first monster group of a map and plays until the fight ends. */
export interface FightProbe {
  status: "ok" | "failed" | "skipped";
  summary: string;
  lines: string[];
  /** How the rehearsed fight ended (the scripted player is level 1: losing is not an error). */
  result?: string;
}

export interface GameCheck {
  status: "ok" | "failed" | "unavailable";
  summary: string;
  /** Lines of the game output that explain a failure (errors and warnings only). */
  lines: string[];
  ms: number;
  fight?: FightProbe;
}

export const DEFAULT_GODOT = "C:\\Users\\natha\\Documents\\Godot\\Godot_v4.7-stable_win64_console.exe";
const BAD = /SCRIPT ERROR|Parse Error|^ERROR|^WARNING|failed|introuvable|invalid/i;
// the engine always prints these two at exit: they say nothing about the world
const NOISE = /ObjectDB instances were leaked|resources still in use at exit/;

const badLines = (stdout: string, stderr: string) => `${stdout}\n${stderr}`.split(/\r?\n/).filter((l) => BAD.test(l) && !l.startsWith("{") && !NOISE.test(l)).slice(0, 20);

/** Pure judgement of the game output, so it can be tested without Godot. */
export function judgeGameOutput(id: string, stdout: string, stderr: string, timedOut: boolean): Pick<GameCheck, "status" | "summary" | "lines"> {
  const lines = badLines(stdout, stderr);
  if (timedOut) return { status: "failed", summary: "Le jeu n'a pas fini de charger ce monde dans le temps imparti.", lines };
  if (/SCRIPT ERROR|Parse Error/.test(`${stdout}\n${stderr}`)) return { status: "failed", summary: "Le jeu a rencontré une erreur de script en chargeant ce monde.", lines };
  if (!stdout.includes(`"id":"${id}"`)) return { status: "failed", summary: "Le jeu n'a pas reconnu ce monde (pas d'accueil à son nom).", lines };
  if (!stdout.includes('"t":"map_enter"')) return { status: "failed", summary: "Le jeu a chargé le monde mais le personnage n'est entré sur aucune map.", lines };
  return { status: "ok", summary: "Le jeu charge ce monde et y fait entrer un personnage.", lines: [] };
}

/** Pure judgement of the fight rehearsal output. */
export function judgeFightOutput(stdout: string, stderr: string, timedOut: boolean): FightProbe {
  const lines = badLines(stdout, stderr);
  const all = `${stdout}\n${stderr}`;
  if (timedOut) return { status: "failed", summary: "Le combat d'essai n'a pas fini dans le temps imparti.", lines };
  if (/SCRIPT ERROR|Parse Error/.test(all)) return { status: "failed", summary: "Le jeu a rencontré une erreur de script pendant le combat d'essai.", lines };
  if (!stdout.includes('"t":"fight_start"')) {
    const none = /"code":"no_target"/.test(stdout);
    return { status: "failed", summary: none ? "Aucun groupe de monstres n'est apparu sur la map d'essai (vérifie la zone de monstres de la map)." : "Le combat d'essai n'a pas démarré.", lines };
  }
  const endLine = stdout.split(/\r?\n/).find((l) => l.includes('"t":"fight_end"'));
  if (!endLine) return { status: "failed", summary: "Le combat a démarré mais ne s'est jamais terminé.", lines };
  const result = /"result":"([a-z_]+)"/.exec(endLine)?.[1];
  return { status: "ok", summary: `Un combat complet se joue sur la map d'essai${result ? ` (issue : ${result === "win" ? "victoire" : result === "lose" ? "défaite" : result})` : ""}.`, lines: [], result };
}

interface Run { out: string; err: string; timedOut: boolean; failedToStart: boolean }

function runSim(godot: string, gameDir: string, args: string[], timeoutMs: number): Promise<Run> {
  return new Promise((resolve) => {
    const child = spawn(godot, ["--headless", "--path", gameDir, "-s", "res://tools/sim_cli.gd", "--", ...args], { cwd: path.dirname(gameDir) });
    let out = "", err = "", timedOut = false;
    const timer = setTimeout(() => { timedOut = true; child.kill(); }, timeoutMs);
    child.stdout.on("data", (d) => { out += d; });
    child.stderr.on("data", (d) => { err += d; });
    child.on("error", () => { clearTimeout(timer); resolve({ out, err, timedOut, failedToStart: true }); });
    child.on("close", () => { clearTimeout(timer); resolve({ out, err, timedOut, failedToStart: false }); });
  });
}

/**
 * `fightMap`: a map of the world where monsters appear. When given and the boot succeeded, one fight is rehearsed there.
 * Only maps numbered above 10000 can be targeted by the game's teleport command (every atelier world qualifies).
 */
export async function runGameCheck(gameDir: string, id: string, godot = process.env.GODOT_EXE ?? DEFAULT_GODOT, timeoutMs = 120_000, fightMap?: number): Promise<GameCheck> {
  const t0 = Date.now();
  if (!fs.existsSync(godot)) {
    return { status: "unavailable", summary: "Godot est introuvable sur cet ordinateur (variable GODOT_EXE pour indiquer où).", lines: [], ms: 0 };
  }
  const boot = await runSim(godot, gameDir, [`--world=${id}`, "--seconds=2"], timeoutMs);
  if (boot.failedToStart) return { status: "unavailable", summary: "Impossible de lancer Godot.", lines: [], ms: Date.now() - t0 };
  const res: GameCheck = { ...judgeGameOutput(id, boot.out, boot.err, boot.timedOut), ms: 0 };
  if (res.status === "ok") {
    if (fightMap === undefined) {
      res.fight = { status: "skipped", summary: "Pas d'essai de combat : aucune map n'a de monstres qui apparaissent.", lines: [] };
    } else {
      const f = await runSim(godot, gameDir, [`--world=${id}`, "--seconds=60", "--bot=fight", `--cmd=1000:tp:${fightMap}`, "--cmd=7000:fight_attack"], timeoutMs);
      res.fight = f.failedToStart ? { status: "failed", summary: "Impossible de lancer le combat d'essai.", lines: [] } : judgeFightOutput(f.out, f.err, f.timedOut);
      if (res.fight.status === "failed") { res.status = "failed"; res.summary = "Le monde se charge, mais le combat d'essai a échoué."; res.lines = res.fight.lines; }
    }
  }
  res.ms = Date.now() - t0;
  return res;
}
