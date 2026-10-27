import { useCallback, useEffect, useState } from "react";
import { navigate } from "../App";
import { api, type Problem, type WorldDetail } from "../api";
import { Banner, Dialog, Field } from "../components";
import { AssetsPanel } from "./AssetsPage";
import { DecorPanel } from "./DecorPage";
import { GuidesPanel } from "./GuidesPage";
import { PlayablePanel } from "./PlayablePanel";
import { ItemsPanel } from "./ItemsPage";
import { ClassesPanel } from "./ClassesPage";
import { QuestsPanel } from "./QuestsPage";
import { NpcsPanel } from "./NpcsPage";
import { ResourcesPanel } from "./ResourcesPage";
import { DungeonsPanel } from "./DungeonsPage";
import { CraftsPanel } from "./CraftsPage";
import { MapsPanel } from "./MapsPage";
import { MonstersPanel } from "./MonstersPage";
import { SpellsPanel } from "./SpellsPage";
import { TextsPanel } from "./TextsPage";

type Tab = "overview" | "assets" | "texts" | "items" | "spells" | "monsters" | "classes" | "maps" | "npcs" | "quests" | "guides" | "decor" | "resources" | "dungeons" | "crafts";
const TABS: [Tab, string, string][] = [["overview", "Vue d'ensemble", ""], ["guides", "Assistants", "/assistants"], ["items", "Objets", "/objets"], ["spells", "Sorts", "/sorts"], ["maps", "Maps", "/maps"], ["decor", "Décor", "/decor"], ["npcs", "PNJ", "/pnj"], ["resources", "Ressources", "/ressources"], ["crafts", "Artisanat", "/artisanat"], ["dungeons", "Donjons", "/donjons"], ["quests", "Quêtes", "/quetes"], ["classes", "Classes", "/classes"], ["monsters", "Monstres", "/monstres"], ["texts", "Textes", "/textes"], ["assets", "Images", "/assets"]];

const COUNT_LABELS: [string, string][] = [
  ["maps", "Maps"], ["items", "Objets"], ["spells", "Sorts"], ["monsters", "Monstres"], ["npcs", "PNJ"], ["quests", "Quêtes"], ["dialogs", "Dialogues"],
  ["resources", "Ressources"], ["recipes", "Recettes"], ["dungeons", "Donjons"],
];
const KIND_LABELS: Record<string, string> = {
  text: "Textes", item: "Objets", set: "Panoplies", spell: "Sorts", monster: "Monstres", npc: "PNJ", quest: "Quêtes",
  step: "Étapes de quête", objective: "Objectifs", interactive: "Métiers, ressources, ateliers, donjons", map: "Maps", asset: "Images importées", breed: "Classes",
};
const fmt = (n: number) => n.toLocaleString("fr-FR");

