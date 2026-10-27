// Dungeon editor. A dungeon is a chain of rooms (maps of the world, played in order, each one a private copy of its map),
// entered from an entrance map with a minimum level and optional keys, left on an exit map. The last room holds the boss(es).
// The game finds a boss in the `bosses` table of the monsters file, so choosing a monster as a boss copies it there (the copy
// is refreshed when the monster is edited and removed when no dungeon names it any more).
// Dungeons share the "interactive" id range with jobs, skills and gathering elements (see editors_resources.ts).
import { AtelierError } from "./errors";
import type { World } from "./io";
import { nextId, type RangeMap } from "./ranges";

export interface DungeonInput {
  name: string;
  /** level of the monsters met (and of the boss grade chosen) */
  level: number;
  /** level needed to enter */
  minLevel: number;
  /** 1..5 */
  difficulty: number;
  entrance: number;
  exit: number;
  /** maps of the rooms, in the order they are played; the last one holds the boss */
  rooms: number[];
  keys: { item: number; qty: number }[];
  /** monster ids (of the world) that wait in the last room */
  bosses: number[];
}
export interface DungeonRow extends DungeonInput {
  id: number;
  entranceName: string;
  exitName: string;
  roomNames: string[];
}

type Raw = Record<string, any>;
const bad = (m: string) => new AtelierError(400, m);
const table = (w: World) => ((w.files as Raw).dungeons ??= { dungeons: {} }).dungeons as Record<string, Raw>;
const read = (w: World) => (((w.files as Raw).dungeons?.dungeons ?? {}) as Record<string, Raw>);
const bossTable = (w: World) => w.files.monsters.bosses as Record<string, Raw>;
const mapName = (w: World, id: number) => {
  const m = w.maps.get(id) as Raw | undefined;
  return m ? (w.files.texts[String(m.name_id)] ?? m.name ?? "") : "";
};

export function listDungeons(w: World): DungeonRow[] {
  return Object.values(read(w)).map((d) => ({
    id: d.id, name: d.name ?? "", level: d.level, minLevel: d.min_level, difficulty: d.difficulty,
    entrance: d.entrance_map, exit: d.exit_map, rooms: d.maps ?? [], keys: (d.keys ?? []).map((k: Raw) => ({ item: k.item, qty: k.qty })), bosses: d.bosses ?? [],
    entranceName: mapName(w, d.entrance_map), exitName: mapName(w, d.exit_map), roomNames: (d.maps ?? []).map((m: number) => mapName(w, m)),
  }));
}

/** monster id -> the dungeons that name it as a boss. */
export function dungeonBossUsages(w: World): Map<number, number[]> {
  const out = new Map<number, number[]>();
  for (const d of Object.values(read(w))) for (const b of d.bosses ?? []) out.set(b, [...(out.get(b) ?? []), d.id]);
  return out;
}

function check(w: World, i: DungeonInput): { name: string } {
  const name = typeof i?.name === "string" ? i.name.trim() : "";
  if (!name) throw bad("nom : valeur vide");
  if (name.length > 60) throw bad("nom : 60 caractères au maximum");
  const int = (v: unknown, lo: number, hi: number, what: string) => { if (!Number.isInteger(v) || (v as number) < lo || (v as number) > hi) throw bad(`${what} : entier entre ${lo} et ${hi} attendu`); };
  int(i.level, 1, 200, "niveau");
  int(i.minLevel, 1, i.level, "niveau minimum");
  int(i.difficulty, 1, 5, "difficulté");
  if (!w.maps.has(i.entrance)) throw bad(`map d'entrée ${i.entrance} inconnue`);
  if (!w.maps.has(i.exit)) throw bad(`map de sortie ${i.exit} inconnue`);
  if (!Array.isArray(i.rooms) || i.rooms.length < 1 || i.rooms.length > 12) throw bad("salles : de 1 à 12");
  if (new Set(i.rooms).size !== i.rooms.length) throw bad("une salle est choisie deux fois");
  for (const r of i.rooms) {
    if (!w.maps.has(r)) throw bad(`salle : map ${r} inconnue`);
    if (r === i.entrance || r === i.exit) throw bad(`la map ${r} ne peut pas être à la fois une salle et l'entrée ou la sortie`);
  }
  const items = new Set(w.files.items.items.map((x) => x.id));
  if (!Array.isArray(i.keys) || i.keys.length > 4) throw bad("clés : 4 au maximum");
  const seen = new Set<number>();
  for (const k of i.keys) {
    if (!items.has(k.item)) throw bad(`clé : objet ${k.item} inconnu`);
    int(k.qty, 1, 99, "quantité de clé");
    if (seen.has(k.item)) throw bad("la même clé est donnée deux fois");
    seen.add(k.item);
  }
  const mobs = w.files.monsters.monsters as Raw;
  if (!Array.isArray(i.bosses) || i.bosses.length > 4) throw bad("boss : 4 au maximum");
  if (new Set(i.bosses).size !== i.bosses.length) throw bad("un boss est choisi deux fois");
  for (const b of i.bosses) if (!(String(b) in mobs) && !(String(b) in bossTable(w))) throw bad(`boss : monstre ${b} inconnu`);
  return { name };
}

function row(id: number, i: DungeonInput, name: string): Raw {
  return { id, name, level: i.level, min_level: i.minLevel, difficulty: i.difficulty, maps: [...i.rooms], entrance_map: i.entrance, exit_map: i.exit, keys: i.keys.map((k) => ({ item: k.item, qty: k.qty })), bosses: [...i.bosses] };
}

/** Bosses are looked up in the bosses table: copy the chosen monsters there, drop the copies nobody names any more. */
export function syncBosses(w: World): void {
  const named = new Set([...dungeonBossUsages(w).keys()]);
  const mobs = w.files.monsters.monsters as Raw;
  const bosses = bossTable(w);
  for (const b of named) if (String(b) in mobs) bosses[String(b)] = structuredClone(mobs[String(b)]);
  for (const k of Object.keys(bosses)) if (k in mobs && !named.has(Number(k))) delete bosses[k]; // a copy of ours, no longer named
}

export function createDungeon(w: World, ranges: RangeMap, input: DungeonInput): number {
  const v = check(w, input);
  const id = nextId(w, "interactive", ranges.interactive);
  table(w)[String(id)] = row(id, input, v.name);
  syncBosses(w);
  return id;
}

export function updateDungeon(w: World, id: number, input: DungeonInput): void {
  if (!(String(id) in read(w))) throw new AtelierError(404, `donjon ${id} inconnu`);
  const v = check(w, input);
  table(w)[String(id)] = row(id, input, v.name);
  syncBosses(w);
}

export function deleteDungeon(w: World, id: number): void {
  if (!(String(id) in read(w))) throw new AtelierError(404, `donjon ${id} inconnu`);
  delete table(w)[String(id)];
  syncBosses(w);
}
