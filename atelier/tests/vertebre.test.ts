// The real world is the reference: the atelier must read La Vertèbre without loss, find it coherent, and agree
// with the Python validator on broken copies.
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterAll, describe, expect, it } from "vitest";
import { loadWorld, serializeWorld } from "../core/io";
import { validateDir } from "../core/validate";

const ROOT = path.resolve(__dirname, "..", "..");
const VERTEBRE = path.join(ROOT, "game", "worlds", "vertebre");
const tmpDirs: string[] = [];
afterAll(() => tmpDirs.forEach((d) => fs.rmSync(d, { recursive: true, force: true })));

function copyWorld(): string {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "atelier-vertebre-"));
  tmpDirs.push(dir);
  fs.cpSync(VERTEBRE, dir, { recursive: true });
  return dir;
}

const edit = (dir: string, rel: string, fn: (j: any) => void) => {
  const f = path.join(dir, rel);
  const j = JSON.parse(fs.readFileSync(f, "utf-8"));
  fn(j);
  fs.writeFileSync(f, JSON.stringify(j), "utf-8");
};

function pythonProblems(dir: string): string[] {
  const out = execFileSync("python", [path.join(__dirname, "py_validate.py"), ROOT, dir], {
    encoding: "utf-8",
    env: { ...process.env, PYTHONIOENCODING: "utf-8" },
    stdio: ["ignore", "pipe", "pipe"],
  });
  return out.split(/\r?\n/).filter((l) => l.startsWith("PROBLEM"));
}

describe("La Vertèbre", () => {
  it("se relit sans perte : charger puis sérialiser redonne le même JSON", () => {
    const { world, issues } = loadWorld(VERTEBRE);
    expect(issues).toEqual([]);
    for (const [rel, text] of serializeWorld(world!)) {
      const disk = JSON.parse(fs.readFileSync(path.join(VERTEBRE, rel), "utf-8"));
      expect(JSON.parse(text), rel).toEqual(disk);
    }
  });

  it("est cohérente (0 erreur, 0 avertissement)", () => {
    expect(validateDir(VERTEBRE)).toEqual([]);
  });

  // [name, edit, python must also see it]
  const BREAKS: [string, (d: string) => void][] = [
    ["texte supprimé", (d) => edit(d, "Content/I18n/extra_fr.json", (j) => { delete j["9000099"]; })],
    ["butin inconnu", (d) => edit(d, "monsters.json", (j) => { const m = Object.values<any>(j.monsters)[0]; m.grades[0].drops.push({ item: 1, pct: 5 }); })],
    ["porte vers une map inconnue", (d) => edit(d, "maps/9001.json", (j) => { j.triggers.push({ cell: 300, to_map: 12345, to_cell: 1 }); })],
    ["boutique vers un objet inconnu", (d) => edit(d, "shops.json", (j) => { Object.values<any>(j.shops)[0].items.push(1); })],
    ["icône supprimée", (d) => fs.rmSync(path.join(d, "Content", "Picto", "Items", "9100001.png"))],
    ["dialogue vers un nœud inconnu", (d) => edit(d, "dialogs.json", (j) => { Object.values<any>(j.dialogs)[0].nodes["0"].replies.push({ id: 99, text: "x", next: "nope" }); })],
    ["objectif de quête sur un monstre inconnu", (d) => edit(d, "quests.json", (j) => { const o = Object.values<any>(j.quests).flatMap((q: any) => q.steps.flatMap((s: any) => s.objectives)).find((o: any) => o.type === 14); o.params[0] = 1; })],
  ];
  for (const [name, brk] of BREAKS) {
    it(`même verdict que validate.py : ${name}`, () => {
      const dir = copyWorld();
      brk(dir);
      const ours = validateDir(dir).filter((p) => p.severity === "error");
      const theirs = pythonProblems(dir);
      expect(theirs.length, "validate.py doit voir la casse").toBeGreaterThan(0);
      expect(ours.length, `atelier : ${ours.map((o) => o.code)}`).toBe(theirs.length);
    });
  }
});
