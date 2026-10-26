import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { api, type MapInput, type MapRow, type ZoneRow } from "../api";
import { Banner, Dialog, Field } from "../components";

const COLS = 14;
const ROWS = 40;
const SIDES: [keyof MapInput["neighbors"], string][] = [["top", "Haut"], ["bottom", "Bas"], ["left", "Gauche"], ["right", "Droite"]];

type Tool = "wall" | "los" | "red" | "blue" | "door" | "phoenix" | "start";
const TOOLS: [Tool, string, string][] = [
  ["wall", "Mur", "Cellule bloquée (marche et combat)"], ["los", "Vue bloquée", "Bloque la ligne de vue"],
  ["red", "Placement rouge", "Départ de l'équipe rouge en combat"], ["blue", "Placement bleu", "Départ de l'équipe bleue en combat"],
  ["door", "Porte", "Clique une cellule pour en faire une porte"], ["phoenix", "Renaissance", "Cellule où l'on renaît"], ["start", "Départ du monde", "Cellule où arrivent les nouveaux personnages"],
];

const toInput = (r: MapRow): MapInput => ({
  name: r.name, coords: [...r.coords] as [number, number], outdoor: r.outdoor, monsterSpawn: r.monsterSpawn, zone: r.zone, blocked: [...r.blocked], los: [...r.los],
  red: [...r.red], blue: [...r.blue], phoenix: r.phoenix, isPhoenix: r.isPhoenix, neighbors: { ...r.neighbors }, doors: r.doors.map((d) => ({ ...d })),
});

