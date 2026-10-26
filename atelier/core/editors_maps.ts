// Map editor: properties, the 14 x 40 grid (walls, line of sight, fight placement, rebirth cell), neighbours and
// doors. A map is saved whole (one undo step). The editor refuses what would break a rule the validator checks
// at once (a door on a wall, an interactive element left on a free cell...) so a saved map is always coherent.
import { AtelierError } from "./errors";
import type { World } from "./io";
import { addText } from "./editors";
import { CELLS, validCell } from "./grid";
import { nextId, type RangeMap } from "./ranges";
import type { MapData, MapVisual } from "./schemas";
import { textUsages } from "./usage";

export const SIDES = ["top", "bottom", "left", "right"] as const;
const OPPOSITE: Record<string, string> = { top: "bottom", bottom: "top", left: "right", right: "left" };

export interface Door { cell: number; to_map: number; to_cell: number }

export interface MapInput {
  name: string;
  coords: [number, number];
  outdoor: boolean;
  monsterSpawn: boolean;
  /** monster zone key, or null */
  zone: string | null;
  blocked: number[];
  los: number[];
  red: number[];
  blue: number[];
  /** rebirth cell, or null */
  phoenix: number | null;
  /** is this map a rebirth map of the world (world.phoenixes) */
  isPhoenix: boolean;
  neighbors: Partial<Record<(typeof SIDES)[number], number>>;
  doors: Door[];
}

export interface MapRow extends MapInput {
  id: number;
  isStart: boolean;
  startCell: number;
  npcs: number;
  interactives: number;
  usedBy: { kind: string; id: string | number }[];
}

type Raw = Record<string, any>;
const bad = (m: string) => new AtelierError(400, m);
const mapsOf = (w: World) => w.maps as Map<number, Raw>;

export function listMaps(w: World): MapRow[] {
  const refs = mapUsages(w);
  return [...w.maps.keys()].map((id) => rowOf(w, id, refs));
}

function rowOf(w: World, id: number, refs: Map<number, { kind: string; id: string | number }[]>): MapRow {
  const m = w.maps.get(id) as Raw;
  const fightBlocked = m.fight_blocked as number[] | undefined;
  return {
    id, name: w.files.texts[String(m.name_id)] ?? m.name ?? "", coords: m.coords, outdoor: !!m.outdoor, monsterSpawn: !!m.monster_spawn,
    zone: m.subarea !== undefined && m.subarea !== null ? String(m.subarea) : null,
    blocked: [...new Set([...(m.blocked ?? []), ...(fightBlocked ?? [])])].sort((a, b) => a - b), los: m.los_blocked ?? [],
    red: m.placement?.red ?? [], blue: m.placement?.blue ?? [], phoenix: m.phoenix ?? null, isPhoenix: (w.files.world.phoenixes ?? []).includes(id),
    neighbors: m.neighbors ?? {}, doors: m.triggers ?? [],
    isStart: w.files.world.start_map === id, startCell: w.files.world.start_cell,
    npcs: (w.files.npcs.maps[String(id)] ?? []).length, interactives: (w.files.interactives.maps[String(id)] ?? []).length,
    usedBy: refs.get(id) ?? [],
  };
}

/** map id -> what points at it: other maps' neighbours and doors, the world's start and rebirth lists, dialogue teleports, quests. */
export function mapUsages(w: World): Map<number, { kind: string; id: string | number }[]> {
  const out = new Map<number, { kind: string; id: string | number }[]>();
  const add = (n: number, kind: string, id: string | number) => { const l = out.get(n) ?? []; l.push({ kind, id }); out.set(n, l); };
  for (const [mid, m] of mapsOf(w)) {
    for (const to of Object.values(m.neighbors ?? {})) if (to !== mid) add(to as number, "map", mid);
    for (const t of m.triggers ?? []) if (t.to_map !== mid) add(t.to_map, "map", mid);
  }
  add(w.files.world.start_map, "world", "départ");
  for (const p of w.files.world.phoenixes ?? []) add(p, "world", "renaissance");
  for (const [nid, d] of Object.entries(w.files.dialogs.dialogs))
    for (const node of Object.values(d.nodes)) for (const r of node.replies) {
      const a = r.action as { type: string; map?: number } | undefined;
      if (a?.type === "teleport" && a.map !== undefined) add(a.map, "dialog", nid);
    }
  for (const [qid, q] of Object.entries(w.files.quests.quests)) {
    add(q.start.map, "quest", qid);
    for (const st of q.steps) for (const o of st.objectives) if (o.map) add(o.map, "quest", qid);
  }
  return out;
}

