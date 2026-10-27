import { useEffect, useState } from "react";
import { api, type Check } from "../api";
import type { GameCheck } from "../../../core/gamecheck";

/** The last word: boot the world in the real game. Any edit makes the previous answer stale. */
function GameCheckBox({ worldId, rev }: { worldId: string; rev: number }) {
  const [res, setRes] = useState<GameCheck | null>(null);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState("");
  useEffect(() => { setRes(null); setErr(""); }, [worldId, rev]);
  const go = async () => {
    setBusy(true); setErr(""); setRes(null);
    try { setRes(await api.gameCheck(worldId)); } catch (e) { setErr((e as Error).message); } finally { setBusy(false); }
  };
  return (
    <div className="game-check">
      <button type="button" className="btn primary" onClick={go} disabled={busy}>{busy ? "Le jeu charge le monde…" : "Vérifier avec le jeu"}</button>
      {err && <p className="muted small" role="alert">{err}</p>}
      {res && (
        <div role="status" className={"game-result " + res.status}>
          <strong>{res.status === "ok" ? "✓ " : res.status === "failed" ? "✕ " : "! "}{res.summary}</strong>
          {res.ms > 0 && <span className="muted small"> ({(res.ms / 1000).toFixed(1)} s)</span>}
          {res.fight && <p className={"small fight-probe " + res.fight.status}>{res.fight.status === "ok" ? "✓ " : res.fight.status === "failed" ? "✕ " : "– "}{res.fight.summary}</p>}
          {res.lines.length > 0 && <pre className="small">{res.lines.join("\n")}</pre>}
        </div>
      )}
    </div>
  );
}

const ICON = { ok: "✓", warning: "!", error: "✕" } as const;

/** Can a player go through this world? One line per question, the failures listed under it. */
export function PlayablePanel({ worldId, rev }: { worldId: string; rev: number }) {
  const [checks, setChecks] = useState<Check[] | null>(null);
  const [open, setOpen] = useState<string | null>(null);
  useEffect(() => { api.report(worldId).then(setChecks).catch(() => setChecks([])); }, [worldId, rev]);
  if (!checks) return null;
  const bad = checks.filter((c) => c.status !== "ok").length;
  return (
    <section className="panel" aria-labelledby="play-h">
      <div className="panel-head">
        <h2 id="play-h">Monde jouable ?</h2>
        {bad === 0 ? <span className="chip ok">Tout passe</span> : <span className="chip warn">{bad} point{bad > 1 ? "s" : ""} à voir</span>}
      </div>
      <p className="muted small">Au-delà des références valides : peut-on vraiment parcourir ce monde (maps atteignables, monstres rencontrables, quêtes terminables, objets obtenables) ?</p>
      <ul className="checks">
        {checks.map((c) => (
          <li key={c.code} className={"check-row " + c.status}>
            <button type="button" className="check-head" onClick={() => setOpen(open === c.code ? null : c.code)} aria-expanded={open === c.code} disabled={c.items.length === 0}>
              <span className="problem-icon" aria-label={c.status === "ok" ? "Réussi" : c.status === "warning" ? "Avertissement" : "Erreur"}>{ICON[c.status]}</span>
              <span><strong>{c.title}</strong><br /><span className="muted small">{c.summary}</span></span>
            </button>
            {open === c.code && <ul className="check-items">{c.items.map((i, k) => <li key={k} className="small">{i.message}</li>)}</ul>}
          </li>
        ))}
      </ul>
      <GameCheckBox worldId={worldId} rev={rev} />
    </section>
  );
}
