// Dialogue graph layout: columns by distance from the start, orphans last, loops flagged.
import { describe, expect, it } from "vitest";
import { layoutDialog } from "../core/dialog_graph";

const d = {
  start: "0",
  nodes: {
    "0": { text: "Salut", replies: [{ text: "Oui", next: "a" }, { text: "Non", next: "b" }, { text: "Fin" }] },
    a: { text: "A", replies: [{ text: "Retour", next: "0" }, { text: "Suite", next: "c" }] },
    b: { text: "B", replies: [{ text: "Suite", next: "c" }] },
    c: { text: "C", replies: [] },
    seul: { text: "Jamais lu", replies: [{ text: "x", next: "c" }] },
  },
};

describe("schéma de dialogue", () => {
  const g = layoutDialog(d);
  const at = (k: string) => g.nodes.find((n) => n.key === k)!;
  it("place les nœuds en colonnes selon la distance au départ", () => {
    expect([at("0").col, at("a").col, at("b").col, at("c").col]).toEqual([0, 1, 1, 2]);
    expect(at("a").row).not.toBe(at("b").row);
    expect(at("0").start).toBe(true);
  });
  it("met les nœuds jamais atteints dans une dernière colonne, marqués", () => {
    expect(at("seul")).toMatchObject({ orphan: true, col: 3 });
    expect(g.nodes.filter((n) => n.orphan).map((n) => n.key)).toEqual(["seul"]);
  });
  it("une flèche par réponse qui mène quelque part, les retours en arrière marqués", () => {
    expect(g.edges).toHaveLength(6); // "Fin" ends the conversation: no arrow
    expect(g.edges.find((e) => e.label === "Retour")!.back).toBe(true);
    expect(g.edges.find((e) => e.label === "Oui")!.back).toBe(false);
  });
  it("ignore une réponse vers un nœud inconnu et supporte un seul nœud", () => {
    const one = layoutDialog({ start: "0", nodes: { "0": { text: "x", replies: [{ text: "?", next: "absent" }] } } });
    expect(one.edges).toEqual([]);
    expect(one.nodes).toHaveLength(1);
  });
});