const cells = (list: unknown, what: string): number[] => {
  if (!Array.isArray(list)) throw bad(`${what} : liste attendue`);
  for (const c of list) if (!validCell(c)) throw bad(`${what} : cellule ${c} hors de la grille (0 à ${CELLS - 1})`);
  return [...new Set(list as number[])].sort((a, b) => a - b);
};

function check(w: World, id: number, i: MapInput) {
  const name = typeof i.name === "string" ? i.name.trim() : "";
  if (!name) throw bad("nom : valeur vide");
  if (name.length > 60) throw bad("nom : 60 caractères au maximum");
  if (!Array.isArray(i.coords) || i.coords.length !== 2 || !i.coords.every((n) => Number.isInteger(n) && Math.abs(n) <= 9999)) throw bad("coordonnées : deux entiers attendus");
  const blocked = cells(i.blocked, "cellules bloquées");
  const los = cells(i.los, "ligne de vue");
  const red = cells(i.red, "placement rouge");
  const blue = cells(i.blue, "placement bleu");
  const bset = new Set(blocked);
  for (const c of [...red, ...blue]) if (bset.has(c)) throw bad(`placement : la cellule ${c} est bloquée`);
  if (red.some((c) => blue.includes(c))) throw bad("placement : une cellule ne peut être à la fois rouge et bleue");
  if (i.phoenix !== null && !validCell(i.phoenix)) throw bad("case de renaissance hors de la grille");
  if (i.phoenix !== null && bset.has(i.phoenix)) throw bad("la case de renaissance est bloquée");
  if (i.isPhoenix && i.phoenix === null) throw bad("une map de renaissance a besoin d'une case de renaissance");
  if (i.zone !== null && !(i.zone in w.files.monsters.subareas)) throw bad(`zone ${i.zone} inconnue`);
  const neighbors: Record<string, number> = {};
  for (const [side, to] of Object.entries(i.neighbors ?? {})) {
    if (!(SIDES as readonly string[]).includes(side)) throw bad(`voisin « ${side} » inconnu`);
    if (to === undefined || to === null) continue;
    if (!w.maps.has(to)) throw bad(`voisin ${side} : map ${to} inconnue`);
    if (to === id) throw bad(`voisin ${side} : une map ne peut pas être sa propre voisine`);
    neighbors[side] = to;
  }
  const seen = new Set<number>();
  const doors = (i.doors ?? []).map((d) => {
    if (!validCell(d.cell) || !validCell(d.to_cell)) throw bad(`porte ${d.cell} : cellule hors de la grille`);
    if (!w.maps.has(d.to_map)) throw bad(`porte ${d.cell} : map ${d.to_map} inconnue`);
    if (bset.has(d.cell)) throw bad(`porte ${d.cell} : cellule bloquée`);
    if (seen.has(d.cell)) throw bad(`porte ${d.cell} : deux portes sur la même cellule`);
    seen.add(d.cell);
    const target = d.to_map === id ? bset : new Set((w.maps.get(d.to_map) as Raw).blocked as number[]);
    if (target.has(d.to_cell)) throw bad(`porte ${d.cell} : la cellule d'arrivée ${d.to_cell} est bloquée`);
    return { cell: d.cell, to_map: d.to_map, to_cell: d.to_cell };
  });
  if (w.files.world.start_map === id && bset.has(w.files.world.start_cell)) throw bad(`la cellule de départ du monde (${w.files.world.start_cell}) ne peut pas être bloquée`);
  for (const it of w.files.interactives.maps[String(id)] ?? []) if (!bset.has(it.cell)) throw bad(`l'élément interactif en ${it.cell} doit rester sur une cellule bloquée`);
  for (const n of w.files.npcs.maps[String(id)] ?? []) if (!bset.has(n.cell)) throw bad(`le PNJ en ${n.cell} occupe sa cellule : elle doit rester bloquée`);
  // cells other maps' doors arrive on
  for (const [mid, other] of mapsOf(w)) for (const t of other.triggers ?? []) if (mid !== id && t.to_map === id && bset.has(t.to_cell)) throw bad(`la porte de la map ${mid} arrive sur la cellule ${t.to_cell} : elle ne peut pas être bloquée`);
  return { name, blocked, los, red, blue, neighbors, doors };
}

