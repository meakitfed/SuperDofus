// Worlds manager: creation, listing, rename with undo / redo, deletion rules, id ranges.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { loadWorld } from "../core/io";
import { collectIds, KINDS, MAX_SLOT, nextId, rangesForSlot, VERTEBRE_RANGES } from "../core/ranges";
import { AtelierError, WorldStore } from "../core/store";
import { validateDir } from "../core/validate";

const ROOT = path.resolve(__dirname, "..", "..");
const TEMPLATES = path.resolve(__dirname, "..", "templates");
let tmp: string;
let store: WorldStore;

beforeEach(() => {
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), "atelier-store-"));
  store = new WorldStore(tmp, path.join(tmp, "ranges.json"), TEMPLATES);
});
afterEach(() => fs.rmSync(tmp, { recursive: true, force: true }));

describe("plages d'ids", () => {
  it("deux emplacements ne se recouvrent jamais, pour aucun type d'id", () => {
    for (const k of KINDS) {
      const a = rangesForSlot(1)[k], b = rangesForSlot(2)[k], z = rangesForSlot(MAX_SLOT)[k];
      expect(a[1] < b[0] && b[1] < z[0], k).toBe(true);
    }
  });
  it("aucune plage ne touche aux ids de Dofus (< 4e8), et tout tient dans 31 bits", () => {
    for (const k of KINDS) {
      expect(rangesForSlot(1)[k][0], k).toBeGreaterThan(4e8);
      expect(rangesForSlot(MAX_SLOT)[k][1], k).toBeLessThan(2 ** 31);
    }
  });
  it("les plages de types différents ne se recouvrent pas non plus", () => {
    const all = KINDS.map((k) => rangesForSlot(7)[k]).sort((a, b) => a[0] - b[0]);
    for (let i = 1; i < all.length; i++) expect(all[i - 1][1]).toBeLessThan(all[i][0]);
  });
  it("La Vertèbre respecte ses propres plages", () => {
    expect(validateDir(path.join(ROOT, "game", "worlds", "vertebre"), { ranges: VERTEBRE_RANGES })).toEqual([]);
  });
});

describe("création", () => {
  it("un monde neuf est valide, dans ses plages, sans classe propre", () => {
    const s = store.create("test_un", "Mon premier monde");
    expect(s).toMatchObject({ id: "test_un", managed: true, created: true, maps: 1 });
    const d = store.detail("test_un");
    expect(d.problems).toEqual([]);
    const { world } = loadWorld(path.join(tmp, "test_un"));
    const ids = collectIds(world!);
    for (const k of KINDS) for (const i of ids[k]) expect(i >= d.ranges[k][0] && i <= d.ranges[k][1], `${k} ${i}`).toBe(true);
  });

  it("refuse un identifiant invalide, un doublon et un nom vide", () => {
    store.create("monde_a", "A");
    for (const bad of ["", "A", "1abc", "a b", "../x", "a".repeat(40)]) expect(() => store.create(bad, "x"), bad).toThrow(AtelierError);
    expect(() => store.create("monde_a", "A")).toThrow(/existe déjà/);
    expect(() => store.create("monde_b", "  ")).toThrow(/nom est vide/);
    expect(fs.existsSync(path.join(tmp, "monde_b"))).toBe(false);
  });

  it("deux mondes créés reçoivent des plages disjointes et ne se gênent pas", () => {
    store.create("monde_a", "A");
    store.create("monde_b", "B");
    expect(store.detail("monde_a").ranges.item[0]).not.toBe(store.detail("monde_b").ranges.item[0]);
    expect(store.detail("monde_a").problems).toEqual([]);
    expect(store.detail("monde_b").problems).toEqual([]);
  });

  it("détecte une collision d'ids entre deux mondes", () => {
    store.create("monde_a", "A");
    store.create("monde_b", "B");
    const bMap = store.detail("monde_b").ranges.map[0];
    store.edit("monde_a", "triche", (w) => {
      w.files.world.maps.push(bMap);
      w.maps.set(bMap, { ...structuredClone(w.maps.get(w.files.world.start_map)!), id: bMap, visual: w.files.world.start_map });
    });
    const codes = new Set(store.detail("monde_a").problems.map((p) => p.code));
    expect(codes.has("E_ID_COLLISION")).toBe(true);
    expect(codes.has("E_ID_RANGE")).toBe(true);
  });

  it("nextId donne le premier id libre de la plage, puis le suivant", () => {
    store.create("monde_a", "A");
    const d = store.detail("monde_a");
    const { world } = loadWorld(path.join(tmp, "monde_a"));
    expect(nextId(world!, "item", d.ranges.item)).toBe(d.ranges.item[0]);
    world!.files.items.items.push({ id: d.ranges.item[0], name_id: 1, icon: 1, type: 1, level: 1 } as any);
    expect(nextId(world!, "item", d.ranges.item)).toBe(d.ranges.item[0] + 1);
    expect(() => nextId(world!, "item", [d.ranges.item[0], d.ranges.item[0]])).toThrow(/épuisée/);
  });
});

