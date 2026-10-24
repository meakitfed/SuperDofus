// Monster editor: grades, drops, zones, and the guards that keep the world coherent.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { describe, expect, it } from "vitest";
import { copyBone, listBones } from "../core/bones";
import * as mo from "../core/editors_monsters";
import { AtelierError } from "../core/errors";
import { VERTEBRE_RANGES } from "../core/ranges";
import { validate } from "../core/validate";
import { makeMini, miniList, miniProbe } from "./mini";

const R = VERTEBRE_RANGES;
const codes = (w: ReturnType<typeof makeMini>) => validate(w, miniProbe, { ranges: R, list: miniList }).map((p) => `${p.code} ${p.message}`);
const BASELINE = new Set(codes(makeMini()));
const check = (w: ReturnType<typeof makeMini>) => codes(w).filter((c) => !BASELINE.has(c));
const refuses = (fn: () => void, status: number, re: RegExp) => {
  try { fn(); } catch (e) { expect(e).toBeInstanceOf(AtelierError); expect((e as AtelierError).status).toBe(status); expect((e as Error).message).toMatch(re); return; }
  throw new Error("aucune erreur levée");
};
const grade = (over: Partial<mo.GradeInput> = {}): mo.GradeInput => ({ ...mo.newGrade(), spells: [900101], drops: [{ item: 9100001, pct: 25 }], ...over });
const base: mo.MonsterInput = { name: "Rôdeur d'os", bone: 950001, size: 100, portrait: 950001, grades: [grade(), grade({ level: 5, hp: 40 })], zones: ["1"] };

describe("monsters", () => {
  it("creates a monster with named grades, in range, placed in its zone, and the world stays valid", () => {
    const w = makeMini();
    const id = mo.createMonster(w, R, base);
    expect(id).toBeGreaterThanOrEqual(R.monster[0]);
    const m = (w.files.monsters.monsters as any)[String(id)];
    expect(m.grades.map((g: any) => g.grade)).toEqual([1, 2]);
    expect(m.grades[1]).toMatchObject({ monster: id, level: 5, hp: 40, look: "{950001|||100}", portrait: 950001, name: "Rôdeur d'os" });
    expect(w.files.texts[String(m.name_id)]).toBe("Rôdeur d'os");
    expect(w.files.monsters.subareas["1"].monsters).toContain(id);
    expect(check(w)).toEqual([]);
  });
  it("round-trips through list and update, keeping unknown grade fields", () => {
    const w = makeMini();
    const id = mo.createMonster(w, R, base);
    (w.files.monsters.monsters as any)[String(id)].grades[0].custom = 7;
    const row = mo.listMonsters(w).find((r) => r.id === id)!;
    mo.updateMonster(w, id, { ...row, name: "Autre", zones: [], grades: [row.grades[0]] });
    const m = (w.files.monsters.monsters as any)[String(id)];
    expect(m.grades).toHaveLength(1);
    expect(m.grades[0].custom).toBe(7);
    expect(w.files.texts[String(m.name_id)]).toBe("Autre");
    expect(check(w)).toEqual(["W_MONSTER_NO_ZONE monstre " + id + " : dans aucune zone, il n'apparaîtra jamais"]);
  });
  it("validates grades, spells, drops and zones", () => {
    const w = makeMini();
    refuses(() => mo.createMonster(w, R, { ...base, name: "" }), 400, /nom/);
    refuses(() => mo.createMonster(w, R, { ...base, grades: [] }), 400, /grades/);
    refuses(() => mo.createMonster(w, R, { ...base, grades: [grade({ level: 9 }), grade({ level: 3 })] }), 400, /croître/);
    refuses(() => mo.createMonster(w, R, { ...base, grades: [grade({ spells: [424242] })] }), 400, /sort 424242/);
    refuses(() => mo.createMonster(w, R, { ...base, grades: [grade({ drops: [{ item: 424242, pct: 5 }] })] }), 400, /objet 424242/);
    refuses(() => mo.createMonster(w, R, { ...base, grades: [grade({ drops: [{ item: 9100001, pct: 150 }] })] }), 400, /butin/);
    refuses(() => mo.createMonster(w, R, { ...base, zones: ["nope"] }), 400, /zone nope/);
    refuses(() => mo.createMonster(w, R, { ...base, grades: [grade({ kamas: [9, 2] })] }), 400, /kamas/);
  });
  it("deletes a free monster with its text and zone entry; refuses one a quest hunts", () => {
    const w = makeMini();
    refuses(() => mo.deleteMonster(w, 910001), 409, /quest/);
    const id = mo.createMonster(w, R, base);
    const nameId = (w.files.monsters.monsters as any)[String(id)].name_id;
    mo.deleteMonster(w, id);
    expect(w.files.texts[String(nameId)]).toBeUndefined();
    expect(w.files.monsters.subareas["1"].monsters).not.toContain(id);
    expect(check(w)).toEqual([]);
  });
  it("makes zones counting down from the top of the monster range; deletes only empty ones", () => {
    const w = makeMini();
    const a = mo.createZone(w, R, 10);
    const b = mo.createZone(w, R, 20);
    expect(Number(a)).toBe(R.monster[1]);
    expect(Number(b)).toBe(R.monster[1] - 1);
    refuses(() => mo.createZone(w, R, 0), 400, /niveau/);
    refuses(() => mo.deleteZone(w, "1"), 409, /non vide/);
    mo.deleteZone(w, a);
    expect(mo.listZones(w).some((z) => z.key === a)).toBe(false);
  });
});

describe("bones", () => {
  it("lists what a world lacks and copies a skeleton once", () => {
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "atelier-bones-"));
    const src = path.join(tmp, "src"), dst = path.join(tmp, "dst");
    fs.mkdirSync(path.join(src, "Content", "Characters", "Bones", "7"), { recursive: true });
    fs.writeFileSync(path.join(src, "Content", "Characters", "Bones", "7", "0.png"), "x");
    fs.mkdirSync(dst);
    expect(listBones(dst, { src })).toEqual({ own: [], library: [{ world: "src", id: 7 }] });
    copyBone(dst, src, 7);
    expect(listBones(dst, { src })).toEqual({ own: [7], library: [] });
    refuses(() => copyBone(dst, src, 7), 409, /déjà/);
    refuses(() => copyBone(dst, src, 8), 404, /introuvable/);
    fs.rmSync(tmp, { recursive: true, force: true });
  });
});
