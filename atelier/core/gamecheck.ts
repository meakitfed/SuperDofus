// "Verify with the game": boots the world in the real headless simulation (the same entry point as the contract test)
// and reports whether it loads. The atelier never links Godot code: it only runs the executable and reads its output.
import { spawn } from "node:child_process";
import fs from "node:fs";
import path from "node:path";

export interface GameCheck {
  status: "ok" | "failed" | "unavailable";
  summary: string;
  /** Lines of the game output that explain a failure (errors and warnings only). */
  lines: string[];
  ms: number;
}

export const DEFAULT_GODOT = "C:\\Users\\natha\\Documents\\Godot\\Godot_v4.7-stable_win64_console.exe";
const BAD = /SCRIPT ERROR|Parse Error|^ERROR|^WARNING|failed|introuvable|invalid/i;

/** Pure judgement of the game output, so it can be tested without Godot. */
export function judgeGameOutput(id: string, stdout: string, stderr: string, timedOut: boolean): Pick<GameCheck, "status" | "summary" | "lines"> {
  const lines = `${stdout}\n${stderr}`.split(/\r?\n/).filter((l) => BAD.test(l) && !l.startsWith("{")).slice(0, 20);
  if (timedOut) return { status: "failed", summary: "Le jeu n'a pas fini de charger ce monde dans le temps imparti.", lines };
  if (/SCRIPT ERROR|Parse Error/.test(`${stdout}\n${stderr}`)) return { status: "failed", summary: "Le jeu a rencontré une erreur de script en chargeant ce monde.", lines };
  if (!stdout.includes(`"id":"${id}"`)) return { status: "failed", summary: "Le jeu n'a pas reconnu ce monde (pas d'accueil à son nom).", lines };
  if (!stdout.includes('"t":"map_enter"')) return { status: "failed", summary: "Le jeu a chargé le monde mais le personnage n'est entré sur aucune map.", lines };
  return { status: "ok", summary: "Le jeu charge ce monde et y fait entrer un personnage.", lines: [] };
}

export function runGameCheck(gameDir: string, id: string, godot = process.env.GODOT_EXE ?? DEFAULT_GODOT, timeoutMs = 120_000): Promise<GameCheck> {
  const t0 = Date.now();
  if (!fs.existsSync(godot)) {
    return Promise.resolve({ status: "unavailable", summary: "Godot est introuvable sur cet ordinateur (variable GODOT_EXE pour indiquer où).", lines: [], ms: 0 });
  }
  return new Promise((resolve) => {
    const child = spawn(godot, ["--headless", "--path", gameDir, "-s", "res://tools/sim_cli.gd", "--", `--world=${id}`, "--seconds=2"], { cwd: path.dirname(gameDir) });
    let out = "", err = "", timedOut = false;
    const timer = setTimeout(() => { timedOut = true; child.kill(); }, timeoutMs);
    child.stdout.on("data", (d) => { out += d; });
    child.stderr.on("data", (d) => { err += d; });
    const done = () => { clearTimeout(timer); resolve({ ...judgeGameOutput(id, out, err, timedOut), ms: Date.now() - t0 }); };
    child.on("error", () => { clearTimeout(timer); resolve({ status: "unavailable", summary: "Impossible de lancer Godot.", lines: [], ms: Date.now() - t0 }); });
    child.on("close", done);
  });
}
