import { useCallback, useEffect, useState } from "react";
import { api, type BoneLibrary, type ClassInput, type ClassRow, type SpellRow } from "../api";
import { BonePicker } from "../BonePicker";
import { Banner, Dialog, Field } from "../components";

export function ClassesPanel({ worldId, rev, onChange }: { worldId: string; rev: number; onChange: () => void }) {
  const [rows, setRows] = useState<ClassRow[] | null>(null);
  const [spells, setSpells] = useState<SpellRow[]>([]);
  const [error, setError] = useState("");
  const [edit, setEdit] = useState<ClassRow | "new" | null>(null);

  const load = useCallback(() => {
    api.rows<ClassRow>(worldId, "classes").then(setRows).catch((e) => setError(e.message));
    api.rows<SpellRow>(worldId, "spells").then(setSpells).catch(() => {});
  }, [worldId]);
  useEffect(load, [load, rev]);

  const nameOf = (family: number) => spells.find((s) => s.family === family)?.name ?? `sort ${family}`;
  async function makeDefault(c: ClassRow) {
    setError("");
    try { await api.setRow(worldId, "classes", c.id, { makeDefault: true }); onChange(); } catch (e) { setError((e as Error).message); }
  }

  return (
    <section className="panel" aria-labelledby="cls-h">
      <div className="panel-head">
        <h2 id="cls-h">Classes jouables</h2>
        <button className="btn primary" onClick={() => setEdit("new")}>+ Nouvelle classe</button>
      </div>
      <p className="muted small">Une classe regroupe un squelette, des textes et un grimoire : les sorts qu'elle apprend, dans l'ordre. Un monde sans classe propose celles que les autres mondes ne revendiquent pas.</p>
      {error && <Banner kind="error">{error}</Banner>}
      {rows === null ? <p className="muted">Chargement…</p> : rows.length === 0 ? (
        <p className="muted empty">Aucune classe dans ce monde. Crée d'abord quelques sorts, puis la classe qui les apprend.</p>
      ) : (
        <ul className="cards">
          {rows.map((c) => (
            <li key={c.id}>
              <div className="card">
                <div className="card-top"><h3>{c.name}</h3>{c.isDefault && <span className="chip ok">par défaut</span>}</div>
                <p className="muted">{c.tagline}</p>
                <p className="small">{c.spells.length} sort{c.spells.length > 1 ? "s" : ""} : {c.spells.slice(0, 4).map(nameOf).join(", ")}{c.spells.length > 4 ? "…" : ""}</p>
                <div className="toolbar">
                  <button className="btn small-btn" onClick={() => setEdit(c)} aria-label={`Modifier la classe ${c.name}`}>Modifier</button>
                  {!c.isDefault && <button className="btn small-btn" onClick={() => makeDefault(c)} aria-label={`Classe ${c.name} par défaut`}>Par défaut</button>}
                </div>
              </div>
            </li>
          ))}
        </ul>
      )}
      {edit && <ClassDialog worldId={worldId} row={edit === "new" ? null : edit} spells={spells} onClose={() => setEdit(null)} onDone={() => { setEdit(null); onChange(); }} />}
    </section>
  );
}

