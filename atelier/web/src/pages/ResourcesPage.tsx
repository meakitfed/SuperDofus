import { useCallback, useEffect, useState } from "react";
import { api, type AssetInfo, type ItemRow, type MapRow } from "../api";
import type { JobRow, ResourceInput, ResourceRow } from "../../../core/editors_resources";
import { CellPicker } from "../CellPicker";
import { Banner, Dialog, Field } from "../components";

export function ResourcesPanel({ worldId, rev, onChange }: { worldId: string; rev: number; onChange: () => void }) {
  const [rows, setRows] = useState<ResourceRow[] | null>(null);
  const [jobs, setJobs] = useState<JobRow[]>([]);
  const [maps, setMaps] = useState<MapRow[]>([]);
  const [error, setError] = useState("");
  const [edit, setEdit] = useState<ResourceRow | "new" | null>(null);
  const [job, setJob] = useState<JobRow | "new" | null>(null);

  const load = useCallback(() => {
    api.rows<ResourceRow>(worldId, "resources").then(setRows).catch((e) => setError(e.message));
    api.rows<JobRow>(worldId, "jobs").then(setJobs).catch(() => {});
    api.rows<MapRow>(worldId, "maps").then(setMaps).catch(() => {});
  }, [worldId]);
  useEffect(load, [load, rev]);

  return (
    <section className="panel" aria-labelledby="res-h">
      <div className="panel-head">
        <h2 id="res-h">Ressources</h2>
        <span className="toolbar">
          <button className="btn" onClick={() => setJob("new")}>+ Nouveau métier</button>
          <button className="btn primary" onClick={() => setEdit("new")}>+ Nouvelle ressource</button>
        </span>
      </div>
      <p className="muted small">Un métier (Bûcheron…) regroupe des ressources. Une ressource donne un objet quand on la récolte, à partir d'un niveau de métier, et se pose à plusieurs endroits. Chaque emplacement occupe sa cellule.</p>
      {error && <Banner kind="error">{error}</Banner>}
      <h3>Métiers</h3>
      {jobs.length === 0 ? <p className="muted small">Aucun métier : crée-en un avant ta première ressource.</p> : (
        <ul className="tpl-list">
          {jobs.map((j) => <li key={j.id}><button type="button" className="btn small-btn" aria-label={`Modifier le métier ${j.name}`} onClick={() => setJob(j)}>{j.name} <span className="muted">· {j.resources} ressource{j.resources > 1 ? "s" : ""}</span></button></li>)}
        </ul>
      )}
      <h3>Ressources à récolter</h3>
      {rows === null ? <p className="muted">Chargement…</p> : rows.length === 0 ? (
        <p className="muted empty">Aucune ressource. Crée un métier, puis une première ressource.</p>
      ) : (
        <table className="table data">
          <thead><tr><th>Ressource</th><th>Métier</th><th>Donne</th><th>Niveau</th><th>Emplacements</th><th /></tr></thead>
          <tbody>
            {rows.map((r) => (
              <tr key={r.id}>
                <td className="wrap"><strong>{r.name}</strong><br /><code className="id">{r.id}</code></td>
                <td>{r.jobName || <span className="muted">—</span>}</td>
                <td>{r.itemName || <span className="muted">objet {r.item}</span>}</td>
                <td className="num">{r.level}</td>
                <td>{r.places.length === 0 ? <span className="chip warn">aucun</span> : <span className="chip ok">{r.places.length}</span>}</td>
                <td className="row-actions"><button className="btn small-btn" onClick={() => setEdit(r)} aria-label={`Modifier la ressource ${r.name}`}>Modifier</button></td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
      {job && <JobDialog worldId={worldId} row={job === "new" ? null : job} onClose={() => setJob(null)} onDone={() => { setJob(null); onChange(); }} />}
      {edit && <ResourceDialog worldId={worldId} row={edit === "new" ? null : edit} jobs={jobs} maps={maps} all={rows ?? []} onClose={() => setEdit(null)} onDone={() => { setEdit(null); onChange(); }} />}
    </section>
  );
}

function JobDialog({ worldId, row, onClose, onDone }: { worldId: string; row: JobRow | null; onClose: () => void; onDone: () => void }) {
  const [name, setName] = useState(row?.name ?? "");
  const [error, setError] = useState("");
  const [confirm, setConfirm] = useState(false);
  async function run(fn: () => Promise<unknown>) { setError(""); try { await fn(); onDone(); } catch (e) { setError((e as Error).message); setConfirm(false); } }
  return (
    <Dialog title={row ? `Modifier le métier « ${row.name} »` : "Nouveau métier"} onClose={onClose}>
      <form onSubmit={(e) => { e.preventDefault(); if (name.trim()) run(() => (row ? api.setRow(worldId, "jobs", row.id, { name }) : api.addRow(worldId, "jobs", { name }))); }}>
        <Field label="Nom du métier"><input value={name} onChange={(e) => setName(e.target.value)} maxLength={60} /></Field>
        {error && <Banner kind="error">{error}</Banner>}
        <div className="actions spread">
          {row ? (confirm
            ? <button type="button" className="btn danger" onClick={() => run(() => api.delRow(worldId, "jobs", row.id))}>Confirmer la suppression</button>
            : <button type="button" className="btn danger" onClick={() => setConfirm(true)}>Supprimer ce métier…</button>) : <span />}
          <span className="toolbar">
            <button type="button" className="btn" onClick={onClose}>Annuler</button>
            <button type="submit" className="btn primary" disabled={!name.trim()}>{row ? "Enregistrer" : "Créer le métier"}</button>
          </span>
        </div>
      </form>
    </Dialog>
  );
}

function ResourceDialog({ worldId, row, jobs, maps, all, onClose, onDone }: { worldId: string; row: ResourceRow | null; jobs: JobRow[]; maps: MapRow[]; all: ResourceRow[]; onClose: () => void; onDone: () => void }) {
  const [f, setF] = useState<ResourceInput>(() => row
    ? { name: row.name, job: row.job, item: row.item, level: row.level, gfx: row.gfx, places: row.places.map((p) => ({ map: p.map, cell: p.cell })) }
    : { name: "", job: jobs[0]?.id ?? 0, item: 0, level: 1, gfx: 0, places: [] });
  const [items, setItems] = useState<ItemRow[]>([]);
  const [tiles, setTiles] = useState<AssetInfo[]>([]);
  const [pickMap, setPickMap] = useState(maps[0]?.id ?? 0);
  const [cell, setCell] = useState(150);
  const [error, setError] = useState("");
  const [confirm, setConfirm] = useState(false);
  useEffect(() => {
    api.rows<ItemRow>(worldId, "items").then((l) => { setItems(l); setF((x) => (x.item ? x : { ...x, item: l[0]?.id ?? 0 })); }).catch(() => {});
    api.assets(worldId, "tile").then((a) => { setTiles(a); setF((x) => (x.gfx ? x : { ...x, gfx: a[0]?.id ?? 0 })); }).catch(() => {});
  }, [worldId]);
  const patch = (p: Partial<ResourceInput>) => setF((x) => ({ ...x, ...p }));
  const map = maps.find((m) => m.id === pickMap);
  // cells already taken on the chosen map: the other resources, and the places chosen here
  const taken = [...all.filter((r) => r.id !== row?.id).flatMap((r) => r.places.filter((p) => p.map === pickMap).map((p) => p.cell)), ...f.places.filter((p) => p.map === pickMap).map((p) => p.cell), ...(map?.isStart ? [map.startCell] : []), ...(map?.doors.map((d) => d.cell) ?? [])];
  const mapName = (id: number) => maps.find((m) => m.id === id)?.name ?? `map ${id}`;
  const addPlace = () => {
    if (f.places.some((p) => p.map === pickMap && p.cell === cell)) return;
    patch({ places: [...f.places, { map: pickMap, cell }] });
  };
  const valid = f.name.trim() && f.job > 0 && f.item > 0 && f.gfx > 0;
  async function run(fn: () => Promise<unknown>) { setError(""); try { await fn(); onDone(); } catch (e) { setError((e as Error).message); setConfirm(false); } }

  return (
    <Dialog title={row ? `Modifier « ${row.name} »` : "Nouvelle ressource"} onClose={onClose} wide>
      <form onSubmit={(e) => { e.preventDefault(); if (valid) run(() => (row ? api.setRow(worldId, "resources", row.id, f) : api.addRow(worldId, "resources", f))); }}>
        {jobs.length === 0 && <Banner kind="error">Aucun métier : ferme cette fenêtre et crée d'abord un métier.</Banner>}
        {items.length === 0 && <Banner kind="error">Aucun objet : la ressource donne un objet, crée-le d'abord dans l'onglet Objets.</Banner>}
        <div className="form-grid">
          <Field label="Nom"><input value={f.name} onChange={(e) => patch({ name: e.target.value })} maxLength={60} /></Field>
          <Field label="Métier"><select value={f.job} onChange={(e) => patch({ job: Number(e.target.value) })}>{jobs.map((j) => <option key={j.id} value={j.id}>{j.name}</option>)}</select></Field>
          <Field label="Objet récolté"><select value={f.item} onChange={(e) => patch({ item: Number(e.target.value) })}>{items.map((i) => <option key={i.id} value={i.id}>{i.name}</option>)}</select></Field>
          <Field label="Niveau de métier requis"><input type="number" min={1} max={200} value={f.level} onChange={(e) => patch({ level: Number(e.target.value) })} /></Field>
        </div>

        <fieldset className="icon-pick">
          <legend className="field-label">Image sur la map</legend>
          {tiles.length === 0 ? <p className="muted small">Aucune image de tuile : importe-en dans l'onglet Images (catégorie Tuiles).</p> : (
            <div className="icons" role="radiogroup" aria-label="Image sur la map">
              {tiles.map((a) => (
                <button type="button" key={a.id} role="radio" aria-checked={a.id === f.gfx} aria-label={`Tuile ${a.name || a.id}`} className={"icon-btn" + (a.id === f.gfx ? " on" : "")} onClick={() => patch({ gfx: a.id })}>
                  <img src={api.assetUrl(worldId, "tile", a.id)} alt="" loading="lazy" />
                </button>
              ))}
            </div>
          )}
        </fieldset>

        <fieldset className="icon-pick">
          <legend className="field-label">Emplacements ({f.places.length})</legend>
          {f.places.length > 0 && (
            <ul className="tpl-list" aria-label="Emplacements choisis">
              {f.places.map((p) => (
                <li key={`${p.map}/${p.cell}`}>
                  <button type="button" className="btn small-btn" aria-label={`Retirer l'emplacement ${mapName(p.map)} cellule ${p.cell}`} onClick={() => patch({ places: f.places.filter((x) => x !== p) })}>{mapName(p.map)} · cellule {p.cell} ✕</button>
                </li>
              ))}
            </ul>
          )}
          <div className="form-grid">
            <Field label="Map"><select value={pickMap} onChange={(e) => setPickMap(Number(e.target.value))}>{maps.map((m) => <option key={m.id} value={m.id}>{m.name}</option>)}</select></Field>
          </div>
          <div className="picker-wrap"><CellPicker label="Choisir la cellule de la ressource" value={cell} onPick={setCell} blocked={map?.blocked} taken={taken} /></div>
          <p className="muted small">Cellule choisie : {cell}. Sombre : obstacle. Jaune : déjà prise. La cellule devient un obstacle ; si tu retires l'emplacement plus tard, libère-la dans la map.</p>
          <button type="button" className="btn small-btn" onClick={addPlace}>Ajouter cet emplacement</button>
        </fieldset>

        {error && <Banner kind="error">{error}</Banner>}
        <div className="actions spread">
          {row ? (confirm
            ? <button type="button" className="btn danger" onClick={() => run(() => api.delRow(worldId, "resources", row.id))}>Confirmer la suppression</button>
            : <button type="button" className="btn danger" onClick={() => setConfirm(true)}>Supprimer cette ressource…</button>) : <span />}
          <span className="toolbar">
            <button type="button" className="btn" onClick={onClose}>Annuler</button>
            <button type="submit" className="btn primary" disabled={!valid}>{row ? "Enregistrer" : "Créer la ressource"}</button>
          </span>
        </div>
      </form>
    </Dialog>
  );
}
