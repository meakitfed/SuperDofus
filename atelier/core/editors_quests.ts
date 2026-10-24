// Quest editor: a giver NPC, steps in order, each with objectives (talk, bring items, discover a map, beat a
// monster, go back to an NPC), a reward (XP and kamas ratios, items). The objective texts shown in the quest log
// (`args`) are built from the names the target already has, so no text is typed twice. A quest that uses
// objective or reward kinds the form does not know stays visible and locked: its data is never rewritten.
import { AtelierError } from "./errors";
import type { World } from "./io";
import { addText } from "./editors";
import { nextId, type RangeMap } from "./ranges";
import { criteriaRefs } from "./rules_story";
import { textUsages, type Ref } from "./usage";

export type ObjectiveInput =
  | { id?: number; type: 1 | 9; npc: number }
  | { id?: number; type: 3; npc: number; item: number; qty: number }
  | { id?: number; type: 4; map: number }
  | { id?: number; type: 7; monster: number }
  | { id?: number; type: 14; monster: number; qty: number };

export interface StepInput {
  id?: number;
  name: string;
  desc: string;
  level: number;
  objectives: ObjectiveInput[];
  reward: { xp: number; kamas: number; items: [number, number][] };
}

export interface QuestInput {
  name: string;
  /** NPC who offers the quest (placed on a map; the map is read from there) */
  giver: number;
  levelMin: number;
  /** 0 once, 1 again at once, 2 / 3 once a day */
  repeat: number;
  steps: StepInput[];
}

export interface QuestRow extends QuestInput {
  id: number;
  locked: boolean;
  lockedWhy: string[];
  usedBy: Ref[];
}

type Raw = Record<string, any>;
const bad = (m: string) => new AtelierError(400, m);
const quests = (w: World) => w.files.quests.quests as Record<string, Raw>;
const SIMPLE = [1, 3, 4, 7, 9, 14];

function giverMap(w: World, npc: number): number | undefined {
  for (const [mid, l] of Object.entries(w.files.npcs.maps)) if (l.some((n) => n.npc === npc)) return Number(mid);
  return undefined;
}
const npcNameId = (w: World, npc: number): number | undefined => {
  for (const l of Object.values(w.files.npcs.maps)) { const n = l.find((x) => x.npc === npc); if (n) return n.name_id; }
  return undefined;
};
const monsterRaw = (w: World, id: number): Raw | undefined => (w.files.monsters.monsters as Raw)[String(id)] ?? (w.files.monsters.bosses as Raw)[String(id)];

export function questUsages(w: World): Map<number, Ref[]> {
  const out = new Map<number, Ref[]>();
  for (const [nid, d] of Object.entries(w.files.dialogs.dialogs))
    for (const node of Object.values(d.nodes)) for (const r of node.replies)
      for (const [k, v] of criteriaRefs(r.criteria)) if (k === "Qf") (out.get(v) ?? out.set(v, []).get(v)!).push({ kind: "dialog", id: nid });
  return out;
}

const text = (w: World, id: unknown) => w.files.texts[String(id)] ?? "";

function toObjective(o: Raw): ObjectiveInput | null {
  const base = { id: o.id };
  switch (o.type) {
    case 1: case 9: return { ...base, type: o.type, npc: o.params[0] };
    case 3: return { ...base, type: 3, npc: o.params[0], item: o.params[1], qty: o.params[2] };
    case 4: return { ...base, type: 4, map: o.map };
    case 7: return { ...base, type: 7, monster: o.params[0] };
    case 14: return { ...base, type: 14, monster: o.params[0], qty: o.params[1] };
    default: return null;
  }
}

export function listQuests(w: World): QuestRow[] {
  const used = questUsages(w);
  return Object.values(quests(w)).map((q) => {
    const why = new Set<string>();
    const steps = (q.steps as Raw[]).map((s) => {
      const objectives = (s.objectives as Raw[]).flatMap((o) => { const x = toObjective(o); if (!x) why.add(`objectif de type ${o.type}`); return x ? [x] : []; });
      for (const r of s.rewards as Raw[]) {
        for (const k of ["emotes", "spells", "titles", "jobs"]) if ((r[k] ?? []).length) why.add(`récompense « ${k} »`);
      }
      if ((s.rewards as Raw[]).length > 1) why.add("plusieurs récompenses par étape");
      const r0 = (s.rewards as Raw[])[0] ?? {};
      return { id: s.id, name: text(w, s.name_id), desc: text(w, s.desc_id), level: s.level ?? 1, objectives, reward: { xp: r0.xp ?? 0, kamas: r0.kamas ?? 0, items: (r0.items ?? []) as [number, number][] } };
    });
    return {
      id: q.id, name: text(w, q.name_id), giver: q.start.npc, levelMin: q.level_min ?? 1, repeat: q.repeat ?? 0, steps,
      locked: why.size > 0, lockedWhy: [...why], usedBy: used.get(q.id) ?? [],
    };
  }).sort((a, b) => a.id - b.id);
}

