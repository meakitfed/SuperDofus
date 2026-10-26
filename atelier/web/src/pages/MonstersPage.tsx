import { useCallback, useEffect, useState } from "react";
import { api, type AssetInfo, type BoneLibrary, type GradeInput, type ItemRow, type MonsterInput, type MonsterRow, type SpellRow, type ZoneRow } from "../api";
import { Banner, Dialog, Field } from "../components";
import { BonePicker } from "../BonePicker";

const STATS: [keyof GradeInput["stats"], string][] = [
  ["strength", "Force"], ["intelligence", "Intelligence"], ["chance", "Chance"], ["agility", "Agilité"], ["wisdom", "Sagesse"], ["ap_dodge", "Esquive PA"], ["mp_dodge", "Esquive PM"],
];
const RES: [keyof GradeInput["res"], string][] = [["neutral", "Neutre"], ["earth", "Terre"], ["fire", "Feu"], ["water", "Eau"], ["air", "Air"]];

const blankGrade = (level: number): GradeInput => ({
  level, hp: 20, ap: 6, mp: 3, xp: 50,
  stats: { strength: 0, intelligence: 0, chance: 0, agility: 0, wisdom: 0, ap_dodge: 0, mp_dodge: 0 },
  res: { earth: 0, fire: 0, water: 0, air: 0, neutral: 0 },
  spells: [], drops: [], kamas: [0, 0], aggro: { zone: 2, level_diff: 60, delay: 8000 },
});

