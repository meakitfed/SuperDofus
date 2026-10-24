// Monster editor: a monster = a name, a skeleton ("look"), a portrait, 1 to 5 grades (level, stats, resistances,
// spells, drops, kamas, aggression) and the monster zones it appears in. Bosses are listed but stay read-only here.
import { AtelierError } from "./errors";
import type { World } from "./io";
import { addText } from "./editors";
import { nextId, type RangeMap } from "./ranges";
import { textUsages, type Ref } from "./usage";

export interface GradeInput {
  level: number;
  hp: number;
  ap: number;
  mp: number;
  xp: number;
  stats: { strength: number; intelligence: number; chance: number; agility: number; wisdom: number; ap_dodge: number; mp_dodge: number };
  res: { earth: number; fire: number; water: number; air: number; neutral: number };
  /** castable grade ids (spell editor) */
  spells: number[];
  drops: { item: number; pct: number }[];
  kamas: [number, number];
  aggro: { zone: number; level_diff: number; delay: number };
}

export interface MonsterInput {
  name: string;
  /** skeleton id, an existing Content/Characters/Bones/<id> */
  bone: number;
  /** size, % */
  size: number;
  portrait: number;
  grades: GradeInput[];
  /** monster zone keys the monster appears in */
  zones: string[];
}

export interface MonsterRow extends MonsterInput {
  id: number;
  boss: boolean;
  usedBy: Ref[];
}

export interface ZoneRow { key: string; level: number; monsters: number[] }

type Raw = Record<string, any>;
const bad = (m: string) => new AtelierError(400, m);
const all = (w: World): [string, Raw, boolean][] => [
  ...Object.entries(w.files.monsters.monsters).map(([k, m]) => [k, m as Raw, false] as [string, Raw, boolean]),
  ...Object.entries(w.files.monsters.bosses).map(([k, m]) => [k, m as Raw, true] as [string, Raw, boolean]),
];
const subareas = (w: World) => w.files.monsters.subareas as Record<string, { level?: number; area?: number; monsters: number[] }>;

const DEFAULT_GRADE: GradeInput = {
  level: 1, hp: 20, ap: 6, mp: 3, xp: 50,
  stats: { strength: 0, intelligence: 0, chance: 0, agility: 0, wisdom: 0, ap_dodge: 0, mp_dodge: 0 },
  res: { earth: 0, fire: 0, water: 0, air: 0, neutral: 0 },
  spells: [], drops: [], kamas: [0, 0], aggro: { zone: 2, level_diff: 60, delay: 8000 },
};
export const newGrade = (): GradeInput => structuredClone(DEFAULT_GRADE);

/** monster id -> who needs it: the zones it is in, and the dungeon / quest data that name it. */
export function monsterUsages(w: World): Map<number, Ref[]> {
  const out = new Map<number, Ref[]>();
  const add = (n: number, r: Ref) => { const l = out.get(n) ?? []; l.push(r); out.set(n, l); };
  for (const [sa, z] of Object.entries(subareas(w))) for (const m of z.monsters) add(m, { kind: "zone", id: sa });
  for (const [qid, q] of Object.entries(w.files.quests.quests))
    for (const st of q.steps) for (const o of st.objectives) if (o.type === 14 || o.type === 7) add(o.params[0], { kind: "quest", id: qid });
  return out;
}

const lookOf = (bone: number, size: number) => `{${bone}|||${size}}`;
const parseLook = (look: string): { bone: number; size: number } => {
  const [b, , , s] = look.replace(/[{}]/g, "").split("|");
  return { bone: Number(b), size: Number(s) || 100 };
};

