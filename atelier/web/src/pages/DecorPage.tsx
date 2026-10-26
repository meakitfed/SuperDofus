import { useCallback, useEffect, useMemo, useState } from "react";
import { api, type AssetInfo, type MapRow } from "../api";
import type { ElementInput, Layer, VisualInput, VisualRow } from "../../../core/editors_visual";
import { Banner, Field } from "../components";

// Map pixels (cell 0 centre = 0,0) -> stage pixels. The stage leaves the same margin as the generated art.
const OX = 90, OY = 50, S = 0.62, MAP_W = 14 * 86 + 43, MAP_H = 39 * 21.5;
const LAYERS: [Layer, string, string][] = [["background", "Sol", "Image de fond, sous tout"], ["sortable", "Objets", "Décor posé sur une cellule, trié avec les personnages"], ["foreground", "Premier plan", "Passe devant les personnages"]];
const cellXY = (c: number): [number, number] => [(c % 14) * 86 + (Math.floor(c / 14) % 2 ? 43 : 0), Math.floor(c / 14) * 21.5];
const nearestCell = (x: number, y: number) => { let best = 0, d = Infinity; for (let c = 0; c < 560; c++) { const [cx, cy] = cellXY(c); const k = (cx - x) ** 2 + ((cy - y) * 2) ** 2; if (k < d) { d = k; best = c; } } return best; };
const hex = (argb: number) => "#" + (argb & 0xffffff).toString(16).padStart(6, "0");
const argb = (h: string) => (0xff000000 | parseInt(h.slice(1), 16)) >>> 0;

/** Visual layers of a map: pick a map, pick a tile of the library, click the stage to place it. */
export function DecorPanel({ worldId, rev, onChange }: { worldId: string; rev: number; onChange: () => void }) {
  const [maps, setMaps] = useState<MapRow[] | null>(null);
  const [mapId, setMapId] = useState<number | null>(null);
  const [tiles, setTiles] = useState<AssetInfo[]>([]);
  const [error, setError] = useState("");

  useEffect(() => {
    api.rows<MapRow>(worldId, "maps").then((m) => { setMaps(m); setMapId((cur) => cur ?? m[0]?.id ?? null); }).catch((e) => setError(e.message));
    api.assets(worldId, "tile").then(setTiles).catch(() => {});
  }, [worldId, rev]);

  return (
    <section className="panel" aria-labelledby="decor-h">
      <div className="panel-head">
        <h2 id="decor-h">Décor des maps</h2>
        {maps && maps.length > 0 && (
          <label className="inline">Map{" "}
            <select aria-label="Map à décorer" value={mapId ?? ""} onChange={(e) => setMapId(Number(e.target.value))}>
              {maps.map((m) => <option key={m.id} value={m.id}>{m.name}</option>)}
            </select>
          </label>
        )}
      </div>
      <p className="muted small">Le décor est ce que le joueur voit : le sol, les objets posés sur les cellules et le premier plan. Les images viennent de l'onglet Images (catégorie « Tuiles de map »). Le décor ne bloque rien : les murs se placent dans l'onglet Maps.</p>
      {error && <Banner kind="error">{error}</Banner>}
      {maps?.length === 0 && <p className="muted empty">Aucune map.</p>}
      {mapId !== null && <Stage key={mapId} worldId={worldId} mapId={mapId} tiles={tiles} onSaved={onChange} />}
    </section>
  );
}

