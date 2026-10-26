// Rules on maps: geometry, doors, neighbours, placement, graphics and reachability.
import { CELLS, neighbors, reachableFromFirstFree, validCell } from "./grid";
import type { Rule } from "./problems";

const OPPOSITE: Record<string, string> = { left: "right", right: "left", top: "bottom", bottom: "top" };
const mref = (id: number) => ({ kind: "map", id });

export const mapRules: Rule[] = [
  {
    code: "E_START_MAP", severity: "error",
    doc: "world.start_map est une map du monde.",
    run({ w, mapIds, report }) {
      if (!mapIds.has(w.files.world.start_map)) report("E_START_MAP", `map de départ ${w.files.world.start_map} inconnue`, { kind: "world", id: w.files.world.id });
    },
  },
  {
    code: "E_START_CELL", severity: "error",
    doc: "world.start_cell est dans la grille et n'est pas bloquée.",
    run({ w, report }) {
      const { start_map, start_cell } = w.files.world;
      const m = w.maps.get(start_map);
      if (!validCell(start_cell)) report("E_START_CELL", `cellule de départ ${start_cell} hors de la grille`, { kind: "world", id: w.files.world.id });
      else if (m && m.blocked.includes(start_cell)) report("E_START_CELL", `cellule de départ ${start_cell} bloquée`, { kind: "world", id: w.files.world.id });
    },
  },
  {
    code: "E_PHOENIX_MAP", severity: "error",
    doc: "Les maps de renaissance (world.phoenixes) existent.",
    run({ w, mapIds, report }) {
      for (const p of w.files.world.phoenixes ?? []) if (!mapIds.has(p)) report("E_PHOENIX_MAP", `phénix : map ${p} inconnue`, mref(p));
    },
  },
  {
    code: "E_MAP_ID_MISMATCH", severity: "error",
    doc: "L'id écrit dans maps/<n>.json est <n>.",
    run({ w, report }) {
      for (const [mid, m] of w.maps) if (m.id !== mid) report("E_MAP_ID_MISMATCH", `maps/${mid}.json contient l'id ${m.id}`, mref(mid));
    },
  },
  {
    code: "E_MAP_CELL_RANGE", severity: "error",
    doc: "Toute cellule citée (blocage, placement, portes, PNJ, éléments interactifs) est dans 0..559.",
    run({ w, report }) {
      const bad = (mid: number, what: string, cells: number[]) => {
        for (const c of cells) if (!validCell(c)) report("E_MAP_CELL_RANGE", `map ${mid} : ${what} ${c} hors de la grille (0..${CELLS - 1})`, mref(mid));
      };
      for (const [mid, m] of w.maps) {
        bad(mid, "cellule bloquée", m.blocked);
        bad(mid, "cellule de combat bloquée", m.fight_blocked ?? []);
        bad(mid, "placement rouge", m.placement?.red ?? []);
        bad(mid, "placement bleu", m.placement?.blue ?? []);
        bad(mid, "porte", (m.triggers ?? []).flatMap((t) => [t.cell, t.to_cell]));
        bad(mid, "PNJ", (w.files.npcs.maps[String(mid)] ?? []).map((n) => n.cell));
        bad(mid, "élément interactif", (w.files.interactives.maps[String(mid)] ?? []).map((n) => n.cell));
      }
    },
  },
  {
    code: "E_MAP_TRIGGER_TARGET", severity: "error",
    doc: "Une porte mène vers une map du monde.",
    run({ w, mapIds, report }) {
      for (const [mid, m] of w.maps)
        for (const t of m.triggers ?? [])
          if (!mapIds.has(t.to_map)) report("E_MAP_TRIGGER_TARGET", `map ${mid} : porte vers la map inconnue ${t.to_map}`, mref(mid));
    },
  },
  {
    code: "E_MAP_TRIGGER_ARRIVAL", severity: "error",
    doc: "Une porte n'arrive pas sur une cellule bloquée de la map d'arrivée.",
    run({ w, report }) {
      for (const [mid, m] of w.maps)
        for (const t of m.triggers ?? []) {
          const dest = w.maps.get(t.to_map);
          if (dest && dest.blocked.includes(t.to_cell))
            report("E_MAP_TRIGGER_ARRIVAL", `map ${mid} : la porte arrive sur la cellule bloquée ${t.to_cell} de la map ${t.to_map}`, mref(mid));
        }
    },
  },
  {
    code: "E_MAP_NEIGHBOR_TARGET", severity: "error",
    doc: "Les maps voisines (left/right/top/bottom) existent.",
    run({ w, mapIds, report }) {
      for (const [mid, m] of w.maps)
        for (const [dir, to] of Object.entries(m.neighbors ?? {}))
          if (!mapIds.has(to)) report("E_MAP_NEIGHBOR_TARGET", `map ${mid} : voisin ${dir} = map inconnue ${to}`, mref(mid));
    },
  },
  {
    code: "W_MAP_NEIGHBOR_RECIPROCAL", severity: "warning",
    doc: "Si A a B comme voisin à droite, B a A comme voisin à gauche.",
    run({ w, report }) {
      for (const [mid, m] of w.maps)
        for (const [dir, to] of Object.entries(m.neighbors ?? {})) {
          const back = w.maps.get(to)?.neighbors?.[OPPOSITE[dir] ?? ""];
          if (w.maps.has(to) && back !== mid) report("W_MAP_NEIGHBOR_RECIPROCAL", `map ${mid} : voisin ${dir} = ${to}, mais le retour ne pointe pas ici`, mref(mid));
        }
    },
  },
  {
    code: "E_PLACEMENT_BLOCKED", severity: "error",
    doc: "Les cellules de placement de combat ne sont pas bloquées en combat.",
    run({ w, report }) {
      for (const [mid, m] of w.maps) {
        const blocked = new Set(m.fight_blocked ?? m.blocked);
        for (const c of [...(m.placement?.red ?? []), ...(m.placement?.blue ?? [])])
          if (blocked.has(c)) report("E_PLACEMENT_BLOCKED", `map ${mid} : placement sur la cellule bloquée ${c}`, mref(mid));
      }
    },
  },
  {
    code: "E_MAP_VISUAL", severity: "error",
    doc: "Le visuel de la map existe (Content/Maps/<visual>.json).",
    run({ w, probe, report }) {
      for (const [mid, m] of w.maps) if (!probe(`Maps/${m.visual}.json`)) report("E_MAP_VISUAL", `map ${mid} : visuel ${m.visual} absent`, mref(mid));
    },
  },
  {
    code: "E_MAP_GFX", severity: "error",
    doc: "Les images utilisées par le visuel existent (Content/Maps/Gfx/<g>.png, ou .webp pour celles du jeu Dofus).",
    run({ w, probe, report }) {
      for (const [mid, m] of w.maps) {
        const v = w.visuals.get(m.visual);
        if (!v) continue;
        for (const e of [...v.layers.background, ...v.layers.sortable])
          if (!probe(`Maps/Gfx/${e.g}.png`) && !probe(`Maps/Gfx/${e.g}.webp`)) report("E_MAP_GFX", `map ${mid} : image ${e.g} absente`, mref(mid));
      }
    },
  },
  {
    code: "E_INTERACTIVE_SKILL", severity: "error",
    doc: "Un élément interactif utilise un métier existant.",
    run({ w, report }) {
      for (const [mid, lst] of Object.entries(w.files.interactives.maps))
        for (const it of lst)
          if (!(String(it.skill) in w.files.skills.objectsById)) report("E_INTERACTIVE_SKILL", `map ${mid} : métier ${it.skill} inconnu`, mref(Number(mid)));
    },
  },
  {
    code: "E_INTERACTIVE_CELL", severity: "error",
    doc: "Un élément interactif est posé sur une cellule bloquée (il occupe sa cellule).",
    run({ w, report }) {
      for (const [mid, lst] of Object.entries(w.files.interactives.maps)) {
        const m = w.maps.get(Number(mid));
        if (!m) { report("E_INTERACTIVE_CELL", `éléments interactifs sur la map inconnue ${mid}`, mref(Number(mid))); continue; }
        for (const it of lst) if (!m.blocked.includes(it.cell)) report("E_INTERACTIVE_CELL", `map ${mid} : élément sur la cellule libre ${it.cell}`, mref(Number(mid)));
      }
    },
  },
  {
    code: "E_MAP_UNREACHABLE_CELL", severity: "error",
    doc: "Chaque PNJ et élément interactif a une case voisine atteignable.",
    run({ w, report }) {
      for (const [mid, m] of w.maps) {
        const blocked = new Set(m.blocked);
        const seen = reachableFromFirstFree(blocked);
        const anchors = [...(w.files.npcs.maps[String(mid)] ?? []), ...(w.files.interactives.maps[String(mid)] ?? [])];
        for (const a of anchors)
          if (validCell(a.cell) && !neighbors(a.cell).some((n) => seen.has(n))) report("E_MAP_UNREACHABLE_CELL", `map ${mid} : la cellule ${a.cell} n'est pas atteignable`, mref(mid));
      }
    },
  },
  {
    code: "E_MAP_TRIGGER_CUTOFF", severity: "error",
    doc: "Une porte est sur une cellule atteignable depuis le reste de la map.",
    run({ w, report }) {
      for (const [mid, m] of w.maps) {
        const blocked = new Set(m.blocked);
        const seen = reachableFromFirstFree(blocked);
        for (const t of m.triggers ?? [])
          if (!seen.has(t.cell) && !blocked.has(t.cell)) report("E_MAP_TRIGGER_CUTOFF", `map ${mid} : la porte en ${t.cell} est coupée du reste`, mref(mid));
      }
    },
  },
  {
    code: "W_WORLD_MAP_UNREACHABLE", severity: "warning",
    doc: "Chaque map est atteignable depuis la map de départ (portes, voisins, téléportations de dialogue).",
    run({ w, mapIds, report }) {
      if (!mapIds.has(w.files.world.start_map)) return; // E_START_MAP already says it
      const seen = reachableMaps(w);
      for (const mid of w.maps.keys()) if (!seen.has(mid)) report("W_WORLD_MAP_UNREACHABLE", `map ${mid} : inatteignable depuis la map de départ`, mref(mid));
    },
  },
];

