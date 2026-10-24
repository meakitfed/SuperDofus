// Spell editor: simple spells round-trip through the validator; rich ones stay locked; used spells are kept.
import { describe, expect, it } from "vitest";
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
const base: sp.SpellInput = {
  name: "Éclat d'os", icon: 5, level: 1, ap: 3, range: [1, 4], los: true, inLine: false, perTurn: 2, cooldown: 0, crit: 5, color: "#aa3322",
  area: { shape: "point", size: 0 },
  effects: [{ kind: "damage", target: "enemies", min: 10, max: 14, element: "earth" }],
};

describe("spells", () => {
  it("creates a castable grade in the world's range with its family, texts and a stronger crit", () => {
    const w = makeMini();
    const id = sp.createSpell(w, R, { ...base, description: "Un éclat." });
    const s = w.files.spells.spells.find((x) => x.id === id) as any;
    expect(id).toBeGreaterThanOrEqual(R.spell[0]);
    expect(w.files.spells.grades[String(s.spell)]).toEqual([id]);
    expect(w.files.texts[String(s.name_id)]).toBe("Éclat d'os");
    expect(s.effects[0]).toMatchObject({ kind: "damage", mask: "A", element: "earth", min: 10, max: 14 });
    expect(s.crit_effects[0]).toMatchObject({ min: 13, max: 18 });
    expect(check(w)).toEqual([]);
  });
  it("supports heal, shield, AP and MP effects", () => {
    const w = makeMini();
    const id = sp.createSpell(w, R, {
      ...base,
      effects: [
        { kind: "heal", target: "allies", min: 5, max: 8, element: "air", area: { shape: "circle", size: 1 } },
        { kind: "shield", target: "caster", min: 10, max: 10, duration: 2 },
        { kind: "ap", target: "enemies", min: 1, max: 1, duration: 1, sign: -1 },
        { kind: "mp", target: "caster", min: 2, max: 2, duration: 1, sign: 1 },
      ],
    });
    const row = sp.listSpells(w).find((r) => r.id === id)!;
    expect(row.locked).toBe(false);
    expect(row.effects.map((e) => e.kind)).toEqual(["heal", "shield", "ap", "mp"]);
    expect(check(w)).toEqual([]);
  });
  it("updates in place, keeps ids, and validates input", () => {
    const w = makeMini();
    const id = sp.createSpell(w, R, base);
    sp.updateSpell(w, R, id, { ...base, name: "Autre", ap: 4, effects: [{ kind: "damage", target: "enemies", min: 20, max: 30, element: "fire" }] });
    const row = sp.listSpells(w).find((r) => r.id === id)!;
    expect(row).toMatchObject({ name: "Autre", ap: 4 });
    expect(row.effects[0].element).toBe("fire");
    refuses(() => sp.createSpell(w, R, { ...base, name: " " }), 400, /nom/);
    refuses(() => sp.createSpell(w, R, { ...base, range: [5, 2] }), 400, /portée/);
    refuses(() => sp.createSpell(w, R, { ...base, color: "red" }), 400, /couleur/);
    refuses(() => sp.createSpell(w, R, { ...base, effects: [] }), 400, /effet/);
    refuses(() => sp.createSpell(w, R, { ...base, effects: [{ kind: "damage", target: "enemies", min: 9, max: 3, element: "fire" }] }), 400, /min/);
    refuses(() => sp.createSpell(w, R, { ...base, effects: [{ kind: "push" as never, target: "enemies", min: 1, max: 1 }] }), 400, /non géré/);
  });
  it("locks spells with rich effects: header editable, effects untouched", () => {
    const w = makeMini();
    const rich = sp.listSpells(w).find((r) => r.id === 900102)!;
    expect(rich.locked).toBe(true);
    expect(rich.complexKinds).toEqual(["summon", "cast"]);
    const { effects: _e, ...head } = { ...base, name: "Invocateur" };
    sp.updateSpell(w, R, 900102, head);
    expect((w.files.spells.spells.find((x) => x.id === 900102) as any).effects).toHaveLength(2);
    refuses(() => sp.updateSpell(w, R, 900102, base), 409, /effets/);
  });
  it("refuses to delete a spell a monster, a class or a summon needs; deletes a free one with its texts", () => {
    const w = makeMini();
    refuses(() => sp.deleteSpell(w, 900101), 409, /utilisé par/);
    const id = sp.createSpell(w, R, base);
    const fam = (w.files.spells.spells.find((x) => x.id === id) as any).spell;
    sp.deleteSpell(w, id);
    expect(w.files.spells.grades[String(fam)]).toBeUndefined();
    expect(check(w)).toEqual([]);
  });
});