export function listMonsters(w: World): MonsterRow[] {
  const used = monsterUsages(w);
  return all(w).map(([k, m, boss]) => {
    const id = Number(k);
    const g0 = m.grades[0] ?? {};
    const { bone, size } = parseLook(g0.look ?? "{0|||100}");
    return {
      id, boss, name: w.files.texts[String(m.name_id)] ?? m.name ?? "", bone, size, portrait: g0.portrait ?? 0,
      grades: (m.grades as Raw[]).map((g) => ({
        level: g.level, hp: g.hp ?? 0, ap: g.ap ?? 6, mp: g.mp ?? 3, xp: g.xp ?? 0,
        stats: { ...DEFAULT_GRADE.stats, ...(g.stats ?? {}) }, res: { ...DEFAULT_GRADE.res, ...(g.res ?? {}) },
        spells: g.spells, drops: g.drops, kamas: g.kamas ?? [0, 0], aggro: { ...DEFAULT_GRADE.aggro, ...(g.aggro ?? {}) },
      })),
      zones: Object.entries(subareas(w)).filter(([, z]) => z.monsters.includes(id)).map(([key]) => key),
      usedBy: used.get(id) ?? [],
    };
  });
}

export function listZones(w: World): ZoneRow[] {
  return Object.entries(subareas(w)).map(([key, z]) => ({ key, level: z.level ?? 1, monsters: z.monsters }));
}

function check(w: World, i: MonsterInput) {
  const name = typeof i.name === "string" ? i.name.trim() : "";
  if (!name) throw bad("nom : valeur vide");
  if (name.length > 80) throw bad("nom : 80 caractères au maximum");
  const int = (n: unknown, what: string, min: number, max: number) => {
    if (!Number.isInteger(n) || (n as number) < min || (n as number) > max) throw bad(`${what} : entier entre ${min} et ${max} attendu`);
    return n as number;
  };
  if (!Array.isArray(i.grades) || i.grades.length < 1 || i.grades.length > 5) throw bad("1 à 5 grades attendus");
  const spellIds = new Set((w.files.spells.spells as Raw[]).map((s) => s.id));
  const itemIds = new Set(w.files.items.items.map((x) => x.id));
  let prev = 0;
  const grades = i.grades.map((g, n) => {
    const tag = `grade ${n + 1}`;
    const level = int(g.level, `${tag} : niveau`, 1, 200);
    if (level < prev) throw bad(`${tag} : les niveaux des grades doivent croître`);
    prev = level;
    for (const s of g.spells) if (!spellIds.has(s)) throw bad(`${tag} : sort ${s} inconnu`);
    if (new Set(g.spells).size !== g.spells.length) throw bad(`${tag} : sort en double`);
    for (const d of g.drops) {
      if (!itemIds.has(d.item)) throw bad(`${tag} : objet ${d.item} inconnu`);
      if (typeof d.pct !== "number" || d.pct <= 0 || d.pct > 100) throw bad(`${tag} : chance de butin entre 0 et 100 %`);
    }
    if (g.kamas[1] < g.kamas[0]) throw bad(`${tag} : kamas, maximum inférieur au minimum`);
    const stats = Object.fromEntries(Object.entries(g.stats).map(([k, v]) => [k, int(v, `${tag} : ${k}`, 0, 9999)]));
    const res = Object.fromEntries(Object.entries(g.res).map(([k, v]) => [k, int(v, `${tag} : résistance ${k}`, -100, 100)]));
    return {
      level, stats, res, spells: g.spells, drops: g.drops.map((d) => ({ item: d.item, pct: d.pct })),
      hp: int(g.hp, `${tag} : vie`, 1, 999_999), ap: int(g.ap, `${tag} : PA`, 0, 20), mp: int(g.mp, `${tag} : PM`, 0, 20),
      xp: int(g.xp, `${tag} : xp`, 0, 100_000_000), kamas: [int(g.kamas[0], `${tag} : kamas`, 0, 1e9), int(g.kamas[1], `${tag} : kamas`, 0, 1e9)],
      aggro: { zone: int(g.aggro.zone, `${tag} : rayon d'agression`, 0, 20), level_diff: int(g.aggro.level_diff, `${tag} : écart de niveau`, 0, 200), delay: int(g.aggro.delay, `${tag} : délai`, 0, 600_000) },
    };
  });
  for (const z of i.zones) if (!(z in subareas(w))) throw bad(`zone ${z} inconnue`);
  return { name, grades, bone: int(i.bone, "squelette", 1, 2_147_483_647), size: int(i.size, "taille", 20, 400), portrait: int(i.portrait, "portrait", 1, 2_147_483_647), zones: [...new Set(i.zones)] };
}