function check(w: World, i: QuestInput) {
  const name = typeof i.name === "string" ? i.name.trim() : "";
  if (!name || name.length > 80) throw bad("nom : 1 à 80 caractères");
  const map = giverMap(w, i.giver);
  if (map === undefined) throw bad(`le PNJ ${i.giver} n'est placé sur aucune map`);
  if (!Number.isInteger(i.levelMin) || i.levelMin < 1 || i.levelMin > 200) throw bad("niveau minimal : entier entre 1 et 200 attendu");
  if (![0, 1, 2, 3].includes(i.repeat)) throw bad("répétition inconnue");
  if (!Array.isArray(i.steps) || i.steps.length < 1 || i.steps.length > 10) throw bad("1 à 10 étapes attendues");
  const itemIds = new Set(w.files.items.items.map((x) => x.id));
  const num = (n: unknown, what: string, min: number, max: number) => {
    if (!Number.isInteger(n) || (n as number) < min || (n as number) > max) throw bad(`${what} : entier entre ${min} et ${max} attendu`);
    return n as number;
  };
  const steps = i.steps.map((s, n) => {
    const tag = `étape ${n + 1}`;
    const sname = typeof s.name === "string" ? s.name.trim() : "";
    const desc = typeof s.desc === "string" ? s.desc.trim() : "";
    if (!sname || sname.length > 80) throw bad(`${tag} : titre de 1 à 80 caractères`);
    if (!desc || desc.length > 600) throw bad(`${tag} : description de 1 à 600 caractères`);
    if (!Array.isArray(s.objectives) || s.objectives.length < 1 || s.objectives.length > 6) throw bad(`${tag} : 1 à 6 objectifs attendus`);
    for (const o of s.objectives) {
      const need = (cond: boolean, msg: string) => { if (!cond) throw bad(`${tag} : ${msg}`); };
      if (o.type === 1 || o.type === 9 || o.type === 3) need(giverMap(w, o.npc) !== undefined, `PNJ ${o.npc} non placé`);
      if (o.type === 3) { need(itemIds.has(o.item), `objet ${o.item} inconnu`); num(o.qty, `${tag} : quantité`, 1, 999); }
      if (o.type === 4) need(w.maps.has(o.map), `map ${o.map} inconnue`);
      if (o.type === 7 || o.type === 14) need(!!monsterRaw(w, o.monster), `monstre ${o.monster} inconnu`);
      if (o.type === 14) num(o.qty, `${tag} : nombre de monstres`, 1, 999);
      if (![1, 3, 4, 7, 9, 14].includes((o as Raw).type)) throw bad(`${tag} : type d'objectif inconnu`);
    }
    const r = s.reward ?? { xp: 0, kamas: 0, items: [] };
    if (typeof r.xp !== "number" || r.xp < 0 || r.xp > 100 || typeof r.kamas !== "number" || r.kamas < 0 || r.kamas > 100) throw bad(`${tag} : XP et kamas, ratios entre 0 et 100`);
    for (const [it, qty] of r.items ?? []) { if (!itemIds.has(it)) throw bad(`${tag} : récompense, objet ${it} inconnu`); num(qty, `${tag} : quantité de récompense`, 1, 999); }
    return { ...s, name: sname, desc, level: num(s.level, `${tag} : niveau`, 1, 200), reward: { xp: r.xp, kamas: r.kamas, items: r.items ?? [] } };
  });
  return { name, map, steps };
}

/** The params / args / map the engine and the quest log read, for one objective. */
function objectiveRaw(w: World, o: ObjectiveInput, id: number, old?: Raw): Raw {
  const targetName = (t?: number) => ({ t: t as number });
  const type = o.type;
  let map = 0, params: number[] = [], args: Raw[] = [];
  if (o.type === 1 || o.type === 9) { params = [o.npc]; args = [targetName(npcNameId(w, o.npc))]; map = giverMap(w, o.npc)!; }
  else if (o.type === 3) {
    params = [o.npc, o.item, o.qty];
    args = [targetName(npcNameId(w, o.npc)), targetName(w.files.items.items.find((x) => x.id === o.item)!.name_id), { n: o.qty }];
    map = giverMap(w, o.npc)!;
  } else if (o.type === 4) { map = o.map; args = [targetName((w.maps.get(o.map) as Raw).name_id)]; }
  else if (o.type === 7) { params = [o.monster]; args = [targetName(monsterRaw(w, o.monster)!.name_id)]; }
  else if (o.type === 14) { params = [o.monster, o.qty]; args = [targetName(monsterRaw(w, o.monster)!.name_id), { n: o.qty }]; }
  return { ...(old ?? {}), id, type, map, params, args };
}

function rewardRaw(r: StepInput["reward"], old?: Raw): Raw {
  return { level_min: -1, level_max: -1, scale: 0, emotes: [], spells: [], titles: [], jobs: [], ...(old ?? {}), xp: r.xp, kamas: r.kamas, items: r.items.map(([a, b]) => [a, b]) };
}