function apply(w: World, ranges: RangeMap, id: number, m: Raw, i: MapInput, v: ReturnType<typeof check>): void {
  if (m.name_id && String(m.name_id) in w.files.texts) w.files.texts[String(m.name_id)] = v.name;
  else m.name_id = addText(w, ranges, v.name);
  Object.assign(m, {
    name: v.name, coords: i.coords, outdoor: i.outdoor, monster_spawn: i.monsterSpawn,
    blocked: v.blocked, fight_blocked: v.blocked, los_blocked: v.los, placement: { red: v.red, blue: v.blue }, triggers: v.doors,
  });
  if (i.zone !== null) { m.subarea = Number(i.zone); m.area = Number(i.zone); } else { delete m.subarea; delete m.area; }
  if (i.phoenix !== null) m.phoenix = i.phoenix; else delete m.phoenix;
  m.neighbors = v.neighbors;
  // neighbours are reciprocal: A.right = B gives B.left = A when B has none yet; a removed side is cleared on the other end
  for (const [side, to] of Object.entries(v.neighbors)) {
    const other = mapsOf(w).get(to)!;
    other.neighbors ??= {};
    if (other.neighbors[OPPOSITE[side]] === undefined) other.neighbors[OPPOSITE[side]] = id;
  }
  for (const [mid, other] of mapsOf(w))
    if (mid !== id) for (const [side, to] of Object.entries(other.neighbors ?? {}))
      if (to === id && !(OPPOSITE[side] in v.neighbors)) delete other.neighbors[side];
  const ph = new Set(w.files.world.phoenixes ?? []);
  if (i.isPhoenix) ph.add(id); else ph.delete(id);
  w.files.world.phoenixes = [...ph];
}

export function updateMap(w: World, ranges: RangeMap, id: number, input: MapInput): void {
  const m = mapsOf(w).get(id);
  if (!m) throw new AtelierError(404, `map ${id} inconnue`);
  if (!input.isPhoenix && (w.files.world.phoenixes ?? []).length === 1 && (w.files.world.phoenixes ?? [])[0] === id)
    throw new AtelierError(409, "c'est la seule map de renaissance du monde : désigne-en une autre d'abord");
  apply(w, ranges, id, m, input, check(w, id, input));
}

/** A new map; with `copyOf`, it starts as a copy of that map's grid and decor (no neighbours, doors, NPCs or fixed monster groups). */
export function createMap(w: World, ranges: RangeMap, name: string, visualTemplate: MapVisual, copyOf?: number): number {
  const n = typeof name === "string" ? name.trim() : "";
  if (!n) throw bad("nom : valeur vide");
  const src = copyOf === undefined || copyOf === null ? undefined : mapsOf(w).get(Number(copyOf));
  if (copyOf !== undefined && copyOf !== null && !src) throw new AtelierError(404, `map ${copyOf} inconnue : copie impossible`);
  const id = nextId(w, "map", ranges.map);
  if (src) {
    const m: Raw = structuredClone(src);
    for (const k of ["groups"]) delete m[k];
    Object.assign(m, { id, name: n, name_id: addText(w, ranges, n), coords: [0, 0], visual: id, neighbors: {}, triggers: [] });
    mapsOf(w).set(id, m);
    w.files.world.maps.push(id);
    w.visuals.set(id, { ...structuredClone((w.visuals.get(src.visual) ?? visualTemplate) as MapVisual), id } as MapVisual);
    return id;
  }
  const m: Raw = {
    id, name: n, name_id: addText(w, ranges, n), coords: [0, 0], visual: id, outdoor: true,
    blocked: [], fight_blocked: [], los_blocked: [], placement: { red: [], blue: [] }, neighbors: {}, triggers: [], monster_spawn: false, phoenix: 300,
  };
  mapsOf(w).set(id, m);
  w.files.world.maps.push(id);
  w.visuals.set(id, { ...structuredClone(visualTemplate), id } as MapVisual);
  return id;
}

