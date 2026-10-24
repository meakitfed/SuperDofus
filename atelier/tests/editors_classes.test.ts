// Class editor: a class and its spell book stay coherent through create, update, default and delete.
import { describe, expect, it } from "vitest";
import * as cl from "../core/editors_classes";
import * as sp from "../core/editors_spells";
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
const spell = (name: string): sp.SpellInput => ({
  name, icon: 5, level: 3, ap: 3, range: [1, 3], los: true, inLine: false, perTurn: 2, cooldown: 0, crit: 5, color: "#aa3322",
  area: { shape: "point", size: 0 }, effects: [{ kind: "damage", target: "enemies", min: 5, max: 8, element: "fire" }],
});
const familyOf = (w: ReturnType<typeof makeMini>, grade: number) => (w.files.spells.spells.find((s) => s.id === grade) as any).spell as number;
const input = (spells: number[]): cl.ClassInput => ({ name: "Brasier", tagline: "Mage de feu", description: "Il brûle tout.", bone: 950001, size: 100, spells });

describe("classes", () => {
  it("creates a class: row, texts, breed list, spell book, bound spells; the world stays valid", () => {
    const w = makeMini();
    const a = familyOf(w, sp.createSpell(w, R, spell("Étincelle")));
    const b = familyOf(w, sp.createSpell(w, R, spell("Brasier")));
    const id = cl.createClass(w, R, input([a, b]));
    expect(id).toBeGreaterThanOrEqual(R.breed[0]);
    expect(w.files.world.breeds).toContain(id);
    const row = (w.files.breeds.objectsById as any)[String(id)];
    expect(row).toMatchObject({ id, maleLook: "{950001|||100}", creatureBonesId: 950001, breedSpellsId: [a, b] });
    expect(w.files.texts[row.shortNameId]).toBe("Brasier");
    expect((w.files.spells.classes as any)[String(id)].pairs).toEqual([[a, a], [b, b]]);
    const bound = w.files.spells.spells.find((s) => s.id === a + 1) as any;
    expect(bound).toMatchObject({ breed: id, bar: true, grade: 1 });
    expect(check(w)).toEqual([]);
  });
  it("updates the spell book: removed spells are freed, new ones bound, name rewritten in place", () => {
    const w = makeMini();
    const a = familyOf(w, sp.createSpell(w, R, spell("A")));
    const b = familyOf(w, sp.createSpell(w, R, spell("B")));
    const id = cl.createClass(w, R, input([a]));
    const nameText = (w.files.breeds.objectsById as any)[String(id)].shortNameId;
    cl.updateClass(w, R, id, { ...input([b]), name: "Autre" });
    expect(w.files.texts[nameText]).toBe("Autre");
    expect((w.files.spells.spells.find((s) => s.id === a + 1) as any).bar).toBe(false);
    expect((w.files.spells.spells.find((s) => s.id === a + 1) as any).breed).toBeUndefined();
    expect((w.files.spells.spells.find((s) => s.id === b + 1) as any).breed).toBe(id);
    expect(check(w)).toEqual([]);
  });
  it("validates input and refuses a spell already in another class", () => {
    const w = makeMini();
    const a = familyOf(w, sp.createSpell(w, R, spell("A")));
    cl.createClass(w, R, input([a]));
    refuses(() => cl.createClass(w, R, input([a])), 409, /déjà dans la classe/);
    refuses(() => cl.createClass(w, R, { ...input([a]), name: " " }), 400, /nom/);
    refuses(() => cl.createClass(w, R, input([])), 400, /sorts/);
    refuses(() => cl.createClass(w, R, input([424242])), 400, /inconnu/);
    refuses(() => cl.createClass(w, R, { ...input([a]), tagline: "" }), 400, /rôle/);
  });
  it("the first class becomes the default; deleting it hands the default over and cleans everything", () => {
    const w = makeMini();
    const a = familyOf(w, sp.createSpell(w, R, spell("A")));
    const b = familyOf(w, sp.createSpell(w, R, spell("B")));
    const c1 = cl.createClass(w, R, input([a]));
    const c2 = cl.createClass(w, R, { ...input([b]), name: "Deux" });
    expect(w.files.world.default_breed).toBe(901); // the mini world already had one
    cl.setDefaultClass(w, c1);
    expect(cl.listClasses(w).find((c) => c.id === c1)!.isDefault).toBe(true);
    const texts = Object.keys(w.files.texts).length;
    cl.deleteClass(w, c1);
    expect(w.files.world.default_breed).toBe(901);
    expect(Object.keys(w.files.texts).length).toBe(texts - 3);
    expect((w.files.spells.spells.find((s) => s.id === a + 1) as any).bar).toBe(false);
    expect(w.files.world.breeds).toContain(c2);
    expect(check(w)).toEqual([]);
  });
  it("makes the spell protected from deletion while a class owns it", () => {
    const w = makeMini();
    const grade = sp.createSpell(w, R, spell("A"));
    cl.createClass(w, R, input([familyOf(w, grade)]));
    refuses(() => sp.deleteSpell(w, grade), 409, /class/);
  });
});
