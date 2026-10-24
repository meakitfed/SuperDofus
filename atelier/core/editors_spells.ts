// Spell editor: "simple" spells (one grade; damage, heal, shield, AP / MP gain or loss). Spells the generators
// wrote with richer effects (push, glyph, summon...) stay editable on their header fields; their effect list is
// kept untouched and shown as locked. A spell here is one grade (the castable thing, id in the world's spell
// range) and its own family id (what the spell book and the class pairs talk about).
import { AtelierError } from "./errors";
import type { World } from "./io";
import { nextId, type RangeMap } from "./ranges";
import { addText } from "./editors";
import { textUsages, type Ref } from "./usage";

export const SIMPLE_KINDS = ["damage", "heal", "shield", "ap", "mp"] as const;
export const ELEMENTS = ["neutral", "earth", "fire", "water", "air"] as const;
export const TARGETS = ["enemies", "allies", "all", "caster"] as const;
export const SHAPES = ["point", "circle", "cross", "line", "ring"] as const;
const MASK: Record<string, string> = { enemies: "A", allies: "a", all: "a,A", caster: "C" };

export interface EffectInput {
  kind: (typeof SIMPLE_KINDS)[number];
  target: (typeof TARGETS)[number];
  min: number;
  max: number;
  element?: (typeof ELEMENTS)[number];
  /** turns (shield, ap, mp) */
  duration?: number;
  /** ap / mp: +1 gain, -1 loss */
  sign?: 1 | -1;
  area?: { shape: (typeof SHAPES)[number]; size: number };
}

export interface SpellInput {
  name: string;
  description?: string;
  icon: number;
  level: number;
  ap: number;
  range: [number, number];
  los: boolean;
  inLine: boolean;
  perTurn: number;
  cooldown: number;
  /** crit chance, % */
  crit: number;
  color: string;
  area: { shape: (typeof SHAPES)[number]; size: number };
  /** left out = keep the spell's current effects (the only choice for a locked spell) */
  effects?: EffectInput[];
}

export interface SpellRow extends Omit<SpellInput, "effects"> {
  id: number;
  family: number;
  effects: EffectInput[];
  locked: boolean;
  /** kinds of the effects that the simple editor cannot show */
  complexKinds: string[];
  usedBy: Ref[];
}

type Raw = Record<string, any>;
const bad = (m: string) => new AtelierError(400, m);
const spellsOf = (w: World): Raw[] => w.files.spells.spells as Raw[];

const isSimple = (e: Raw): boolean =>
  (SIMPLE_KINDS as readonly string[]).includes(e.kind) && Object.values(MASK).includes(e.mask) && e.area?.shape !== undefined;

/** Who needs this grade / family: class slots, monsters, summons, other spells' sub-spells. */
export function spellUsages(w: World): Map<number, Ref[]> {
  const out = new Map<number, Ref[]>();
  const add = (n: number, r: Ref) => {
    const l = out.get(n) ?? [];
    if (!l.some((x) => x.kind === r.kind && x.id === r.id)) l.push(r);
    out.set(n, l);
  };
  const f = w.files;
  for (const [breed, c] of Object.entries(f.spells.classes)) for (const p of c.pairs) for (const s of p) add(s, { kind: "class", id: breed });
  for (const [k, m] of [...Object.entries(f.monsters.monsters), ...Object.entries(f.monsters.bosses)])
    for (const g of m.grades) for (const s of g.spells) add(s, { kind: "monster", id: k });
  for (const [k, sm] of Object.entries(f.spells.summons)) for (const g of sm.grades) for (const s of g.spells) add(s, { kind: "summon", id: k });
  for (const s of spellsOf(w)) for (const e of [...s.effects, ...(s.crit_effects ?? [])]) if (e.spell) add(e.spell, { kind: "spell", id: s.id });
  return out;
}

const toEffectInput = (e: Raw): EffectInput => ({
  kind: e.kind, target: e.target, min: e.min, max: e.max, element: e.element, duration: e.duration, sign: e.sign, area: e.area,
});

