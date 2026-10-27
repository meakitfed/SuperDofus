import { useCallback, useEffect, useMemo, useState } from "react";
import { api, type BoneLibrary, type DialogInput, type ItemRow, type MapRow, type NpcInput, type NpcRow, type ReplyInput } from "../api";
import { BonePicker } from "../BonePicker";
import { CellPicker } from "../CellPicker";
import { DialogGraph } from "./DialogGraph";
import type { NpcTemplate } from "../../../core/library_npcs";
import { Banner, Dialog, Field } from "../components";

const DIRS = ["Est", "Sud-est", "Sud", "Sud-ouest", "Ouest", "Nord-ouest", "Nord", "Nord-est"];

export function NpcsPanel({ worldId, rev, onChange }: { worldId: string; rev: number; onChange: () => void }) {
  const [rows, setRows] = useState<NpcRow[] | null>(null);
  const [maps, setMaps] = useState<MapRow[]>([]);
  const [error, setError] = useState("");
  const [edit, setEdit] = useState<NpcRow | "new" | null>(null);
  const [talk, setTalk] = useState<number | null>(null);

  const load = useCallback(() => {
    api.rows<NpcRow>(worldId, "npcs").then(setRows).catch((e) => setError(e.message));
    api.rows<MapRow>(worldId, "maps").then(setMaps).catch(() => {});
  }, [worldId]);
  useEffect(load, [load, rev]);

  const mapName = (id: number) => maps.find((m) => m.id === id)?.name ?? `map ${id}`;
  const npc = rows?.find((r) => r.id === talk);
  if (talk !== null && npc) return <DialogEditor worldId={worldId} npc={npc} maps={maps} onClose={() => setTalk(null)} onChange={onChange} />;

  return (
    <section className="panel" aria-labelledby="npc-h">
      <div className="panel-head">
        <h2 id="npc-h">PNJ</h2>
        <button className="btn primary" onClick={() => setEdit("new")}>+ Nouveau PNJ</button>
      </div>
      <p className="muted small">Un PNJ occupe sa cellule (elle devient un obstacle). Il peut parler, vendre, tenir la banque, donner des quêtes.</p>
      {error && <Banner kind="error">{error}</Banner>}
      {rows === null ? <p className="muted">Chargement…</p> : rows.length === 0 ? (
        <p className="muted empty">Aucun PNJ. Place le premier sur une map.</p>
      ) : (
        <table className="table data">
          <thead><tr><th>Nom</th><th>Map</th><th>Cellule</th><th>Rôles</th><th /></tr></thead>
          <tbody>
            {rows.map((r) => (
              <tr key={r.id}>
                <td className="wrap"><strong>{r.name}</strong><br /><code className="id">{r.id}</code></td>
                <td>{mapName(r.map)}</td>
                <td className="num">{r.cell}</td>
                <td>
                  {r.hasDialog && <span className="chip accent">dialogue</span>} {r.shop && <span className="chip ok">boutique ({r.shop.length})</span>} {r.banker && <span className="chip">banque</span>}
                  {r.usedBy.length > 0 && <> <span className="chip warn" title={r.usedBy.map((u) => `${u.kind} ${u.id}`).join(", ")}>quête ×{r.usedBy.length}</span></>}
                </td>
                <td className="row-actions">
                  <button className="btn small-btn" onClick={() => setTalk(r.id)} aria-label={`Dialogue de ${r.name}`}>Dialogue</button>
                  <button className="btn small-btn" onClick={() => setEdit(r)} aria-label={`Modifier le PNJ ${r.name}`}>Modifier</button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
      {edit && <NpcDialog worldId={worldId} row={edit === "new" ? null : edit} maps={maps} npcs={rows ?? []} onClose={() => setEdit(null)} onDone={() => { setEdit(null); onChange(); }} />}
    </section>
  );
}

function NpcDialog({ worldId, row, maps, npcs, onClose, onDone }: { worldId: string; row: NpcRow | null; maps: MapRow[]; npcs: NpcRow[]; onClose: () => void; onDone: () => void }) {
  const [f, setF] = useState<NpcInput>(() => row
    ? { map: row.map, cell: row.cell, dir: row.dir, name: row.name, bone: row.bone, size: row.size, banker: row.banker, shop: row.shop }
    : { map: maps[0]?.id ?? 0, cell: 150, dir: 3, name: "", bone: 0, size: 100, banker: false, shop: null });
  const [bones, setBones] = useState<BoneLibrary>({ own: [], library: [] });
  const [items, setItems] = useState<ItemRow[]>([]);
  const [error, setError] = useState("");
  const [confirm, setConfirm] = useState(false);
  useEffect(() => {
    api.bones(worldId).then((b) => { setBones(b); setF((x) => (x.bone ? x : { ...x, bone: b.own[0] ?? 0 })); }).catch(() => {});
    api.rows<ItemRow>(worldId, "items").then(setItems).catch(() => {});
  }, [worldId]);
  const patch = (p: Partial<NpcInput>) => setF((x) => ({ ...x, ...p }));

  // start from a NPC of the game: name and look come along, the place, dialogue and shop are chosen here
  const [tplQuery, setTplQuery] = useState("");
  const [tpls, setTpls] = useState<NpcTemplate[] | null>(null);
  const [tplNote, setTplNote] = useState("");
  async function searchTpl() {
    setError(""); setTplNote("");
    try { setTpls(await api.npcTemplates(tplQuery)); } catch (e) { setTpls(null); setError((e as Error).message); }
  }
  async function useTpl(t: NpcTemplate) {
    setError(""); setTplNote("");
    let bone = f.bone;
    try { await api.importBone(worldId, "dofus", t.bone); bone = t.bone; } catch (e) {
      if (/déjà présent/.test((e as Error).message)) bone = t.bone; else setTplNote("Son squelette n'est pas disponible ici : choisis-en un.");
    }
    api.bones(worldId).then(setBones).catch(() => {});
    setF((x) => ({ ...x, name: t.name, bone, size: t.size }));
    setTpls(null);
  }
  const map = maps.find((m) => m.id === f.map);
  const taken = [...npcs.filter((n) => n.map === f.map && n.id !== row?.id).map((n) => n.cell), ...(map?.doors.map((d) => d.cell) ?? []), ...(map?.isStart ? [map.startCell] : []), ...(map?.phoenix !== null && map ? [map.phoenix] : [])];
  const valid = f.name.trim() && f.bone > 0 && f.map > 0;
  async function run(fn: () => Promise<unknown>) { setError(""); try { await fn(); onDone(); } catch (e) { setError((e as Error).message); setConfirm(false); } }

  return (
    <Dialog title={row ? `Modifier « ${row.name} »` : "Nouveau PNJ"} onClose={onClose} wide>
      <form onSubmit={(e) => { e.preventDefault(); if (valid) run(() => (row ? api.setRow(worldId, "npcs", row.id, f) : api.addRow(worldId, "npcs", f))); }}>
        {!row && (
          <details className="tpl-box">
            <summary>Partir d'un PNJ du jeu Dofus</summary>
            <div className="lib-bar">
              <input aria-label="Chercher un PNJ du jeu" placeholder="Nom ou numéro (ex. Amine)" value={tplQuery} onChange={(e) => setTplQuery(e.target.value)}
                onKeyDown={(e) => { if (e.key === "Enter") { e.preventDefault(); searchTpl(); } }} />
              <button type="button" className="btn small-btn" disabled={tplQuery.trim().length < 2} onClick={searchTpl}>Chercher</button>
            </div>
            {tpls && (tpls.length === 0 ? <p className="muted small">Aucun PNJ trouvé.</p> : (
              <ul className="tpl-list">
                {tpls.map((t) => <li key={t.source}><button type="button" className="btn small-btn" onClick={() => useTpl(t)}>{t.name} <span className="muted">· n° {t.source}</span></button></li>)}
              </ul>
            ))}
            {tplNote && <p className="muted small" role="note">{tplNote}</p>}
            <p className="muted small">Reprend son nom et son apparence. Sa place, son dialogue et sa boutique sont à choisir ici.</p>
          </details>
        )}
        <div className="form-grid">
          <Field label="Nom"><input value={f.name} onChange={(e) => patch({ name: e.target.value })} maxLength={60} /></Field>
          <Field label="Map"><select value={f.map} onChange={(e) => patch({ map: Number(e.target.value) })}>{maps.map((m) => <option key={m.id} value={m.id}>{m.name}</option>)}</select></Field>
          <Field label="Regarde vers"><select value={f.dir} onChange={(e) => patch({ dir: Number(e.target.value) })}>{DIRS.map((d, i) => <option key={d} value={i}>{d}</option>)}</select></Field>
          <Field label="Taille (%)"><input type="number" min={20} max={400} value={f.size} onChange={(e) => patch({ size: Number(e.target.value) })} /></Field>
        </div>
        <fieldset className="icon-pick">
          <legend className="field-label">Cellule : {f.cell}</legend>
          <div className="picker-wrap"><CellPicker label="Choisir la cellule du PNJ" value={f.cell} onPick={(cell) => patch({ cell })} blocked={map?.blocked} taken={taken} /></div>
          <p className="muted small">Sombre : obstacle. Jaune : déjà prise (PNJ, porte, départ, renaissance). La cellule choisie devient un obstacle.</p>
        </fieldset>
        <BonePicker worldId={worldId} value={f.bone} onChange={(bone) => patch({ bone })} bones={bones} setBones={setBones} onError={setError} />
        <label className="check"><input type="checkbox" checked={f.banker} onChange={(e) => patch({ banker: e.target.checked })} /> Tient la banque</label>
        <label className="check"><input type="checkbox" checked={f.shop !== null} disabled={items.length === 0} onChange={(e) => patch({ shop: e.target.checked ? [items[0].id] : null })} /> Vend des objets {items.length === 0 && <span className="muted small">(crée d'abord des objets)</span>}</label>
        {f.shop !== null && (
          <fieldset className="icon-pick">
            <legend className="field-label">Boutique ({f.shop.length})</legend>
            {items.map((it) => (
              <label className="check" key={it.id}>
                <input type="checkbox" checked={f.shop!.includes(it.id)} onChange={(e) => patch({ shop: e.target.checked ? [...f.shop!, it.id] : f.shop!.filter((x) => x !== it.id) })} /> {it.name} <span className="muted small">niv. {it.level}</span>
              </label>
            ))}
          </fieldset>
        )}
        {error && <Banner kind="error">{error}</Banner>}
        <div className="actions spread">
          {row ? (confirm
            ? <button type="button" className="btn danger" onClick={() => run(() => api.delRow(worldId, "npcs", row.id))}>Confirmer le retrait</button>
            : <button type="button" className="btn danger" onClick={() => setConfirm(true)}>Retirer ce PNJ…</button>) : <span />}
          <span className="toolbar">
            <button type="button" className="btn" onClick={onClose}>Annuler</button>
            <button type="submit" className="btn primary" disabled={!valid || (f.shop !== null && f.shop.length === 0)}>{row ? "Enregistrer" : "Placer le PNJ"}</button>
          </span>
        </div>
      </form>
    </Dialog>
  );
}

// ---- dialogue ----
type ActionKind = "" | "shop" | "bank" | "teleport" | "give_item";
const ACTIONS: [ActionKind, string][] = [["", "Aucune"], ["shop", "Ouvrir la boutique"], ["bank", "Ouvrir la banque"], ["teleport", "Téléporter"], ["give_item", "Donner un objet"]];

function reachable(d: DialogInput): Set<string> {
  const seen = new Set<string>();
  const stack = [d.start];
  while (stack.length) {
    const k = stack.pop()!;
    if (seen.has(k) || !(k in d.nodes)) continue;
    seen.add(k);
    for (const r of d.nodes[k].replies) if (r.next) stack.push(r.next);
  }
  return seen;
}

function DialogEditor({ worldId, npc, maps, onClose, onChange }: { worldId: string; npc: NpcRow; maps: MapRow[]; onClose: () => void; onChange: () => void }) {
  const [d, setD] = useState<DialogInput | null>(null);
  const [items, setItems] = useState<ItemRow[]>([]);
  const [error, setError] = useState("");
  const [saved, setSaved] = useState(true);
  const [newKey, setNewKey] = useState("");
  const [confirm, setConfirm] = useState(false);

  useEffect(() => {
    api.dialog(worldId, npc.id).then((t) => setD(t ?? { start: "0", nodes: { "0": { text: "Bonjour, voyageur.", replies: [] } } })).catch((e) => setError(e.message));
    api.rows<ItemRow>(worldId, "items").then(setItems).catch(() => {});
  }, [worldId, npc.id]);

  const seen = useMemo(() => (d ? reachable(d) : new Set<string>()), [d]);
  if (!d) return <section className="panel">{error ? <Banner kind="error">{error}</Banner> : <p className="muted">Chargement…</p>}</section>;
  const keys = Object.keys(d.nodes);
  const edit = (fn: (x: DialogInput) => void) => { const c = structuredClone(d); fn(c); setD(c); setSaved(false); };
  const setReply = (k: string, i: number, p: Partial<ReplyInput>) => edit((c) => { c.nodes[k].replies[i] = { ...c.nodes[k].replies[i], ...p }; });
  const actionKind = (r: ReplyInput): ActionKind => (r.action?.type ?? "") as ActionKind;
  function setAction(k: string, i: number, kind: ActionKind) {
    const a = kind === "" ? undefined : kind === "teleport" ? { type: "teleport" as const, map: maps[0]?.id ?? 0, cell: 300 } : kind === "give_item" ? { type: "give_item" as const, item: items[0]?.id ?? 0, qty: 1 } : { type: kind };
    edit((c) => { const r = c.nodes[k].replies[i]; if (a) r.action = a; else delete r.action; });
  }

  async function save() {
    setError("");
    try { await api.setRow(worldId, "dialogs", npc.id, d); setSaved(true); onChange(); } catch (e) { setError((e as Error).message); }
  }
  async function removeAll() {
    setError("");
    try { await api.delRow(worldId, "dialogs", npc.id); onChange(); onClose(); } catch (e) { setError((e as Error).message); setConfirm(false); }
  }

  return (
    <section className="panel" aria-labelledby="dlg-h">
      <div className="panel-head">
        <h2 id="dlg-h">Dialogue de {npc.name}</h2>
        <span className="toolbar">
          <button className="btn" onClick={onClose}>← Tous les PNJ</button>
          <button className="btn primary" disabled={saved} onClick={save}>{saved ? "Enregistré" : "Enregistrer le dialogue"}</button>
        </span>
      </div>
      <p className="muted small">Chaque nœud est une phrase du PNJ suivie de réponses du joueur. Une réponse mène à un autre nœud, ou termine la conversation. Un critère limite une réponse (ex. <code>Qf=quête</code>, <code>PO=objet</code>).</p>
      {error && <Banner kind="error">{error}</Banner>}

      <DialogGraph d={d} />

      <div className="nodes">
        {keys.map((k) => {
          const node = d.nodes[k];
          return (
            <article className={"node" + (seen.has(k) ? "" : " orphan")} key={k} aria-label={`Nœud ${k}`}>
              <header className="node-head">
                <code>{k}</code>
                {k === d.start ? <span className="chip ok">départ</span> : <button type="button" className="btn small-btn" onClick={() => edit((c) => { c.start = k; })}>Définir comme départ</button>}
                {!seen.has(k) && <span className="chip warn">jamais atteint</span>}
                {k !== d.start && <button type="button" className="btn small-btn danger" aria-label={`Supprimer le nœud ${k}`}
                  onClick={() => edit((c) => { delete c.nodes[k]; for (const n of Object.values(c.nodes)) for (const r of n.replies) if (r.next === k) delete r.next; })}>Supprimer</button>}
              </header>
              <textarea rows={2} aria-label={`Texte du nœud ${k}`} value={node.text} onChange={(e) => edit((c) => { c.nodes[k].text = e.target.value; })} maxLength={1500} />
              {node.replies.map((r, i) => (
                <div className="reply" key={i}>
                  <input aria-label={`Réponse ${i + 1} du nœud ${k}`} value={r.text} onChange={(e) => setReply(k, i, { text: e.target.value })} maxLength={300} placeholder="Réponse du joueur" />
                  <select aria-label={`Mène à, réponse ${i + 1} du nœud ${k}`} value={r.next ?? ""} onChange={(e) => edit((c) => { const rr = c.nodes[k].replies[i]; if (e.target.value) rr.next = e.target.value; else delete rr.next; })}>
                    <option value="">⏹ Fin de la conversation</option>
                    {keys.map((n) => <option key={n} value={n}>→ {n}</option>)}
                  </select>
                  <input aria-label={`Critère, réponse ${i + 1} du nœud ${k}`} className="crit" value={r.criteria ?? ""} onChange={(e) => edit((c) => { const rr = c.nodes[k].replies[i]; if (e.target.value) rr.criteria = e.target.value; else delete rr.criteria; })} placeholder="Critère (facultatif)" />
                  <select aria-label={`Action, réponse ${i + 1} du nœud ${k}`} value={actionKind(r)} onChange={(e) => setAction(k, i, e.target.value as ActionKind)}>
                    {ACTIONS.filter(([a]) => a !== "shop" || npc.shop).filter(([a]) => a !== "bank" || npc.banker).map(([a, l]) => <option key={a} value={a}>{l}</option>)}
                  </select>
                  {r.action?.type === "teleport" && <>
                    <select aria-label="Map d'arrivée" value={r.action.map} onChange={(e) => setReply(k, i, { action: { ...(r.action as { type: "teleport"; map: number; cell: number }), map: Number(e.target.value) } })}>{maps.map((m) => <option key={m.id} value={m.id}>{m.name}</option>)}</select>
                    <input type="number" aria-label="Cellule d'arrivée" value={r.action.cell} min={0} max={559} onChange={(e) => setReply(k, i, { action: { ...(r.action as { type: "teleport"; map: number; cell: number }), cell: Number(e.target.value) } })} />
                  </>}
                  {r.action?.type === "give_item" && <>
                    <select aria-label="Objet donné" value={r.action.item} onChange={(e) => setReply(k, i, { action: { ...(r.action as { type: "give_item"; item: number; qty: number }), item: Number(e.target.value) } })}>{items.map((it) => <option key={it.id} value={it.id}>{it.name}</option>)}</select>
                    <input type="number" aria-label="Quantité" value={r.action.qty} min={1} max={999} onChange={(e) => setReply(k, i, { action: { ...(r.action as { type: "give_item"; item: number; qty: number }), qty: Number(e.target.value) } })} />
                  </>}
                  <button type="button" className="btn small-btn" aria-label={`Retirer la réponse ${i + 1} du nœud ${k}`} onClick={() => edit((c) => { c.nodes[k].replies.splice(i, 1); })}>✕</button>
                </div>
              ))}
              {node.replies.length < 8 && <button type="button" className="btn small-btn" onClick={() => edit((c) => { c.nodes[k].replies.push({ text: "" }); })}>+ Réponse</button>}
            </article>
          );
        })}
      </div>

      <form className="toolbar new-node" onSubmit={(e) => { e.preventDefault(); const key = newKey.trim(); if (key && !(key in d.nodes)) { edit((c) => { c.nodes[key] = { text: "", replies: [] }; }); setNewKey(""); } }}>
        <input aria-label="Identifiant du nouveau nœud" placeholder="identifiant du nœud (a-z, 0-9, _)" value={newKey} onChange={(e) => setNewKey(e.target.value.toLowerCase().replace(/[^a-z0-9_]/g, ""))} maxLength={24} />
        <button type="submit" className="btn" disabled={!newKey.trim() || newKey in d.nodes}>+ Nouveau nœud</button>
      </form>

      {npc.hasDialog && (
        <div className="danger-zone">
          {confirm ? <button className="btn danger" onClick={removeAll}>Confirmer : ce PNJ ne parlera plus</button> : <button className="btn danger" onClick={() => setConfirm(true)}>Supprimer tout le dialogue…</button>}
        </div>
      )}
    </section>
  );
}
