// Rules on NPCs, dialogues, shops and quests, plus identifier hygiene.
import type { Rule } from "./problems";
import { collectIds, KINDS } from "./ranges";

const PART = /^(Qf|PO)=(\d+)$/;

/** "Qf=930004&PO=9100120" -> [["Qf", 930004], ["PO", 9100120]]; other criteria (BT=1...) are ignored. */
export function criteriaRefs(crit: string | undefined): [string, number][] {
  const out: [string, number][] = [];
  for (const part of (crit ?? "").replace(/\|/g, "&").split("&")) {
    const m = PART.exec(part.trim());
    if (m) out.push([m[1], Number(m[2])]);
  }
  return out;
}

const dref = (id: string) => ({ kind: "dialog", id });
const qref = (id: string | number) => ({ kind: "quest", id });

/** Walks the dialog graph from `start`; returns the node keys it can reach. */
export function reachableNodes(tree: { start: string; nodes: Record<string, { replies: { next?: string | null }[] }> }): Set<string> {
  const seen = new Set<string>();
  const stack = [tree.start];
  while (stack.length) {
    const k = stack.pop()!;
    if (seen.has(k) || !(k in tree.nodes)) continue;
    seen.add(k);
    for (const r of tree.nodes[k].replies) if (r.next) stack.push(r.next);
  }
  return seen;
}