/** A map made from a real Dofus map: its grid and decor; no links, NPCs, monster zone or fixed groups. Elements whose image is in `missing` are left out. */
export function createMapFromDofus(w: World, ranges: RangeMap, name: string, src: Raw, visual: MapVisual, missing: Set<number>): { id: number; dropped: number } {
  const n = typeof name === "string" ? name.trim() : "";
  if (!n) throw bad("nom : valeur vide");
  const id = nextId(w, "map", ranges.map);
  const cells = (l: unknown) => (Array.isArray(l) ? l.filter((c): c is number => validCell(c)) : []);
  const blocked = cells(src.blocked);
  const wall = new Set(blocked);
  const spawn = (list: unknown) => cells(list).filter((c) => !wall.has(c));
  // rebirth cell: the free cell nearest to the middle of the map
  let phoenix = 300;
  for (let d = 0; d < CELLS && wall.has(phoenix); d++) phoenix = (300 + (d % 2 ? -1 : 1) * Math.ceil(d / 2) + CELLS) % CELLS;
  const m: Raw = {
    id, name: n, name_id: addText(w, ranges, n), coords: [0, 0], visual: id, outdoor: !!src.outdoor,
    blocked, fight_blocked: cells(src.fight_blocked), los_blocked: cells(src.los_blocked),
    placement: { red: spawn(src.placement?.red), blue: spawn(src.placement?.blue) }, neighbors: {}, triggers: [], monster_spawn: false, phoenix,
  };
  mapsOf(w).set(id, m);
  w.files.world.maps.push(id);
  const v = structuredClone(visual) as Raw;
  let dropped = 0;
  for (const k of Object.keys(v.layers ?? {})) {
    const before = v.layers[k].length;
    v.layers[k] = v.layers[k].filter((e: Raw) => !missing.has(Number(e.g)));
    dropped += before - v.layers[k].length;
  }
  Object.assign(v, { id, neighbors: {}, animated: [] });
  w.visuals.set(id, v as MapVisual);
  return { id, dropped };
}

export function setStart(w: World, map: number, cell: number): void {
  const m = mapsOf(w).get(map);
  if (!m) throw new AtelierError(404, `map ${map} inconnue`);
  if (!validCell(cell) || (m.blocked as number[]).includes(cell)) throw bad("cellule de départ invalide ou bloquée");
  w.files.world.start_map = map;
  w.files.world.start_cell = cell;
}

export function deleteMap(w: World, id: number): void {
  const m = mapsOf(w).get(id);
  if (!m) throw new AtelierError(404, `map ${id} inconnue`);
  if (w.maps.size <= 1) throw new AtelierError(409, "un monde garde au moins une map");
  const refs = (mapUsages(w).get(id) ?? []).filter((r) => !(r.kind === "world" && r.id === "renaissance"));
  const npcs = (w.files.npcs.maps[String(id)] ?? []).length + (w.files.interactives.maps[String(id)] ?? []).length;
  if (refs.length) throw new AtelierError(409, `map ${id} utilisée par ${refs.slice(0, 3).map((r) => `${r.kind} ${r.id}`).join(", ")} : retire d'abord ces liens`);
  if (npcs) throw new AtelierError(409, `map ${id} : des PNJ ou éléments interactifs y sont posés, déplace-les d'abord`);
  if ((w.files.world.phoenixes ?? []).filter((p) => p !== id).length === 0) throw new AtelierError(409, "c'est la seule map de renaissance du monde");
  mapsOf(w).delete(id);
  w.files.world.maps = w.files.world.maps.filter((x) => x !== id);
  w.files.world.phoenixes = (w.files.world.phoenixes ?? []).filter((x) => x !== id);
  if (![...mapsOf(w).values()].some((o) => o.visual === m.visual)) w.visuals.delete(m.visual);
  delete w.files.npcs.maps[String(id)];
  delete w.files.interactives.maps[String(id)];
  for (const other of mapsOf(w).values()) for (const [side, to] of Object.entries(other.neighbors ?? {})) if (to === id) delete other.neighbors[side];
  if (m.name_id && !textUsages(w).get(m.name_id)?.length) delete w.files.texts[String(m.name_id)];
}

export function listZoneKeys(w: World): string[] { return Object.keys(w.files.monsters.subareas); }
