import { useCallback, useEffect, useState } from "react";
import { api, type ItemRow, type MapRow, type MonsterRow } from "../api";
import type { DungeonInput, DungeonRow } from "../../../core/editors_dungeons";
import { Banner, Dialog, Field } from "../components";

export function DungeonsPanel({ worldId, rev, onChange }: { worldId: string; rev: number; onChange: () => void }) {
  const [rows, setRows] = useState<DungeonRow[] | null>(null);
  const [maps, setMaps] = useState<MapRow[]>([]);
  const [error, setError] = useState("");
  const [edit, setEdit] = useState<DungeonRow | "new" | null>(null);

  const load = useCallback(() => {
    api.rows<DungeonRow>(worldId, "dungeons").then(setRows).catch((e) => setError(e.message));
    api.rows<MapRow>(worldId, "maps").then(setMaps).catch(() => {});
  }, [worldId]);
  useEffect(load, [load, rev]);

  return (
    <section className="panel" aria-labelledby="dun-h">
      <div className="panel-head">
        <h2 id="dun-h">Donjons</h2>
        <button className="btn primary" onClick={() => setEdit("new")}>+ Nouveau donjon</button>
      </div>
      <p className="muted small">Un donjon est une suite de salles (des maps du monde) jouées dans l'ordre, depuis une map d'entrée. Chaque salle est une copie privée de sa map ; on passe à la suivante en battant tous ses monstres. La dernière salle abrite le boss.</p>
      {error && <Banner kind="error">{error}</Banner>}
      {rows === null ? <p className="muted">Chargement…</p> : rows.length === 0 ? (
        <p className="muted empty">Aucun donjon. Crée d'abord les maps des salles et une zone de monstres.</p>
      ) : (
        <table className="table data">
          <thead><tr><th>Donjon</th><th>Entrée</th><th>Salles</th><th>Niveau</th><th>Clés</th><th>Boss</th><th /></tr></thead>
          <tbody>
            {rows.map((r) => (
              <tr key={r.id}>
                <td className="wrap"><strong>{r.name}</strong><br /><code className="id">{r.id}</code></td>
                <td>{r.entranceName}</td>
                <td className="num">{r.rooms.length}</td>
                <td className="num">{r.minLevel}–{r.level}</td>
                <td className="num">{r.keys.length || "—"}</td>
                <td className="num">{r.bosses.length || "—"}</td>
                <td className="row-actions"><button className="btn small-btn" onClick={() => setEdit(r)} aria-label={`Modifier le donjon ${r.name}`}>Modifier</button></td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
      {edit && <DungeonDialog worldId={worldId} row={edit === "new" ? null : edit} maps={maps} onClose={() => setEdit(null)} onDone={() => { setEdit(null); onChange(); }} />}
    </section>
  );
}

function DungeonDialog({ worldId, row, maps, onClose, onDone }: { worldId: string; row: DungeonRow | null; maps: MapRow[]; onClose: () => void; onDone: () => void }) {
  const first = maps[0]?.id ?? 0;
  const [f, setF] = useState<DungeonInput>(() => row
    ? { name: row.name, level: row.level, minLevel: row.minLevel, difficulty: row.difficulty, entrance: row.entrance, exit: row.exit, rooms: [...row.rooms], keys: row.keys.map((k) => ({ ...k })), bosses: [...row.bosses] }
    : { name: "", level: 10, minLevel: 1, difficulty: 1, entrance: first, exit: first, rooms: [], keys: [], bosses: [] });
  const [items, setItems] = useState<ItemRow[]>([]);
  const [monsters, setMonsters] = useState<MonsterRow[]>([]);
  const [addRoom, setAddRoom] = useState(0);
  const [error, setError] = useState("");
  const [confirm, setConfirm] = useState(false);
  useEffect(() => {
    api.rows<ItemRow>(worldId, "items").then(setItems).catch(() => {});
    api.rows<MonsterRow>(worldId, "monsters").then(setMonsters).catch(() => {});
  }, [worldId]);
  const patch = (p: Partial<DungeonInput>) => setF((x) => ({ ...x, ...p }));
  const name = (id: number) => maps.find((m) => m.id === id)?.name ?? `map ${id}`;
  const candidates = maps.filter((m) => !f.rooms.includes(m.id) && m.id !== f.entrance && m.id !== f.exit);
  const pick = candidates.some((m) => m.id === addRoom) ? addRoom : candidates[0]?.id ?? 0;
  const move = (i: number, d: number) => { const r = [...f.rooms]; [r[i], r[i + d]] = [r[i + d], r[i]]; patch({ rooms: r }); };
  const setKey = (i: number, p: Partial<{ item: number; qty: number }>) => patch({ keys: f.keys.map((k, j) => (j === i ? { ...k, ...p } : k)) });
  const valid = f.name.trim() && f.rooms.length > 0 && f.entrance > 0 && f.exit > 0;
  async function run(fn: () => Promise<unknown>) { setError(""); try { await fn(); onDone(); } catch (e) { setError((e as Error).message); setConfirm(false); } }

  return (
    <Dialog title={row ? `Modifier « ${row.name} »` : "Nouveau donjon"} onClose={onClose} wide>
      <form onSubmit={(e) => { e.preventDefault(); if (valid) run(() => (row ? api.setRow(worldId, "dungeons", row.id, f) : api.addRow(worldId, "dungeons", f))); }}>
        <div className="form-grid">
          <Field label="Nom"><input value={f.name} onChange={(e) => patch({ name: e.target.value })} maxLength={60} /></Field>
          <Field label="Difficulté"><select value={f.difficulty} onChange={(e) => patch({ difficulty: Number(e.target.value) })}>{[1, 2, 3, 4, 5].map((d) => <option key={d} value={d}>{d}</option>)}</select></Field>
          <Field label="Niveau des monstres"><input type="number" min={1} max={200} value={f.level} onChange={(e) => patch({ level: Number(e.target.value) })} /></Field>
          <Field label="Niveau minimum pour entrer"><input type="number" min={1} max={f.level} value={f.minLevel} onChange={(e) => patch({ minLevel: Number(e.target.value) })} /></Field>
          <Field label="Map d'entrée" hint="Là où se trouve la porte du donjon."><select value={f.entrance} onChange={(e) => patch({ entrance: Number(e.target.value) })}>{maps.map((m) => <option key={m.id} value={m.id}>{m.name}</option>)}</select></Field>
          <Field label="Map de sortie" hint="Où l'on revient en sortant."><select value={f.exit} onChange={(e) => patch({ exit: Number(e.target.value) })}>{maps.map((m) => <option key={m.id} value={m.id}>{m.name}</option>)}</select></Field>
        </div>

        <fieldset className="icon-pick">
          <legend className="field-label">Salles, dans l'ordre ({f.rooms.length})</legend>
          {f.rooms.length === 0 ? <p className="muted small">Aucune salle : ajoute au moins une map.</p> : (
            <ol className="rooms" aria-label="Salles">
              {f.rooms.map((r, i) => (
                <li key={r}>
                  <span>{i + 1}. {name(r)}{i === f.rooms.length - 1 && f.rooms.length > 1 ? " (dernière : le boss)" : ""}</span>
                  <span className="toolbar">
                    <button type="button" className="btn small-btn" disabled={i === 0} aria-label={`Monter la salle ${name(r)}`} onClick={() => move(i, -1)}>↑</button>
                    <button type="button" className="btn small-btn" disabled={i === f.rooms.length - 1} aria-label={`Descendre la salle ${name(r)}`} onClick={() => move(i, 1)}>↓</button>
                    <button type="button" className="btn small-btn" aria-label={`Retirer la salle ${name(r)}`} onClick={() => patch({ rooms: f.rooms.filter((x) => x !== r) })}>✕</button>
                  </span>
                </li>
              ))}
            </ol>
          )}
          {candidates.length > 0 && (
            <div className="lib-bar">
              <select aria-label="Salle à ajouter" value={pick} onChange={(e) => setAddRoom(Number(e.target.value))}>{candidates.map((m) => <option key={m.id} value={m.id}>{m.name}</option>)}</select>
              <button type="button" className="btn small-btn" onClick={() => patch({ rooms: [...f.rooms, pick] })}>Ajouter la salle</button>
            </div>
          )}
          <p className="muted small">Chaque salle fait apparaître les monstres de la zone de sa map (à défaut, de celle de l'entrée). Une map ne peut pas être à la fois salle, entrée ou sortie.</p>
        </fieldset>

        <fieldset className="icon-pick">
          <legend className="field-label">Clés ({f.keys.length})</legend>
          {f.keys.map((k, i) => (
            <div className="lib-bar" key={i}>
              <select aria-label={`Objet de la clé ${i + 1}`} value={k.item} onChange={(e) => setKey(i, { item: Number(e.target.value) })}>{items.map((it) => <option key={it.id} value={it.id}>{it.name}</option>)}</select>
              <input aria-label={`Quantité de la clé ${i + 1}`} type="number" min={1} max={99} value={k.qty} onChange={(e) => setKey(i, { qty: Number(e.target.value) })} />
              <button type="button" className="btn small-btn" aria-label={`Retirer la clé ${i + 1}`} onClick={() => patch({ keys: f.keys.filter((_, j) => j !== i) })}>✕</button>
            </div>
          ))}
          <button type="button" className="btn small-btn" disabled={items.length === 0 || f.keys.length >= 4} onClick={() => patch({ keys: [...f.keys, { item: items.find((it) => !f.keys.some((k) => k.item === it.id))?.id ?? items[0].id, qty: 1 }] })}>Ajouter une clé</button>
          <p className="muted small">Les clés sont prises à l'entrée du donjon, auprès du chef du groupe.</p>
        </fieldset>

        <fieldset className="icon-pick">
          <legend className="field-label">Boss de la dernière salle ({f.bosses.length})</legend>
          {monsters.filter((m) => !m.boss).length === 0 ? <p className="muted small">Aucun monstre : crées-en un dans l'onglet Monstres.</p> : monsters.filter((m) => !m.boss).map((m) => (
            <label className="check" key={m.id}>
              <input type="checkbox" checked={f.bosses.includes(m.id)} onChange={(e) => patch({ bosses: e.target.checked ? [...f.bosses, m.id] : f.bosses.filter((b) => b !== m.id) })} /> {m.name} <span className="muted">· niv. {m.grades[0]?.level} à {m.grades[m.grades.length - 1]?.level}</span>
            </label>
          ))}
          <p className="muted small">Le monstre choisi est copié comme boss (la copie le suit quand tu le modifies). Sans boss, la dernière salle est une salle de monstres comme les autres.</p>
        </fieldset>

        {error && <Banner kind="error">{error}</Banner>}
        <div className="actions spread">
          {row ? (confirm
            ? <button type="button" className="btn danger" onClick={() => run(() => api.delRow(worldId, "dungeons", row.id))}>Confirmer la suppression</button>
            : <button type="button" className="btn danger" onClick={() => setConfirm(true)}>Supprimer ce donjon…</button>) : <span />}
          <span className="toolbar">
            <button type="button" className="btn" onClick={onClose}>Annuler</button>
            <button type="submit" className="btn primary" disabled={!valid}>{row ? "Enregistrer" : "Créer le donjon"}</button>
          </span>
        </div>
      </form>
    </Dialog>
  );
}