function writeText(w: World, ranges: RangeMap, holder: Raw, key: string, value: string): void {
  if (holder[key] && String(holder[key]) in w.files.texts) w.files.texts[String(holder[key])] = value;
  else holder[key] = addText(w, ranges, value);
}

function writeSteps(w: World, ranges: RangeMap, q: Raw, v: ReturnType<typeof check>): void {
  const old = (q.steps ?? []) as Raw[];
  const keep = new Set(v.steps.map((s) => s.id).filter(Boolean));
  for (const s of old) if (!keep.has(s.id)) for (const k of ["name_id", "desc_id"]) { const t = s[k]; delete s[k]; if (t && !textUsages(w).get(t)?.length) delete w.files.texts[String(t)]; }
  const steps: Raw[] = [];
  for (const s of v.steps) {
    const cur = old.find((x) => x.id === s.id);
    const step: Raw = cur ? { ...cur } : { id: nextStepId(w, ranges, steps) };
    writeText(w, ranges, step, "name_id", s.name);
    writeText(w, ranges, step, "desc_id", s.desc);
    step.level = s.level;
    const objs: Raw[] = [];
    for (const o of s.objectives) {
      const prev = o.id ? ((cur?.objectives ?? []) as Raw[]).find((x) => x.id === o.id) : undefined;
      objs.push(objectiveRaw(w, o, prev ? prev.id : nextObjectiveId(w, ranges, [...steps, step], objs), prev));
    }
    step.objectives = objs;
    step.rewards = [rewardRaw(s.reward, cur?.rewards?.[0])];
    steps.push(step);
  }
  q.steps = steps;
}

const allIds = (w: World, extraSteps: Raw[], extraObjs: Raw[]) => ({
  steps: [...Object.values(quests(w)).flatMap((q) => (q.steps as Raw[]).map((s) => s.id as number)), ...extraSteps.map((s) => s.id as number)],
  objs: [...Object.values(quests(w)).flatMap((q) => (q.steps as Raw[]).flatMap((s) => (s.objectives as Raw[]).map((o) => o.id as number))), ...extraSteps.flatMap((s) => ((s.objectives ?? []) as Raw[]).map((o) => o.id as number)), ...extraObjs.map((o) => o.id as number)],
});
function nextIn(used: number[], range: [number, number], what: string): number {
  const inRange = used.filter((n) => n >= range[0] && n <= range[1]);
  const next = inRange.length ? Math.max(...inRange) + 1 : range[0];
  if (next > range[1]) throw new AtelierError(409, `plage d'ids épuisée pour « ${what} »`);
  return next;
}
const nextStepId = (w: World, ranges: RangeMap, pending: Raw[]) => nextIn(allIds(w, pending, []).steps, ranges.step, "étape");
const nextObjectiveId = (w: World, ranges: RangeMap, pendingSteps: Raw[], pendingObjs: Raw[]) => nextIn(allIds(w, pendingSteps, pendingObjs).objs, ranges.objective, "objectif");

export function createQuest(w: World, ranges: RangeMap, input: QuestInput): number {
  const v = check(w, input);
  const id = nextId(w, "quest", ranges.quest);
  const q: Raw = { id, category: 1, level_min: input.levelMin, level_max: 0, criteria: "BT=1", repeat: input.repeat, start: { npc: input.giver, map: v.map }, steps: [] };
  writeText(w, ranges, q, "name_id", v.name);
  writeSteps(w, ranges, q, v);
  quests(w)[String(id)] = q;
  return id;
}

export function updateQuest(w: World, ranges: RangeMap, id: number, input: QuestInput): void {
  const q = quests(w)[String(id)];
  if (!q) throw new AtelierError(404, `quête ${id} inconnue`);
  if (listQuests(w).find((x) => x.id === id)!.locked) throw new AtelierError(409, "cette quête utilise des éléments que l'éditeur ne gère pas : elle est en lecture seule");
  const v = check(w, input);
  writeText(w, ranges, q, "name_id", v.name);
  Object.assign(q, { level_min: input.levelMin, repeat: input.repeat, start: { npc: input.giver, map: v.map } });
  writeSteps(w, ranges, q, v);
}

export function deleteQuest(w: World, id: number): void {
  const q = quests(w)[String(id)];
  if (!q) throw new AtelierError(404, `quête ${id} inconnue`);
  const refs = questUsages(w).get(id) ?? [];
  if (refs.length) throw new AtelierError(409, `quête ${id} utilisée par ${refs.slice(0, 3).map((r) => `${r.kind} ${r.id}`).join(", ")} : retire d'abord ces critères`);
  delete quests(w)[String(id)];
  for (const t of [q.name_id, ...(q.steps as Raw[]).flatMap((s) => [s.name_id, s.desc_id])]) if (t && !textUsages(w).get(t)?.length) delete w.files.texts[String(t)];
}

export const SIMPLE_OBJECTIVES = SIMPLE;
