import { useCallback, useEffect, useMemo, useState } from "react";
import { api, type TextRow } from "../api";
import { Banner, Dialog, Field } from "../components";

const KIND: Record<string, string> = {
  spell: "sort", summon: "invocation", item: "objet", set: "panoplie", monster: "monstre", npc: "PNJ", quest: "quête",
};

/** The i18n table of the world: every name and description lives here, never inline. */
export function TextsPanel({ worldId, rev, onChange }: { worldId: string; rev: number; onChange: () => void }) {
  const [rows, setRows] = useState<TextRow[] | null>(null);
  const [error, setError] = useState("");
  const [q, setQ] = useState("");
  const [edit, setEdit] = useState<TextRow | "new" | null>(null);

  const load = useCallback(() => { api.rows<TextRow>(worldId, "texts").then(setRows).catch((e) => setError(e.message)); }, [worldId]);
  useEffect(load, [load, rev]);

  const shown = useMemo(() => {
    const n = q.trim().toLowerCase();
    return (rows ?? []).filter((r) => !n || r.text.toLowerCase().includes(n) || String(r.id).includes(n));
  }, [rows, q]);

  async function remove(r: TextRow) {
    setError("");
    try { await api.delRow(worldId, "texts", r.id); onChange(); } catch (e) { setError((e as Error).message); }
  }

  return (
    <section className="panel" aria-labelledby="texts-h">
      <div className="panel-head">
        <h2 id="texts-h">Textes</h2>
        <div className="toolbar">
          <input className="search" type="search" placeholder="Rechercher…" aria-label="Rechercher un texte" value={q} onChange={(e) => setQ(e.target.value)} />
          <button className="btn primary" onClick={() => setEdit("new")}>+ Nouveau texte</button>
        </div>
      </div>
      <p className="muted small">Tous les noms et descriptions du monde passent par cette table. Un texte utilisé ne peut pas être supprimé.</p>
      {error && <Banner kind="error">{error}</Banner>}
      {rows === null ? <p className="muted">Chargement…</p> : shown.length === 0 ? (
        <p className="muted empty">{rows.length === 0 ? "Aucun texte pour l'instant." : "Aucun texte ne correspond."}</p>
      ) : (
        <table className="table data">
          <thead><tr><th>Id</th><th>Texte</th><th>Utilisé par</th><th /></tr></thead>
          <tbody>
            {shown.map((r) => (
              <tr key={r.id}>
                <td className="num">{r.id}</td>
                <td className="wrap">{r.text}</td>
                <td>{r.usedBy.length === 0 ? <span className="chip warn">libre</span> : (
                  <span className="chip accent" title={r.usedBy.map((u) => `${u.kind} ${u.id}`).join(", ")}>{KIND[r.usedBy[0].kind] ?? r.usedBy[0].kind} {r.usedBy[0].id}{r.usedBy.length > 1 ? ` +${r.usedBy.length - 1}` : ""}</span>
                )}</td>
                <td className="row-actions">
                  <button className="btn small-btn" onClick={() => setEdit(r)} aria-label={`Modifier le texte ${r.id}`}>Modifier</button>
                  <button className="btn small-btn danger" disabled={r.usedBy.length > 0} onClick={() => remove(r)} aria-label={`Supprimer le texte ${r.id}`}
                    title={r.usedBy.length ? "Utilisé : modifie-le plutôt" : "Supprimer"}>Supprimer</button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
      {edit && <TextDialog worldId={worldId} row={edit === "new" ? null : edit} onClose={() => setEdit(null)} onDone={() => { setEdit(null); onChange(); }} />}
    </section>
  );
}

function TextDialog({ worldId, row, onClose, onDone }: { worldId: string; row: TextRow | null; onClose: () => void; onDone: () => void }) {
  const [text, setText] = useState(row?.text ?? "");
  const [error, setError] = useState("");
  return (
    <Dialog title={row ? `Modifier le texte ${row.id}` : "Nouveau texte"} onClose={onClose}>
      <form onSubmit={async (e) => {
        e.preventDefault();
        try { row ? await api.setRow(worldId, "texts", row.id, { text }) : await api.addRow(worldId, "texts", { text }); onDone(); } catch (err) { setError((err as Error).message); }
      }}>
        <Field label="Texte" hint={row ? undefined : "Son identifiant est attribué automatiquement dans la plage du monde."}>
          <textarea rows={4} value={text} onChange={(e) => setText(e.target.value)} maxLength={2000} />
        </Field>
        {error && <Banner kind="error">{error}</Banner>}
        <div className="actions">
          <button type="button" className="btn" onClick={onClose}>Annuler</button>
          <button type="submit" className="btn primary" disabled={!text.trim() || text === row?.text}>{row ? "Enregistrer" : "Ajouter"}</button>
        </div>
      </form>
    </Dialog>
  );
}
