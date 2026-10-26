import { layoutDialog } from "../../../core/dialog_graph";
import type { DialogInput } from "../api";

const W = 150, H = 52, GX = 70, GY = 22, PAD = 12;
const clip = (s: string, n: number) => (s.length > n ? s.slice(0, n - 1) + "…" : s);

/** The conversation as boxes and arrows. Read only: the cards below stay the place to edit. */
export function DialogGraph({ d }: { d: DialogInput }) {
  const g = layoutDialog(d);
  const pos = (k: string) => { const n = g.nodes.find((x) => x.key === k)!; return { x: PAD + n.col * (W + GX), y: PAD + n.row * (H + GY) }; };
  const width = PAD * 2 + g.cols * W + (g.cols - 1) * GX;
  const height = PAD * 2 + g.rows * H + (g.rows - 1) * GY;
  return (
    <details className="dlg-graph">
      <summary>Voir le schéma de la conversation</summary>
      <div className="dlg-scroll">
        <svg role="img" aria-label="Schéma du dialogue" width={width} height={height} viewBox={`0 0 ${width} ${height}`}>
          <defs><marker id="arr" viewBox="0 0 8 8" refX="7" refY="4" markerWidth="7" markerHeight="7" orient="auto"><path d="M0,0 L8,4 L0,8 z" fill="currentColor" /></marker></defs>
          {g.edges.map((e, i) => {
            const a = pos(e.from), b = pos(e.to);
            const sameSpot = e.from === e.to;
            const x1 = a.x + W, y1 = a.y + H / 2, x2 = b.x, y2 = b.y + H / 2;
            // forward arrows leave by the right side; arrows going back loop under the boxes
            const path = sameSpot ? `M${a.x + W / 2},${a.y + H} c40,40 -40,40 0,0`
              : e.back ? `M${a.x + W / 2},${a.y + H} C${a.x + W / 2},${a.y + H + 40} ${b.x + W / 2},${b.y + H + 40} ${b.x + W / 2},${b.y + H}`
              : `M${x1},${y1} C${x1 + GX / 2},${y1} ${x2 - GX / 2},${y2} ${x2},${y2}`;
            return <path key={i} d={path} className={"dlg-edge" + (e.back ? " back" : "")} fill="none" markerEnd="url(#arr)"><title>{e.label}</title></path>;
          })}
          {g.nodes.map((n) => {
            const p = pos(n.key);
            return (
              <g key={n.key} transform={`translate(${p.x},${p.y})`} className={"dlg-node" + (n.orphan ? " orphan" : "") + (n.start ? " start" : "")}>
                <rect width={W} height={H} rx={9} />
                <text x={10} y={19} className="dlg-key">{n.key}{n.start ? " · départ" : n.orphan ? " · jamais atteint" : ""}</text>
                <text x={10} y={38} className="dlg-txt">{clip(d.nodes[n.key].text, 22)}</text>
              </g>
            );
          })}
        </svg>
      </div>
      <p className="muted small">Les flèches pleines vont vers la suite, les pointillées reviennent en arrière. Survole une flèche pour lire la réponse du joueur.</p>
    </details>
  );
}