export function WorldPage({ id, tab }: { id: string; tab: Tab }) {
  const [d, setD] = useState<WorldDetail | null>(null);
  const [error, setError] = useState("");
  const [dialog, setDialog] = useState<"rename" | "delete" | "clone" | null>(null);
  const [busy, setBusy] = useState(false);
  const [rev, setRev] = useState(0); // bumped by every successful change: the editors reload their rows

  const run = useCallback(async (f: () => Promise<WorldDetail>) => {
    setBusy(true);
    setError("");
    try { setD(await f()); setRev((r) => r + 1); } catch (e) { setError((e as Error).message); } finally { setBusy(false); }
  }, []);
  useEffect(() => { run(() => api.detail(id)); }, [id, tab, run]); // also on tab change: images imported meanwhile change the coherence report

  if (!d) return error ? <Banner kind="error">{error}</Banner> : <p className="muted">Chargement…</p>;
  const errors = d.problems.filter((p) => p.severity === "error");
  const warnings = d.problems.filter((p) => p.severity === "warning");

  return (
    <>
      <nav className="crumbs" aria-label="Fil d'Ariane">
        <a href="/" onClick={(e) => { e.preventDefault(); navigate("/"); }}>Mondes</a> <span>/</span> <span>{d.summary.name}</span>
      </nav>
      <header className="page-head">
        <div>
          <h1>{d.summary.name}</h1>
          <code className="id">game/worlds/{id}</code>
        </div>
        <div className="toolbar">
          <button className="btn" disabled={!d.canUndo || busy} onClick={() => run(() => api.undo(id))} title="Annuler la dernière modification">↶ Annuler</button>
          <button className="btn" disabled={!d.canRedo || busy} onClick={() => run(() => api.redo(id))} title="Refaire">↷ Refaire</button>
          <button className="btn" disabled={busy} onClick={() => run(() => api.reload(id))} title="Relire le dossier (après une modification à la main)">⟳ Relire</button>
          <button className="btn" onClick={() => setDialog("rename")}>Renommer</button>
          {d.summary.created && <a className="btn" href={api.exportUrl(id)} download={`${id}.zip`} title="Télécharger ce monde en archive ZIP (pour le partager ou le sauvegarder)">Exporter (.zip)</a>}
          {d.summary.created && <button className="btn" onClick={() => setDialog("clone")} title="Copier ce monde sous un autre nom, avec de nouveaux numéros">Dupliquer…</button>}
        </div>
      </header>
      {error && <Banner kind="error">{error}</Banner>}

      <nav className="tabs" aria-label="Sections du monde">
        {TABS.map(([k, label, suffix]) => { const href = `/mondes/${id}${suffix}`; return (
          <a key={k} href={href} className={tab === k ? "on" : ""} aria-current={tab === k ? "page" : undefined} onClick={(e) => { e.preventDefault(); navigate(href); }}>{label}</a>
        ); })}
      </nav>

      {tab !== "overview" && tab !== "assets" && <Strip errors={errors.length} warnings={warnings.length} problems={d.problems} />}
      {tab === "assets" ? <AssetsPanel worldId={id} /> :
       tab === "decor" ? <DecorPanel worldId={id} rev={rev} onChange={() => run(() => api.detail(id))} /> :
       tab === "guides" ? <GuidesPanel worldId={id} rev={rev} /> :
       tab === "texts" ? <TextsPanel worldId={id} rev={rev} onChange={() => run(() => api.detail(id))} /> :
       tab === "quests" ? <QuestsPanel worldId={id} rev={rev} onChange={() => run(() => api.detail(id))} /> :
       tab === "crafts" ? <CraftsPanel worldId={id} rev={rev} onChange={() => run(() => api.detail(id))} /> :
       tab === "dungeons" ? <DungeonsPanel worldId={id} rev={rev} onChange={() => run(() => api.detail(id))} /> :
       tab === "resources" ? <ResourcesPanel worldId={id} rev={rev} onChange={() => run(() => api.detail(id))} /> :
       tab === "npcs" ? <NpcsPanel worldId={id} rev={rev} onChange={() => run(() => api.detail(id))} /> :
       tab === "maps" ? <MapsPanel worldId={id} rev={rev} onChange={() => run(() => api.detail(id))} /> :
       tab === "classes" ? <ClassesPanel worldId={id} rev={rev} onChange={() => run(() => api.detail(id))} /> :
       tab === "monsters" ? <MonstersPanel worldId={id} rev={rev} onChange={() => run(() => api.detail(id))} /> :
       tab === "spells" ? <SpellsPanel worldId={id} rev={rev} onChange={() => run(() => api.detail(id))} /> :
       tab === "items" ? <ItemsPanel worldId={id} rev={rev} onChange={() => run(() => api.detail(id))} /> : <>
      <section className="tiles" aria-label="Contenu du monde">
        {COUNT_LABELS.map(([k, label]) => (
          <div className="tile" key={k}><span className="tile-n">{fmt(d.counts[k] ?? 0)}</span><span className="tile-l">{label}</span></div>
        ))}
      </section>

      <section className="panel" aria-labelledby="coh">
        <div className="panel-head">
          <h2 id="coh">Cohérence</h2>
          {d.problems.length === 0 ? <span className="chip ok">Aucun problème</span> : (
            <span>
              {errors.length > 0 && <span className="chip err">{errors.length} erreur{errors.length > 1 ? "s" : ""}</span>}{" "}
              {warnings.length > 0 && <span className="chip warn">{warnings.length} avertissement{warnings.length > 1 ? "s" : ""}</span>}
            </span>
          )}
        </div>
        {d.problems.length === 0 ? (
          <p className="muted">Toutes les références existent, les portes mènent quelque part et les ids sont dans la tranche du monde.</p>
        ) : (
          <ul className="problems">
            {[...errors, ...warnings].map((p, i) => <ProblemRow key={i} p={p} />)}
          </ul>
        )}
      </section>

      <PlayablePanel worldId={id} rev={rev} />

      <div className="two-col">
        <section className="panel" aria-labelledby="ranges">
          <h2 id="ranges">Tranches d'identifiants</h2>
          <p className="muted small">Réservées à ce monde : aucun autre monde ne peut y puiser.</p>
          <table className="table">
            <thead><tr><th>Type</th><th>De</th><th>À</th></tr></thead>
            <tbody>
              {Object.entries(d.ranges).map(([k, [lo, hi]]) => (
                <tr key={k}><td>{KIND_LABELS[k] ?? k}</td><td className="num">{fmt(lo)}</td><td className="num">{fmt(hi)}</td></tr>
              ))}
            </tbody>
          </table>
        </section>
        <section className="panel" aria-labelledby="journal">
          <h2 id="journal">Journal des modifications</h2>
          <ol className="journal">
            {[...d.journal].reverse().map((j, i) => <li key={i} className={i === 0 ? "current" : ""}>{j}</li>)}
          </ol>
          {d.summary.created && (
            <div className="danger-zone">
              <h3>Zone sensible</h3>
              <p className="muted small">Supprime le dossier du monde et libère sa tranche d'identifiants. Aucune corbeille.</p>
              <button className="btn danger" onClick={() => setDialog("delete")}>Supprimer ce monde…</button>
            </div>
          )}
        </section>
      </div>

      </>}

      {dialog === "clone" && <CloneDialog id={id} name={d.summary.name} onClose={() => setDialog(null)} />}
      {dialog === "rename" && <RenameDialog current={d.summary.name} onClose={() => setDialog(null)} onSave={(name) => { setDialog(null); run(() => api.rename(id, name)); }} />}
      {dialog === "delete" && (
        <DeleteDialog id={id} name={d.summary.name} onClose={() => setDialog(null)}
          onConfirm={async (c) => { await api.remove(id, c); navigate("/"); }} />
      )}
    </>
  );
}

