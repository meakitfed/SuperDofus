// Class editor: a playable class = a row of the breeds table (name, description, look), an entry in the world's
// breed list, and a spell book (the spell families it learns, in order; each is learnt when its first grade's
// level is reached). The class' spells get `breed` and `bar` so the spell bar shows them.
import { AtelierError } from "./errors";
import type { World } from "./io";
import { addText } from "./editors";
import { nextId, type RangeMap } from "./ranges";
import { textUsages } from "./usage";

export interface ClassInput {
  name: string;
  /** one-line role shown on the creation screen */
  tagline: string;
  description: string;
  bone: number;
  size: number;
  /** spell families, in spell book order */
  spells: number[];
}

export interface ClassRow extends ClassInput {
  id: number;
  isDefault: boolean;
}

type Raw = Record<string, any>;
const bad = (m: string) => new AtelierError(400, m);
const rows = (w: World) => w.files.breeds.objectsById as Record<string, Raw>;
const spellList = (w: World) => w.files.spells.spells as Raw[];
const classes = (w: World) => w.files.spells.classes as Record<string, { start_states?: unknown[]; pairs: number[][] }>;
const text = (w: World, id: unknown) => w.files.texts[String(id)] ?? "";

const parseLook = (look: string | undefined) => {
  const [b, , , s] = (look ?? "{0|||100}").replace(/[{}]/g, "").split("|");
  return { bone: Number(b) || 0, size: Number(s) || 100 };
};

export function listClasses(w: World): ClassRow[] {
  return w.files.world.breeds.map((id) => {
    const r = rows(w)[String(id)] ?? {};
    const { bone, size } = parseLook(r.maleLook);
    return {
      id, name: text(w, r.shortNameId), tagline: text(w, r.gameplayDescriptionId), description: text(w, r.descriptionId), bone, size,
      spells: (classes(w)[String(id)]?.pairs ?? []).map((p) => p[0]), isDefault: w.files.world.default_breed === id,
    };
  });
}

function check(w: World, i: ClassInput, self?: number) {
  const name = typeof i.name === "string" ? i.name.trim() : "";
  if (!name) throw bad("nom : valeur vide");
  if (name.length > 40) throw bad("nom : 40 caractères au maximum");
  const tagline = (i.tagline ?? "").trim();
  if (!tagline || tagline.length > 120) throw bad("rôle : 1 à 120 caractères");
  const description = (i.description ?? "").trim();
  if (!description || description.length > 2000) throw bad("description : 1 à 2000 caractères");
  if (!Number.isInteger(i.bone) || i.bone < 1) throw bad("squelette : requis");
  if (!Number.isInteger(i.size) || i.size < 20 || i.size > 400) throw bad("taille : entier entre 20 et 400 attendu");
  if (!Array.isArray(i.spells) || i.spells.length < 1 || i.spells.length > 40) throw bad("1 à 40 sorts attendus");
  if (new Set(i.spells).size !== i.spells.length) throw bad("sort en double");
  const taken = new Map<number, number>();
  for (const [b, c] of Object.entries(classes(w))) if (Number(b) !== self) for (const p of c.pairs) for (const s of p) taken.set(s, Number(b));
  for (const f of i.spells) {
    if (!(String(f) in w.files.spells.grades)) throw bad(`sort ${f} inconnu`);
    if (taken.has(f)) throw new AtelierError(409, `sort ${f} déjà dans la classe ${taken.get(f)}`);
  }
  return { name, tagline, description, bone: i.bone, size: i.size, spells: i.spells };
}

/** Marks the grades of `families` as the class' own (breed + bar) and frees those of `freed`. */
function bindSpells(w: World, breed: number, families: number[], freed: number[]): void {
  const grades = w.files.spells.grades as Record<string, number[]>;
  for (const f of freed) for (const g of grades[String(f)] ?? []) {
    const s = spellList(w).find((x) => x.id === g);
    if (s) { delete s.breed; delete s.grade; s.bar = false; }
  }
  for (const f of families) (grades[String(f)] ?? []).forEach((g, n) => {
    const s = spellList(w).find((x) => x.id === g);
    if (s) { s.breed = breed; s.grade = n + 1; s.bar = true; }
  });
}