export function MonstersPanel({ worldId, rev, onChange }: { worldId: string; rev: number; onChange: () => void }) {
  const [rows, setRows] = useState<MonsterRow[] | null>(null);
  const [zones, setZones] = useState<ZoneRow[]>([]);
  const [error, setError] = useState("");
  const [edit, setEdit] = useState<MonsterRow | "new" | null>(null);
  const [zoneLevel, setZoneLevel] = useState(5);

  const load = useCallback(() => {
    api.rows<MonsterRow>(worldId, "monsters").then(setRows).catch((e) => setError(e.message));
    api.rows<ZoneRow>(worldId, "zones").then(setZones).catch((e) => setError(e.message));
  }, [worldId]);
  useEffect(load, [load, rev]);

  async function zoneOp(fn: () => Promise<unknown>) { setError(""); try { await fn(); onChange(); } catch (e) { setError((e as Error).message); } }

  return (
    <>
      <section className="panel" aria-labelledby="mon-h">
        <div className="panel-head">
          <h2 id="mon-h">Monstres</h2>
          <button className="btn primary" onClick={() => setEdit("new")}>+ Nouveau monstre</button>
        </div>
        {error && <Banner kind="error">{error}</Banner>}
        {rows === null ? <p className="muted">Chargement…</p> : rows.length === 0 ? (
          <p className="muted empty">Aucun monstre. Il faut un squelette, un portrait (onglet Images) et, pour qu'il se batte, des sorts.</p>
        ) : (
          <table className="table data">
            <thead><tr><th /><th>Nom</th><th>Niveaux</th><th>Zones</th><th>Butin</th></tr></thead>
            <tbody>
              {rows.map((r) => (
                <tr key={r.id} className="clickable" tabIndex={0} onClick={() => setEdit(r)} onKeyDown={(e) => e.key === "Enter" && setEdit(r)} aria-label={`Modifier ${r.name}`}>
                  <td><img className="icon" src={api.assetUrl(worldId, "monster", r.portrait)} alt="" loading="lazy" /></td>
                  <td className="wrap"><strong>{r.name}</strong> {r.boss && <span className="chip">boss</span>}<br /><code className="id">{r.id}</code></td>
                  <td className="num">{r.grades.map((g) => g.level).join(" · ")}</td>
                  <td>{r.zones.length ? r.zones.length : <span className="chip warn">aucune</span>}</td>
                  <td className="num">{new Set(r.grades.flatMap((g) => g.drops.map((d) => d.item))).size}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </section>

      <section className="panel" aria-labelledby="zones-h">
        <div className="panel-head">
          <h2 id="zones-h">Zones de monstres</h2>
          <span className="toolbar">
            <label className="inline">Niveau <input type="number" min={1} max={200} value={zoneLevel} onChange={(e) => setZoneLevel(Number(e.target.value))} aria-label="Niveau de la nouvelle zone" /></label>
            <button className="btn" onClick={() => zoneOp(() => api.addRow(worldId, "zones", { level: zoneLevel }))}>+ Nouvelle zone</button>
          </span>
        </div>
        <p className="muted small">Un monstre n'apparaît que dans les zones où il est placé. Une zone est ensuite attribuée à une map (éditeur de maps, à venir).</p>
        {zones.length === 0 ? <p className="muted empty">Aucune zone.</p> : (
          <ul className="sets">
            {zones.map((z) => (
              <li key={z.key}>
                <span className="chip accent">niveau {z.level}</span>
                <span className="muted small">{z.monsters.length} monstre{z.monsters.length > 1 ? "s" : ""} · <code>{z.key}</code></span>
                <button className="btn small-btn" disabled={z.monsters.length > 0} onClick={() => zoneOp(() => api.delRow(worldId, "zones", Number(z.key)))} aria-label={`Supprimer la zone ${z.key}`}>Supprimer</button>
              </li>
            ))}
          </ul>
        )}
      </section>

      {edit && <MonsterDialog worldId={worldId} row={edit === "new" ? null : edit} zones={zones} onClose={() => setEdit(null)} onDone={() => { setEdit(null); onChange(); }} />}
    </>
  );
}

function MonsterDialog({ worldId, row, zones, onClose, onDone }: { worldId: string; row: MonsterRow | null; zones: ZoneRow[]; onClose: () => void; onDone: () => void }) {
  const [portraits, setPortraits] = useState<AssetInfo[]>([]);
  const [bones, setBones] = useState<BoneLibrary>({ own: [], library: [] });
  const [spells, setSpells] = useState<SpellRow[]>([]);
  const [items, setItems] = useState<ItemRow[]>([]);
  const [f, setF] = useState<MonsterInput>(() => row
    ? { name: row.name, bone: row.bone, size: row.size, portrait: row.portrait, grades: structuredClone(row.grades), zones: row.zones }
    : { name: "", bone: 0, size: 100, portrait: 0, grades: [blankGrade(1)], zones: [] });
  const [g, setG] = useState(0);
  const [error, setError] = useState("");
  const [confirm, setConfirm] = useState(false);
  const readOnly = row?.boss ?? false;

  useEffect(() => {
    api.assets(worldId, "monster").then((a) => { setPortraits(a); setF((x) => (x.portrait ? x : { ...x, portrait: a[0]?.id ?? 0 })); }).catch(() => {});
    api.bones(worldId).then((b) => { setBones(b); setF((x) => (x.bone ? x : { ...x, bone: b.own[0] ?? 0 })); }).catch(() => {});
    api.rows<SpellRow>(worldId, "spells").then(setSpells).catch(() => {});
    api.rows<ItemRow>(worldId, "items").then(setItems).catch(() => {});
  }, [worldId]);

  const patch = (p: Partial<MonsterInput>) => setF((x) => ({ ...x, ...p }));

  // start from a monster of the game: stats and look come along, spells and drops are chosen here
  const [tplQuery, setTplQuery] = useState("");
  const [tpls, setTpls] = useState<(MonsterInput & { source: number })[] | null>(null);
  const [tplNotes, setTplNotes] = useState<string[]>([]);
  async function searchTpl() {
    setError(""); setTplNotes([]);
    try { setTpls(await api.monsterTemplates(tplQuery)); } catch (e) { setTpls(null); setError((e as Error).message); }
  }
  async function useTpl(t: MonsterInput & { source: number }) {
    setError("");
    const notes: string[] = [];
    let bone = f.bone, portrait = f.portrait;
    try { await api.importBone(worldId, "dofus", t.bone); bone = t.bone; } catch (e) {
      if (/déjà présent/.test((e as Error).message)) bone = t.bone; else notes.push("Son squelette n'est pas disponible ici : choisis-en un.");
    }
    try {
      const [r] = await api.importFromLibrary(worldId, "monster", [t.portrait]);
      if (r?.id) portrait = r.id; else notes.push("Son portrait n'a pas pu être copié : choisis-en un.");
    } catch { notes.push("Son portrait n'est pas disponible ici : choisis-en un."); }
    api.bones(worldId).then(setBones).catch(() => {});
    api.assets(worldId, "monster").then(setPortraits).catch(() => {});
    notes.push("Ses sorts et son butin ne viennent pas avec lui : choisis-les ci-dessous.");
    setTplNotes(notes);
    const { source: _s, ...rest } = t;
    setF({ ...rest, bone, portrait, zones: [] });
    setG(0);
    setTpls(null);
  }
  const grade = f.grades[g];
  const setGrade = (p: Partial<GradeInput>) => patch({ grades: f.grades.map((x, i) => (i === g ? { ...x, ...p } : x)) });
  const num = (v: string) => Number(v);
  const valid = f.name.trim() && f.bone > 0 && f.portrait > 0 && !readOnly;

  async function run(fn: () => Promise<unknown>) { setError(""); try { await fn(); onDone(); } catch (e) { setError((e as Error).message); setConfirm(false); } }
  const toggleSpell = (id: number) => setGrade({ spells: grade.spells.includes(id) ? grade.spells.filter((s) => s !== id) : [...grade.spells, id] });

  return (
    <Dialog title={row ? `${readOnly ? "Boss" : "Modifier"} « ${row.name} »` : "Nouveau monstre"} onClose={onClose} wide>
      <form onSubmit={(e) => { e.preventDefault(); if (valid) run(() => (row ? api.setRow(worldId, "monsters", row.id, f) : api.addRow(worldId, "monsters", f))); }}>
        {readOnly && <Banner kind="error">Les boss se modifient dans les fichiers du monde : ils ne sont affichés qu'en lecture.</Banner>}
        {!row && (
          <details className="tpl-box">
            <summary>Partir d'un monstre du jeu Dofus</summary>
            <div className="lib-bar">
              <input aria-label="Chercher un monstre du jeu" placeholder="Nom ou numéro (ex. bouftou)" value={tplQuery} onChange={(e) => setTplQuery(e.target.value)}
                onKeyDown={(e) => { if (e.key === "Enter") { e.preventDefault(); searchTpl(); } }} />
              <button type="button" className="btn small-btn" disabled={tplQuery.trim().length < 2} onClick={searchTpl}>Chercher</button>
            </div>
            {tpls && (tpls.length === 0 ? <p className="muted small">Aucun monstre trouvé.</p> : (
              <ul className="tpl-list">
                {tpls.map((t) => <li key={t.source}><button type="button" className="btn small-btn" onClick={() => useTpl(t)}>{t.name} <span className="muted">· niv. {t.grades[0]?.level} à {t.grades[t.grades.length - 1]?.level}</span></button></li>)}
              </ul>
            ))}
            {tplNotes.map((n, i) => <p key={i} className="muted small" role="note">{n}</p>)}
            <p className="muted small">Reprend ses statistiques (jusqu'à 5 grades), ses résistances, son apparence et son portrait.</p>
          </details>
        )}
        <div className="form-grid">
          <Field label="Nom"><input value={f.name} onChange={(e) => patch({ name: e.target.value })} maxLength={80} disabled={readOnly} /></Field>
          <Field label="Taille (%)"><input type="number" min={20} max={400} value={f.size} onChange={(e) => patch({ size: num(e.target.value) })} disabled={readOnly} /></Field>
        </div>

        <BonePicker worldId={worldId} value={f.bone} onChange={(bone) => patch({ bone })} disabled={readOnly} bones={bones} setBones={setBones} onError={setError} />

        <fieldset className="icon-pick">
          <legend className="field-label">Portrait</legend>
          {portraits.length === 0 ? <p className="muted small">Aucun portrait : importe-en dans l'onglet Images (catégorie Monstres).</p> : (
            <div className="icons" role="radiogroup" aria-label="Portrait">
              {portraits.map((a) => (
                <button type="button" key={a.id} role="radio" aria-checked={a.id === f.portrait} aria-label={`Portrait ${a.name || a.id}`} className={"icon-btn" + (a.id === f.portrait ? " on" : "")} onClick={() => patch({ portrait: a.id })} disabled={readOnly}>
                  <img src={api.assetUrl(worldId, "monster", a.id)} alt="" loading="lazy" />
                </button>
              ))}
            </div>
          )}
        </fieldset>

        <fieldset className="icon-pick">
          <legend className="field-label">Zones où il apparaît</legend>
          {zones.length === 0 ? <p className="muted small">Aucune zone : crées-en une sous la liste des monstres.</p> : zones.map((z) => (
            <label className="check" key={z.key}>
              <input type="checkbox" checked={f.zones.includes(z.key)} disabled={readOnly} onChange={(e) => patch({ zones: e.target.checked ? [...f.zones, z.key] : f.zones.filter((k) => k !== z.key) })} />
              Zone niveau {z.level} <code className="id">{z.key}</code>
            </label>
          ))}
        </fieldset>

        <div className="seg" role="tablist" aria-label="Grades">
          {f.grades.map((x, i) => <button type="button" key={i} role="tab" aria-selected={i === g} className={i === g ? "on" : ""} onClick={() => setG(i)}>Grade {i + 1} · niv. {x.level}</button>)}
          {!readOnly && f.grades.length < 5 && (
            <button type="button" onClick={() => { patch({ grades: [...f.grades, { ...structuredClone(grade), level: grade.level + 4 }] }); setG(f.grades.length); }}>+ Grade</button>
          )}
        </div>
        <div className="grade" role="tabpanel">
          <div className="form-grid">
            <Field label="Niveau"><input type="number" min={1} max={200} value={grade.level} onChange={(e) => setGrade({ level: num(e.target.value) })} disabled={readOnly} /></Field>
            <Field label="Vie"><input type="number" min={1} value={grade.hp} onChange={(e) => setGrade({ hp: num(e.target.value) })} disabled={readOnly} /></Field>
            <Field label="PA"><input type="number" min={0} max={20} value={grade.ap} onChange={(e) => setGrade({ ap: num(e.target.value) })} disabled={readOnly} /></Field>
            <Field label="PM"><input type="number" min={0} max={20} value={grade.mp} onChange={(e) => setGrade({ mp: num(e.target.value) })} disabled={readOnly} /></Field>
            <Field label="XP donnée"><input type="number" min={0} value={grade.xp} onChange={(e) => setGrade({ xp: num(e.target.value) })} disabled={readOnly} /></Field>
            <Field label="Kamas min"><input type="number" min={0} value={grade.kamas[0]} onChange={(e) => setGrade({ kamas: [num(e.target.value), grade.kamas[1]] })} disabled={readOnly} /></Field>
            <Field label="Kamas max"><input type="number" min={0} value={grade.kamas[1]} onChange={(e) => setGrade({ kamas: [grade.kamas[0], num(e.target.value)] })} disabled={readOnly} /></Field>
            <Field label="Rayon d'agression"><input type="number" min={0} max={20} value={grade.aggro.zone} onChange={(e) => setGrade({ aggro: { ...grade.aggro, zone: num(e.target.value) } })} disabled={readOnly} /></Field>
          </div>
          <fieldset className="icon-pick">
            <legend className="field-label">Caractéristiques et résistances (%)</legend>
            <div className="form-grid compact">
              {STATS.map(([k, label]) => <Field key={k} label={label}><input type="number" min={0} value={grade.stats[k]} onChange={(e) => setGrade({ stats: { ...grade.stats, [k]: num(e.target.value) } })} disabled={readOnly} /></Field>)}
              {RES.map(([k, label]) => <Field key={k} label={`Rés. ${label}`}><input type="number" min={-100} max={100} value={grade.res[k]} onChange={(e) => setGrade({ res: { ...grade.res, [k]: num(e.target.value) } })} disabled={readOnly} /></Field>)}
            </div>
          </fieldset>
          <fieldset className="icon-pick">
            <legend className="field-label">Sorts</legend>
            {spells.length === 0 ? <p className="muted small">Aucun sort dans ce monde : crée-les dans l'onglet Sorts.</p> : spells.map((s) => (
              <label className="check" key={s.id}>
                <input type="checkbox" checked={grade.spells.includes(s.id)} disabled={readOnly} onChange={() => toggleSpell(s.id)} /> {s.name} <span className="muted small">({s.ap} PA)</span>
              </label>
            ))}
          </fieldset>
          <fieldset className="effects">
            <legend className="field-label">Butin</legend>
            {grade.drops.length === 0 && <p className="muted small">Aucun butin.</p>}
            {grade.drops.map((d, i) => (
              <div className="effect-row" key={i}>
                <select aria-label={`Objet ${i + 1}`} value={d.item} disabled={readOnly} onChange={(e) => setGrade({ drops: grade.drops.map((x, j) => (j === i ? { ...x, item: num(e.target.value) } : x)) })}>
                  {items.map((it) => <option key={it.id} value={it.id}>{it.name}</option>)}
                  {!items.some((it) => it.id === d.item) && <option value={d.item}>objet {d.item}</option>}
                </select>
                <input type="number" min={0.1} max={100} step={0.1} aria-label={`Chance ${i + 1}`} value={d.pct} disabled={readOnly} onChange={(e) => setGrade({ drops: grade.drops.map((x, j) => (j === i ? { ...x, pct: num(e.target.value) } : x)) })} />
                <span className="muted">%</span>
                {!readOnly && <button type="button" className="btn small-btn" aria-label={`Retirer le butin ${i + 1}`} onClick={() => setGrade({ drops: grade.drops.filter((_, j) => j !== i) })}>✕</button>}
              </div>
            ))}
            {!readOnly && <button type="button" className="btn small-btn" disabled={items.length === 0} onClick={() => setGrade({ drops: [...grade.drops, { item: items[0].id, pct: 10 }] })}>+ Ajouter un butin</button>}
          </fieldset>
          {!readOnly && f.grades.length > 1 && <button type="button" className="btn small-btn" onClick={() => { patch({ grades: f.grades.filter((_, i) => i !== g) }); setG(0); }}>Retirer ce grade</button>}
        </div>

        {error && <Banner kind="error">{error}</Banner>}
        <div className="actions spread">
          {row && !readOnly ? (confirm
            ? <button type="button" className="btn danger" onClick={() => run(() => api.delRow(worldId, "monsters", row.id))}>Confirmer la suppression</button>
            : <button type="button" className="btn danger" onClick={() => setConfirm(true)}>Supprimer…</button>) : <span />}
          <span className="toolbar">
            <button type="button" className="btn" onClick={onClose}>{readOnly ? "Fermer" : "Annuler"}</button>
            {!readOnly && <button type="submit" className="btn primary" disabled={!valid}>{row ? "Enregistrer" : "Créer le monstre"}</button>}
          </span>
        </div>
      </form>
    </Dialog>
  );
}