/** Coherence at a glance while editing; the list opens under the chip. */
function Strip({ errors, warnings, problems }: { errors: number; warnings: number; problems: Problem[] }) {
  const [open, setOpen] = useState(false);
  const total = errors + warnings;
  return (
    <section className="strip" aria-label="Cohérence du monde">
      <button className="btn small-btn" onClick={() => setOpen(!open)} disabled={total === 0} aria-expanded={open}>
        {total === 0 ? <span className="chip ok">Monde cohérent</span> : <>
          {errors > 0 && <span className="chip err">{errors} erreur{errors > 1 ? "s" : ""}</span>}{" "}
          {warnings > 0 && <span className="chip warn">{warnings} avertissement{warnings > 1 ? "s" : ""}</span>}</>}
      </button>
      {open && <ul className="problems">{problems.map((p, i) => <ProblemRow key={i} p={p} />)}</ul>}
    </section>
  );
}

function ProblemRow({ p }: { p: Problem }) {
  return (
    <li className={"problem " + p.severity}>
      <span className="problem-icon" aria-label={p.severity === "error" ? "Erreur" : "Avertissement"}>{p.severity === "error" ? "✕" : "!"}</span>
      <div>
        <p>{p.message}</p>
        <p className="problem-meta"><code>{p.code}</code>{p.ref ? <> · {p.ref.kind} <code>{String(p.ref.id)}</code></> : null}</p>
      </div>
    </li>
  );
}

