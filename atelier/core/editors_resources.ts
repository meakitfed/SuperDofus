// Resources a player gathers: a JOB (a trade, e.g. Woodcutter), a RESOURCE (a gathering skill of a job that yields one item
// at a level, e.g. Ash: wood) and the PLACES where it stands on the maps (an interactive element per place, with its picture).
// In the files: jobs = data/tables/jobs.json, a resource = a row of data/tables/skills.json, a place = an entry of interactives.json.
// Jobs, skills and elements share one numbering (the "interactive" range of the world). An element occupies its cell,
// like an NPC: the editor blocks it. Removing an element leaves its cell blocked (free it in the map editor).
import { AtelierError } from "./errors";
import type { World } from "./io";
import { addText } from "./editors";
import { validCell } from "./grid";
import { nextId, type RangeMap } from "./ranges";

export interface Place { map: number; cell: number }
export interface ResourceInput {
  name: string;
  /** job id (a job of the world) */
  job: number;
  /** item id (an item of the world) the gathering yields */
  item: number;
  /** job level needed, 1..200 */
  level: number;
  /** picture of the elements: a map tile image id */
  gfx: number;
  places: Place[];
}
export interface ResourceRow extends ResourceInput {
  id: number;
  jobName: string;
  itemName: string;
  places: (Place & { element: number; mapName: string })[];
}
export interface JobInput { name: string }
export interface JobRow extends JobInput { id: number; resources: number }

type Raw = Record<string, any>;
const bad = (m: string) => new AtelierError(400, m);
const lists = (w: World) => w.files.interactives.maps as Record<string, Raw[]>;
const skills = (w: World) => w.files.skills.objectsById as Record<string, Raw>;
const jobsTable = (w: World) => ((w.files as Raw).jobs ??= { objectsById: {} }).objectsById as Record<string, Raw>;
const jobsRead = (w: World) => (((w.files as Raw).jobs?.objectsById ?? {}) as Record<string, Raw>);
const text = (w: World, id: unknown) => w.files.texts[String(id)] ?? "";

/** The skills that gather something (the others, such as crafts, are not resources). */
const gathering = (w: World) => Object.values(skills(w)).filter((s) => Number(s.gatheredRessourceItem) > 0);

// ---- jobs ----
export function listJobs(w: World): JobRow[] {
  return Object.values(jobsRead(w)).map((j) => ({ id: j.id, name: text(w, j.nameId), resources: gathering(w).filter((s) => s.parentJobId === j.id).length }));
}

function jobName(raw: unknown): string {
  const n = typeof raw === "string" ? raw.trim() : "";
  if (!n) throw bad("nom : valeur vide");
  if (n.length > 60) throw bad("nom : 60 caractères au maximum");
  return n;
}

export function createJob(w: World, ranges: RangeMap, input: JobInput): number {
  const name = jobName(input?.name);
  const id = nextId(w, "interactive", ranges.interactive);
  jobsTable(w)[String(id)] = { id, nameId: addText(w, ranges, name), iconId: 0, hasLegendaryCraft: 0 };
  return id;
}

export function updateJob(w: World, ranges: RangeMap, id: number, input: JobInput): void {
  const j = jobsRead(w)[String(id)];
  if (!j) throw new AtelierError(404, `métier ${id} inconnu`);
  const name = jobName(input?.name);
  if (String(j.nameId) in w.files.texts) w.files.texts[String(j.nameId)] = name; else j.nameId = addText(w, ranges, name);
}

export function deleteJob(w: World, id: number): void {
  const j = jobsRead(w)[String(id)];
  if (!j) throw new AtelierError(404, `métier ${id} inconnu`);
  const used = gathering(w).filter((s) => s.parentJobId === id);
  if (used.length) throw new AtelierError(409, `métier utilisé par ${used.length} ressource(s) : supprime-les d'abord`);
  delete jobsTable(w)[String(id)];
  delete w.files.texts[String(j.nameId)];
}

// ---- resources ----
export function listResources(w: World): ResourceRow[] {
  const items = new Map(w.files.items.items.map((i) => [i.id, i as Raw]));
  return gathering(w).map((s) => {
    const places = Object.entries(lists(w)).flatMap(([mid, l]) => l.filter((e) => e.skill === s.id).map((e) => ({ map: Number(mid), cell: e.cell as number, element: e.e as number, mapName: text(w, (w.maps.get(Number(mid)) as Raw | undefined)?.name_id) || (w.maps.get(Number(mid)) as Raw | undefined)?.name || "" })));
    const itemRaw = items.get(s.gatheredRessourceItem);
    return {
      id: s.id, name: text(w, s.nameId), job: s.parentJobId, jobName: text(w, jobsRead(w)[String(s.parentJobId)]?.nameId), item: s.gatheredRessourceItem,
      itemName: itemRaw ? text(w, itemRaw.name_id) || String(itemRaw.name ?? "") : "", level: s.levelMin ?? 1,
      gfx: Number(s.gfx ?? Object.values(lists(w)).flat().find((e) => e.skill === s.id)?.gfx ?? 0), places,
    };
  });
}

