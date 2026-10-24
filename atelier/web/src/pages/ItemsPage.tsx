import { useCallback, useEffect, useState } from "react";
import { api, type AssetInfo, type ItemInput, type ItemRow, type SetRow } from "../api";
import { Banner, Dialog, Field } from "../components";
import { effectName, EFFECTS, ITEM_TYPES, typeName } from "../gamedata";

interface Props { worldId: string; rev: number; onChange: () => void }

export function ItemsPanel({ worldId, rev, onChange }: Props) {
  const [items, setItems] = useState<ItemRow[] | null>(null);
  const [sets, setSets] = useState<SetRow[]>([]);
  const [icons, setIcons] = useState<AssetInfo[]>([]);
  const [error, setError] = useState("");
  const [edit, setEdit] = useState<ItemRow | "new" | null>(null);
  const [setDlg, setSetDlg] = useState<SetRow | "new" | null>(null);

  const load = useCallback(() => {
    api.rows<ItemRow>(worldId, "items").then(setItems).catch((e) => setError(e.message));
    api.rows<SetRow>(worldId, "sets").then(setSets).catch((e) => setError(e.message));
    api.assets(worldId, "item").then(setIcons).catch(() => setIcons([]));
  }, [worldId]);
  useEffect(load, [load, rev]);

  const setName = (id: number | null) => (id === null ? "" : sets.find((s) => s.id === id)?.name ?? `panoplie ${id}`);

  return (
    <>
      <section className="panel" aria-labelledby="items-h">
        <div className="panel-head">
          <h2 id="items-h">Objets</h2>
          <button className="btn primary" onClick={() => setEdit("new")}>+ Nouvel objet</button>
        </div>
        {error && <Banner kind="error">{error}</Banner>}
        {items === null ? <p className="muted">Chargement…</p> : items.length === 0 ? (
          <p className="muted empty">Aucun objet. Crée le premier : il faut d'abord une icône dans l'onglet Images.</p>
        ) : (
          <table className="table data">
            <thead><tr><th /><th>Nom</th><th>Type</th><th>Niv.</th><th>Panoplie</th><th>Utilisé par</th></tr></thead>
            <tbody>
              {items.map((it) => (
                <tr key={it.id} className="clickable" tabIndex={0} onClick={() => setEdit(it)} onKeyDown={(e) => e.key === "Enter" && setEdit(it)} aria-label={`Modifier ${it.name}`}>
                  <td><img className="icon" src={api.assetUrl(worldId, "item", it.icon)} alt="" loading="lazy" /></td>
                  <td className="wrap"><strong>{it.name}</strong><br /><code className="id">{it.id}</code></td>
                  <td>{typeName(it.type)}</td>
                  <td className="num">{it.level}</td>
                  <td>{setName(it.set)}</td>
                  <td>{it.usedBy.length === 0 ? <span className="muted">—</span> : <span className="chip accent" title={it.usedBy.map((u) => `${u.kind} ${u.id}`).join(", ")}>×{it.usedBy.length}</span>}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </section>

      <section className="panel" aria-labelledby="sets-h">
        <div className="panel-head">
          <h2 id="sets-h">Panoplies</h2>
          <button className="btn" onClick={() => setSetDlg("new")}>+ Nouvelle panoplie</button>
        </div>
        {sets.length === 0 ? <p className="muted empty">Aucune panoplie.</p> : (
          <ul className="sets">
            {sets.map((s) => (
              <li key={s.id}>
                <button className="btn" onClick={() => setSetDlg(s)} aria-label={`Modifier la panoplie ${s.name}`}>{s.name}</button>
                <span className="muted small">{s.items.length} pièce{s.items.length > 1 ? "s" : ""}</span>
              </li>
            ))}
          </ul>
        )}
      </section>

      {edit && (
        <ItemDialog worldId={worldId} row={edit === "new" ? null : edit} sets={sets} icons={icons}
          onClose={() => setEdit(null)} onDone={() => { setEdit(null); onChange(); }} />
      )}
      {setDlg && <SetDialog worldId={worldId} row={setDlg === "new" ? null : setDlg} onClose={() => setSetDlg(null)} onDone={() => { setSetDlg(null); onChange(); }} />}
    </>
  );
}

function ItemDialog({ worldId, row, sets, icons, onClose, onDone }: {
  worldId: string; row: ItemRow | null; sets: SetRow[]; icons: AssetInfo[]; onClose: () => void; onDone: () => void;
}) {
  const [f, setF] = useState<ItemInput>(() => row
    ? { name: row.name, description: row.description, icon: row.icon, type: row.type, level: row.level, price: row.price, weight: row.weight, effects: row.effects.map((e) => [...e]), set: row.set }
    : { name: "", description: "", icon: icons[0]?.id ?? 0, type: 9, level: 1, price: 0, weight: 1, effects: [], set: null });
  const [error, setError] = useState("");
  const [confirmDelete, setConfirmDelete] = useState(false);
  const patch = (p: Partial<ItemInput>) => setF((x) => ({ ...x, ...p }));
  const setEffect = (i: number, e: number[]) => patch({ effects: f.effects.map((x, j) => (j === i ? e : x)) });
  const valid = f.name.trim() && f.icon > 0 && f.level >= 1 && f.level <= 200;

  async function save() {
    setError("");
    try {
      if (row) await api.setRow(worldId, "items", row.id, f); else await api.addRow(worldId, "items", f);
      onDone();
    } catch (e) { setError((e as Error).message); }
  }
  async function remove() {
    setError("");
    try { await api.delRow(worldId, "items", row!.id); onDone(); } catch (e) { setError((e as Error).message); setConfirmDelete(false); }
  }

  return (
    <Dialog title={row ? `Modifier « ${row.name} »` : "Nouvel objet"} onClose={onClose} wide>
      <form onSubmit={(e) => { e.preventDefault(); if (valid) save(); }}>
        <div className="form-grid">
          <Field label="Nom"><input value={f.name} onChange={(e) => patch({ name: e.target.value })} maxLength={80} /></Field>
          <Field label="Type">
            <select value={f.type} onChange={(e) => patch({ type: Number(e.target.value) })}>
              {ITEM_TYPES.map(([id, n]) => <option key={id} value={id}>{n}</option>)}
              {!ITEM_TYPES.some(([id]) => id === f.type) && <option value={f.type}>{typeName(f.type)}</option>}
            </select>
          </Field>
          <Field label="Niveau" error={f.level < 1 || f.level > 200 ? "1 à 200" : undefined}>
            <input type="number" min={1} max={200} value={f.level} onChange={(e) => patch({ level: Number(e.target.value) })} />
          </Field>
          <Field label="Prix"><input type="number" min={0} value={f.price} onChange={(e) => patch({ price: Number(e.target.value) })} /></Field>
          <Field label="Panoplie">
            <select value={f.set ?? ""} onChange={(e) => patch({ set: e.target.value === "" ? null : Number(e.target.value) })}>
              <option value="">Aucune</option>
              {sets.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
            </select>
          </Field>
        </div>
        <Field label="Description (facultative)"><textarea rows={2} value={f.description ?? ""} onChange={(e) => patch({ description: e.target.value })} maxLength={1000} /></Field>

        <fieldset className="icon-pick">
          <legend className="field-label">Icône</legend>
          {icons.length === 0 ? <p className="muted small">Aucune icône : importe-en dans l'onglet Images.</p> : (
            <div className="icons" role="radiogroup" aria-label="Icône">
              {icons.map((a) => (
                <button type="button" key={a.id} role="radio" aria-checked={a.id === f.icon} aria-label={`Icône ${a.name || a.id}`}
                  className={"icon-btn" + (a.id === f.icon ? " on" : "")} onClick={() => patch({ icon: a.id })}>
                  <img src={api.assetUrl(worldId, "item", a.id)} alt="" loading="lazy" />
                </button>
              ))}
            </div>
          )}
        </fieldset>

        <fieldset className="effects">
          <legend className="field-label">Effets</legend>
          {f.effects.length === 0 && <p className="muted small">Aucun effet.</p>}
          {f.effects.map((e, i) => (
            <div className="effect-row" key={i}>
              <select aria-label={`Effet ${i + 1}`} value={e[0]} onChange={(ev) => setEffect(i, [Number(ev.target.value), e[1], e[2] ?? 0, 0])}>
                {EFFECTS.map(([id, n]) => <option key={id} value={id}>{n}</option>)}
                {!EFFECTS.some(([id]) => id === e[0]) && <option value={e[0]}>{effectName(e[0])}</option>}
              </select>
              <input type="number" aria-label={`Valeur min ${i + 1}`} value={e[1]} onChange={(ev) => setEffect(i, [e[0], Number(ev.target.value), e[2] ?? 0, 0])} />
              <span className="muted">à</span>
              <input type="number" aria-label={`Valeur max ${i + 1}`} value={e[2] ?? 0} onChange={(ev) => setEffect(i, [e[0], e[1], Number(ev.target.value), 0])} />
              <button type="button" className="btn small-btn" onClick={() => patch({ effects: f.effects.filter((_, j) => j !== i) })} aria-label={`Retirer l'effet ${i + 1}`}>✕</button>
            </div>
          ))}
          <button type="button" className="btn small-btn" onClick={() => patch({ effects: [...f.effects, [125, 1, 0, 0]] })}>+ Ajouter un effet</button>
        </fieldset>

        {error && <Banner kind="error">{error}</Banner>}
        <div className="actions spread">
          {row ? (confirmDelete
            ? <button type="button" className="btn danger" onClick={remove}>Confirmer la suppression</button>
            : <button type="button" className="btn danger" onClick={() => setConfirmDelete(true)}>Supprimer…</button>) : <span />}
          <span className="toolbar">
            <button type="button" className="btn" onClick={onClose}>Annuler</button>
            <button type="submit" className="btn primary" disabled={!valid}>{row ? "Enregistrer" : "Créer l'objet"}</button>
          </span>
        </div>
      </form>
    </Dialog>
  );
}

function SetDialog({ worldId, row, onClose, onDone }: { worldId: string; row: SetRow | null; onClose: () => void; onDone: () => void }) {
  const [name, setName] = useState(row?.name ?? "");
  const [error, setError] = useState("");
  const [confirm, setConfirm] = useState(false);
  async function run(f: () => Promise<unknown>) { setError(""); try { await f(); onDone(); } catch (e) { setError((e as Error).message); setConfirm(false); } }
  return (
    <Dialog title={row ? `Panoplie « ${row.name} »` : "Nouvelle panoplie"} onClose={onClose}>
      <form onSubmit={(e) => { e.preventDefault(); if (name.trim()) run(() => (row ? api.setRow(worldId, "sets", row.id, { name }) : api.addRow(worldId, "sets", { name }))); }}>
        <Field label="Nom" hint={row ? "Pour ajouter ou retirer des pièces, modifie l'objet et choisis sa panoplie." : undefined}>
          <input value={name} onChange={(e) => setName(e.target.value)} maxLength={80} />
        </Field>
        {error && <Banner kind="error">{error}</Banner>}
        <div className="actions spread">
          {row ? (confirm
            ? <button type="button" className="btn danger" onClick={() => run(() => api.delRow(worldId, "sets", row.id))}>Confirmer la suppression</button>
            : <button type="button" className="btn danger" onClick={() => setConfirm(true)}>Supprimer…</button>) : <span />}
          <span className="toolbar">
            <button type="button" className="btn" onClick={onClose}>Annuler</button>
            <button type="submit" className="btn primary" disabled={!name.trim() || name === row?.name}>{row ? "Enregistrer" : "Créer"}</button>
          </span>
        </div>
      </form>
    </Dialog>
  );
}
