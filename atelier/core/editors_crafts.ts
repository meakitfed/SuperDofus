// Crafting. A WORKSHOP is a craft skill of a job (Forge, Cooking...) that stands on maps as an element, like a resource but giving
// nothing: the player opens it to craft. A RECIPE makes one item of the world (the key of the recipe table is the result item)
// from up to 8 items of the world, in one workshop. Files: workshop = a row of data/tables/skills.json (no gathered item),
// recipe = a row of data/tables/recipes.json, elements = interactives.json. Ids of workshops share the "interactive" range.
import { AtelierError } from "./errors";
import type { World } from "./io";
import { addText } from "./editors";
import { checkPlaces, jobsRead, lists, setPlaces, skillRow, skills, text, type Place } from "./editors_resources";
import { nextId, type RangeMap } from "./ranges";

export interface WorkshopInput { name: string; job: number; gfx: number; places: Place[] }
export interface WorkshopRow extends WorkshopInput {
  id: number;
  jobName: string;
  places: (Place & { element: number; mapName: string })[];
  recipes: number;
}
export interface RecipeInput { result: number; skill: number; ingredients: { item: number; qty: number }[] }
export interface RecipeRow {
  /** the result item id: a world has one recipe per item */
  id: number;
  resultName: string;
  skill: number;
  skillName: string;
  jobName: string;
  level: number;
  ingredients: { item: number; name: string; qty: number }[];
}

type Raw = Record<string, any>;
const bad = (m: string) => new AtelierError(400, m);
const conflict = (m: string) => new AtelierError(409, m);
const recipesTable = (w: World) => ((w.files as Raw).recipes ??= { objectsById: {} }).objectsById as Record<string, Raw>;
const recipesRead = (w: World) => (((w.files as Raw).recipes?.objectsById ?? {}) as Record<string, Raw>);
const isWorkshop = (s: Raw | undefined) => !!s && !(Number(s.gatheredRessourceItem) > 0);
const itemRaw = (w: World, id: number) => w.files.items.items.find((i) => i.id === id) as Raw | undefined;
const itemName = (w: World, id: number) => { const i = itemRaw(w, id); return i ? text(w, i.name_id) || String(i.name ?? "") : ""; };

// ---- workshops ----
export function listWorkshops(w: World): WorkshopRow[] {
  return Object.values(skills(w)).filter(isWorkshop).map((s) => {
    const places = Object.entries(lists(w)).flatMap(([mid, l]) => l.filter((e) => e.skill === s.id).map((e) => {
      const m = w.maps.get(Number(mid)) as Raw | undefined;
      return { map: Number(mid), cell: e.cell as number, element: e.e as number, mapName: text(w, m?.name_id) || String(m?.name ?? "") };
    }));
    return {
      id: s.id, name: text(w, s.nameId), job: s.parentJobId, jobName: text(w, jobsRead(w)[String(s.parentJobId)]?.nameId),
      gfx: Number(s.gfx ?? Object.values(lists(w)).flat().find((e) => e.skill === s.id)?.gfx ?? 0), places,
      recipes: Object.values(recipesRead(w)).filter((r) => r.skillId === s.id).length,
    };
  });
}

function checkWorkshop(w: World, i: WorkshopInput, probe: (rel: string) => boolean, self?: number): string {
  const name = typeof i?.name === "string" ? i.name.trim() : "";
  if (!name) throw bad("nom : valeur vide");
  if (name.length > 60) throw bad("nom : 60 caractères au maximum");
  if (!(String(i.job) in jobsRead(w))) throw bad(`métier ${i.job} inconnu : crée-le d'abord`);
  checkPlaces(w, i, probe, self);
  return name;
}

const workshopRow = (id: number, nameId: number, i: WorkshopInput): Raw => ({ ...skillRow(id, nameId, { name: "", job: i.job, item: -1, level: 1, gfx: i.gfx, places: [] }), gatheredRessourceItem: -1 });

export function createWorkshop(w: World, ranges: RangeMap, input: WorkshopInput, probe: (rel: string) => boolean): number {
  const name = checkWorkshop(w, input, probe);
  const id = nextId(w, "interactive", ranges.interactive);
  skills(w)[String(id)] = workshopRow(id, addText(w, ranges, name), input);
  setPlaces(w, ranges, id, input.gfx, input.places);
  return id;
}

export function updateWorkshop(w: World, ranges: RangeMap, id: number, input: WorkshopInput, probe: (rel: string) => boolean): void {
  const s = skills(w)[String(id)];
  if (!isWorkshop(s)) throw new AtelierError(404, `atelier ${id} inconnu`);
  const name = checkWorkshop(w, input, probe, id);
  Object.assign(s, { parentJobId: input.job, gfx: input.gfx });
  for (const r of Object.values(recipesRead(w))) if (r.skillId === id) r.jobId = input.job;
  if (String(s.nameId) in w.files.texts) w.files.texts[String(s.nameId)] = name; else s.nameId = addText(w, ranges, name);
  setPlaces(w, ranges, id, input.gfx, input.places);
}