function writeRow(w: World, ranges: RangeMap, id: number, v: ReturnType<typeof check>, row: Raw): void {
  const setText = (key: string, value: string, asString: boolean) => {
    const cur = row[key];
    if (cur && String(cur) in w.files.texts) w.files.texts[String(cur)] = value;
    else { const t = addText(w, ranges, value); row[key] = asString ? String(t) : t; }
  };
  setText("shortNameId", v.name, true);
  setText("gameplayDescriptionId", v.tagline, true);
  setText("descriptionId", v.description, false);
  Object.assign(row, {
    id, maleLook: `{${v.bone}|||${v.size}}`, femaleLook: `{${v.bone}|||${Math.max(20, v.size - 4)}}`, creatureBonesId: v.bone,
    breedSpellsId: v.spells,
  });
  classes(w)[String(id)] = { start_states: classes(w)[String(id)]?.start_states ?? [], pairs: v.spells.map((s) => [s, s]) };
}

const BASE_ROW = (): Raw => ({
  statsPointsForStrength: [{ values: [0, 1] }], statsPointsForIntelligence: [{ values: [0, 1] }], statsPointsForChance: [{ values: [0, 1] }],
  statsPointsForAgility: [{ values: [0, 1] }], statsPointsForVitality: [{ values: [0, 1] }], statsPointsForWisdom: [{ values: [0, 3] }],
  breedRoles: [], maleColors: [], femaleColors: [], complexity: 2,
});

export function createClass(w: World, ranges: RangeMap, input: ClassInput): number {
  const v = check(w, input);
  const id = nextId(w, "breed", ranges.breed);
  const row = { ...BASE_ROW(), sortIndex: w.files.world.breeds.length + 1 };
  writeRow(w, ranges, id, v, row);
  rows(w)[String(id)] = row;
  w.files.world.breeds.push(id);
  if (w.files.world.default_breed === undefined) w.files.world.default_breed = id;
  bindSpells(w, id, v.spells, []);
  return id;
}

export function updateClass(w: World, ranges: RangeMap, id: number, input: ClassInput): void {
  if (!w.files.world.breeds.includes(id)) throw new AtelierError(404, `classe ${id} inconnue`);
  const v = check(w, input, id);
  const before = (classes(w)[String(id)]?.pairs ?? []).map((p) => p[0]);
  writeRow(w, ranges, id, v, rows(w)[String(id)] ?? (rows(w)[String(id)] = { ...BASE_ROW(), sortIndex: w.files.world.breeds.indexOf(id) + 1 }));
  bindSpells(w, id, v.spells, before.filter((f) => !v.spells.includes(f)));
}

export function setDefaultClass(w: World, id: number): void {
  if (!w.files.world.breeds.includes(id)) throw new AtelierError(404, `classe ${id} inconnue`);
  w.files.world.default_breed = id;
}

export function deleteClass(w: World, id: number): void {
  const wb = w.files.world;
  if (!wb.breeds.includes(id)) throw new AtelierError(404, `classe ${id} inconnue`);
  const row = rows(w)[String(id)] ?? {};
  bindSpells(w, id, [], (classes(w)[String(id)]?.pairs ?? []).map((p) => p[0]));
  wb.breeds = wb.breeds.filter((b) => b !== id);
  delete classes(w)[String(id)];
  delete rows(w)[String(id)];
  if (wb.default_breed === id) {
    if (wb.breeds.length) wb.default_breed = wb.breeds[0]; else delete wb.default_breed;
  }
  for (const k of ["shortNameId", "gameplayDescriptionId", "descriptionId"]) {
    const t = Number(row[k]);
    if (t && !textUsages(w).get(t)?.length) delete w.files.texts[String(t)];
  }
}
