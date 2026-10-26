// Layout of a dialogue as a graph: nodes in columns by distance from the start node (breadth first), the nodes the
// conversation never reaches in a last column. Pure data, drawn by the web app.
import type { DialogInput } from "./editors_npcs";

export interface GraphNode { key: string; col: number; row: number; orphan: boolean; start: boolean }
export interface GraphEdge { from: string; to: string; label: string; /** the target node is already on the way back (a loop) */ back: boolean }
export interface DialogGraph { nodes: GraphNode[]; edges: GraphEdge[]; cols: number; rows: number }

export function layoutDialog(d: DialogInput): DialogGraph {
  const depth = new Map<string, number>();
  const queue: string[] = [];
  if (d.start in d.nodes) { depth.set(d.start, 0); queue.push(d.start); }
  while (queue.length) {
    const k = queue.shift()!;
    for (const r of d.nodes[k].replies) if (r.next && r.next in d.nodes && !depth.has(r.next)) { depth.set(r.next, depth.get(k)! + 1); queue.push(r.next); }
  }
  const lastCol = Math.max(-1, ...depth.values());
  const colOf = (k: string) => depth.get(k) ?? lastCol + 1;
  const used = new Map<number, number>();
  const nodes = Object.keys(d.nodes).map((key) => {
    const col = colOf(key);
    const row = used.get(col) ?? 0;
    used.set(col, row + 1);
    return { key, col, row, orphan: !depth.has(key), start: key === d.start };
  });
  const edges: GraphEdge[] = [];
  for (const [from, n] of Object.entries(d.nodes))
    for (const r of n.replies) if (r.next && r.next in d.nodes) edges.push({ from, to: r.next, label: r.text, back: colOf(r.next) <= colOf(from) });
  return { nodes, edges, cols: used.size, rows: Math.max(1, ...used.values()) };
}