export function MapsPanel({ worldId, rev, onChange }: { worldId: string; rev: number; onChange: () => void }) {
  const [rows, setRows] = useState<MapRow[] | null>(null);
  const [zones, setZones] = useState<ZoneRow[]>([]);
  const [error, setError] = useState("");
  const [open, setOpen] = useState<number | null>(null);
  const [creating, setCreating] = useState(false);

  const load = useCallback(() => {
    api.rows<MapRow>(worldId, "maps").then(setRows).catch((e) => setError(e.message));
    api.rows<ZoneRow>(worldId, "zones").then(setZones).catch(() => {});
  }, [worldId]);
  useEffect(load, [load, rev]);

  const current = rows?.find((r) => r.id === open);
  if (open !== null && current && rows) return <MapEditor worldId={worldId} row={current} maps={rows} zones={zones} onClose={() => setOpen(null)} onChange={onChange} />;

  return (
    <section className="panel" aria-labelledby="maps-h">
      <div className="panel-head">
        <h2 id="maps-h">Maps</h2>
        <button className="btn primary" onClick={() => setCreating(true)}>+ Nouvelle map</button>
      </div>
      {error && <Banner kind="error">{error}</Banner>}
      {rows === null ? <p className="muted">Chargement…</p> : (
        <table className="table data">
          <thead><tr><th>Nom</th><th>Coord.</th><th>Liens</th><th>Contenu</th><th /></tr></thead>
          <tbody>
            {rows.map((r) => (
              <tr key={r.id} className="clickable" tabIndex={0} onClick={() => setOpen(r.id)} onKeyDown={(e) => e.key === "Enter" && setOpen(r.id)} aria-label={`Modifier la map ${r.name}`}>
                <td className="wrap"><strong>{r.name}</strong><br /><code className="id">{r.id}</code></td>
                <td className="num">{r.coords[0]}, {r.coords[1]}</td>
                <td>{Object.keys(r.neighbors).length} voisine{Object.keys(r.neighbors).length > 1 ? "s" : ""} · {r.doors.length} porte{r.doors.length > 1 ? "s" : ""}</td>
                <td>{r.npcs} PNJ · {r.interactives} él. interactif{r.interactives > 1 ? "s" : ""}{r.zone ? " · zone" : ""}</td>
                <td>{r.isStart && <span className="chip ok">départ</span>} {r.isPhoenix && <span className="chip accent">renaissance</span>}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
      {creating && <NewMapDialog worldId={worldId} maps={rows ?? []} onClose={() => setCreating(false)} onDone={(id) => { setCreating(false); setOpen(id); onChange(); }} />}
    </section>
  );
}

function NewMapDialog({ worldId, maps, onClose, onDone }: { worldId: string; maps: MapRow[]; onClose: () => void; onDone: (id: number) => void }) {
  const [name, setName] = useState("");
  const [copyOf, setCopyOf] = useState("");
  const [error, setError] = useState("");
  return (
    <Dialog title="Nouvelle map" onClose={onClose}>
      <form onSubmit={async (e) => { e.preventDefault(); try { onDone((await api.addRow(worldId, "maps", copyOf ? { name, copyOf: Number(copyOf) } : { name })).id); } catch (err) { setError((err as Error).message); } }}>
        <Field label="Nom" hint="La map naît vide, sans obstacle. Tu la dessines ensuite sur la grille."><input value={name} onChange={(e) => setName(e.target.value)} maxLength={60} /></Field>
        <Field label="Point de départ" hint="Copier une map reprend sa grille (murs, vue, placement) et son décor, mais ni ses voisines, portes, PNJ ni groupes de monstres.">
          <select aria-label="Copier une map" value={copyOf} onChange={(e) => setCopyOf(e.target.value)}>
            <option value="">Une map vide</option>
            {maps.map((m) => <option key={m.id} value={m.id}>Copie de « {m.name} »</option>)}
          </select>
        </Field>
        {error && <Banner kind="error">{error}</Banner>}
        <div className="actions">
          <button type="button" className="btn" onClick={onClose}>Annuler</button>
          <button type="submit" className="btn primary" disabled={!name.trim()}>Créer la map</button>
        </div>
      </form>
    </Dialog>
  );
}

function MapEditor({ worldId, row, maps, zones, onClose, onChange }: { worldId: string; row: MapRow; maps: MapRow[]; zones: ZoneRow[]; onClose: () => void; onChange: () => void }) {
  const [f, setF] = useState<MapInput>(() => toInput(row));
  const [tool, setTool] = useState<Tool>("wall");
  const [door, setDoor] = useState<number | null>(null);
  const [error, setError] = useState("");
  const [saved, setSaved] = useState(false);
  const [confirm, setConfirm] = useState(false);
  const paint = useRef<"add" | "remove" | null>(null);
  const patch = (p: Partial<MapInput>) => { setF((x) => ({ ...x, ...p })); setSaved(false); };
  const dirty = useMemo(() => JSON.stringify(f) !== JSON.stringify(toInput(row)), [f, row]);
  useEffect(() => { setF(toInput(row)); }, [row]); // after a save or an undo, the row is the truth

  const sets = useMemo(() => ({ wall: new Set(f.blocked), los: new Set(f.los), red: new Set(f.red), blue: new Set(f.blue), door: new Map(f.doors.map((d) => [d.cell, d])) }), [f]);
  const others = maps.filter((m) => m.id !== row.id);

  function toggle(list: number[], cell: number, mode: "add" | "remove"): number[] {
    const has = list.includes(cell);
    if (mode === "add" && !has) return [...list, cell].sort((a, b) => a - b);
    if (mode === "remove" && has) return list.filter((c) => c !== cell);
    return list;
  }
  function apply(cell: number, mode: "add" | "remove") {
    if (tool === "wall") patch({ blocked: toggle(f.blocked, cell, mode), red: mode === "add" ? f.red.filter((c) => c !== cell) : f.red, blue: mode === "add" ? f.blue.filter((c) => c !== cell) : f.blue, doors: mode === "add" ? f.doors.filter((d) => d.cell !== cell) : f.doors });
    else if (tool === "los") patch({ los: toggle(f.los, cell, mode) });
    else if (tool === "red") patch({ red: toggle(f.red, cell, mode), blue: f.blue.filter((c) => c !== cell), blocked: f.blocked.filter((c) => c !== cell || mode === "remove") });
    else if (tool === "blue") patch({ blue: toggle(f.blue, cell, mode), red: f.red.filter((c) => c !== cell), blocked: f.blocked.filter((c) => c !== cell || mode === "remove") });
    else if (tool === "phoenix") patch({ phoenix: cell, blocked: f.blocked.filter((c) => c !== cell) });
  }
  function down(cell: number) {
    if (tool === "door") {
      const d = sets.door.get(cell);
      if (!d) {
        const to = others[0];
        if (!to) { setError("Il faut une autre map pour y mener une porte."); return; }
        patch({ doors: [...f.doors, { cell, to_map: to.id, to_cell: 300 }], blocked: f.blocked.filter((c) => c !== cell) });
      }
      setDoor(cell);
      return;
    }
    if (tool === "start") { startHere(cell); return; }
    const mode = (tool === "wall" ? sets.wall : tool === "los" ? sets.los : tool === "red" ? sets.red : tool === "blue" ? sets.blue : new Set<number>()).has(cell) ? "remove" : "add";
    paint.current = mode;
    apply(cell, mode);
  }

  async function save() {
    setError("");
    try { await api.setRow(worldId, "maps", row.id, f); setSaved(true); onChange(); } catch (e) { setError((e as Error).message); }
  }
  async function startHere(cell: number) {
    setError("");
    try { await api.setRow(worldId, "maps", row.id, { start: cell }); onChange(); } catch (e) { setError((e as Error).message); }
  }
  async function remove() {
    setError("");
    try { await api.delRow(worldId, "maps", row.id); onChange(); onClose(); } catch (e) { setError((e as Error).message); setConfirm(false); }
  }
  const sel = door !== null ? sets.door.get(door) : undefined;
  const setDoorField = (p: Partial<{ to_map: number; to_cell: number }>) => patch({ doors: f.doors.map((d) => (d.cell === door ? { ...d, ...p } : d)) });

  return (
    <section className="panel" aria-labelledby="map-h" onPointerUp={() => { paint.current = null; }} onPointerLeave={() => { paint.current = null; }}>
      <div className="panel-head">
        <h2 id="map-h">{row.name}</h2>
        <span className="toolbar">
          <button className="btn" onClick={onClose}>← Toutes les maps</button>
          <button className="btn primary" disabled={!dirty} onClick={save}>{saved ? "Enregistré" : "Enregistrer la map"}</button>
        </span>
      </div>
      {error && <Banner kind="error">{error}</Banner>}
      <div className="map-layout">
        <div>
          <div className="seg tools" role="radiogroup" aria-label="Outil">
            {TOOLS.map(([k, label, hint]) => <button type="button" key={k} role="radio" aria-checked={tool === k} className={tool === k ? "on" : ""} title={hint} onClick={() => setTool(k)}>{label}</button>)}
          </div>
          <div className="mgrid" role="grid" aria-label="Grille de la map (14 colonnes, 40 lignes)" onPointerLeave={() => { paint.current = null; }}>
            {Array.from({ length: ROWS }, (_, r) => (
              <div className={"mrow" + (r % 2 ? " odd" : "")} key={r} role="row">
                {Array.from({ length: COLS }, (_, c) => {
                  const cell = r * COLS + c;
                  const cls = ["mcell", sets.wall.has(cell) && "wall", sets.los.has(cell) && "los", sets.red.has(cell) && "red", sets.blue.has(cell) && "blue",
                    sets.door.has(cell) && "door", f.phoenix === cell && "phoenix", row.isStart && row.startCell === cell && "start", door === cell && tool === "door" && "sel"].filter(Boolean).join(" ");
                  return <button type="button" key={c} role="gridcell" className={cls} aria-label={`Cellule ${cell}`} title={String(cell)} tabIndex={-1}
                    onPointerDown={(e) => { e.preventDefault(); down(cell); }}
                    onPointerEnter={(e) => { if (paint.current && e.buttons === 1) apply(cell, paint.current); }} />;
                })}
              </div>
            ))}
          </div>
          <p className="legend small muted">
            <span className="sw wall" /> mur <span className="sw los" /> vue bloquée <span className="sw red" /> rouge <span className="sw blue" /> bleu <span className="sw door" /> porte <span className="sw phoenix" /> renaissance <span className="sw start" /> départ
          </p>
        </div>

        <div className="map-side">
          <Field label="Nom"><input value={f.name} onChange={(e) => patch({ name: e.target.value })} maxLength={60} /></Field>
          <div className="form-grid compact">
            <Field label="Coord. X"><input type="number" value={f.coords[0]} onChange={(e) => patch({ coords: [Number(e.target.value), f.coords[1]] })} /></Field>
            <Field label="Coord. Y"><input type="number" value={f.coords[1]} onChange={(e) => patch({ coords: [f.coords[0], Number(e.target.value)] })} /></Field>
          </div>
          <label className="check"><input type="checkbox" checked={f.outdoor} onChange={(e) => patch({ outdoor: e.target.checked })} /> En extérieur</label>
          <label className="check"><input type="checkbox" checked={f.monsterSpawn} onChange={(e) => patch({ monsterSpawn: e.target.checked })} /> Des monstres y apparaissent</label>
          <Field label="Zone de monstres">
            <select value={f.zone ?? ""} onChange={(e) => patch({ zone: e.target.value || null })}>
              <option value="">Aucune</option>
              {zones.map((z) => <option key={z.key} value={z.key}>Niveau {z.level} ({z.monsters.length} monstre{z.monsters.length > 1 ? "s" : ""})</option>)}
            </select>
          </Field>
          <label className="check"><input type="checkbox" checked={f.isPhoenix} onChange={(e) => patch({ isPhoenix: e.target.checked, phoenix: f.phoenix ?? 300 })} /> On peut renaître ici</label>

          <fieldset className="icon-pick">
            <legend className="field-label">Maps voisines</legend>
            {SIDES.map(([side, label]) => (
              <label className="side-row" key={side}>
                <span>{label}</span>
                <select aria-label={`Voisine ${label}`} value={f.neighbors[side] ?? ""} onChange={(e) => { const n = { ...f.neighbors }; if (e.target.value) n[side] = Number(e.target.value); else delete n[side]; patch({ neighbors: n }); }}>
                  <option value="">—</option>
                  {others.map((m) => <option key={m.id} value={m.id}>{m.name}</option>)}
                </select>
              </label>
            ))}
          </fieldset>

          <fieldset className="icon-pick">
            <legend className="field-label">Portes ({f.doors.length})</legend>
            {f.doors.length === 0 && <p className="muted small">Aucune. Choisis l'outil « Porte » puis clique une cellule.</p>}
            {f.doors.map((d) => (
              <div className={"door-row" + (d.cell === door ? " sel" : "")} key={d.cell}>
                <button type="button" className="btn small-btn" onClick={() => { setTool("door"); setDoor(d.cell); }}>Cellule {d.cell}</button>
                <span className="muted small">→ {maps.find((m) => m.id === d.to_map)?.name ?? d.to_map} ({d.to_cell})</span>
                <button type="button" className="btn small-btn" aria-label={`Retirer la porte ${d.cell}`} onClick={() => { patch({ doors: f.doors.filter((x) => x.cell !== d.cell) }); if (door === d.cell) setDoor(null); }}>✕</button>
              </div>
            ))}
            {sel && (
              <div className="door-edit">
                <Field label={`Porte ${sel.cell} mène à`}>
                  <select value={sel.to_map} onChange={(e) => setDoorField({ to_map: Number(e.target.value) })}>
                    {maps.map((m) => <option key={m.id} value={m.id}>{m.name}</option>)}
                  </select>
                </Field>
                <Field label="Cellule d'arrivée"><input type="number" min={0} max={559} value={sel.to_cell} onChange={(e) => setDoorField({ to_cell: Number(e.target.value) })} /></Field>
              </div>
            )}
          </fieldset>

          <p className="muted small">{row.npcs} PNJ, {row.interactives} élément{row.interactives > 1 ? "s" : ""} interactif{row.interactives > 1 ? "s" : ""} (éditeurs à venir). Rappel : les cellules de départ et de renaissance restent libres.</p>
          <div className="danger-zone">
            {confirm ? <button className="btn danger" onClick={remove}>Confirmer la suppression de la map</button> : <button className="btn danger" onClick={() => setConfirm(true)}>Supprimer cette map…</button>}
          </div>
        </div>
      </div>
    </section>
  );
}
