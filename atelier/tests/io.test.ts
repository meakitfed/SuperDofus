// Disk round trip and atomic save of a world folder.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { loadWorld, saveWorld, serializeWorld, stableStringify } from "../core/io";
import { FILES } from "../core/schemas";
import { validate } from "../core/validate";
import { makeMini, miniProbe } from "./mini";

const dirs: string[] = [];
afterEach(() => { dirs.splice(0).forEach((d) => fs.rmSync(d, { recursive: true, force: true })); });
const tmp = () => { const d = fs.mkdtempSync(path.join(os.tmpdir(), "atelier-io-")); dirs.push(d); return d; };

const snapshot = (dir: string): Record<string, string> => {
  const out: Record<string, string> = {};
  const walk = (d: string) => fs.readdirSync(d, { withFileTypes: true }).forEach((e) => {
    const p = path.join(d, e.name);
    if (e.isDirectory()) walk(p); else out[path.relative(dir, p)] = fs.readFileSync(p, "utf-8");
  });
  walk(dir);
  return out;
};

describe("écriture d'un monde", () => {
  it("sauvegarder puis recharger redonne le même monde, qui reste valide", () => {
    const w = makeMini();
    w.dir = tmp();
    saveWorld(w);
    const { world, issues } = loadWorld(w.dir);
    expect(issues).toEqual([]);
    expect(serializeWorld(world!)).toEqual(serializeWorld(w));
    expect(validate(world!, miniProbe)).toEqual([]);
  });

  it("une seconde sauvegarde identique n'écrit rien", () => {
    const w = makeMini();
    w.dir = tmp();
    saveWorld(w);
    expect(saveWorld(w)).toEqual([]);
  });

  it("n'écrit que ce qui a changé et garde l'ancienne version en .bak", () => {
    const w = makeMini();
    w.dir = tmp();
    saveWorld(w);
    w.files.world.name = "Autre nom";
    expect(saveWorld(w)).toEqual(["world.json"]);
    expect(JSON.parse(fs.readFileSync(path.join(w.dir, "world.json.bak"), "utf-8")).name).toBe("Mini");
  });

  it("un échec en cours d'écriture ne touche à rien (pas de .tmp, fichiers intacts)", () => {
    const w = makeMini();
    w.dir = tmp();
    saveWorld(w);
    const before = snapshot(w.dir);
    w.files.world.name = "Cassé";
    w.maps.get(1)!.name = "Cassé aussi";
    expect(() => saveWorld(w, { beforeRename: () => { throw new Error("disque plein"); } })).toThrow("disque plein");
    expect(snapshot(w.dir)).toEqual(before);
  });

  it("la sortie est stable : mêmes données, mêmes octets", () => {
    expect(stableStringify(makeMini().files)).toBe(stableStringify(makeMini().files));
  });
});

describe("lecture d'un monde cassé", () => {
  it("signale un fichier absent, un JSON illisible et un schéma violé, sans planter", () => {
    const w = makeMini();
    w.dir = tmp();
    saveWorld(w);
    fs.rmSync(path.join(w.dir, FILES.shops.path));
    fs.writeFileSync(path.join(w.dir, FILES.quests.path), "{ pas du json", "utf-8");
    fs.writeFileSync(path.join(w.dir, FILES.world.path), JSON.stringify({ id: "mini" }), "utf-8");
    const { world, issues } = loadWorld(w.dir);
    expect(world).toBeNull();
    expect(issues.map((i) => i.file).sort()).toEqual([FILES.quests.path, FILES.shops.path, FILES.world.path].sort());
  });
});
