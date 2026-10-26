// Undo history: one step per change, a bounded number of steps, and undo / redo that walk the same states.
import { describe, expect, it } from "vitest";
import { History, MAX_STEPS } from "../core/history";
import { makeMini } from "./mini";

describe("historique", () => {
  it("un changement = une étape ; rien de changé = pas d'étape", () => {
    const w = makeMini();
    const h = new History(w);
    expect(h.commit(w, "rien")).toBe(false);
    w.files.world.name = "A";
    expect(h.commit(w, "nom A")).toBe(true);
    expect(h.journal).toEqual(["ouverture", "nom A"]);
    expect(h.canUndo).toBe(true);
    expect(h.canRedo).toBe(false);
  });

  it("annuler puis refaire rend les mêmes états ; une nouvelle modification efface le futur", () => {
    const w = makeMini();
    const h = new History(w);
    for (const n of ["A", "B", "C"]) { w.files.world.name = n; h.commit(w, `nom ${n}`); }
    const back = h.undo("x")!;
    expect(back.files.world.name).toBe("B");
    expect(h.undo("x")!.files.world.name).toBe("A");
    expect(h.redo("x")!.files.world.name).toBe("B");
    const w2 = makeMini();
    w2.files.world.name = "Z";
    h.commit(w2, "nom Z");
    expect(h.canRedo).toBe(false);
  });

  it("ne garde que les dernières étapes (borne), sans casser l'annulation récente", () => {
    const w = makeMini();
    const h = new History(w);
    for (let i = 0; i < MAX_STEPS + 50; i++) { w.files.world.name = `v${i}`; h.commit(w, `v${i}`); }
    expect(h.journal.length).toBeLessThanOrEqual(MAX_STEPS + 1);
    expect(h.journal[h.journal.length - 1]).toBe(`v${MAX_STEPS + 49}`);
    expect(h.undo("x")!.files.world.name).toBe(`v${MAX_STEPS + 48}`);
  });
});
