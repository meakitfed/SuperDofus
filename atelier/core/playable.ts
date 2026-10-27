// "Playable world" report: beyond the validator's references, can a player actually go through this world?
// Each check answers one question and lists what fails. Reachability follows doors, neighbours and
// NPC teleports from the start map, exactly like the W_WORLD_MAP_UNREACHABLE rule.
import type { World } from "./io";
import { reachableMaps } from "./rules_maps";

export type CheckStatus = "ok" | "warning" | "error";
export interface CheckItem { message: string; ref?: { kind: string; id: string | number } }
export interface Check { code: string; title: string; status: CheckStatus; summary: string; items: CheckItem[] }

type Raw = Record<string, any>;

interface Facts {
  reach: Set<number>;
  npcMap: Map<number, number>;
  zonesOnReachableMaps: Set<string>;
  monsterOk: Set<number>;
  questOk: Set<number>;
}

function facts(w: World): Facts {
  const reach = reachableMaps(w);
  const npcMap = new Map<number, number>();
  for (const [mid, l] of Object.entries(w.files.npcs.maps)) for (const n of l) npcMap.set(n.npc, Number(mid));
  const zones = new Set<string>();
  for (const [mid, m] of w.maps) if (reach.has(mid) && (m as Raw).monster_spawn && (m as Raw).subarea !== undefined) zones.add(String((m as Raw).subarea));
  const monsterOk = new Set<number>();
  for (const [key, z] of Object.entries(w.files.monsters.subareas)) if (zones.has(key)) for (const m of z.monsters) monsterOk.add(m);
  const questOk = new Set<number>();
  for (const q of Object.values(w.files.quests.quests)) { const m = npcMap.get(q.start.npc); if (m !== undefined && reach.has(m)) questOk.add(q.id); }
  return { reach, npcMap, zonesOnReachableMaps: zones, monsterOk, questOk };
}

const mk = (code: string, title: string, items: CheckItem[], okText: string, failText: string, severity: "warning" | "error" = "warning"): Check =>
  ({ code, title, status: items.length ? severity : "ok", summary: items.length ? failText : okText, items });

/** item id -> a reason it can be obtained, for every item that can. */
function obtainable(w: World, f: Facts): Map<number, string> {
  const out = new Map<number, string>();
  const add = (item: number, why: string) => { if (!out.has(item)) out.set(item, why); };
  const mobs = [...Object.entries(w.files.monsters.monsters), ...Object.entries(w.files.monsters.bosses)] as [string, Raw][];
  for (const [id, m] of mobs) if (f.monsterOk.has(Number(id)) || (id in w.files.monsters.bosses)) for (const g of m.grades) for (const d of g.drops) add(d.item, `butin du monstre ${id}`);
  for (const [npc, s] of Object.entries(w.files.shops.shops)) { const m = f.npcMap.get(Number(npc)); if (m !== undefined && f.reach.has(m)) for (const i of s.items) add(i, `boutique du PNJ ${npc}`); }
  for (const q of Object.values(w.files.quests.quests)) if (f.questOk.has(q.id)) for (const st of q.steps) for (const rw of st.rewards) for (const [it] of rw.items ?? []) add(it, `récompense de la quête ${q.id}`);
  for (const [nid, t] of Object.entries(w.files.dialogs.dialogs)) {
    const m = f.npcMap.get(Number(nid));
    if (m === undefined || !f.reach.has(m)) continue;
    for (const node of Object.values(t.nodes)) for (const r of node.replies) { const a = r.action as Raw | undefined; if (a?.type === "give_item") add(a.item, `don du PNJ ${nid}`); }
  }
  const skillItem = new Map(Object.values(w.files.skills.objectsById).map((s) => [s.id, s.gatheredRessourceItem]));
  const standing = new Set<number>(); // skills with an element on a reachable map (resources and workshops)
  for (const [mid, l] of Object.entries(w.files.interactives.maps)) if (f.reach.has(Number(mid))) for (const e of l) { standing.add(e.skill); const it = skillItem.get(e.skill); if (it && it > 0) add(it, `récolte sur la map ${mid}`); }
  // crafts: a recipe works when its workshop stands on a reachable map and every ingredient can be obtained; repeat until nothing new
  const recipes = Object.values(((w.files as Raw).recipes?.objectsById ?? {}) as Record<string, Raw>);
  for (let grew = true; grew;) {
    grew = false;
    for (const r of recipes) if (!out.has(r.resultId) && standing.has(r.skillId) && (r.ingredientIds as number[]).every((i) => out.has(i))) { out.set(r.resultId, `fabriqué à l'atelier ${r.skillId}`); grew = true; }
  }
  return out;
}

