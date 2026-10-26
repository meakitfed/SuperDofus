// Data editors: every edit leaves a world the validator accepts, and every refused deletion says why.
import { describe, expect, it } from "vitest";
import * as ed from "../core/editors";
import { AtelierError } from "../core/errors";
import { VERTEBRE_RANGES } from "../core/ranges";
import { validate } from "../core/validate";
import { makeMini, miniList, miniProbe } from "./mini";

const R = VERTEBRE_RANGES;
const codes = (w: ReturnType<typeof makeMini>) => validate(w, miniProbe, { ranges: R, list: miniList }).map((p) => `${p.code} ${p.message}`);
const BASELINE = new Set(codes(makeMini())); // the mini world predates the ranges: only what an edit adds counts
const check = (w: ReturnType<typeof makeMini>) => codes(w).filter((c) => !BASELINE.has(c));
const base = { name: "Anneau de test", icon: 9100001, type: 9, level: 5, effects: [[125, 10, 0, 0]] };
const refuses = (fn: () => void, status: number, re: RegExp) => {
  try { fn(); } catch (e) { expect(e).toBeInstanceOf(AtelierError); expect((e as AtelierError).status).toBe(status); expect((e as Error).message).toMatch(re); return; }
  throw new Error("aucune erreur levée");
};

describe("texts", () => {
  it("adds in the world's range, edits in place, lists usage", () => {
    const w = makeMini();
    const id = ed.addText(w, R, "Bonjour");
    expect(id).toBeGreaterThanOrEqual(R.text[0]);
    expect(id).toBeLessThanOrEqual(R.text[1]);
    ed.setText(w, id, "Salut");
    expect(w.files.texts[String(id)]).toBe("Salut");
    const used = ed.listTexts(w).find((t) => t.id === 9000004)!;
    expect(used.usedBy).toEqual([{ kind: "item", id: 9100001 }]);
    expect(check(w)).toEqual([]);
  });
  it("refuses empty text, unknown id and deleting a used text; deletes a free one", () => {
    const w = makeMini();
    refuses(() => ed.addText(w, R, "  "), 400, /vide/);
    refuses(() => ed.setText(w, 1, "x"), 404, /inconnu/);
    refuses(() => ed.deleteText(w, 9000004), 409, /utilisé par item 9100001/);
    const id = ed.addText(w, R, "temporaire");
    ed.deleteText(w, id);
    expect(w.files.texts[String(id)]).toBeUndefined();
  });
});

describe("items", () => {
  it("creates an item with its texts, in range, in its set, and the world stays valid", () => {
    const w = makeMini();
    const id = ed.createItem(w, R, { ...base, description: "Un anneau.", set: 9101 });
    const it = w.files.items.items.find((i) => i.id === id)!;
    expect(id).toBeGreaterThanOrEqual(R.item[0]);
    expect(w.files.texts[String(it.name_id)]).toBe("Anneau de test");
    expect(w.files.texts[String(it.description_id)]).toBe("Un anneau.");
    expect(w.files.items.sets[0].items).toContain(id);
    expect((w.files.items.sets[0] as any).effects.length).toBeGreaterThanOrEqual(2);
    expect(check(w)).toEqual([]);
  });
  it("updates in place: same id, same text ids, set moved, description removed", () => {
    const w = makeMini();
    const id = ed.createItem(w, R, { ...base, description: "x", set: 9101 });
    const before = w.files.items.items.find((i) => i.id === id)!;
    const [nameId, descId] = [before.name_id, before.description_id!];
    ed.updateItem(w, R, id, { ...base, name: "Autre nom", level: 9, set: null });
    const it = w.files.items.items.find((i) => i.id === id)!;
    expect(it.name_id).toBe(nameId);
    expect(w.files.texts[String(nameId)]).toBe("Autre nom");
    expect(it.description_id).toBeUndefined();
    expect(w.files.texts[String(descId)]).toBeUndefined();
    expect(w.files.items.sets[0].items).not.toContain(id);
    expect(check(w)).toEqual([]);
  });
  it("validates the input", () => {
    const w = makeMini();
    refuses(() => ed.createItem(w, R, { ...base, name: "" }), 400, /nom/);
    refuses(() => ed.createItem(w, R, { ...base, level: 0 }), 400, /niveau/);
    refuses(() => ed.createItem(w, R, { ...base, set: 424242 }), 400, /panoplie/);
    refuses(() => ed.createItem(w, R, { ...base, effects: [[0, 1]] }), 400, /effet/);
    refuses(() => ed.createItem(w, R, { ...base, effects: [["a" as never]] }), 400, /effet/);
  });
  it("refuses to delete an item that a shop, a drop, a quest, a skill or a dialog needs", () => {
    const w = makeMini();
    refuses(() => ed.deleteItem(w, 9100001), 409, /utilisé par/);
    const id = ed.createItem(w, R, { ...base, set: 9101 });
    ed.deleteItem(w, id);
    expect(w.files.items.sets[0].items).not.toContain(id);
    expect(check(w)).toEqual([]);
  });
  it("lists the usage so the screen can show it", () => {
    const row = ed.listItems(makeMini()).find((i) => i.id === 9100001)!;
    expect(row.usedBy.map((u) => u.kind).sort()).toEqual(["dialog", "monster", "quest", "shop", "skill"]);
  });
});

