import { useCallback, useEffect, useRef, useState } from "react";
import { api, CATEGORY_LABELS, toBase64, type AssetInfo, type Category, type ImportResult } from "../api";
import { Banner } from "../components";

const CATS = Object.keys(CATEGORY_LABELS) as Category[];
const ACCEPT = ".png,.jpg,.jpeg,.webp,.zip,image/png,image/jpeg,image/webp,application/zip";
const HINT: Record<Category, string> = {
  item: "Redimensionnées en 96 × 96 (fond transparent).",
  spell: "Redimensionnées en 96 × 96 (fond transparent).",
  monster: "Redimensionnés en 96 × 96 (fond transparent).",
  tile: "Gardent leur taille (4096 px maximum par côté).",
};

export function AssetsPanel({ worldId }: { worldId: string }) {
  const [cat, setCat] = useState<Category>("item");
  const [assets, setAssets] = useState<AssetInfo[] | null>(null);
  const [results, setResults] = useState<ImportResult[] | null>(null);
  const [error, setError] = useState("");
  const [over, setOver] = useState(false);
  const [busy, setBusy] = useState(false);
  const input = useRef<HTMLInputElement>(null);

  const load = useCallback(() => {
    setAssets(null);
    api.assets(worldId, cat).then(setAssets).catch((e) => setError(e.message));
  }, [worldId, cat]);
  useEffect(load, [load]);

  async function upload(list: FileList | File[]) {
    const files = [...list];
    if (!files.length) return;
    setBusy(true);
    setError("");
    setResults(null);
    try {
      const zips = files.filter((f) => /\.zip$/i.test(f.name));
      const images = files.filter((f) => !/\.zip$/i.test(f.name));
      const out: ImportResult[] = [];
      if (images.length) {
        const data = await Promise.all(images.map(async (f) => ({ name: f.name, data: await toBase64(f) })));
        out.push(...(await api.importAssets(worldId, cat, { files: data })));
      }
      for (const z of zips) out.push(...(await api.importAssets(worldId, cat, { zip: await toBase64(z) })));
      setResults(out);
      load();
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }

  async function remove(a: AssetInfo) {
    setError("");
    try { await api.removeAsset(worldId, cat, a.id); load(); } catch (e) { setError((e as Error).message); }
  }

  const imported = results?.filter((r) => r.status === "imported").length ?? 0;
  const dup = results?.filter((r) => r.status === "duplicate").length ?? 0;
  const rejected = results?.filter((r) => r.status === "rejected") ?? [];

  return (
    <section className="panel" aria-labelledby="assets-h">
      <div className="panel-head">
        <h2 id="assets-h">Bibliothèque d'images</h2>
        <div className="seg" role="tablist" aria-label="Catégorie">
          {CATS.map((c) => (
            <button key={c} role="tab" aria-selected={c === cat} className={c === cat ? "on" : ""} onClick={() => { setCat(c); setResults(null); setError(""); }}>
              {CATEGORY_LABELS[c]}
            </button>
          ))}
        </div>
      </div>

      <div
        className={"drop" + (over ? " over" : "")}
        onDragOver={(e) => { e.preventDefault(); setOver(true); }}
        onDragLeave={() => setOver(false)}
        onDrop={(e) => { e.preventDefault(); setOver(false); upload(e.dataTransfer.files); }}
      >
        <p><strong>Dépose des images ou une archive ZIP ici</strong></p>
        <p className="muted small">PNG, JPEG ou WebP, 8 Mo maximum chacune. {HINT[cat]}</p>
        <button className="btn primary" disabled={busy} onClick={() => input.current?.click()}>{busy ? "Import en cours…" : "Choisir des fichiers…"}</button>
        <input ref={input} type="file" multiple accept={ACCEPT} hidden aria-label="Fichiers à importer" onChange={(e) => { if (e.target.files) upload(e.target.files); e.target.value = ""; }} />
      </div>

      {error && <Banner kind="error">{error}</Banner>}
      {results && (
        <div className="import-report" role="status">
          <p>
            {imported > 0 && <span className="chip ok">{imported} importée{imported > 1 ? "s" : ""}</span>}{" "}
            {dup > 0 && <span className="chip">{dup} déjà présente{dup > 1 ? "s" : ""}</span>}{" "}
            {rejected.length > 0 && <span className="chip err">{rejected.length} refusée{rejected.length > 1 ? "s" : ""}</span>}
          </p>
          {rejected.length > 0 && (
            <ul className="rejected">{rejected.map((r, i) => <li key={i}><strong>{r.name}</strong> : {r.reason}</li>)}</ul>
          )}
        </div>
      )}

      {assets === null ? <p className="muted">Chargement…</p> : assets.length === 0 ? (
        <p className="muted empty">Aucune image dans cette catégorie pour l'instant.</p>
      ) : (
        <ul className="gallery">
          {assets.map((a) => (
            <li key={a.id} className="asset">
              <div className={"thumb" + (cat === "tile" ? " tile" : "")}><img src={api.assetUrl(worldId, cat, a.id)} alt={a.name || `Image ${a.id}`} loading="lazy" /></div>
              <p className="asset-name" title={a.name}>{a.name || "sans nom"}</p>
              <p className="asset-meta"><code>{a.id}</code> · {a.width}×{a.height}</p>
              <p className="asset-meta">
                {a.usedBy.length > 0
                  ? <span className="chip accent" title={a.usedBy.map((u) => `${u.kind} ${u.id}`).join(", ")}>utilisée ×{a.usedBy.length}</span>
                  : <span className="chip warn">inutilisée</span>}
              </p>
              <button className="btn small-btn" disabled={a.usedBy.length > 0} onClick={() => remove(a)} title={a.usedBy.length ? "Utilisée : retire d'abord ses références" : "Supprimer l'image"}>Supprimer</button>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}
