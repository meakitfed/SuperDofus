import { useState } from "react";
import { api, type MapTemplate } from "../api";
import { Banner, Dialog, Field } from "../components";

/** The walls of a map as a tiny picture: one dot per cell, dark where blocked. */
function MiniGrid({ blocked }: { blocked: number[] }) {
  const wall = new Set(blocked);
  return (
    <svg viewBox="0 0 14.5 20" width={87} height={120} aria-hidden="true" className="mini-grid">
      {Array.from({ length: 560 }, (_, c) => {
        const row = Math.floor(c / 14);
        return <rect key={c} x={(c % 14) + (row % 2 ? 0.5 : 0)} y={row * 0.5} width={0.92} height={0.46} className={wall.has(c) ? "w" : "f"} />;
      })}
    </svg>
  );
}

/** Start a map from a real Dofus map: its walls, placement and decor are copied into the world. */
export function DofusMapDialog({ worldId, onClose, onDone }: { worldId: string; onClose: () => void; onDone: (id: number, note: string) => void }) {
  const [q, setQ] = useState("");
  const [found, setFound] = useState<MapTemplate[] | null>(null);
  const [pick, setPick] = useState<MapTemplate | null>(null);
  const [name, setName] = useState("");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);

  async function search() {
    setError(""); setPick(null);
    try { setFound(await api.mapTemplates(q)); } catch (e) { setFound(null); setError((e as Error).message); }
  }
  async function copy() {
    if (!pick) return;
    setBusy(true); setError("");
    try {
      const r = await api.importDofusMap(worldId, name.trim(), pick.source);
      const lost = r.dropped > 0 ? `${r.dropped} élément${r.dropped > 1 ? "s" : ""} de décor sans image ont été laissés de côté. ` : "";
      onDone(r.id, `${lost}La map n'est reliée à rien pour l'instant : pose une voisine ou une porte.`);
    } catch (e) { setError((e as Error).message); setBusy(false); }
  }

  return (
    <Dialog title="Réutiliser une map du jeu Dofus" onClose={onClose} wide>
      <p className="muted small">Cherche par coordonnées du monde (ex. <code>-3,5</code>) ou par numéro de map. La grille (murs, vue, placement de combat) et le décor sont copiés dans ton monde, avec les images dont il a besoin. Ni les liens, ni les PNJ, ni les monstres ne viennent.</p>
      <div className="lib-bar">
        <input aria-label="Chercher une map du jeu" placeholder="Coordonnées (-3,5) ou numéro de map" value={q} onChange={(e) => setQ(e.target.value)}
          onKeyDown={(e) => { if (e.key === "Enter") { e.preventDefault(); search(); } }} />
        <button type="button" className="btn small-btn" disabled={!q.trim()} onClick={search}>Chercher</button>
      </div>
      {found && (found.length === 0 ? <p className="muted small">Aucune map à cet endroit.</p> : (
        <div className="map-results" role="listbox" aria-label="Maps du jeu">
          {found.map((m) => (
            <button key={m.source} type="button" role="option" aria-selected={pick?.source === m.source} aria-label={`Map ${m.source}`} className={"map-card" + (pick?.source === m.source ? " on" : "")}
              onClick={() => { setPick(m); setName(m.place || `Map ${m.source}`); }}>
              <MiniGrid blocked={m.blocked} />
              <span className="small"><strong>{m.place || "Sans nom"}</strong><br />n° {m.source}<br />{m.coords[0]}, {m.coords[1]} · {m.outdoor ? "extérieur" : "intérieur"}<br />{m.elements} éléments</span>
            </button>
          ))}
        </div>
      ))}
      {pick && <Field label="Nom de la nouvelle map"><input value={name} onChange={(e) => setName(e.target.value)} maxLength={60} /></Field>}
      {error && <Banner kind="error">{error}</Banner>}
      <div className="actions">
        <button type="button" className="btn" onClick={onClose}>Annuler</button>
        <button type="button" className="btn primary" disabled={!pick || !name.trim() || busy} onClick={copy}>{busy ? "Copie en cours…" : "Copier dans le monde"}</button>
      </div>
    </Dialog>
  );
}