export const storyRules: Rule[] = [
  {
    code: "E_DIALOG_NPC", severity: "error",
    doc: "Un dialogue appartient à un PNJ placé sur une map.",
    run({ npcIds, w, report }) {
      for (const nid of Object.keys(w.files.dialogs.dialogs)) if (!npcIds.has(Number(nid))) report("E_DIALOG_NPC", `dialogue d'un PNJ non placé : ${nid}`, dref(nid));
    },
  },
  {
    code: "E_DIALOG_START", severity: "error",
    doc: "Le nœud de départ d'un dialogue existe.",
    run({ w, report }) {
      for (const [nid, t] of Object.entries(w.files.dialogs.dialogs)) if (!(t.start in t.nodes)) report("E_DIALOG_START", `dialogue ${nid} : nœud de départ ${t.start} absent`, dref(nid));
    },
  },
  {
    code: "E_DIALOG_NODE", severity: "error",
    doc: "Chaque réponse mène à un nœud existant.",
    run({ w, report }) {
      for (const [nid, t] of Object.entries(w.files.dialogs.dialogs))
        for (const node of Object.values(t.nodes))
          for (const r of node.replies) if (r.next && !(r.next in t.nodes)) report("E_DIALOG_NODE", `dialogue ${nid} : nœud ${r.next} inconnu`, dref(nid));
    },
  },
  {
    code: "W_DIALOG_ORPHAN", severity: "warning",
    doc: "Chaque nœud d'un dialogue est atteignable depuis le départ.",
    run({ w, report }) {
      for (const [nid, t] of Object.entries(w.files.dialogs.dialogs)) {
        const seen = reachableNodes(t);
        for (const k of Object.keys(t.nodes)) if (!seen.has(k)) report("W_DIALOG_ORPHAN", `dialogue ${nid} : le nœud ${k} n'est jamais atteint`, dref(nid));
      }
    },
  },
  {
    code: "E_DIALOG_TELEPORT", severity: "error",
    doc: "Une action de téléportation vise une map du monde.",
    run({ w, mapIds, report }) {
      for (const [nid, t] of Object.entries(w.files.dialogs.dialogs))
        for (const node of Object.values(t.nodes))
          for (const r of node.replies) {
            const a = r.action as { type: string; map?: number } | undefined;
            if (a?.type === "teleport" && !mapIds.has(a.map as number)) report("E_DIALOG_TELEPORT", `dialogue ${nid} : téléportation vers la map inconnue ${a.map}`, dref(nid));
          }
    },
  },
  {
    code: "E_DIALOG_GIVE_ITEM", severity: "error",
    doc: "Une action de don d'objet vise un objet existant.",
    run({ w, itemIds, report }) {
      for (const [nid, t] of Object.entries(w.files.dialogs.dialogs))
        for (const node of Object.values(t.nodes))
          for (const r of node.replies) {
            const a = r.action as { type: string; item?: number } | undefined;
            if (a?.type === "give_item" && !itemIds.has(a.item as number)) report("E_DIALOG_GIVE_ITEM", `dialogue ${nid} : objet donné ${a.item} inconnu`, dref(nid));
          }
    },
  },
  {
    code: "E_DIALOG_CRIT_QUEST", severity: "error",
    doc: "Un critère Qf=<id> vise une quête existante.",
    run({ w, questIds, report }) {
      for (const [nid, t] of Object.entries(w.files.dialogs.dialogs))
        for (const node of Object.values(t.nodes))
          for (const r of node.replies)
            for (const [k, v] of criteriaRefs(r.criteria)) if (k === "Qf" && !questIds.has(v)) report("E_DIALOG_CRIT_QUEST", `dialogue ${nid} : critère sur la quête inconnue ${v}`, dref(nid));
    },
  },
  {
    code: "E_DIALOG_CRIT_ITEM", severity: "error",
    doc: "Un critère PO=<id> vise un objet existant.",
    run({ w, itemIds, report }) {
      for (const [nid, t] of Object.entries(w.files.dialogs.dialogs))
        for (const node of Object.values(t.nodes))
          for (const r of node.replies)
            for (const [k, v] of criteriaRefs(r.criteria)) if (k === "PO" && !itemIds.has(v)) report("E_DIALOG_CRIT_ITEM", `dialogue ${nid} : critère sur l'objet inconnu ${v}`, dref(nid));
    },
  },
  {
    code: "E_SHOP_NPC", severity: "error",
    doc: "Une boutique appartient à un PNJ placé.",
    run({ w, npcIds, report }) {
      for (const nid of Object.keys(w.files.shops.shops)) if (!npcIds.has(Number(nid))) report("E_SHOP_NPC", `boutique d'un PNJ non placé : ${nid}`, { kind: "shop", id: nid });
    },
  },
  {
    code: "E_SHOP_ITEM", severity: "error",
    doc: "Une boutique ne vend que des objets existants.",
    run({ w, itemIds, report }) {
      for (const [nid, s] of Object.entries(w.files.shops.shops))
        for (const i of s.items) if (!itemIds.has(i)) report("E_SHOP_ITEM", `boutique ${nid} : objet ${i} inconnu`, { kind: "shop", id: nid });
    },
  },
  {
    code: "E_QUEST_GIVER", severity: "error",
    doc: "Le PNJ donneur d'une quête est placé sur la map indiquée.",
    run({ w, report }) {
      for (const [qid, q] of Object.entries(w.files.quests.quests)) {
        const placed = (w.files.npcs.maps[String(q.start.map)] ?? []).some((n) => n.npc === q.start.npc);
        if (!placed) report("E_QUEST_GIVER", `quête ${qid} : le PNJ ${q.start.npc} n'est pas placé sur la map ${q.start.map}`, qref(qid));
      }
    },
  },
  {
    code: "E_QUEST_NO_STEPS", severity: "error",
    doc: "Une quête a au moins une étape, et chaque étape au moins un objectif.",
    run({ w, report }) {
      for (const [qid, q] of Object.entries(w.files.quests.quests)) {
        if (!q.steps.length) report("E_QUEST_NO_STEPS", `quête ${qid} sans étape`, qref(qid));
        for (const st of q.steps) if (!st.objectives.length) report("E_QUEST_NO_STEPS", `quête ${qid} : l'étape ${st.id} n'a aucun objectif`, qref(qid));
      }
    },
  },
  {
    code: "E_QUEST_OBJ_NPC", severity: "error",
    doc: "Les objectifs de type 1/9/3 visent un PNJ placé.",
    run({ w, npcIds, report }) {
      for (const [qid, q] of Object.entries(w.files.quests.quests))
        for (const st of q.steps) for (const o of st.objectives)
          if ([1, 9, 3].includes(o.type) && !npcIds.has(o.params[0])) report("E_QUEST_OBJ_NPC", `quête ${qid} : PNJ d'objectif ${o.params[0]} non placé`, qref(qid));
    },
  },
  {
    code: "E_QUEST_OBJ_ITEM", severity: "error",
    doc: "Les objectifs de type 3 demandent un objet existant.",
    run({ w, itemIds, report }) {
      for (const [qid, q] of Object.entries(w.files.quests.quests))
        for (const st of q.steps) for (const o of st.objectives)
          if (o.type === 3 && !itemIds.has(o.params[1])) report("E_QUEST_OBJ_ITEM", `quête ${qid} : objet d'objectif ${o.params[1]} inconnu`, qref(qid));
    },
  },
  {
    code: "E_QUEST_OBJ_MONSTER", severity: "error",
    doc: "Les objectifs de type 7/14 visent un monstre existant.",
    run({ w, mobIds, report }) {
      for (const [qid, q] of Object.entries(w.files.quests.quests))
        for (const st of q.steps) for (const o of st.objectives)
          if ([7, 14].includes(o.type) && !mobIds.has(o.params[0])) report("E_QUEST_OBJ_MONSTER", `quête ${qid} : monstre d'objectif ${o.params[0]} inconnu`, qref(qid));
    },
  },
  {
    code: "E_QUEST_OBJ_MAP", severity: "error",
    doc: "Les objectifs de type 4 visent une map du monde.",
    run({ w, mapIds, report }) {
      for (const [qid, q] of Object.entries(w.files.quests.quests))
        for (const st of q.steps) for (const o of st.objectives)
          if (o.type === 4 && !mapIds.has(o.map ?? 0)) report("E_QUEST_OBJ_MAP", `quête ${qid} : map d'objectif ${o.map} inconnue`, qref(qid));
    },
  },
  {
    code: "E_QUEST_REWARD_ITEM", severity: "error",
    doc: "Les récompenses de quête sont des objets existants.",
    run({ w, itemIds, report }) {
      for (const [qid, q] of Object.entries(w.files.quests.quests))
        for (const st of q.steps) for (const rw of st.rewards) for (const [it] of rw.items ?? [])
          if (!itemIds.has(it)) report("E_QUEST_REWARD_ITEM", `quête ${qid} : récompense ${it} inconnue`, qref(qid));
    },
  },
  {
    code: "E_ID_DUPLICATE", severity: "error",
    doc: "Un id n'est défini qu'une fois (objets, sorts, panoplies).",
    run({ w, report }) {
      const dup = (kind: string, list: number[]) => {
        const seen = new Set<number>();
        for (const i of list) { if (seen.has(i)) report("E_ID_DUPLICATE", `${kind} ${i} défini plusieurs fois`, { kind, id: i }); seen.add(i); }
      };
      dup("item", w.files.items.items.map((i) => i.id));
      dup("spell", w.files.spells.spells.map((s) => s.id));
      dup("set", w.files.items.sets.map((s) => s.id));
    },
  },
  {
    code: "E_ID_RANGE", severity: "error",
    doc: "Les ids définis par le monde sont dans les plages réservées à ce monde (si elles sont données).",
    run(c) {
      const all = collectIds(c.w);
      for (const kind of KINDS) {
        const r = c.opts.ranges?.[kind];
        if (!r) continue;
        for (const id of all[kind])
          // texts below 1 000 000 are Dofus quest-objective templates a world may restate: not new ids
          if ((id < r[0] || id > r[1]) && !(kind === "text" && id < 1_000_000)) c.report("E_ID_RANGE", `${kind} ${id} hors de la plage ${r[0]}..${r[1]}`, { kind, id });
      }
    },
  },
  {
    code: "E_ID_COLLISION", severity: "error",
    doc: "Les ids définis par le monde ne sont pas déjà pris (autre monde, données globales).",
    run(c) {
      const all = collectIds(c.w);
      for (const kind of KINDS) {
        const taken = c.opts.reserved?.[kind];
        if (!taken) continue;
        for (const id of all[kind]) if (taken.has(id)) c.report("E_ID_COLLISION", `${kind} ${id} déjà utilisé par un autre monde`, { kind, id });
      }
    },
  },
];