describe("armes", () => {
  const sword = { name: "Épée d'os", icon: 9100001, type: 6, level: 5, effects: [[97, 8, 12, 0]], weapon: { ap: 4, min_range: 1, range: 1, crit: 20, crit_bonus: 5, in_line: 0 as const, los: 1 as const, per_turn: 1 } };
  it("une arme garde ses statistiques ; les relire, les modifier, les retirer", () => {
    const w = makeMini();
    const id = ed.createItem(w, R, sword);
    expect(ed.listItems(w).find((i) => i.id === id)!.weapon).toEqual(sword.weapon);
    expect((w.files.items.items.find((i) => i.id === id) as Record<string, unknown>).weapon).toEqual(sword.weapon);
    expect(check(w)).toEqual([]);
    ed.updateItem(w, R, id, { ...sword, weapon: { ...sword.weapon, range: 3, in_line: 1 } });
    expect(ed.listItems(w).find((i) => i.id === id)!.weapon).toMatchObject({ range: 3, in_line: 1 });
    ed.updateItem(w, R, id, { ...sword, weapon: null });
    expect(ed.listItems(w).find((i) => i.id === id)!.weapon).toBeNull();
    expect(check(w).map((c) => c.split(" ")[0])).toEqual(["W_WEAPON_NO_STATS"]); // a weapon without stats is flagged
  });
  it("refuse des statistiques sur ce qui n'est pas une arme, et des valeurs hors limites", () => {
    const w = makeMini();
    refuses(() => ed.createItem(w, R, { ...sword, type: 9 }), 400, /qu'à une arme/);
    refuses(() => ed.createItem(w, R, { ...sword, weapon: { ...sword.weapon, min_range: 5, range: 2 } }), 400, /portée minimale/);
    refuses(() => ed.createItem(w, R, { ...sword, weapon: { ...sword.weapon, ap: 0 } }), 400, /PA de l'arme/);
    refuses(() => ed.createItem(w, R, { ...sword, weapon: { ...sword.weapon, crit: 101 } }), 400, /critique/);
    refuses(() => ed.createItem(w, R, { ...sword, weapon: { ...sword.weapon, per_turn: 0 } }), 400, /coups par tour/);
  });
});

describe("sets", () => {
  it("creates, renames, and deletes only when empty", () => {
    const w = makeMini();
    const id = ed.createSet(w, R, "Panoplie neuve");
    expect(id).toBeGreaterThanOrEqual(R.set[0]);
    ed.renameSet(w, id, "Autre");
    expect(ed.listSets(w).find((s) => s.id === id)!.name).toBe("Autre");
    expect(check(w)).toEqual([]);
    refuses(() => ed.deleteSet(w, 9101), 409, /non vide/);
    ed.deleteSet(w, id);
    expect(ed.listSets(w).some((s) => s.id === id)).toBe(false);
  });
});