function writeGrades(m: Raw, id: number, v: ReturnType<typeof check>): void {
  const old = (m.grades ?? []) as Raw[];
  m.grades = v.grades.map((g, n) => ({
    ...(old[n] ?? {}), monster: id, name_id: m.name_id, name: v.name, look: lookOf(v.bone, v.size), portrait: v.portrait, grade: n + 1, ...g,
  }));
  m.name = v.name;
}

function placeIn(w: World, id: number, zones: string[]): void {
  for (const [key, z] of Object.entries(subareas(w))) {
    z.monsters = z.monsters.filter((x) => x !== id);
    if (zones.includes(key)) z.monsters.push(id);
  }
}

export function createMonster(w: World, ranges: RangeMap, input: MonsterInput): number {
  const v = check(w, input);
  const id = nextId(w, "monster", ranges.monster);
  const m: Raw = { name_id: addText(w, ranges, v.name), name: v.name, race: 0, grades: [] };
  writeGrades(m, id, v);
  (w.files.monsters.monsters as Raw)[String(id)] = m;
  placeIn(w, id, v.zones);
  return id;
}

function find(w: World, id: number): [Raw, boolean] {
  const hit = all(w).find(([k]) => Number(k) === id);
  if (!hit) throw new AtelierError(404, `monstre ${id} inconnu`);
  return [hit[1], hit[2]];
}

export function updateMonster(w: World, id: number, input: MonsterInput): void {
  const [m, boss] = find(w, id);
  if (boss) throw new AtelierError(409, "les boss ne sont pas modifiables ici");
  const v = check(w, input);
  if (m.name_id && String(m.name_id) in w.files.texts) w.files.texts[String(m.name_id)] = v.name;
  writeGrades(m, id, v);
  placeIn(w, id, v.zones);
}

export function deleteMonster(w: World, id: number): void {
  const [m, boss] = find(w, id);
  if (boss) throw new AtelierError(409, "les boss ne sont pas modifiables ici");
  const refs = (monsterUsages(w).get(id) ?? []).filter((r) => r.kind !== "zone");
  if (refs.length) throw new AtelierError(409, `monstre ${id} utilisé par ${refs.map((r) => `${r.kind} ${r.id}`).join(", ")} : retire d'abord ces références`);
  placeIn(w, id, []);
  delete (w.files.monsters.monsters as Raw)[String(id)];
  if (m.name_id && !textUsages(w).get(m.name_id)?.length) delete w.files.texts[String(m.name_id)];
}

// ---- zones ----
export function createZone(w: World, ranges: RangeMap, level: number): string {
  if (!Number.isInteger(level) || level < 1 || level > 200) throw bad("niveau de zone : entier entre 1 et 200 attendu");
  // zone keys count down from the top of the monster range, monster ids count up from the bottom: they never meet
  const keys = Object.keys(subareas(w)).map(Number).filter((n) => n >= ranges.monster[0] && n <= ranges.monster[1]);
  const key = keys.length ? Math.min(...keys) - 1 : ranges.monster[1];
  subareas(w)[String(key)] = { level, area: key, monsters: [] };
  return String(key);
}

export function deleteZone(w: World, key: string): void {
  const z = subareas(w)[key];
  if (!z) throw new AtelierError(404, `zone ${key} inconnue`);
  if (z.monsters.length) throw new AtelierError(409, `zone ${key} non vide : retire d'abord ses monstres`);
  const used = [...w.maps.values()].filter((m) => String((m as Raw).subarea) === key);
  if (used.length) throw new AtelierError(409, `zone ${key} utilisée par la map ${used[0].id}`);
  delete subareas(w)[key];
}
