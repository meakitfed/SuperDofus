// Who references a text or an item: what the editors check before a deletion, and what they show as "utilisé par".
import type { World } from "./io";
import { criteriaRefs } from "./rules_story";

export interface Ref { kind: string; id: string | number }

function collect(): { map: Map<number, Ref[]>; add: (n: number | null | undefined, ref: Ref) => void } {
  const map = new Map<number, Ref[]>();
  const add = (n: number | null | undefined, ref: Ref) => {
    if (!n) return;
    const l = map.get(n) ?? [];
    if (!l.some((r) => r.kind === ref.kind && r.id === ref.id)) l.push(ref);
    map.set(n, l);
  };
  return { map, add };
}

/** text id -> the things whose name or description it is. */
export function textUsages(w: World): Map<number, Ref[]> {
  const { map, add } = collect();
  const f = w.files;
  for (const s of f.spells.spells) add(s.name_id, { kind: "spell", id: s.id });
  for (const [k, s] of Object.entries(f.spells.summons)) add(s.name_id, { kind: "summon", id: k });
  for (const it of f.items.items) {
    add(it.name_id, { kind: "item", id: it.id });
    add(it.description_id, { kind: "item", id: it.id });
  }
  for (const [k, r] of Object.entries(f.breeds.objectsById) as [string, Record<string, unknown>][])
    for (const key of ["shortNameId", "gameplayDescriptionId", "descriptionId"]) add(Number(r[key]), { kind: "class", id: k });
  for (const [mid, m] of w.maps) add((m as { name_id?: number }).name_id, { kind: "map", id: mid });
  for (const st of f.items.sets) add(st.name_id, { kind: "set", id: st.id });
  for (const [k, m] of [...Object.entries(f.monsters.monsters), ...Object.entries(f.monsters.bosses)]) add(m.name_id, { kind: "monster", id: k });
  for (const lst of Object.values(f.npcs.maps)) for (const n of lst) add(n.name_id, { kind: "npc", id: n.npc });
  for (const [qid, q] of Object.entries(f.quests.quests)) {
    add(q.name_id, { kind: "quest", id: qid });
    for (const st of q.steps) {
      add(st.name_id, { kind: "quest", id: qid });
      add(st.desc_id, { kind: "quest", id: qid });
      for (const o of st.objectives) for (const a of o.args ?? []) if ("t" in a) add(a.t as number, { kind: "quest", id: qid });
    }
  }
  return map;
}

/** item id -> who needs it (set membership is kept in step by the editor, so it is not a blocker). */
export function itemUsages(w: World): Map<number, Ref[]> {
  const { map, add } = collect();
  const f = w.files;
  for (const [k, m] of [...Object.entries(f.monsters.monsters), ...Object.entries(f.monsters.bosses)])
    for (const g of m.grades) for (const d of g.drops) add(d.item, { kind: "monster", id: k });
  for (const [npc, s] of Object.entries(f.shops.shops)) for (const i of s.items) add(i, { kind: "shop", id: npc });
  for (const sk of Object.values(f.skills.objectsById)) if (sk.gatheredRessourceItem > 0) add(sk.gatheredRessourceItem, { kind: "skill", id: sk.id });
  for (const r of Object.values(((f as unknown as { recipes?: { objectsById: Record<string, { resultId: number; ingredientIds: number[] }> } }).recipes?.objectsById) ?? {})) for (const it of [r.resultId, ...r.ingredientIds]) add(it, { kind: "recipe", id: r.resultId });
  for (const [qid, q] of Object.entries(f.quests.quests))
    for (const st of q.steps) for (const rw of st.rewards) for (const [it] of rw.items ?? []) add(it, { kind: "quest", id: qid });
  for (const [nid, t] of Object.entries(f.dialogs.dialogs))
    for (const node of Object.values(t.nodes))
      for (const r of node.replies) {
        for (const [k, v] of criteriaRefs(r.criteria)) if (k === "PO") add(v, { kind: "dialog", id: nid });
        const a = r.action as { type: string; item?: number } | undefined;
        if (a?.type === "give_item") add(a.item, { kind: "dialog", id: nid });
      }
  return map;
}