/** Maps a player can get to from the start map: doors, neighbours, and teleports offered by an NPC of a reached map. */
export function reachableMaps(w: import("./io").World): Set<number> {
  const edges = new Map<number, Set<number>>();
  const add = (a: number, b: number) => { (edges.get(a) ?? edges.set(a, new Set()).get(a)!).add(b); };
  for (const [mid, m] of w.maps) {
    for (const t of m.triggers ?? []) add(mid, t.to_map);
    for (const to of Object.values(m.neighbors ?? {})) add(mid, to);
  }
  const npcMap = new Map<number, number>();
  for (const [mid, lst] of Object.entries(w.files.npcs.maps)) for (const n of lst) npcMap.set(n.npc, Number(mid));
  for (const [nid, tree] of Object.entries(w.files.dialogs.dialogs))
    for (const node of Object.values(tree.nodes))
      for (const r of node.replies) {
        const a = r.action as { type: string; map?: number } | undefined;
        const from = npcMap.get(Number(nid));
        if (a?.type === "teleport" && a.map !== undefined && from !== undefined) add(from, a.map);
      }
  const seen = new Set<number>([w.files.world.start_map]);
  const queue = [w.files.world.start_map];
  while (queue.length) for (const n of edges.get(queue.shift()!) ?? []) if (!seen.has(n)) { seen.add(n); queue.push(n); }
  return seen;
}
