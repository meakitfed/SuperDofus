import { useCallback, useEffect, useState } from "react";
import { navigate } from "../App";
import { api, type WorldSummary } from "../api";
import { Banner, Dialog, Field } from "../components";

const ID_RE = /^[a-z][a-z0-9_]{1,31}$/;
/** "Les Terres Brisées" -> "les_terres_brisees" */
export const slug = (name: string) =>
  name.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().replace(/[^a-z0-9]+/g, "_").replace(/^_+|_+$/g, "").slice(0, 32);

export function WorldsPage() {
  const [worlds, setWorlds] = useState<WorldSummary[] | null>(null);
  const [error, setError] = useState("");
  const [creating, setCreating] = useState(false);

  const load = useCallback(() => api.list().then(setWorlds).catch((e) => setError(e.message)), []);
  useEffect(() => { load(); }, [load]);

  return (
    <>
      <header className="page-head">
        <div>
          <h1>Mondes</h1>
          <p className="sub">Crée et modifie des mondes sans toucher au code du jeu. Chaque modification est vérifiée.</p>
        </div>
        <button className="btn primary" onClick={() => setCreating(true)}>+ Nouveau monde</button>
      </header>
      {error && <Banner kind="error">{error}</Banner>}
      {worlds === null && !error && <p className="muted">Chargement…</p>}
      {worlds && (
        <ul className="cards">
          {worlds.map((w) => (
            <li key={w.id}>
              {w.managed ? (
                <a className="card" href={`/mondes/${w.id}`} onClick={(e) => { e.preventDefault(); navigate(`/mondes/${w.id}`); }}>
                  <CardBody w={w} />
                </a>
              ) : (
                <div className="card disabled" title="Monde fait à la main : visible, mais non modifiable par l'atelier">
                  <CardBody w={w} />
                </div>
              )}
            </li>
          ))}
        </ul>
      )}
      {creating && <CreateDialog existing={worlds ?? []} onClose={() => setCreating(false)} onCreated={(id) => navigate(`/mondes/${id}`)} />}
    </>
  );
}

function CardBody({ w }: { w: WorldSummary }) {
  return (
    <>
      <div className="card-top">
        <h3>{w.name}</h3>
        {w.created ? <span className="chip accent">créé ici</span> : w.managed ? <span className="chip">géré</span> : <span className="chip muted">lecture seule</span>}
      </div>
      <code className="id">{w.id}</code>
      <dl className="mini">
        <div><dt>Maps</dt><dd>{w.maps}</dd></div>
        <div><dt>Classes</dt><dd>{w.breeds || "—"}</dd></div>
      </dl>
    </>
  );
}

function CreateDialog({ existing, onClose, onCreated }: { existing: WorldSummary[]; onClose: () => void; onCreated: (id: string) => void }) {
  const [name, setName] = useState("");
  const [id, setId] = useState("");
  const [idTouched, setIdTouched] = useState(false);
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);

  const effectiveId = idTouched ? id : slug(name);
  const idError =
    !effectiveId ? "" :
    !ID_RE.test(effectiveId) ? "2 à 32 caractères : minuscules, chiffres et _, en commençant par une lettre." :
    existing.some((w) => w.id === effectiveId) ? "Ce monde existe déjà." : "";
  const ok = name.trim() && effectiveId && !idError && !busy;

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (!ok) return;
    setBusy(true);
    setError("");
    try {
      await api.create(effectiveId, name.trim());
      onCreated(effectiveId);
    } catch (err) {
      setError((err as Error).message);
      setBusy(false);
    }
  }

  return (
    <Dialog title="Nouveau monde" onClose={onClose}>
      <form onSubmit={submit}>
        <Field label="Nom du monde" hint="Affiché aux joueurs.">
          <input value={name} onChange={(e) => setName(e.target.value)} placeholder="Les Terres Brisées" maxLength={60} />
        </Field>
        <Field label="Identifiant" hint="Nom du dossier dans game/worlds/. Ne change plus ensuite." error={idError}>
          <input value={effectiveId} onChange={(e) => { setId(e.target.value); setIdTouched(true); }} placeholder="les_terres_brisees" spellCheck={false} />
        </Field>
        <p className="muted small">Le monde démarre avec une map vide et aucune règle cassée. Il reçoit sa propre tranche d'identifiants, qui ne peut pas entrer en collision avec un autre monde.</p>
        {error && <Banner kind="error">{error}</Banner>}
        <div className="actions">
          <button type="button" className="btn" onClick={onClose}>Annuler</button>
          <button type="submit" className="btn primary" disabled={!ok}>Créer le monde</button>
        </div>
      </form>
    </Dialog>
  );
}
