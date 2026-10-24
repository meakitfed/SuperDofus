import { useCallback, useEffect, useState } from "react";
import { api, type ItemRow, type MapRow, type MonsterRow, type NpcRow, type ObjectiveInput, type QuestInput, type QuestRow, type StepInput } from "../api";
import { Banner } from "../components";

const OBJ: [ObjectiveInput["type"], string][] = [
  [1, "Parler à un PNJ"], [9, "Retourner voir un PNJ"], [3, "Apporter des objets à un PNJ"], [4, "Découvrir une map"], [7, "Vaincre un monstre"], [14, "Vaincre plusieurs monstres"],
];
const REPEAT = ["Une seule fois", "Répétable à volonté", "Une fois par jour", "Une fois par jour (cumul)"];

export function QuestsPanel({ worldId, rev, onChange }: { worldId: string; rev: number; onChange: () => void }) {
  const [rows, setRows] = useState<QuestRow[] | null>(null);
  const [npcs, setNpcs] = useState<NpcRow[]>([]);
  const [error, setError] = useState("");
  const [open, setOpen] = useState<QuestRow | "new" | null>(null);

  const load = useCallback(() => {
    api.rows<QuestRow>(worldId, "quests").then(setRows).catch((e) => setError(e.message));
    api.rows<NpcRow>(worldId, "npcs").then(setNpcs).catch(() => {});
  }, [worldId]);
  useEffect(load, [load, rev]);

  if (open) return <QuestEditor worldId={worldId} row={open === "new" ? null : rows?.find((r) => r.id === open.id) ?? open} onClose={() => setOpen(null)} onChange={onChange} />;
  const npcName = (id: number) => npcs.find((n) => n.id === id)?.name ?? `PNJ ${id}`;

  return (
    <section className="panel" aria-labelledby="q-h">
      <div className="panel-head">
        <h2 id="q-h">Quêtes</h2>
        <button className="btn primary" onClick={() => setOpen("new")} disabled={npcs.length === 0} title={npcs.length ? "" : "Place d'abord un PNJ qui donnera la quête"}>+ Nouvelle quête</button>
      </div>
      <p className="muted small">Une quête est proposée par son PNJ : le jeu ajoute lui-même la réponse correspondante à sa conversation. Elle se déroule en étapes, chacune avec ses objectifs et sa récompense.</p>
      {error && <Banner kind="error">{error}</Banner>}
      {rows === null ? <p className="muted">Chargement…</p> : rows.length === 0 ? (
        <p className="muted empty">{npcs.length === 0 ? "Aucune quête. Il faut d'abord un PNJ (onglet PNJ)." : "Aucune quête pour l'instant."}</p>
      ) : (
        <table className="table data">
          <thead><tr><th>Quête</th><th>Donneur</th><th>Étapes</th><th /></tr></thead>
          <tbody>
            {rows.map((r) => (
              <tr key={r.id} className="clickable" tabIndex={0} onClick={() => setOpen(r)} onKeyDown={(e) => e.key === "Enter" && setOpen(r)} aria-label={`Ouvrir la quête ${r.name}`}>
                <td className="wrap"><strong>{r.name}</strong><br /><code className="id">{r.id}</code></td>
                <td>{npcName(r.giver)}</td>
                <td className="num">{r.steps.length}</td>
                <td>{r.locked && <span className="chip" title={r.lockedWhy.join(", ")}>lecture seule</span>}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </section>
  );
}

const blankStep = (level: number): StepInput => ({ name: "", desc: "", level, objectives: [], reward: { xp: 1, kamas: 1, items: [] } });

function QuestEditor({ worldId, row, onClose, onChange }: { worldId: string; row: QuestRow | null; onClose: () => void; onChange: () => void }) {
  const [npcs, setNpcs] = useState<NpcRow[]>([]);
  const [maps, setMaps] = useState<MapRow[]>([]);
  const [monsters, setMonsters] = useState<MonsterRow[]>([]);
  const [items, setItems] = useState<ItemRow[]>([]);
  const [f, setF] = useState<QuestInput>(() => row
    ? { name: row.name, giver: row.giver, levelMin: row.levelMin, repeat: row.repeat, steps: structuredClone(row.steps) }
    : { name: "", giver: 0, levelMin: 1, repeat: 0, steps: [blankStep(1)] });
  const [error, setError] = useState("");
  const [saved, setSaved] = useState(true);
  const [confirm, setConfirm] = useState(false);
  const readOnly = row?.locked ?? false;

  useEffect(() => {
    api.rows<NpcRow>(worldId, "npcs").then((n) => { setNpcs(n); setF((x) => (x.giver ? x : { ...x, giver: n[0]?.id ?? 0 })); }).catch(() => {});
    api.rows<MapRow>(worldId, "maps").then(setMaps).catch(() => {});
    api.rows<MonsterRow>(worldId, "monsters").then(setMonsters).catch(() => {});
    api.rows<ItemRow>(worldId, "items").then(setItems).catch(() => {});
  }, [worldId]);

  const edit = (fn: (q: QuestInput) => void) => { const c = structuredClone(f); fn(c); setF(c); setSaved(false); };
  const newObjective = (type: ObjectiveInput["type"]): ObjectiveInput => {
    const npc = npcs[0]?.id ?? 0, monster = monsters[0]?.id ?? 0, item = items[0]?.id ?? 0, map = maps[0]?.id ?? 0;
    if (type === 3) return { type, npc, item, qty: 1 };
    if (type === 4) return { type, map };
    if (type === 7) return { type, monster };
    if (type === 14) return { type, monster, qty: 3 };
    return { type, npc };
  };
  const valid = f.name.trim() && f.giver > 0 && f.steps.length > 0 && f.steps.every((s) => s.name.trim() && s.desc.trim() && s.objectives.length > 0);

  async function save() {
    setError("");
    try {
      if (row) await api.setRow(worldId, "quests", row.id, f); else { const r = await api.addRow(worldId, "quests", f); void r; }
      setSaved(true); onChange();
      if (!row) onClose();
    } catch (e) { setError((e as Error).message); }
  }
  async function remove() {
    setError("");
    try { await api.delRow(worldId, "quests", row!.id); onChange(); onClose(); } catch (e) { setError((e as Error).message); setConfirm(false); }
  }
  const num = (v: string) => Number(v);

  return (
    <section className="panel" aria-labelledby="qe-h">
      <div className="panel-head">
        <h2 id="qe-h">{row ? row.name : "Nouvelle quête"}</h2>
        <span className="toolbar">
          <button className="btn" onClick={onClose}>← Toutes les quêtes</button>
          {!readOnly && <button className="btn primary" disabled={saved || !valid} onClick={save}>{saved && row ? "Enregistrée" : row ? "Enregistrer la quête" : "Créer la quête"}</button>}
        </span>
      </div>
      {readOnly && <Banner kind="error">Cette quête utilise {row!.lockedWhy.join(", ")} : l'éditeur ne les gère pas, elle reste en lecture seule pour ne rien abîmer.</Banner>}
      {error && <Banner kind="error">{error}</Banner>}

      <fieldset className="quest-head" disabled={readOnly}>
        <label className="field"><span className="field-label">Nom</span><input value={f.name} onChange={(e) => edit((q) => { q.name = e.target.value; })} maxLength={80} /></label>
        <label className="field"><span className="field-label">PNJ donneur</span>
          <select value={f.giver} onChange={(e) => edit((q) => { q.giver = num(e.target.value); })}>{npcs.map((n) => <option key={n.id} value={n.id}>{n.name}</option>)}</select>
        </label>
        <label className="field"><span className="field-label">Niveau minimal conseillé</span><input type="number" min={1} max={200} value={f.levelMin} onChange={(e) => edit((q) => { q.levelMin = num(e.target.value); })} /></label>
        <label className="field"><span className="field-label">Répétition</span>
          <select value={f.repeat} onChange={(e) => edit((q) => { q.repeat = num(e.target.value); })}>{REPEAT.map((r, i) => <option key={r} value={i}>{r}</option>)}</select>
        </label>
      </fieldset>

      <ol className="steps">
        {f.steps.map((s, i) => (
          <li className="step" key={i} aria-label={`Étape ${i + 1}`}>
            <fieldset disabled={readOnly}>
              <header className="node-head">
                <strong>Étape {i + 1}</strong>
                <button type="button" className="btn small-btn" disabled={i === 0} aria-label={`Monter l'étape ${i + 1}`} onClick={() => edit((q) => { [q.steps[i - 1], q.steps[i]] = [q.steps[i], q.steps[i - 1]]; })}>↑</button>
                <button type="button" className="btn small-btn" disabled={i === f.steps.length - 1} aria-label={`Descendre l'étape ${i + 1}`} onClick={() => edit((q) => { [q.steps[i + 1], q.steps[i]] = [q.steps[i], q.steps[i + 1]]; })}>↓</button>
                {f.steps.length > 1 && <button type="button" className="btn small-btn danger" aria-label={`Supprimer l'étape ${i + 1}`} onClick={() => edit((q) => { q.steps.splice(i, 1); })}>Supprimer</button>}
              </header>
              <div className="form-grid">
                <label className="field"><span className="field-label">Titre</span><input aria-label={`Titre de l'étape ${i + 1}`} value={s.name} onChange={(e) => edit((q) => { q.steps[i].name = e.target.value; })} maxLength={80} /></label>
                <label className="field"><span className="field-label">Niveau</span><input type="number" aria-label={`Niveau de l'étape ${i + 1}`} min={1} max={200} value={s.level} onChange={(e) => edit((q) => { q.steps[i].level = num(e.target.value); })} /></label>
              </div>
              <label className="field"><span className="field-label">Description (vue dans le journal de quêtes)</span>
                <textarea rows={2} aria-label={`Description de l'étape ${i + 1}`} value={s.desc} onChange={(e) => edit((q) => { q.steps[i].desc = e.target.value; })} maxLength={600} /></label>

              <div className="objs">
                <span className="field-label">Objectifs (dans l'ordre ; deux objectifs du même type d'affilée se font dans n'importe quel ordre)</span>
                {s.objectives.map((o, j) => (
                  <div className="effect-row wrap" key={j}>
                    <select aria-label={`Type de l'objectif ${j + 1} de l'étape ${i + 1}`} value={o.type} onChange={(e) => edit((q) => { q.steps[i].objectives[j] = newObjective(num(e.target.value) as ObjectiveInput["type"]); })}>
                      {OBJ.map(([t, l]) => <option key={t} value={t}>{l}</option>)}
                    </select>
                    {"npc" in o && <select aria-label="PNJ visé" value={o.npc} onChange={(e) => edit((q) => { (q.steps[i].objectives[j] as { npc: number }).npc = num(e.target.value); })}>{npcs.map((n) => <option key={n.id} value={n.id}>{n.name}</option>)}</select>}
                    {o.type === 3 && <>
                      <select aria-label="Objet demandé" value={o.item} onChange={(e) => edit((q) => { (q.steps[i].objectives[j] as { item: number }).item = num(e.target.value); })}>{items.map((it) => <option key={it.id} value={it.id}>{it.name}</option>)}</select>
                      <input type="number" aria-label="Quantité" min={1} max={999} value={o.qty} onChange={(e) => edit((q) => { (q.steps[i].objectives[j] as { qty: number }).qty = num(e.target.value); })} />
                    </>}
                    {o.type === 4 && <select aria-label="Map à découvrir" value={o.map} onChange={(e) => edit((q) => { (q.steps[i].objectives[j] as { map: number }).map = num(e.target.value); })}>{maps.map((m) => <option key={m.id} value={m.id}>{m.name}</option>)}</select>}
                    {(o.type === 7 || o.type === 14) && <select aria-label="Monstre visé" value={o.monster} onChange={(e) => edit((q) => { (q.steps[i].objectives[j] as { monster: number }).monster = num(e.target.value); })}>{monsters.map((m) => <option key={m.id} value={m.id}>{m.name}</option>)}</select>}
                    {o.type === 14 && <><input type="number" aria-label="Nombre de monstres" min={1} max={999} value={o.qty} onChange={(e) => edit((q) => { (q.steps[i].objectives[j] as { qty: number }).qty = num(e.target.value); })} /><span className="muted small">à vaincre</span></>}
                    <button type="button" className="btn small-btn" aria-label={`Retirer l'objectif ${j + 1} de l'étape ${i + 1}`} onClick={() => edit((q) => { q.steps[i].objectives.splice(j, 1); })}>✕</button>
                  </div>
                ))}
                {s.objectives.length < 6 && !readOnly && (
                  <select aria-label={`Ajouter un objectif à l'étape ${i + 1}`} value="" onChange={(e) => e.target.value && edit((q) => { q.steps[i].objectives.push(newObjective(num(e.target.value) as ObjectiveInput["type"])); })}>
                    <option value="">+ Ajouter un objectif…</option>
                    {OBJ.map(([t, l]) => <option key={t} value={t}>{l}</option>)}
                  </select>
                )}
              </div>

              <div className="objs">
                <span className="field-label">Récompense</span>
                <div className="effect-row wrap">
                  <label className="inline">XP ×<input type="number" step="0.5" min={0} max={100} aria-label={`Ratio d'XP de l'étape ${i + 1}`} value={s.reward.xp} onChange={(e) => edit((q) => { q.steps[i].reward.xp = num(e.target.value); })} /></label>
                  <label className="inline">Kamas ×<input type="number" step="0.5" min={0} max={100} aria-label={`Ratio de kamas de l'étape ${i + 1}`} value={s.reward.kamas} onChange={(e) => edit((q) => { q.steps[i].reward.kamas = num(e.target.value); })} /></label>
                </div>
                {s.reward.items.map(([it, qty], j) => (
                  <div className="effect-row" key={j}>
                    <select aria-label={`Objet de récompense ${j + 1}`} value={it} onChange={(e) => edit((q) => { q.steps[i].reward.items[j][0] = num(e.target.value); })}>{items.map((x) => <option key={x.id} value={x.id}>{x.name}</option>)}</select>
                    <input type="number" min={1} max={999} aria-label={`Quantité de récompense ${j + 1}`} value={qty} onChange={(e) => edit((q) => { q.steps[i].reward.items[j][1] = num(e.target.value); })} />
                    <button type="button" className="btn small-btn" aria-label={`Retirer l'objet de récompense ${j + 1}`} onClick={() => edit((q) => { q.steps[i].reward.items.splice(j, 1); })}>✕</button>
                  </div>
                ))}
                {!readOnly && <button type="button" className="btn small-btn" disabled={items.length === 0} onClick={() => edit((q) => { q.steps[i].reward.items.push([items[0].id, 1]); })}>+ Objet de récompense</button>}
                <p className="muted small">Les ratios multiplient l'XP et les kamas calculés par le jeu pour ce niveau (1 = récompense normale).</p>
              </div>
            </fieldset>
          </li>
        ))}
      </ol>
      {!readOnly && f.steps.length < 10 && <button type="button" className="btn" onClick={() => edit((q) => { q.steps.push(blankStep(q.steps[q.steps.length - 1]?.level ?? 1)); })}>+ Ajouter une étape</button>}

      {row && (
        <div className="danger-zone">
          {confirm ? <button className="btn danger" onClick={remove}>Confirmer la suppression de la quête</button> : <button className="btn danger" onClick={() => setConfirm(true)}>Supprimer cette quête…</button>}
        </div>
      )}
    </section>
  );
}
