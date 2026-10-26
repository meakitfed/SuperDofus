// The Dofus monsters (game/worlds/dofus/monsters.json, names from the client's texts) as templates: stats, look and
// portrait come along; spells and drops do not, since they would point at things that are not in the new world.
import fs from "node:fs";
import { AtelierError } from "./errors";
import type { GradeInput, MonsterInput } from "./editors_monsters";
import { readI18n } from "./dofus_text";

export interface MonsterTemplate extends MonsterInput { source: number; portrait: number }
export const MONSTER_TEMPLATE_LIMIT = 30;
const fold = (s: string) => s.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();

interface Row { id: number; name: string; key: string; raw: { grades: Record<string, any>[] } }
let cache: { file: string; rows: Row[] } | null = null;

function rowsOf(monstersFile: string, i18nFile: string): Row[] {
  if (cache?.file === monstersFile) return cache.rows;
  if (!fs.existsSync(monstersFile) || !fs.existsSync(i18nFile)) throw new AtelierError(404, "les monstres du jeu ne sont pas sur cet ordinateur (game/worlds/dofus et game/content)");
  const text = readI18n(i18nFile);
  const data = JSON.parse(fs.readFileSync(monstersFile, "utf-8")) as { monsters: Record<string, { name_id: number; grades: Record<string, any>[] }> };
  const rows = Object.entries(data.monsters).map(([id, m]) => {
    const name = text(m.name_id);
    return { id: Number(id), name, key: fold(name), raw: m };
  }).filter((r) => r.name);
  cache = { file: monstersFile, rows };
  return rows;
}

const look = (s: string) => { const [b, , , size] = String(s ?? "").replace(/[{}]/g, "").split("|"); return { bone: Number(b) || 0, size: Number(size) || 100 }; };
const num = (v: unknown, d = 0) => (Number.isFinite(Number(v)) ? Number(v) : d);

export function searchDofusMonsters(monstersFile: string, i18nFile: string, query: string): MonsterTemplate[] {
  const q = fold(query.trim());
  if (q.length < 2) throw new AtelierError(400, "recherche : au moins 2 caractères (un nom de monstre, ou un numéro)");
  const byNumber = /^\d+$/.test(q);
  const hits = rowsOf(monstersFile, i18nFile).filter((r) => (byNumber ? String(r.id) === q : r.key.includes(q)));
  hits.sort((a, b) => (a.key.startsWith(q) === b.key.startsWith(q) ? a.name.localeCompare(b.name) : a.key.startsWith(q) ? -1 : 1));
  return hits.slice(0, MONSTER_TEMPLATE_LIMIT).map((r) => {
    const first = r.raw.grades[0] ?? {};
    const { bone, size } = look(first.look);
    const grades: GradeInput[] = r.raw.grades.slice(0, 5).map((g) => ({
      level: Math.max(1, Math.min(200, num(g.level, 1))), hp: Math.max(1, num(g.hp, 1)), ap: num(g.ap, 6), mp: num(g.mp, 3), xp: Math.max(0, num(g.xp)),
      stats: { strength: num(g.stats?.strength), intelligence: num(g.stats?.intelligence), chance: num(g.stats?.chance), agility: num(g.stats?.agility), wisdom: num(g.stats?.wisdom), ap_dodge: num(g.stats?.ap_dodge), mp_dodge: num(g.stats?.mp_dodge) },
      res: { earth: num(g.res?.earth), fire: num(g.res?.fire), water: num(g.res?.water), air: num(g.res?.air), neutral: num(g.res?.neutral) },
      spells: [], drops: [], kamas: [num(g.kamas?.[0]), num(g.kamas?.[1])] as [number, number],
      aggro: { zone: num(g.aggro?.zone, 2), level_diff: num(g.aggro?.level_diff, 60), delay: num(g.aggro?.delay, 8000) },
    }));
    return { source: r.id, name: r.name, bone, size, portrait: num(first.portrait), grades, zones: [] } as MonsterTemplate;
  });
}
