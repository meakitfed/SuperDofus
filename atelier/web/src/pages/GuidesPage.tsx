import { useEffect, useState } from "react";
import { navigate } from "../App";
import { api } from "../api";
import type { Workflow } from "../../../core/workflows";

/** Guided workflows: a goal, its steps in order, each one ticked from the world's own data. */
export function GuidesPanel({ worldId, rev }: { worldId: string; rev: number }) {
  const [list, setList] = useState<Workflow[] | null>(null);
  const [error, setError] = useState("");
  useEffect(() => { api.workflows(worldId).then(setList).catch((e) => setError(e.message)); }, [worldId, rev]);
  return (
    <section className="panel" aria-labelledby="guides-h">
      <div className="panel-head"><h2 id="guides-h">Assistants</h2></div>
      <p className="muted small">Chaque assistant mène à un résultat jouable, étape par étape. Les cases se cochent toutes seules d'après les données du monde : rien n'est mémorisé à part, donc rien ne peut rester cassé sans que l'étape le montre.</p>
      {error && <p role="alert">{error}</p>}
      {list === null ? !error && <p className="muted">Chargement…</p> : (
        <ul className="cards">
          {list.map((w) => {
            const next = w.steps.find((s) => !s.done);
            return (
              <li key={w.id}>
                <div className="card guide">
                  <div className="card-top"><h3>{w.title}</h3>{w.done ? <span className="chip ok">Terminé</span> : <span className="chip warn">{w.steps.filter((s) => s.done).length} / {w.steps.length}</span>}</div>
                  <p className="muted small">{w.goal}</p>
                  <ol className="guide-steps">
                    {w.steps.map((s, i) => (
                      <li key={i} className={s.done ? "done" : s === next ? "next" : ""}>
                        <span className="problem-icon" aria-label={s.done ? "Fait" : "À faire"}>{s.done ? "✓" : i + 1}</span>
                        <span><strong>{s.label}</strong><br /><span className="muted small">{s.hint}</span></span>
                      </li>
                    ))}
                  </ol>
                  {next && <button className="btn primary" onClick={() => navigate(`/mondes/${worldId}${next.tab}`)}>Aller à l'étape : {next.label}</button>}
                </div>
              </li>
            );
          })}
        </ul>
      )}
    </section>
  );
}