export function listSpells(w: World): SpellRow[] {
  const used = spellUsages(w);
  return spellsOf(w).map((s) => {
    const complexKinds = [...new Set((s.effects as Raw[]).filter((e) => !isSimple(e)).map((e) => String(e.kind)))];
    const refs = [...(used.get(s.id) ?? []), ...(used.get(s.spell ?? -1) ?? [])];
    return {
      id: s.id, family: s.spell ?? s.id,
      name: w.files.texts[String(s.name_id)] ?? s.name ?? "", description: w.files.texts[String(s.description_id)] ?? "",
      icon: s.icon ?? s.id, level: s.level ?? 1, ap: s.ap ?? 0, range: s.range ?? [1, 1], los: !!s.los, inLine: !!s.in_line,
      perTurn: s.per_turn ?? 0, cooldown: s.cooldown ?? 0, crit: s.crit ?? 0, color: s.fx?.color ?? "#d8d4e0", area: s.area ?? { shape: "point", size: 0 },
      effects: complexKinds.length ? [] : (s.effects as Raw[]).map(toEffectInput), locked: complexKinds.length > 0, complexKinds, usedBy: refs,
    };
  });
}

function check(i: SpellInput) {
  const int = (n: unknown, what: string, min: number, max: number) => {
    if (!Number.isInteger(n) || (n as number) < min || (n as number) > max) throw bad(`${what} : entier entre ${min} et ${max} attendu`);
    return n as number;
  };
  const name = typeof i.name === "string" ? i.name.trim() : "";
  if (!name) throw bad("nom : valeur vide");
  if (name.length > 80) throw bad("nom : 80 caractères au maximum");
  const range = [int(i.range?.[0], "portée min", 0, 63), int(i.range?.[1], "portée max", 0, 63)] as [number, number];
  if (range[1] < range[0]) throw bad("portée : le maximum est inférieur au minimum");
  const area = checkArea(i.area, "zone du sort");
  if (!/^#[0-9a-fA-F]{6}$/.test(i.color ?? "")) throw bad("couleur : #rrggbb attendu");
  const effects = i.effects?.map(checkEffect);
  if (effects && effects.length > 8) throw bad("8 effets au maximum");
  return {
    name, range, area, effects, color: i.color,
    icon: int(i.icon, "icône", 1, 2_147_483_647), level: int(i.level, "niveau", 1, 200), ap: int(i.ap, "PA", 0, 20),
    perTurn: int(i.perTurn, "lancers par tour", 0, 20), cooldown: int(i.cooldown, "délai de relance", 0, 20), crit: int(i.crit, "critique", 0, 100),
    description: i.description?.trim() || undefined, los: !!i.los, inLine: !!i.inLine,
  };
}

function checkArea(a: SpellInput["area"] | undefined, what: string) {
  if (!a || !(SHAPES as readonly string[]).includes(a.shape)) throw bad(`${what} : forme inconnue`);
  if (!Number.isInteger(a.size) || a.size < 0 || a.size > 10) throw bad(`${what} : taille entre 0 et 10`);
  return { shape: a.shape, size: a.size };
}

function checkEffect(e: EffectInput): Raw {
  if (!(SIMPLE_KINDS as readonly string[]).includes(e.kind)) throw bad(`effet « ${e.kind} » non géré par l'éditeur simple`);
  if (!(TARGETS as readonly string[]).includes(e.target)) throw bad("effet : cible inconnue");
  if (!Number.isInteger(e.min) || !Number.isInteger(e.max) || e.min < 0 || e.max < e.min || e.max > 9999) throw bad("effet : valeurs min / max invalides");
  const base: Raw = { target: e.target, min: e.min, max: e.max, duration: 0, delay: 0, area: checkArea(e.area ?? { shape: "point", size: 0 }, "zone de l'effet"), mask: MASK[e.target], kind: e.kind };
  if (e.kind === "damage" || e.kind === "heal") {
    if (!(ELEMENTS as readonly string[]).includes(e.element ?? "")) throw bad("effet : élément inconnu");
    base.element = e.element;
  } else {
    const d = e.duration ?? 1;
    if (!Number.isInteger(d) || d < 0 || d > 20) throw bad("effet : durée entre 0 et 20 tours");
    base.duration = d;
    if (e.kind === "shield") base.of = "max_hp";
    else { base.sign = e.sign === -1 ? -1 : 1; base.dodge = base.sign === -1; base.dispellable = 3; }
  }
  return base;
}

/** Critical hits hit harder: +30 % on damage and heals, the rest unchanged. */
const critOf = (effects: Raw[]): Raw[] =>
  effects.map((e) => (e.kind === "damage" || e.kind === "heal" ? { ...e, min: Math.round(e.min * 1.3), max: Math.round(e.max * 1.3) } : { ...e }));

function apply(w: World, ranges: RangeMap, s: Raw, v: ReturnType<typeof check>): void {
  const texts = w.files.texts;
  if (s.name_id && String(s.name_id) in texts) texts[String(s.name_id)] = v.name; else s.name_id = addText(w, ranges, v.name);
  if (v.description) {
    if (s.description_id && String(s.description_id) in texts) texts[String(s.description_id)] = v.description;
    else s.description_id = addText(w, ranges, v.description);
  } else if (s.description_id) {
    const d = s.description_id;
    delete s.description_id;
    if (!textUsages(w).get(d)?.length) delete texts[String(d)];
  }
  Object.assign(s, {
    name: v.name, icon: v.icon, level: v.level, ap: v.ap, range: v.range, los: v.los, in_line: v.inLine, per_turn: v.perTurn,
    cooldown: v.cooldown, crit: v.crit, area: v.area, fx: { type: "impact", color: v.color },
  });
  if (v.effects) {
    s.effects = v.effects;
    s.crit_effects = critOf(v.effects);
  }
}

export function createSpell(w: World, ranges: RangeMap, input: SpellInput): number {
  const v = check(input);
  if (!v.effects?.length) throw bad("un sort a besoin d'au moins un effet");
  const family = nextId(w, "spell", ranges.spell);
  const grade = family + 1;
  const s: Raw = {
    id: grade, spell: family, origin: family, grade: 1, range_boost: false, need_free_cell: false, need_taken_cell: false, per_target: 99,
    initial_cooldown: 0, anim: ["AnimAttaque0"], max_stack: 0, bar: false, effects: [], crit_effects: [],
  };
  apply(w, ranges, s, v);
  spellsOf(w).push(s);
  (w.files.spells.grades as Record<string, number[]>)[String(family)] = [grade];
  return grade;
}

export function updateSpell(w: World, ranges: RangeMap, id: number, input: SpellInput): void {
  const s = spellsOf(w).find((x) => x.id === id);
  if (!s) throw new AtelierError(404, `sort ${id} inconnu`);
  const locked = (s.effects as Raw[]).some((e) => !isSimple(e));
  if (locked && input.effects) throw new AtelierError(409, "ce sort a des effets que l'éditeur simple ne sait pas modifier : seuls ses réglages le sont");
  if (!locked && !input.effects?.length) throw bad("un sort a besoin d'au moins un effet");
  apply(w, ranges, s, check(input));
}

export function deleteSpell(w: World, id: number): void {
  const list = spellsOf(w);
  const idx = list.findIndex((x) => x.id === id);
  if (idx < 0) throw new AtelierError(404, `sort ${id} inconnu`);
  const s = list[idx];
  const used = spellUsages(w);
  const refs = [...(used.get(s.id) ?? []), ...(used.get(s.spell ?? -1) ?? [])];
  if (refs.length) throw new AtelierError(409, `sort ${id} utilisé par ${refs.slice(0, 3).map((r) => `${r.kind} ${r.id}`).join(", ")} : retire d'abord ces références`);
  list.splice(idx, 1);
  const grades = w.files.spells.grades as Record<string, number[]>;
  const fam = String(s.spell ?? s.id);
  if (grades[fam]) {
    grades[fam] = grades[fam].filter((g) => g !== id);
    if (!grades[fam].length) delete grades[fam];
  }
  for (const t of [s.name_id, s.description_id]) if (t && !textUsages(w).get(t)?.length) delete w.files.texts[String(t)];
}