function CloneDialog({ id, name, onClose }: { id: string; name: string; onClose: () => void }) {
  const [newId, setNewId] = useState(`${id}_copie`.slice(0, 32));
  const [newName, setNewName] = useState(`${name} (copie)`);
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  return (
    <Dialog title="Dupliquer le monde" onClose={onClose}>
      <form onSubmit={async (e) => { e.preventDefault(); setBusy(true); setError(""); try { await api.clone(id, newId, newName.trim()); onClose(); navigate(`/mondes/${newId}`); } catch (err) { setError((err as Error).message); setBusy(false); } }}>
        <p className="muted small">La copie reprend tout (maps, objets, quêtes, images…) avec de nouveaux numéros : les deux mondes pourront cohabiter. Elle est contrôlée avant d'être gardée.</p>
        <Field label="Nom de la copie"><input value={newName} onChange={(e) => setNewName(e.target.value)} maxLength={60} /></Field>
        <Field label="Identifiant du dossier" hint="Minuscules, chiffres et _ (2 à 32 caractères)."><input value={newId} onChange={(e) => setNewId(e.target.value)} spellCheck={false} /></Field>
        {error && <Banner kind="error">{error}</Banner>}
        <div className="actions">
          <button type="button" className="btn" onClick={onClose}>Annuler</button>
          <button type="submit" className="btn primary" disabled={busy || !newName.trim() || !newId}>{busy ? "Copie en cours…" : "Dupliquer"}</button>
        </div>
      </form>
    </Dialog>
  );
}

function RenameDialog({ current, onClose, onSave }: { current: string; onClose: () => void; onSave: (n: string) => void }) {
  const [name, setName] = useState(current);
  return (
    <Dialog title="Renommer le monde" onClose={onClose}>
      <form onSubmit={(e) => { e.preventDefault(); if (name.trim()) onSave(name.trim()); }}>
        <Field label="Nom du monde" hint="L'identifiant du dossier ne change pas.">
          <input value={name} onChange={(e) => setName(e.target.value)} maxLength={60} />
        </Field>
        <div className="actions">
          <button type="button" className="btn" onClick={onClose}>Annuler</button>
          <button type="submit" className="btn primary" disabled={!name.trim() || name.trim() === current}>Renommer</button>
        </div>
      </form>
    </Dialog>
  );
}

function DeleteDialog({ id, name, onClose, onConfirm }: { id: string; name: string; onClose: () => void; onConfirm: (c: string) => Promise<void> }) {
  const [typed, setTyped] = useState("");
  const [error, setError] = useState("");
  return (
    <Dialog title={`Supprimer « ${name} » ?`} onClose={onClose}>
      <form onSubmit={async (e) => { e.preventDefault(); try { await onConfirm(typed); } catch (err) { setError((err as Error).message); } }}>
        <p>Le dossier <code>game/worlds/{id}</code> et tout son contenu seront effacés définitivement.</p>
        <Field label={`Tape « ${id} » pour confirmer`}>
          <input value={typed} onChange={(e) => setTyped(e.target.value)} spellCheck={false} />
        </Field>
        {error && <Banner kind="error">{error}</Banner>}
        <div className="actions">
          <button type="button" className="btn" onClick={onClose}>Annuler</button>
          <button type="submit" className="btn danger" disabled={typed !== id}>Supprimer définitivement</button>
        </div>
      </form>
    </Dialog>
  );
}
