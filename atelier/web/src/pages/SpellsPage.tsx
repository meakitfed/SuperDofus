import { useCallback, useEffect, useState } from "react";
import { api, type AssetInfo, type EffectInput, type SpellInput, type SpellRow } from "../api";
import { Banner, Dialog, Field } from "../components";

const KIND: Record<string, string> = { damage: "Dommages", heal: "Soin", shield: "Bouclier", ap: "PA", mp: "PM" };
const TARGET: Record<string, string> = { enemies: "Ennemis", allies: "Alliés", all: "Tous", caster: "Lanceur" };
const ELEMENT: Record<string, string> = { neutral: "Neutre", earth: "Terre", fire: "Feu", water: "Eau", air: "Air" };
const SHAPE: Record<string, string> = { point: "Case", circle: "Cercle", cross: "Croix", line: "Ligne", ring: "Anneau" };

export function SpellsPanel({ worldId, rev, onChange }: { worldId: string; rev: number; onChange: () => void }) {
  const [rows, setRows] = useState<SpellRow[] | null>(null);
  const [icons, setIcons] = useState<AssetInfo[]>([]);
  const [error, setError] = useState("");
  const [edit, setEdit] = useState<SpellRow | "new" | null>(null);

  const load = useCallback(() => {
    api.rows<SpellRow>(worldId, "spells").then(setRows).catch((e) => setError(e.message));
    api.assets(worldId, "spell").then(setIcons).catch(() => setIcons([]));
  }, [worldId]);
  useEffect(load, [load, rev]);

  return (
    <section className="panel" aria-labelledby="spells-h">
      <div className="panel-head">
        <h2 id="spells-h">Sorts</h2>
        <button className="btn primary" onClick={() => setEdit("new")}>+ Nouveau sort</button>
      </div>
      <p className="muted small">Un sort est ici un grade lançable. Les sorts à effets riches (poussée, glyphe, invocation…) restent modifiables sur leurs réglages, leurs effets sont verrouillés.</p>
      {error && <Banner kind="error">{error}</Banner>}
      {rows === null ? <p className="muted">Chargement…</p> : rows.length === 0 ? (
        <p className="muted empty">Aucun sort. Importe une icône dans l'onglet Images, puis crée le premier.</p>
      ) : (
        <table className="table data">
          <thead><tr><th /><th>Nom</th><th>PA</th><th>Portée</th><th>Effets</th><th>Utilisé par</th></tr></thead>
          <tbody>
            {rows.map((r) => (
              <tr key={r.id} className="clickable" tabIndex={0} onClick={() => setEdit(r)} onKeyDown={(e) => e.key === "Enter" && setEdit(r)} aria-label={`Modifier ${r.name}`}>
                <td><img className="icon" src={api.assetUrl(worldId, "spell", r.icon)} alt="" loading="lazy" /></td>
                <td className="wrap"><strong>{r.name}</strong><br /><code className="id">{r.id}</code></td>
                <td className="num">{r.ap}</td>
                <td className="num">{r.range[0]}–{r.range[1]}</td>
                <td className="wrap">{r.locked ? <span className="chip">verrouillé : {r.complexKinds.join(", ")}</span> : r.effects.map((e) => `${KIND[e.kind]} ${e.min}–${e.max}`).join(", ")}</td>
                <td>{r.usedBy.length ? <span className="chip accent" title={r.usedBy.map((u) => `${u.kind} ${u.id}`).join(", ")}>×{r.usedBy.length}</span> : <span className="muted">—</span>}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
      {edit && <SpellDialog worldId={worldId} row={edit === "new" ? null : edit} icons={icons} onClose={() => setEdit(null)} onDone={() => { setEdit(null); onChange(); }} />}
    </section>
  );
}

const NEW_EFFECT: EffectInput = { kind: "damage", target: "enemies", min: 5, max: 8, element: "neutral" };

function SpellDialog({ worldId, row, icons, onClose, onDone }: { worldId: string; row: SpellRow | null; icons: AssetInfo[]; onClose: () => void; onDone: () => void }) {
  const [f, setF] = useState<SpellInput>(() => row
    ? { name: row.name, description: row.description, icon: row.icon, level: row.level, ap: row.ap, range: row.range, los: row.los, inLine: row.inLine, perTurn: row.perTurn, cooldown: row.cooldown, crit: row.crit, color: row.color, area: row.area, effects: row.locked ? undefined : row.effects }
    : { name: "", description: "", icon: icons[0]?.id ?? 0, level: 1, ap: 3, range: [1, 4], los: true, inLine: false, perTurn: 2, cooldown: 0, crit: 5, color: "#d8d4e0", area: { shape: "point", size: 0 }, effects: [{ ...NEW_EFFECT }] });
  const [error, setError] = useState("");
  const [confirm, setConfirm] = useState(false);
  const patch = (p: Partial<SpellInput>) => setF((x) => ({ ...x, ...p }));
  const effects = f.effects;
  const setEffect = (i: number, p: Partial<EffectInput>) => patch({ effects: effects!.map((e, j) => (j === i ? { ...e, ...p } : e)) });
  const num = (v: string) => Number(v);
  const valid = f.name.trim() && f.icon > 0 && (row?.locked || (effects && effects.length > 0));

  async function run(fn: () => Promise<unknown>) { setError(""); try { await fn(); onDone(); } catch (e) { setError((e as Error).message); setConfirm(false); } }

  return (
    <Dialog title={row ? `Modifier « ${row.name} »` : "Nouveau sort"} onClose={onClose} wide>
      <form onSubmit={(e) => { e.preventDefault(); if (valid) run(() => (row ? api.setRow(worldId, "spells", row.id, f) : api.addRow(worldId, "spells", f))); }}>
        <div className="form-grid">
          <Field label="Nom"><input value={f.name} onChange={(e) => patch({ name: e.target.value })} maxLength={80} /></Field>
          <Field label="PA"><input type="number" min={0} max={20} value={f.ap} onChange={(e) => patch({ ap: num(e.target.value) })} /></Field>
          <Field label="Niveau requis"><input type="number" min={1} max={200} value={f.level} onChange={(e) => patch({ level: num(e.target.value) })} /></Field>
          <Field label="Portée min"><input type="number" min={0} max={63} value={f.range[0]} onChange={(e) => patch({ range: [num(e.target.value), f.range[1]] })} /></Field>
          <Field label="Portée max"><input type="number" min={0} max={63} value={f.range[1]} onChange={(e) => patch({ range: [f.range[0], num(e.target.value)] })} /></Field>
          <Field label="Lancers par tour"><input type="number" min={0} max={20} value={f.perTurn} onChange={(e) => patch({ perTurn: num(e.target.value) })} /></Field>
          <Field label="Relance (tours)"><input type="number" min={0} max={20} value={f.cooldown} onChange={(e) => patch({ cooldown: num(e.target.value) })} /></Field>
          <Field label="Critique (%)"><input type="number" min={0} max={100} value={f.crit} onChange={(e) => patch({ crit: num(e.target.value) })} /></Field>
          <Field label="Couleur de l'impact"><input type="color" value={f.color} onChange={(e) => patch({ color: e.target.value })} /></Field>
          <Field label="Zone">
            <select value={f.area.shape} onChange={(e) => patch({ area: { ...f.area, shape: e.target.value as SpellInput["area"]["shape"] } })}>
              {Object.entries(SHAPE).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
            </select>
          </Field>
          <Field label="Taille de zone"><input type="number" min={0} max={10} value={f.area.size} onChange={(e) => patch({ area: { ...f.area, size: num(e.target.value) } })} /></Field>
        </div>
        <label className="check"><input type="checkbox" checked={f.los} onChange={(e) => patch({ los: e.target.checked })} /> Ligne de vue requise</label>
        <label className="check"><input type="checkbox" checked={f.inLine} onChange={(e) => patch({ inLine: e.target.checked })} /> Lancer en ligne uniquement</label>
        <Field label="Description (facultative)"><textarea rows={2} value={f.description ?? ""} onChange={(e) => patch({ description: e.target.value })} maxLength={1000} /></Field>

        <fieldset className="icon-pick">
          <legend className="field-label">Icône</legend>
          {icons.length === 0 ? <p className="muted small">Aucune icône de sort : importe-en dans l'onglet Images.</p> : (
            <div className="icons" role="radiogroup" aria-label="Icône">
              {icons.map((a) => (
                <button type="button" key={a.id} role="radio" aria-checked={a.id === f.icon} aria-label={`Icône ${a.name || a.id}`} className={"icon-btn" + (a.id === f.icon ? " on" : "")} onClick={() => patch({ icon: a.id })}>
                  <img src={api.assetUrl(worldId, "spell", a.id)} alt="" loading="lazy" />
                </button>
              ))}
            </div>
          )}
        </fieldset>

        <fieldset className="effects">
          <legend className="field-label">Effets</legend>
          {!effects ? <p className="muted small">Effets verrouillés ({row?.complexKinds.join(", ")}) : conservés tels quels.</p> : <>
            {effects.map((e, i) => (
              <div className="effect-row wrap" key={i}>
                <select aria-label={`Type ${i + 1}`} value={e.kind} onChange={(ev) => setEffect(i, { kind: ev.target.value as EffectInput["kind"], element: "neutral", duration: 1, sign: -1 })}>
                  {Object.entries(KIND).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
                </select>
                <select aria-label={`Cible ${i + 1}`} value={e.target} onChange={(ev) => setEffect(i, { target: ev.target.value as EffectInput["target"] })}>
                  {Object.entries(TARGET).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
                </select>
                {(e.kind === "damage" || e.kind === "heal") && (
                  <select aria-label={`Élément ${i + 1}`} value={e.element ?? "neutral"} onChange={(ev) => setEffect(i, { element: ev.target.value as EffectInput["element"] })}>
                    {Object.entries(ELEMENT).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
                  </select>
                )}
                {(e.kind === "ap" || e.kind === "mp") && (
                  <select aria-label={`Sens ${i + 1}`} value={e.sign ?? 1} onChange={(ev) => setEffect(i, { sign: Number(ev.target.value) as 1 | -1 })}>
                    <option value={1}>Gain</option><option value={-1}>Retrait</option>
                  </select>
                )}
                <input type="number" min={0} aria-label={`Minimum ${i + 1}`} value={e.min} onChange={(ev) => setEffect(i, { min: num(ev.target.value) })} />
                <span className="muted">à</span>
                <input type="number" min={0} aria-label={`Maximum ${i + 1}`} value={e.max} onChange={(ev) => setEffect(i, { max: num(ev.target.value) })} />
                {e.kind !== "damage" && e.kind !== "heal" && (
                  <><input type="number" min={0} max={20} aria-label={`Durée ${i + 1}`} value={e.duration ?? 1} onChange={(ev) => setEffect(i, { duration: num(ev.target.value) })} /><span className="muted">tours</span></>
                )}
                <button type="button" className="btn small-btn" onClick={() => patch({ effects: effects.filter((_, j) => j !== i) })} aria-label={`Retirer l'effet ${i + 1}`}>✕</button>
              </div>
            ))}
            <button type="button" className="btn small-btn" onClick={() => patch({ effects: [...effects, { ...NEW_EFFECT }] })}>+ Ajouter un effet</button>
          </>}
        </fieldset>

        {error && <Banner kind="error">{error}</Banner>}
        <div className="actions spread">
          {row ? (confirm
            ? <button type="button" className="btn danger" onClick={() => run(() => api.delRow(worldId, "spells", row.id))}>Confirmer la suppression</button>
            : <button type="button" className="btn danger" onClick={() => setConfirm(true)}>Supprimer…</button>) : <span />}
          <span className="toolbar">
            <button type="button" className="btn" onClick={onClose}>Annuler</button>
            <button type="submit" className="btn primary" disabled={!valid}>{row ? "Enregistrer" : "Créer le sort"}</button>
          </span>
        </div>
      </form>
    </Dialog>
  );
}