function ClassDialog({ worldId, row, spells, onClose, onDone }: { worldId: string; row: ClassRow | null; spells: SpellRow[]; onClose: () => void; onDone: () => void }) {
  const [f, setF] = useState<ClassInput>(() => row
    ? { name: row.name, tagline: row.tagline, description: row.description, bone: row.bone, size: row.size, spells: row.spells }
    : { name: "", tagline: "", description: "", bone: 0, size: 100, spells: [] });
  const [bones, setBones] = useState<BoneLibrary>({ own: [], library: [] });
  const [error, setError] = useState("");
  const [confirm, setConfirm] = useState(false);
  useEffect(() => { api.bones(worldId).then((b) => { setBones(b); setF((x) => (x.bone ? x : { ...x, bone: b.own[0] ?? 0 })); }).catch(() => {}); }, [worldId]);

  const patch = (p: Partial<ClassInput>) => setF((x) => ({ ...x, ...p }));
  const byFamily = new Map(spells.map((s) => [s.family, s]));
  // a spell another class already owns cannot be taken
  const free = spells.filter((s) => !f.spells.includes(s.family) && !s.usedBy.some((u) => u.kind === "class" && Number(u.id) !== row?.id));
  const move = (i: number, d: number) => {
    const l = [...f.spells];
    [l[i], l[i + d]] = [l[i + d], l[i]];
    patch({ spells: l });
  };
  const valid = f.name.trim() && f.tagline.trim() && f.description.trim() && f.bone > 0 && f.spells.length > 0;
  async function run(fn: () => Promise<unknown>) { setError(""); try { await fn(); onDone(); } catch (e) { setError((e as Error).message); setConfirm(false); } }

  return (
    <Dialog title={row ? `Modifier « ${row.name} »` : "Nouvelle classe"} onClose={onClose} wide>
      <form onSubmit={(e) => { e.preventDefault(); if (valid) run(() => (row ? api.setRow(worldId, "classes", row.id, f) : api.addRow(worldId, "classes", f))); }}>
        <div className="form-grid">
          <Field label="Nom"><input value={f.name} onChange={(e) => patch({ name: e.target.value })} maxLength={40} /></Field>
          <Field label="Rôle (une ligne)"><input value={f.tagline} onChange={(e) => patch({ tagline: e.target.value })} maxLength={120} /></Field>
          <Field label="Taille (%)"><input type="number" min={20} max={400} value={f.size} onChange={(e) => patch({ size: Number(e.target.value) })} /></Field>
        </div>
        <Field label="Description"><textarea rows={3} value={f.description} onChange={(e) => patch({ description: e.target.value })} maxLength={2000} /></Field>
        <BonePicker worldId={worldId} value={f.bone} onChange={(bone) => patch({ bone })} bones={bones} setBones={setBones} onError={setError} />

        <fieldset className="effects">
          <legend className="field-label">Grimoire (dans l'ordre d'apprentissage)</legend>
          {f.spells.length === 0 && <p className="muted small">Aucun sort.</p>}
          {f.spells.map((fam, i) => (
            <div className="effect-row" key={fam}>
              <span className="grow">{byFamily.get(fam)?.name ?? `sort ${fam}`} <span className="muted small">niv. {byFamily.get(fam)?.level ?? "?"} · {byFamily.get(fam)?.ap ?? "?"} PA</span></span>
              <button type="button" className="btn small-btn" disabled={i === 0} onClick={() => move(i, -1)} aria-label={`Monter ${byFamily.get(fam)?.name}`}>↑</button>
              <button type="button" className="btn small-btn" disabled={i === f.spells.length - 1} onClick={() => move(i, 1)} aria-label={`Descendre ${byFamily.get(fam)?.name}`}>↓</button>
              <button type="button" className="btn small-btn" onClick={() => patch({ spells: f.spells.filter((x) => x !== fam) })} aria-label={`Retirer ${byFamily.get(fam)?.name}`}>✕</button>
            </div>
          ))}
          {free.length > 0 ? (
            <select aria-label="Ajouter un sort" value="" onChange={(e) => e.target.value && patch({ spells: [...f.spells, Number(e.target.value)] })}>
              <option value="">+ Ajouter un sort…</option>
              {free.map((s) => <option key={s.family} value={s.family}>{s.name} (niv. {s.level}, {s.ap} PA)</option>)}
            </select>
          ) : <p className="muted small">Aucun autre sort libre : crée-en dans l'onglet Sorts.</p>}
        </fieldset>

        {error && <Banner kind="error">{error}</Banner>}
        <div className="actions spread">
          {row ? (confirm
            ? <button type="button" className="btn danger" onClick={() => run(() => api.delRow(worldId, "classes", row.id))}>Confirmer la suppression</button>
            : <button type="button" className="btn danger" onClick={() => setConfirm(true)}>Supprimer…</button>) : <span />}
          <span className="toolbar">
            <button type="button" className="btn" onClick={onClose}>Annuler</button>
            <button type="submit" className="btn primary" disabled={!valid}>{row ? "Enregistrer" : "Créer la classe"}</button>
          </span>
        </div>
      </form>
    </Dialog>
  );
}
