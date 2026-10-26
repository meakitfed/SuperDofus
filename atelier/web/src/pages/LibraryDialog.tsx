import { useEffect, useState } from "react";
import { api, CATEGORY_LABELS, type Category, type ImportResult } from "../api";
import { Banner, Dialog } from "../components";

const PAGE = 60;

/** The Dofus images already on this computer: search by number, tick some, copy them into the world. */
export function LibraryDialog({ worldId, cat, onClose, onDone }: { worldId: string; cat: Category; onClose: () => void; onDone: (r: ImportResult[]) => void }) {
  const [q, setQ] = useState("");
  const [page, setPage] = useState({ available: true, total: 0, ids: [] as number[] });
  const [offset, setOffset] = useState(0);
  const [picked, setPicked] = useState<number[]>([]);
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);

  useEffect(() => { setOffset(0); }, [q]);
  useEffect(() => {
    let live = true; // a slow answer for an older search must not replace the current one
    api.library(cat, q.trim(), offset, PAGE).then((p) => { if (live) { setPage(p); setError(""); } }).catch((e) => { if (live) setError(e.message); });
    return () => { live = false; };
  }, [cat, q, offset]);

  const toggle = (id: number) => setPicked((p) => (p.includes(id) ? p.filter((x) => x !== id) : p.length < 100 ? [...p, id] : p));
  async function add() {
    setBusy(true); setError("");
    try { onDone(await api.importFromLibrary(worldId, cat, picked)); } catch (e) { setError((e as Error).message); setBusy(false); }
  }

  return (
    <Dialog title={`Bibliothèque Dofus · ${CATEGORY_LABELS[cat]}`} onClose={onClose} wide>
      {!page.available ? (
        <p className="muted">Les images du jeu ne sont pas sur cet ordinateur (<code>game/content</code>). Importe plutôt tes propres images.</p>
      ) : (
        <>
          <p className="muted small">Les images du jeu Dofus déjà présentes ici. Tu en gardes une copie dans ton monde : il continuera de marcher sans elles. Elles ne sont jamais publiées avec le projet.</p>
          <div className="lib-bar">
            <input aria-label="Chercher par numéro" placeholder="Numéro d'image (ex. 1000)" inputMode="numeric" value={q} onChange={(e) => setQ(e.target.value)} maxLength={12} />
            <span className="muted small">{page.total} image{page.total > 1 ? "s" : ""}</span>
          </div>
          <div className="lib-grid" role="listbox" aria-label="Images du jeu" aria-multiselectable="true">
            {page.ids.map((id) => (
              <button key={id} type="button" role="option" aria-selected={picked.includes(id)} aria-label={`Image ${id}`} className={"lib-tile" + (picked.includes(id) ? " on" : "")} onClick={() => toggle(id)}>
                <img src={api.libraryUrl(cat, id, 96)} alt="" loading="lazy" />
                <span className="small">{id}</span>
              </button>
            ))}
          </div>
          <div className="lib-bar">
            <button className="btn small-btn" disabled={offset === 0} onClick={() => setOffset(Math.max(0, offset - PAGE))}>← Précédentes</button>
            <button className="btn small-btn" disabled={offset + PAGE >= page.total} onClick={() => setOffset(offset + PAGE)}>Suivantes →</button>
          </div>
        </>
      )}
      {error && <Banner kind="error">{error}</Banner>}
      <div className="actions">
        <button type="button" className="btn" onClick={onClose}>Fermer</button>
        {page.available && <button type="button" className="btn primary" disabled={busy || picked.length === 0} onClick={add}>{busy ? "Copie en cours…" : `Ajouter ${picked.length} image${picked.length > 1 ? "s" : ""} au monde`}</button>}
      </div>
    </Dialog>
  );
}