export function deleteWorkshop(w: World, id: number): void {
  const s = skills(w)[String(id)];
  if (!isWorkshop(s)) throw new AtelierError(404, `atelier ${id} inconnu`);
  const used = Object.values(recipesRead(w)).filter((r) => r.skillId === id);
  if (used.length) throw conflict(`atelier utilisé par ${used.length} recette(s) : supprime-les d'abord`);
  const all = lists(w);
  for (const [mid, l] of Object.entries(all)) { all[mid] = l.filter((e) => e.skill !== id); if (!all[mid].length) delete all[mid]; }
  delete skills(w)[String(id)];
  delete w.files.texts[String(s.nameId)];
}

// ---- recipes ----
export function listRecipes(w: World): RecipeRow[] {
  return Object.values(recipesRead(w)).map((r) => ({
    id: r.resultId, resultName: itemName(w, r.resultId), skill: r.skillId, skillName: text(w, skills(w)[String(r.skillId)]?.nameId),
    jobName: text(w, jobsRead(w)[String(r.jobId)]?.nameId), level: r.resultLevel,
    ingredients: (r.ingredientIds as number[]).map((item, k) => ({ item, name: itemName(w, item), qty: (r.quantities as number[])[k] })),
  }));
}

/** item id -> the recipes that use it as an ingredient (a blocker for deleting the item). */
export function recipeUsages(w: World): Map<number, number[]> {
  const out = new Map<number, number[]>();
  for (const r of Object.values(recipesRead(w))) for (const item of [r.resultId, ...(r.ingredientIds as number[])]) out.set(item, [...(out.get(item) ?? []), r.resultId]);
  return out;
}

const signature = (ings: { item: number; qty: number }[]) => [...ings].sort((a, b) => a.item - b.item).map((x) => `${x.item}:${x.qty}`).join(",");

function checkRecipe(w: World, i: RecipeInput, isNew: boolean): void {
  if (!itemRaw(w, i.result)) throw bad(`objet fabriqué ${i.result} inconnu`);
  if (isNew && String(i.result) in recipesRead(w)) throw conflict(`l'objet ${i.result} a déjà une recette`);
  if (!isWorkshop(skills(w)[String(i.skill)])) throw bad(`atelier ${i.skill} inconnu`);
  if (!Array.isArray(i.ingredients) || i.ingredients.length < 1 || i.ingredients.length > 8) throw bad("ingrédients : de 1 à 8");
  const seen = new Set<number>();
  for (const g of i.ingredients) {
    if (!itemRaw(w, g.item)) throw bad(`ingrédient : objet ${g.item} inconnu`);
    if (!Number.isInteger(g.qty) || g.qty < 1 || g.qty > 999) throw bad("quantité d'ingrédient : entier entre 1 et 999 attendu");
    if (g.item === i.result) throw bad("un objet ne peut pas être son propre ingrédient");
    if (seen.has(g.item)) throw bad("le même ingrédient est donné deux fois (augmente sa quantité)");
    seen.add(g.item);
  }
  // two recipes of one workshop with the same ingredients would be one and the same for the game
  for (const r of Object.values(recipesRead(w)))
    if (r.skillId === i.skill && r.resultId !== i.result && signature(r.ingredientIds.map((item: number, k: number) => ({ item, qty: r.quantities[k] }))) === signature(i.ingredients))
      throw conflict(`la recette de l'objet ${r.resultId} utilise déjà exactement ces ingrédients dans cet atelier`);
}

function writeRecipe(w: World, i: RecipeInput): void {
  const skill = skills(w)[String(i.skill)];
  recipesTable(w)[String(i.result)] = {
    id: i.result, resultId: i.result, resultLevel: itemRaw(w, i.result)!.level, ingredientIds: i.ingredients.map((g) => g.item),
    quantities: i.ingredients.map((g) => g.qty), jobId: skill.parentJobId, skillId: i.skill,
  };
}

export function createRecipe(w: World, input: RecipeInput): number {
  checkRecipe(w, input, true);
  writeRecipe(w, input);
  return input.result;
}

export function updateRecipe(w: World, id: number, input: RecipeInput): void {
  if (!(String(id) in recipesRead(w))) throw new AtelierError(404, `recette ${id} inconnue`);
  if (input.result !== id) throw bad("l'objet fabriqué ne change pas : supprime la recette et refais-en une");
  checkRecipe(w, input, false);
  writeRecipe(w, input);
}

export function deleteRecipe(w: World, id: number): void {
  if (!(String(id) in recipesRead(w))) throw new AtelierError(404, `recette ${id} inconnue`);
  delete recipesTable(w)[String(id)];
}