function check(w: World, i: ResourceInput, probe: (rel: string) => boolean, self?: number): { name: string } {
  const name = typeof i?.name === "string" ? i.name.trim() : "";
  if (!name) throw bad("nom : valeur vide");
  if (name.length > 60) throw bad("nom : 60 caractères au maximum");
  if (!(String(i.job) in jobsRead(w))) throw bad(`métier ${i.job} inconnu : crée-le d'abord`);
  if (!w.files.items.items.some((x) => x.id === i.item)) throw bad(`objet ${i.item} inconnu : la ressource donne un objet du monde`);
  if (!Number.isInteger(i.level) || i.level < 1 || i.level > 200) throw bad("niveau : entier entre 1 et 200 attendu");
  if (!Number.isInteger(i.gfx) || i.gfx < 1) throw bad("image : requise");
  if (!probe(`Maps/Gfx/${i.gfx}.png`) && !probe(`Maps/Gfx/${i.gfx}.webp`)) throw bad(`image ${i.gfx} introuvable : importe-la d'abord dans les tuiles`);
  if (!Array.isArray(i.places) || i.places.length > 60) throw bad("emplacements : 60 au maximum");
  const seen = new Set<string>();
  for (const p of i.places) {
    const m = w.maps.get(p.map) as Raw | undefined;
    if (!m) throw bad(`map ${p.map} inconnue`);
    if (!validCell(p.cell)) throw bad(`cellule ${p.cell} hors de la grille`);
    const key = `${p.map}/${p.cell}`;
    if (seen.has(key)) throw bad(`la cellule ${p.cell} de la map ${p.map} est choisie deux fois`);
    seen.add(key);
    const taken = [
      ...(w.files.npcs.maps[String(p.map)] ?? []).map((n) => n.cell),
      ...(lists(w)[String(p.map)] ?? []).filter((e) => e.skill !== self).map((e) => e.cell),
    ];
    if (taken.includes(p.cell)) throw new AtelierError(409, `la cellule ${p.cell} de la map ${p.map} est déjà occupée`);
    if ((m.triggers ?? []).some((t: Raw) => t.cell === p.cell)) throw new AtelierError(409, `la cellule ${p.cell} est une porte`);
    if (w.files.world.start_map === p.map && w.files.world.start_cell === p.cell) throw new AtelierError(409, "la cellule de départ du monde ne peut pas porter de ressource");
    if (m.phoenix === p.cell) throw new AtelierError(409, "la cellule de renaissance ne peut pas porter de ressource");
  }
  return { name };
}

/** The element occupies its cell: blocked for walking and fighting, and not a placement cell. */
function occupy(w: World, p: Place): void {
  const m = w.maps.get(p.map) as Raw;
  for (const k of ["blocked", "fight_blocked"]) if (Array.isArray(m[k]) && !m[k].includes(p.cell)) m[k] = [...m[k], p.cell].sort((a: number, b: number) => a - b);
  for (const side of ["red", "blue"]) if (m.placement?.[side]) m.placement[side] = m.placement[side].filter((c: number) => c !== p.cell);
}

function setPlaces(w: World, ranges: RangeMap, skill: number, gfx: number, places: Place[]): void {
  const all = lists(w);
  // keep the elements that stay (same map and cell: their id does not change), drop the others, add the new ones
  for (const [mid, l] of Object.entries(all)) {
    all[mid] = l.filter((e) => e.skill !== skill || places.some((p) => String(p.map) === mid && p.cell === e.cell));
    if (!all[mid].length) delete all[mid];
  }
  for (const p of places) {
    const here = (all[String(p.map)] ??= []);
    const mine = here.find((e) => e.skill === skill && e.cell === p.cell);
    if (mine) { mine.gfx = gfx; continue; }
    here.push({ e: nextId(w, "interactive", ranges.interactive), cell: p.cell, gfx, skill });
  }
  for (const p of places) occupy(w, p);
}

function skillRow(id: number, nameId: number, i: ResourceInput): Raw {
  return {
    id, nameId, parentJobId: i.job, isForgemagus: 0, modifiableItemTypeIds: [], gatheredRessourceItem: i.item, craftableItemIds: [],
    range: 1, useRangeInClient: 0, useAnimation: "AnimAttaque0", cursor: 5, elementActionId: 1, availableInHouse: 0, clientDisplay: 1,
    levelMin: i.level, allowMarking: 0, gfx: i.gfx,
  };
}

export function createResource(w: World, ranges: RangeMap, input: ResourceInput, probe: (rel: string) => boolean): number {
  const v = check(w, input, probe);
  const id = nextId(w, "interactive", ranges.interactive);
  skills(w)[String(id)] = skillRow(id, addText(w, ranges, v.name), input);
  setPlaces(w, ranges, id, input.gfx, input.places);
  return id;
}

export function updateResource(w: World, ranges: RangeMap, id: number, input: ResourceInput, probe: (rel: string) => boolean): void {
  const s = skills(w)[String(id)];
  if (!s || !(Number(s.gatheredRessourceItem) > 0)) throw new AtelierError(404, `ressource ${id} inconnue`);
  const v = check(w, input, probe, id);
  Object.assign(s, { parentJobId: input.job, gatheredRessourceItem: input.item, levelMin: input.level, gfx: input.gfx });
  if (String(s.nameId) in w.files.texts) w.files.texts[String(s.nameId)] = v.name; else s.nameId = addText(w, ranges, v.name);
  setPlaces(w, ranges, id, input.gfx, input.places);
}

export function deleteResource(w: World, id: number): void {
  const s = skills(w)[String(id)];
  if (!s || !(Number(s.gatheredRessourceItem) > 0)) throw new AtelierError(404, `ressource ${id} inconnue`);
  const all = lists(w);
  for (const [mid, l] of Object.entries(all)) {
    all[mid] = l.filter((e) => e.skill !== id);
    if (!all[mid].length) delete all[mid];
  }
  delete skills(w)[String(id)];
  delete w.files.texts[String(s.nameId)];
}