function Stage({ worldId, mapId, tiles, onSaved }: { worldId: string; mapId: number; tiles: AssetInfo[]; onSaved: () => void }) {
  const [row, setRow] = useState<VisualRow | null>(null);
  const [v, setV] = useState<VisualInput | null>(null);
  const [layer, setLayer] = useState<Layer>("sortable");
  const [tile, setTile] = useState<number | null>(null);
  const [sel, setSel] = useState<number | null>(null);
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  const [saved, setSaved] = useState(false);

  const load = useCallback(() => {
    api.visual(worldId, mapId).then((r) => { setRow(r); setV({ bg: r.bg, background: r.background, sortable: r.sortable, foreground: r.foreground }); setSel(null); }).catch((e) => setError(e.message));
  }, [worldId, mapId]);
  useEffect(load, [load]);

  const byId = useMemo(() => new Map(tiles.map((t) => [t.id, t])), [tiles]);
  useEffect(() => { if (tile === null && tiles[0]) setTile(tiles[0].id); }, [tiles, tile]);
  if (!v || !row) return error ? <Banner kind="error">{error}</Banner> : <p className="muted">Chargement…</p>;

  const dirty = JSON.stringify(v) !== JSON.stringify({ bg: row.bg, background: row.background, sortable: row.sortable, foreground: row.foreground });
  const patchLayer = (l: Layer, f: (list: ElementInput[]) => ElementInput[]) => { setSaved(false); setV((x) => (x ? { ...x, [l]: f(x[l]) } : x)); };

  function place(e: React.MouseEvent<HTMLDivElement>) {
    if (tile === null) return;
    const t = byId.get(tile);
    if (!t) return;
    const r = e.currentTarget.getBoundingClientRect();
    const mx = (e.clientX - r.left) / S - OX, my = (e.clientY - r.top) / S - OY;
    let el: ElementInput;
    if (layer === "sortable") { // the foot of the image stands on the nearest cell
      const cell = nearestCell(mx, my);
      const [cx, cy] = cellXY(cell);
      el = { g: tile, cell, x: Math.round(cx), y: Math.round(cy + 12 - t.height / 2) };
    } else el = { g: tile, x: Math.round(mx), y: Math.round(my) };
    patchLayer(layer, (l) => [...l, el]);
    setSel(v![layer].length);
  }
  const nudge = (dx: number, dy: number) => sel !== null && patchLayer(layer, (l) => l.map((e, i) => (i === sel ? { ...e, x: e.x + dx, y: e.y + dy } : e)));
  const setCell = (cell: number) => sel !== null && patchLayer(layer, (l) => l.map((e, i) => { if (i !== sel) return e; const [cx, cy] = cellXY(cell); const h = byId.get(e.g)?.height ?? 0; return { ...e, cell, x: Math.round(cx), y: Math.round(cy + 12 - h / 2) }; }));
  const remove = () => { if (sel === null) return; patchLayer(layer, (l) => l.filter((_, i) => i !== sel)); setSel(null); };
  const move = (d: number) => { if (sel === null) return; patchLayer(layer, (l) => { const a = [...l]; const j = sel + d; if (j < 0 || j >= a.length) return a; [a[sel], a[j]] = [a[j], a[sel]]; return a; }); setSel(sel + d); };

  async function save() {
    setBusy(true); setError("");
    try { await api.setRow(worldId, "visuals", mapId, v); setSaved(true); onSaved(); load(); } catch (e) { setError((e as Error).message); } finally { setBusy(false); }
  }

  const items = v[layer];
  const cur = sel !== null ? items[sel] : undefined;
  return (
    <div className="decor">
      <div className="decor-main">
        <div className="toolbar" role="tablist" aria-label="Couche">
          {LAYERS.map(([k, label, hint]) => (
            <button key={k} role="tab" aria-selected={layer === k} className={"btn small-btn" + (layer === k ? " on" : "")} title={hint} onClick={() => { setLayer(k); setSel(null); }}>{label} ({v[k].length})</button>
          ))}
          <label className="inline">Fond <input type="color" aria-label="Couleur de fond" value={hex(v.bg)} onChange={(e) => { setSaved(false); setV({ ...v, bg: argb(e.target.value) }); }} /></label>
        </div>
        <div className="stage-wrap">
          <div className="stage" role="img" aria-label="Aperçu de la map" style={{ width: (MAP_W + 2 * OX) * S, height: (MAP_H + 2 * OY) * S, background: hex(v.bg) }} onClick={place}>
            {LAYERS.flatMap(([k]) => v[k].map((e, i) => {
              const t = byId.get(e.g);
              const on = k === layer && i === sel;
              return <img key={k + i} src={api.assetUrl(worldId, "tile", e.g)} alt="" draggable={false} className={"stage-el" + (on ? " sel" : "") + (k === layer ? "" : " dim")}
                style={{ left: (e.x + OX) * S, top: (e.y + OY) * S, width: t?.width, height: t?.height, transform: `translate(-50%,-50%) scale(${S})${e.m ? ` matrix(${e.m.join(",")},0,0)` : ""}` }}
                onClick={(ev) => { if (k === layer) { ev.stopPropagation(); setSel(i); } }} />;
            }))}
            {layer === "sortable" && Array.from({ length: 560 }, (_, c) => { const [cx, cy] = cellXY(c); return <i key={c} className="stage-dot" style={{ left: (cx + OX) * S, top: (cy + OY) * S }} />; })}
          </div>
        </div>
      </div>

      <aside className="decor-side">
        <h3>Images</h3>
        {tiles.length === 0 ? <p className="muted small">Aucune tuile. Importe des images dans l'onglet Images, catégorie « Tuiles de map ».</p> : (
          <div className="palette" role="listbox" aria-label="Tuiles">
            {tiles.map((t) => (
              <button key={t.id} type="button" role="option" aria-selected={tile === t.id} className={"palette-tile" + (tile === t.id ? " on" : "")} title={`${t.name} (${t.width}×${t.height})`} onClick={() => setTile(t.id)}>
                <img src={api.assetUrl(worldId, "tile", t.id)} alt={t.name} />
              </button>
            ))}
          </div>
        )}
        <p className="muted small">Clique sur l'aperçu pour poser l'image choisie{layer === "sortable" ? " (elle se cale sur la cellule la plus proche)" : ""}. Clique un élément pour le régler.</p>

        <h3>Éléments de la couche</h3>
        {items.length === 0 ? <p className="muted small">Aucun élément.</p> : (
          <ol className="decor-list">
            {items.map((e, i) => (
              <li key={i}><button type="button" className={"btn small-btn" + (sel === i ? " on" : "")} aria-pressed={sel === i} onClick={() => setSel(i)}>{byId.get(e.g)?.name ?? `image ${e.g}`}{e.cell !== undefined ? ` · cellule ${e.cell}` : ` · ${Math.round(e.x)}, ${Math.round(e.y)}`}</button></li>
            ))}
          </ol>
        )}
        {cur && (
          <div className="decor-tools" role="group" aria-label="Élément choisi">
            <div className="toolbar">
              <button className="btn small-btn" onClick={() => nudge(-10, 0)} aria-label="Gauche de 10">←</button>
              <button className="btn small-btn" onClick={() => nudge(10, 0)} aria-label="Droite de 10">→</button>
              <button className="btn small-btn" onClick={() => nudge(0, -10)} aria-label="Haut de 10">↑</button>
              <button className="btn small-btn" onClick={() => nudge(0, 10)} aria-label="Bas de 10">↓</button>
              <button className="btn small-btn" onClick={() => nudge(-1, 0)} aria-label="Gauche de 1">‹</button>
              <button className="btn small-btn" onClick={() => nudge(1, 0)} aria-label="Droite de 1">›</button>
            </div>
            {cur.cell !== undefined && <Field label="Cellule"><input type="number" min={0} max={559} value={cur.cell} onChange={(e) => { const c = Number(e.target.value); if (Number.isInteger(c) && c >= 0 && c < 560) setCell(c); }} /></Field>}
            <div className="toolbar">
              <button className="btn small-btn" disabled={sel === 0} onClick={() => move(-1)}>Plus bas dans l'ordre</button>
              <button className="btn small-btn" disabled={sel === items.length - 1} onClick={() => move(1)}>Plus haut dans l'ordre</button>
              <button className="btn danger small-btn" onClick={remove}>Retirer l'élément</button>
            </div>
          </div>
        )}
        {row.shared && <p className="muted small" role="note">Ce décor est partagé avec une autre map : le modifier change les deux.</p>}
        {error && <Banner kind="error">{error}</Banner>}
        <div className="actions">
          {saved && !dirty && <span className="chip ok" role="status">Décor enregistré</span>}
          <button className="btn" disabled={!dirty || busy} onClick={load}>Annuler les changements</button>
          <button className="btn primary" disabled={!dirty || busy} onClick={save}>Enregistrer le décor</button>
        </div>
      </aside>
    </div>
  );
}
