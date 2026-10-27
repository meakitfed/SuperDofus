import { useCallback, useEffect, useState } from "react";
import { api, type ItemRow, type MapRow } from "../api";
import type { RecipeInput, RecipeRow, WorkshopInput, WorkshopRow } from "../../../core/editors_crafts";
import type { JobRow, ResourceRow } from "../../../core/editors_resources";
import { PlacesPicker } from "../PlacesPicker";
import { Banner, Dialog, Field } from "../components";

export function CraftsPanel({ worldId, rev, onChange }: { worldId: string; rev: number; onChange: () => void }) {
  const [shops, setShops] = useState<WorkshopRow[] | null>(null);
  const [recipes, setRecipes] = useState<RecipeRow[] | null>(null);
  const [jobs, setJobs] = useState<JobRow[]>([]);
  const [maps, setMaps] = useState<MapRow[]>([]);
  const [res, setRes] = useState<ResourceRow[]>([]);
  const [error, setError] = useState("");
  const [shop, setShop] = useState<WorkshopRow | "new" | null>(null);
  const [recipe, setRecipe] = useState<RecipeRow | "new" | null>(null);

  const load = useCallback(() => {
    api.rows<WorkshopRow>(worldId, "workshops").then(setShops).catch((e) => setError(e.message));
    api.rows<RecipeRow>(worldId, "recipes").then(setRecipes).catch((e) => setError(e.message));
    api.rows<JobRow>(worldId, "jobs").then(setJobs).catch(() => {});
    api.rows<MapRow>(worldId, "maps").then(setMaps).catch(() => {});
    api.rows<ResourceRow>(worldId, "resources").then(setRes).catch(() => {});
  }, [worldId]);
  useEffect(load, [load, rev]);

  return (
    <section className="panel" aria-labelledby="craft-h">
      <div className="panel-head">
        <h2 id="craft-h">Artisanat</h2>
        <span className="toolbar">
          <button className="btn" onClick={() => setShop("new")}>+ Nouvel atelier</button>
          <button className="btn primary" onClick={() => setRecipe("new")}>+ Nouvelle recette</button>
        </span>
      </div>
      <p className="muted small">Un atelier (Forge, Cuisine…) est posé sur une map : on l'ouvre pour fabriquer. Une recette transforme jusqu'à 8 objets du monde en un autre objet, dans un atelier. Les métiers se créent dans l'onglet Ressources.</p>
      {error && <Banner kind="error">{error}</Banner>}

      <h3>Ateliers</h3>
      {shops === null ? <p className="muted">Chargement…</p> : shops.length === 0 ? <p className="muted small">Aucun atelier.</p> : (
        <table className="table data">
          <thead><tr><th>Atelier</th><th>Métier</th><th>Recettes</th><th>Emplacements</th><th /></tr></thead>
          <tbody>
            {shops.map((s) => (
              <tr key={s.id}>
                <td className="wrap"><strong>{s.name}</strong><br /><code className="id">{s.id}</code></td>
                <td>{s.jobName || <span className="muted">—</span>}</td>
                <td className="num">{s.recipes}</td>
                <td>{s.places.length === 0 ? <span className="chip warn">aucun</span> : <span className="chip ok">{s.places.length}</span>}</td>
                <td className="row-actions"><button className="btn small-btn" aria-label={`Modifier l'atelier ${s.name}`} onClick={() => setShop(s)}>Modifier</button></td>
              </tr>
            ))}
          </tbody>
        </table>
      )}

      <h3>Recettes</h3>
      {recipes === null ? <p className="muted">Chargement…</p> : recipes.length === 0 ? <p className="muted empty">Aucune recette. Crée un atelier puis une première recette.</p> : (
        <table className="table data">
          <thead><tr><th>Fabrique</th><th>À partir de</th><th>Atelier</th><th /></tr></thead>
          <tbody>
            {recipes.map((r) => (
              <tr key={r.id}>
                <td className="wrap"><strong>{r.resultName}</strong><br /><span className="muted small">niv. {r.level}</span></td>
                <td>{r.ingredients.map((g) => `${g.qty} × ${g.name || g.item}`).join(", ")}</td>
                <td>{r.skillName}{r.jobName ? <span className="muted"> · {r.jobName}</span> : null}</td>
                <td className="row-actions"><button className="btn small-btn" aria-label={`Modifier la recette ${r.resultName}`} onClick={() => setRecipe(r)}>Modifier</button></td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
      {shop && <WorkshopDialog worldId={worldId} row={shop === "new" ? null : shop} jobs={jobs} maps={maps} all={shops ?? []} others={res} onClose={() => setShop(null)} onDone={() => { setShop(null); onChange(); }} />}
      {recipe && <RecipeDialog worldId={worldId} row={recipe === "new" ? null : recipe} shops={shops ?? []} onClose={() => setRecipe(null)} onDone={() => { setRecipe(null); onChange(); }} />}
    </section>
  );
}

function WorkshopDialog({ worldId, row, jobs, maps, all, others, onClose, onDone }: { worldId: string; row: WorkshopRow | null; jobs: JobRow[]; maps: MapRow[]; all: WorkshopRow[]; others: ResourceRow[]; onClose: () => void; onDone: () => void }) {
  const [f, setF] = useState<WorkshopInput>(() => row
    ? { name: row.name, job: row.job, gfx: row.gfx, places: row.places.map((p) => ({ map: p.map, cell: p.cell })) }
    : { name: "", job: jobs[0]?.id ?? 0, gfx: 0, places: [] });
  const [error, setError] = useState("");
  const [confirm, setConfirm] = useState(false);
  const patch = (p: Partial<WorkshopInput>) => setF((x) => ({ ...x, ...p }));
  const valid = f.name.trim() && f.job > 0 && f.gfx > 0;
  async function run(fn: () => Promise<unknown>) { setError(""); try { await fn(); onDone(); } catch (e) { setError((e as Error).message); setConfirm(false); } }
  return (
    <Dialog title={row ? `Modifier l'atelier « ${row.name} »` : "Nouvel atelier"} onClose={onClose} wide>
      <form onSubmit={(e) => { e.preventDefault(); if (valid) run(() => (row ? api.setRow(worldId, "workshops", row.id, f) : api.addRow(worldId, "workshops", f))); }}>
        {jobs.length === 0 && <Banner kind="error">Aucun métier : ferme cette fenêtre et crée-en un dans l'onglet Ressources.</Banner>}
        <div className="form-grid">
          <Field label="Nom"><input value={f.name} onChange={(e) => patch({ name: e.target.value })} maxLength={60} /></Field>
          <Field label="Métier"><select value={f.job} onChange={(e) => patch({ job: Number(e.target.value) })}>{jobs.map((j) => <option key={j.id} value={j.id}>{j.name}</option>)}</select></Field>
        </div>
        <PlacesPicker worldId={worldId} maps={maps} gfx={f.gfx} places={f.places} onGfx={(gfx) => patch({ gfx })} onPlaces={(places) => patch({ places })}
          takenBy={(m) => [...all.filter((r) => r.id !== row?.id), ...others].flatMap((r) => r.places.filter((p) => p.map === m).map((p) => p.cell))} />
        {error && <Banner kind="error">{error}</Banner>}
        <div className="actions spread">
          {row ? (confirm
            ? <button type="button" className="btn danger" onClick={() => run(() => api.delRow(worldId, "workshops", row.id))}>Confirmer la suppression</button>
            : <button type="button" className="btn danger" onClick={() => setConfirm(true)}>Supprimer cet atelier…</button>) : <span />}
          <span className="toolbar">
            <button type="button" className="btn" onClick={onClose}>Annuler</button>
            <button type="submit" className="btn primary" disabled={!valid}>{row ? "Enregistrer" : "Créer l'atelier"}</button>
          </span>
        </div>
      </form>
    </Dialog>
  );
}

function RecipeDialog({ worldId, row, shops, onClose, onDone }: { worldId: string; row: RecipeRow | null; shops: WorkshopRow[]; onClose: () => void; onDone: () => void }) {
  const [items, setItems] = useState<ItemRow[]>([]);
  const [f, setF] = useState<RecipeInput>(() => row
    ? { result: row.id, skill: row.skill, ingredients: row.ingredients.map((g) => ({ item: g.item, qty: g.qty })) }
    : { result: 0, skill: shops[0]?.id ?? 0, ingredients: [] });
  const [error, setError] = useState("");
  const [confirm, setConfirm] = useState(false);
  useEffect(() => {
    api.rows<ItemRow>(worldId, "items").then((l) => { setItems(l); setF((x) => (x.result || row ? x : { ...x, result: l[0]?.id ?? 0 })); }).catch(() => {});
  }, [worldId, row]);
  const patch = (p: Partial<RecipeInput>) => setF((x) => ({ ...x, ...p }));
  const setIng = (i: number, p: Partial<{ item: number; qty: number }>) => patch({ ingredients: f.ingredients.map((g, j) => (j === i ? { ...g, ...p } : g)) });
  const free = items.find((it) => it.id !== f.result && !f.ingredients.some((g) => g.item === it.id));
  const valid = f.result > 0 && f.skill > 0 && f.ingredients.length > 0;
  async function run(fn: () => Promise<unknown>) { setError(""); try { await fn(); onDone(); } catch (e) { setError((e as Error).message); setConfirm(false); } }
  return (
    <Dialog title={row ? `Modifier la recette « ${row.resultName} »` : "Nouvelle recette"} onClose={onClose} wide>
      <form onSubmit={(e) => { e.preventDefault(); if (valid) run(() => (row ? api.setRow(worldId, "recipes", row.id, f) : api.addRow(worldId, "recipes", f))); }}>
        {shops.length === 0 && <Banner kind="error">Aucun atelier : ferme cette fenêtre et crée-en un d'abord.</Banner>}
        <div className="form-grid">
          <Field label="Objet fabriqué" hint={row ? "L'objet ne change pas : supprime la recette pour en refaire une." : undefined}>
            <select value={f.result} disabled={!!row} onChange={(e) => patch({ result: Number(e.target.value) })}>{items.map((it) => <option key={it.id} value={it.id}>{it.name}</option>)}</select>
          </Field>
          <Field label="Atelier"><select value={f.skill} onChange={(e) => patch({ skill: Number(e.target.value) })}>{shops.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}</select></Field>
        </div>
        <fieldset className="icon-pick">
          <legend className="field-label">Ingrédients ({f.ingredients.length} sur 8)</legend>
          {f.ingredients.map((g, i) => (
            <div className="lib-bar" key={i}>
              <select aria-label={`Ingrédient ${i + 1}`} value={g.item} onChange={(e) => setIng(i, { item: Number(e.target.value) })}>{items.filter((it) => it.id !== f.result).map((it) => <option key={it.id} value={it.id}>{it.name}</option>)}</select>
              <input aria-label={`Quantité de l'ingrédient ${i + 1}`} type="number" min={1} max={999} value={g.qty} onChange={(e) => setIng(i, { qty: Number(e.target.value) })} />
              <button type="button" className="btn small-btn" aria-label={`Retirer l'ingrédient ${i + 1}`} onClick={() => patch({ ingredients: f.ingredients.filter((_, j) => j !== i) })}>✕</button>
            </div>
          ))}
          <button type="button" className="btn small-btn" disabled={!free || f.ingredients.length >= 8} onClick={() => free && patch({ ingredients: [...f.ingredients, { item: free.id, qty: 1 }] })}>Ajouter un ingrédient</button>
          <p className="muted small">Le joueur doit mettre exactement ces objets et ces quantités dans l'atelier. Deux recettes d'un même atelier ne peuvent pas avoir les mêmes ingrédients.</p>
        </fieldset>
        {error && <Banner kind="error">{error}</Banner>}
        <div className="actions spread">
          {row ? (confirm
            ? <button type="button" className="btn danger" onClick={() => run(() => api.delRow(worldId, "recipes", row.id))}>Confirmer la suppression</button>
            : <button type="button" className="btn danger" onClick={() => setConfirm(true)}>Supprimer cette recette…</button>) : <span />}
          <span className="toolbar">
            <button type="button" className="btn" onClick={onClose}>Annuler</button>
            <button type="submit" className="btn primary" disabled={!valid}>{row ? "Enregistrer" : "Créer la recette"}</button>
          </span>
        </div>
      </form>
    </Dialog>
  );
}