describe("liste", () => {
  it("distingue mondes gérés et non gérés", () => {
    fs.mkdirSync(path.join(tmp, "a_la_main"));
    fs.writeFileSync(path.join(tmp, "a_la_main", "world.json"), JSON.stringify({ id: "a_la_main", name: "Fait main", maps: [1, 2], breeds: [] }));
    store.create("monde_a", "A");
    const l = store.list();
    expect(l.find((w) => w.id === "a_la_main")).toMatchObject({ managed: false, created: false, maps: 2 });
    expect(l.find((w) => w.id === "monde_a")).toMatchObject({ managed: true, created: true });
    expect(() => store.detail("a_la_main")).toThrow(/non géré/);
  });
});

describe("renommer, annuler, refaire", () => {
  it("renomme dans world.json et dans le texte, puis annule et refait", () => {
    store.create("monde_a", "Avant");
    expect(store.detail("monde_a").canUndo).toBe(false);
    store.rename("monde_a", "Après");
    const read = () => JSON.parse(fs.readFileSync(path.join(tmp, "monde_a", "world.json"), "utf-8")).name;
    expect(read()).toBe("Après");
    expect(store.detail("monde_a")).toMatchObject({ canUndo: true, canRedo: false });
    expect(store.undo("monde_a")).toBe(true);
    expect(read()).toBe("Avant");
    expect(store.detail("monde_a")).toMatchObject({ canUndo: false, canRedo: true });
    expect(store.redo("monde_a")).toBe(true);
    expect(read()).toBe("Après");
    expect(store.detail("monde_a").problems).toEqual([]);
    expect(store.undo("monde_a")).toBe(true);
    expect(store.undo("monde_a")).toBe(false);
  });

  it("une nouvelle modification efface la pile « refaire »", () => {
    store.create("monde_a", "A");
    store.rename("monde_a", "B");
    store.undo("monde_a");
    store.rename("monde_a", "C");
    expect(store.detail("monde_a").canRedo).toBe(false);
    expect(store.detail("monde_a").journal).toEqual(["ouverture", "renommer en « C »"]);
  });

  it("un renommage identique n'ajoute pas d'étape", () => {
    store.create("monde_a", "A");
    store.rename("monde_a", "A");
    expect(store.detail("monde_a").canUndo).toBe(false);
  });

  it("une édition qui échoue laisse le monde intact", () => {
    store.create("monde_a", "A");
    expect(() => store.edit("monde_a", "boum", (w) => { w.files.world.name = "Cassé"; throw new Error("boum"); })).toThrow("boum");
    expect(store.detail("monde_a").summary.name).toBe("A");
    expect(JSON.parse(fs.readFileSync(path.join(tmp, "monde_a", "world.json"), "utf-8")).name).toBe("A");
  });
});

describe("recharger", () => {
  it("relit le dossier après une modification à la main et signale la casse", () => {
    store.create("monde_a", "A");
    expect(store.detail("monde_a").problems).toEqual([]);
    const f = path.join(tmp, "monde_a", "maps");
    const mapFile = path.join(f, fs.readdirSync(f)[0]);
    const m = JSON.parse(fs.readFileSync(mapFile, "utf-8"));
    m.triggers.push({ cell: 300, to_map: 12345, to_cell: 1 });
    fs.writeFileSync(mapFile, JSON.stringify(m));
    expect(store.detail("monde_a").problems).toEqual([]); // still the copy in memory
    store.reload("monde_a");
    expect(store.detail("monde_a").problems.map((p) => p.code)).toEqual(["E_MAP_TRIGGER_TARGET"]);
    expect(store.detail("monde_a").canUndo).toBe(false);
  });
});

describe("suppression", () => {
  it("demande de retaper l'identifiant et efface dossier + registre", () => {
    store.create("monde_a", "A");
    expect(() => store.remove("monde_a", "autre")).toThrow(/confirmation/);
    expect(fs.existsSync(path.join(tmp, "monde_a"))).toBe(true);
    store.remove("monde_a", "monde_a");
    expect(fs.existsSync(path.join(tmp, "monde_a"))).toBe(false);
    expect(store.list()).toEqual([]);
    expect(Object.keys(store.registry())).not.toContain("monde_a");
  });

  it("refuse de supprimer un monde qu'il n'a pas créé (La Vertèbre)", () => {
    const real = new WorldStore(path.join(ROOT, "game", "worlds"), path.join(tmp, "r.json"), TEMPLATES);
    expect(() => real.remove("vertebre", "vertebre")).toThrow(/refusée/);
    expect(fs.existsSync(path.join(ROOT, "game", "worlds", "vertebre", "world.json"))).toBe(true);
  });

  it("un emplacement libéré est réutilisé par le monde suivant", () => {
    store.create("monde_a", "A");
    const first = store.detail("monde_a").ranges.item[0];
    store.remove("monde_a", "monde_a");
    store.create("monde_c", "C");
    expect(store.detail("monde_c").ranges.item[0]).toBe(first);
  });
});