export function playableReport(w: World): Check[] {
  const f = facts(w);
  const wf = w.files;
  const checks: Check[] = [];
  const hasAction = (npc: number, type: string) => Object.values(wf.dialogs.dialogs[String(npc)]?.nodes ?? {}).some((n) => n.replies.some((r) => (r.action as Raw | undefined)?.type === type));

  // classes
  const classItems: CheckItem[] = [];
  const spells = wf.spells.spells as Raw[];
  for (const b of wf.world.breeds) {
    const pairs = (wf.spells.classes as Raw)[String(b)]?.pairs ?? [];
    const first = pairs.some((p: number[]) => ((wf.spells.grades as Raw)[String(p[0])] ?? []).some((g: number) => (spells.find((s) => s.id === g)?.level ?? 99) <= 1));
    if (!first) classItems.push({ message: `la classe ${b} n'a aucun sort utilisable au niveau 1`, ref: { kind: "class", id: b } });
  }
  checks.push(mk("P_CLASS_STARTER", "Chaque classe peut se battre dès le niveau 1", classItems, wf.world.breeds.length ? "Toutes les classes ont un sort de niveau 1." : "Le monde n'a pas de classe propre : il propose celles que les autres mondes ne revendiquent pas.", "Des classes naissent sans sort.", "error"));

  // monsters
  const mobItems: CheckItem[] = [];
  for (const k of Object.keys(wf.monsters.monsters)) if (!f.monsterOk.has(Number(k))) mobItems.push({ message: `le monstre ${k} n'apparaît sur aucune map atteignable (zone non attribuée, ou map sans apparition de monstres)`, ref: { kind: "monster", id: k } });
  checks.push(mk("P_MONSTER_REACHABLE", "Chaque monstre peut être rencontré", mobItems, "Tous les monstres vivent sur une map atteignable où ils apparaissent.", "Des monstres ne seront jamais rencontrés."));

  const zoneItems: CheckItem[] = [];
  for (const [k, z] of Object.entries(wf.monsters.subareas)) {
    const maps = [...w.maps.values()].filter((m) => String((m as Raw).subarea) === k);
    if (!maps.length) zoneItems.push({ message: `la zone ${k} (niveau ${z.level ?? "?"}) n'est attribuée à aucune map`, ref: { kind: "zone", id: k } });
    else if (!maps.some((m) => (m as Raw).monster_spawn)) zoneItems.push({ message: `la zone ${k} n'est sur aucune map où des monstres apparaissent`, ref: { kind: "zone", id: k } });
  }
  checks.push(mk("P_ZONE_USED", "Chaque zone de monstres sert", zoneItems, "Chaque zone est attribuée à une map avec apparitions.", "Des zones ne servent à rien."));

  // shops and banks
  const shopItems: CheckItem[] = [];
  for (const npc of Object.keys(wf.shops.shops)) if (!hasAction(Number(npc), "shop")) shopItems.push({ message: `le PNJ ${npc} vend des objets mais aucune réponse de son dialogue n'ouvre la boutique`, ref: { kind: "npc", id: npc } });
  for (const npc of (wf.bank as Raw | undefined)?.bankers ?? []) if (!hasAction(npc, "bank")) shopItems.push({ message: `le PNJ ${npc} est banquier mais aucune réponse de son dialogue n'ouvre la banque`, ref: { kind: "npc", id: npc } });
  checks.push(mk("P_SHOP_OPENABLE", "Boutiques et banques s'ouvrent", shopItems, "Chaque boutique et chaque banque a sa réponse de dialogue.", "Des boutiques ou banques sont inaccessibles."));

  // quests
  const giverItems: CheckItem[] = [];
  const targetItems: CheckItem[] = [];
  const levelItems: CheckItem[] = [];
  const got = obtainable(w, f);
  for (const q of Object.values(wf.quests.quests)) {
    const ref = { kind: "quest", id: q.id };
    if (!f.questOk.has(q.id)) giverItems.push({ message: `quête ${q.id} : son PNJ donneur ${q.start.npc} n'est pas sur une map atteignable`, ref });
    let prev = 0;
    for (const st of q.steps) {
      const lvl = (st as Raw).level ?? 1;
      if (lvl < prev) levelItems.push({ message: `quête ${q.id} : l'étape de niveau ${lvl} suit une étape de niveau ${prev}`, ref });
      prev = lvl;
      for (const o of st.objectives) {
        const npcs = [1, 9, 3].includes(o.type) ? [o.params[0]] : [];
        for (const n of npcs) { const m = f.npcMap.get(n); if (m === undefined || !f.reach.has(m)) targetItems.push({ message: `quête ${q.id} : le PNJ ${n} n'est pas atteignable`, ref }); }
        if (o.type === 4 && !f.reach.has(o.map ?? 0)) targetItems.push({ message: `quête ${q.id} : la map ${o.map} à découvrir n'est pas atteignable`, ref });
        if ([7, 14].includes(o.type) && !f.monsterOk.has(o.params[0]) && !(String(o.params[0]) in wf.monsters.bosses)) targetItems.push({ message: `quête ${q.id} : le monstre ${o.params[0]} ne peut pas être rencontré`, ref });
        if (o.type === 3 && !got.has(o.params[1])) targetItems.push({ message: `quête ${q.id} : l'objet ${o.params[1]} demandé ne peut être obtenu nulle part`, ref });
      }
    }
  }
  checks.push(mk("P_QUEST_GIVER", "Chaque quête peut être commencée", giverItems, "Tous les donneurs de quête sont atteignables.", "Des quêtes ne peuvent pas être commencées.", "error"));
  checks.push(mk("P_QUEST_TARGETS", "Chaque quête peut être terminée", targetItems, "Les PNJ, maps, monstres et objets des objectifs sont atteignables.", "Des quêtes ne peuvent pas être terminées.", "error"));
  checks.push(mk("P_QUEST_LEVELS", "Les niveaux des étapes croissent", levelItems, "Les étapes de chaque quête montent en niveau.", "Des étapes redescendent en niveau."));

  // items
  const itemItems: CheckItem[] = [];
  for (const it of wf.items.items) if (!got.has(it.id)) itemItems.push({ message: `l'objet ${it.id} ne peut être obtenu nulle part (ni butin, ni boutique, ni récompense, ni don, ni récolte)`, ref: { kind: "item", id: it.id } });
  checks.push(mk("P_ITEM_OBTAINABLE", "Chaque objet peut être obtenu", itemItems, "Chaque objet a une source atteignable.", "Des objets sont introuvables."));

  return checks;
}
