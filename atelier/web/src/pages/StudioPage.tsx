import { useEffect, useRef, useState } from "react";
import { api, CATEGORY_LABELS, type Adjust, type AiStatus, type BoneLibrary, type Category, type Job, type Preview } from "../api";
import { Banner, Field } from "../components";
import { DofusPickDialog } from "./LibraryDialog";

type Mode = "character" | Category;
const MODES: [Mode, string][] = [["character", "Personnage"], ["item", "Icône d'objet"], ["spell", "Icône de sort"], ["monster", "Portrait"], ["tile", "Décor"]];
const NO_ADJUST: Adjust = { hue: 0, saturation: 1, brightness: 1 };

/** AI studio: a template + a description -> variants drawn by the local generator -> preview -> into the world. */
export function StudioPanel({ worldId, onChange }: { worldId: string; onChange: () => void }) {
  const [status, setStatus] = useState<(AiStatus & { godot: boolean }) | null>(null);
  const [mode, setMode] = useState<Mode>("character");
  const [job, setJob] = useState<Job | null>(null);
  const [error, setError] = useState("");
  useEffect(() => { api.aiStatus().then(setStatus).catch((e) => setError(e.message)); }, []);

  // follow the running job
  useEffect(() => {
    if (!job || job.status !== "running") return;
    const t = setTimeout(() => api.aiJob(job.id).then(setJob).catch((e) => setError(e.message)), 1500);
    return () => clearTimeout(t);
  }, [job]);

  return (
    <section className="panel" aria-labelledby="studio-h">
      <div className="panel-head">
        <h2 id="studio-h">Studio IA</h2>
        <div className="seg" role="tablist" aria-label="Que créer">
          {MODES.map(([m, label]) => (
            <button key={m} role="tab" aria-selected={m === mode} className={m === mode ? "on" : ""} onClick={() => { setMode(m); setJob(null); setError(""); }}>{label}</button>
          ))}
        </div>
      </div>
      {status && !status.ready && <Banner kind="error">{status.summary}</Banner>}
      {status?.ready && <p className="muted small">{status.summary}{status.device ? ` (${status.device}${status.vramGb ? `, ${status.vramGb} Go` : ""})` : ""} Une image prend environ une minute : rien ne quitte cet ordinateur.</p>}
      {error && <Banner kind="error">{error}</Banner>}
      {mode === "character"
        ? <CharacterForm worldId={worldId} busy={job?.status === "running"} onStart={(j) => { setError(""); setJob(j); }} onError={setError} />
        : <ImageForm worldId={worldId} cat={mode} busy={job?.status === "running"} onStart={(j) => { setError(""); setJob(j); }} onError={setError} />}
      {job && <JobView worldId={worldId} job={job} onChange={onChange} />}
    </section>
  );
}

function CharacterForm({ worldId, busy, onStart, onError }: { worldId: string; busy: boolean; onStart: (j: Job) => void; onError: (m: string) => void }) {
  const [look, setLook] = useState("");
  const [prompt, setPrompt] = useState("");
  const [count, setCount] = useState(3);
  const [bones, setBones] = useState<BoneLibrary | null>(null);
  const [dofus, setDofus] = useState(false);
  useEffect(() => { api.bones(worldId).then(setBones).catch(() => setBones(null)); }, [worldId]);
  const bone = Number(/^\{(\d+)/.exec(look)?.[1] ?? -1);
  async function start() {
    try { onStart(await api.aiCharacter(worldId, look, prompt, count)); } catch (e) { onError((e as Error).message); }
  }
  return (
    <div className="studio-form">
      <p className="muted small">L'IA repeint le modèle choisi : sa silhouette, son squelette et toutes ses animations restent ceux du modèle, dans toutes les directions.</p>
      <fieldset className="icon-pick">
        <legend className="field-label">Modèle de départ</legend>
        <div className="icons" role="radiogroup" aria-label="Squelettes du monde">
          {bones?.own.map((id) => (
            <button type="button" key={id} role="radio" aria-checked={id === bone} aria-label={`Squelette ${id}`} className={"icon-btn" + (id === bone ? " on" : "")} onClick={() => setLook(`{${id}|||100}`)}>
              <img src={api.boneUrl(worldId, id)} alt="" loading="lazy" />
            </button>
          ))}
        </div>
        <button type="button" className="btn small-btn" onClick={() => setDofus(true)}>Squelettes du jeu Dofus…</button>
        <Field label="Apparence (look)" hint="Rempli par le choix ci-dessus ; un look complet ({1|10,2195||100}) marche aussi.">
          <input value={look} onChange={(e) => setLook(e.target.value)} placeholder="{104|||100}" maxLength={400} />
        </Field>
      </fieldset>
      {dofus && <DofusPickDialog worldId={worldId} cat="bone" title="Modèle : un squelette du jeu Dofus" label="Prendre ce modèle" onClose={() => setDofus(false)} onPick={(id) => { setDofus(false); setLook(`{${id}|||100}`); }} />}
      <Field label="Description" hint="Matières, couleurs, ambiance : « golem de cristal violet, mousse sur les épaules »">
        <textarea rows={2} value={prompt} onChange={(e) => setPrompt(e.target.value)} maxLength={600} />
      </Field>
      <Count value={count} onChange={setCount} />
      <button className="btn primary" disabled={busy || !look.trim() || !prompt.trim()} onClick={start}>{busy ? "Génération en cours…" : "Générer"}</button>
    </div>
  );
}

function ImageForm({ worldId, cat, busy, onStart, onError }: { worldId: string; cat: Category; busy: boolean; onStart: (j: Job) => void; onError: (m: string) => void }) {
  const [ref, setRef] = useState<{ from: "library" | "world"; id: number } | null>(null);
  const [prompt, setPrompt] = useState("");
  const [count, setCount] = useState(4);
  const [pick, setPick] = useState(false);
  const [own, setOwn] = useState<number[]>([]);
  useEffect(() => { setRef(null); api.assets(worldId, cat).then((a) => setOwn(a.map((x) => x.id))).catch(() => setOwn([])); }, [worldId, cat]);
  async function start() {
    try { onStart(await api.aiImage(worldId, cat, prompt, count, ref ? { ...ref, cat } : undefined)); } catch (e) { onError((e as Error).message); }
  }
  const refUrl = ref && (ref.from === "library" ? api.libraryUrl(cat, ref.id, 128) : api.assetUrl(worldId, cat, ref.id));
  return (
    <div className="studio-form">
      <fieldset className="icon-pick">
        <legend className="field-label">Image de référence (facultative)</legend>
        <p className="muted small">L'IA garde son cadrage, sa perspective et son style. Sans référence, elle part du texte seul.</p>
        <div className="studio-ref">
          <div className="thumb small-thumb">{refUrl ? <img src={refUrl} alt="Référence choisie" /> : <span className="muted small">aucune</span>}</div>
          <div className="icons" role="radiogroup" aria-label="Images du monde">
            {own.slice(0, 60).map((id) => (
              <button type="button" key={id} role="radio" aria-checked={ref?.from === "world" && ref.id === id} aria-label={`Image ${id}`} className={"icon-btn" + (ref?.from === "world" && ref.id === id ? " on" : "")} onClick={() => setRef({ from: "world", id })}>
                <img src={api.assetUrl(worldId, cat, id)} alt="" loading="lazy" />
              </button>
            ))}
          </div>
        </div>
        <button type="button" className="btn small-btn" onClick={() => setPick(true)}>Bibliothèque Dofus…</button>{" "}
        {ref && <button type="button" className="btn small-btn" onClick={() => setRef(null)}>Sans référence</button>}
      </fieldset>
      {pick && <DofusPickDialog worldId={worldId} cat={cat} title={`Référence : ${CATEGORY_LABELS[cat]}`} label="Prendre comme référence" onClose={() => setPick(false)} onPick={(id) => { setPick(false); setRef({ from: "library", id }); }} />}
      <Field label="Description" hint={cat === "tile" ? "« tronc d'arbre mort couvert de champignons bleus »" : "« épée en os de dragon, garde dorée »"}>
        <textarea rows={2} value={prompt} onChange={(e) => setPrompt(e.target.value)} maxLength={600} />
      </Field>
      <Count value={count} onChange={setCount} />
      <button className="btn primary" disabled={busy || !prompt.trim()} onClick={start}>{busy ? "Génération en cours…" : "Générer"}</button>
    </div>
  );
}

function Count({ value, onChange }: { value: number; onChange: (n: number) => void }) {
  return (
    <Field label="Variantes" hint="Environ une minute chacune.">
      <select value={value} onChange={(e) => onChange(Number(e.target.value))}>{[1, 2, 3, 4].map((n) => <option key={n} value={n}>{n}</option>)}</select>
    </Field>
  );
}

function JobView({ worldId, job, onChange }: { worldId: string; job: Job; onChange: () => void }) {
  const [pick, setPick] = useState<number | null>(null);
  const [adjust, setAdjust] = useState<Adjust>(NO_ADJUST);
  const [bake, setBake] = useState(true);
  const [preview, setPreview] = useState<Preview | null>(null);
  const [name, setName] = useState(job.prompt.slice(0, 60));
  const [busy, setBusy] = useState("");
  const [done, setDone] = useState("");
  const [error, setError] = useState("");
  useEffect(() => { setPick(null); setPreview(null); setDone(""); setError(""); setAdjust(NO_ADJUST); setName(job.prompt.slice(0, 60)); }, [job.id]);
  const character = job.kind === "character";

  async function act<T>(label: string, fn: () => Promise<T>): Promise<T | undefined> {
    setBusy(label); setError("");
    try { return await fn(); } catch (e) { setError((e as Error).message); } finally { setBusy(""); }
  }
  const showPreview = (v: number) => act("aperçu", async () => setPreview(await api.aiPreview(job.id, v, adjust, bake)));
  async function accept() {
    if (pick === null) return;
    const r = await act("ajout", () => api.aiAccept(job.id, pick, { adjust, bake, name }));
    if (!r) return;
    setDone(character
      ? `Nouveau squelette ${r.bones?.join(", ") || "(skins seulement)"} ajouté au monde : choisis-le dans les éditeurs de monstres, de PNJ ou de classes. Apparence : ${r.look}`
      : `Image ${r.asset} ajoutée à la bibliothèque du monde (${CATEGORY_LABELS[job.category!]}).`);
    onChange();
  }

  return (
    <div className="studio-job">
      <p className="studio-step">
        {job.status === "running" && <span className="chip accent">{job.step}</span>}
        {job.status === "failed" && <span className="chip err">échec</span>}
        {job.status === "ready" && <span className="chip ok">variantes prêtes</span>}
      </p>
      {job.error && <Banner kind="error">{job.error}</Banner>}
      <ul className="studio-variants">
        {job.sheet && <li><p className="asset-meta">Modèle</p><div className={"thumb" + (character ? " sheet" : "")}><img src={api.aiFileUrl(job.id, job.sheet)} alt="Modèle envoyé à l'IA" /></div></li>}
        {job.variants.map((v, k) => (
          <li key={k}>
            <p className="asset-meta">Variante {k + 1}</p>
            {v ? (
              <button type="button" className={"thumb pickable" + (character ? " sheet" : "") + (pick === k ? " on" : "")} aria-pressed={pick === k} onClick={() => { setPick(k); setPreview(null); if (character) showPreview(k); }}>
                <img src={api.aiFileUrl(job.id, v)} alt={`Variante ${k + 1}`} />
              </button>
            ) : <div className={"thumb" + (character ? " sheet" : "")}><span className="muted small">en attente…</span></div>}
          </li>
        ))}
      </ul>
      {pick !== null && (
        <div className="studio-accept">
          {character && (
            <>
              <div className="studio-sliders">
                <label>Teinte <input type="range" min={-180} max={180} value={adjust.hue} onChange={(e) => setAdjust({ ...adjust, hue: Number(e.target.value) })} /></label>
                <label>Saturation <input type="range" min={0} max={2} step={0.05} value={adjust.saturation} onChange={(e) => setAdjust({ ...adjust, saturation: Number(e.target.value) })} /></label>
                <label>Luminosité <input type="range" min={0.5} max={1.5} step={0.05} value={adjust.brightness} onChange={(e) => setAdjust({ ...adjust, brightness: Number(e.target.value) })} /></label>
                <label className="check"><input type="checkbox" checked={!bake} onChange={(e) => setBake(!e.target.checked)} /> Garder les couleurs personnalisables du modèle</label>
                <button className="btn small-btn" disabled={!!busy} onClick={() => showPreview(pick)}>Recalculer l'aperçu</button>
              </div>
              {busy === "aperçu" && <p className="muted">Calcul de l'aperçu animé…</p>}
              {preview && <AnimPreview job={job.id} preview={preview} />}
            </>
          )}
          {!character && <Field label="Nom de l'image"><input value={name} onChange={(e) => setName(e.target.value)} maxLength={60} /></Field>}
          <button className="btn primary" disabled={!!busy || !!done} onClick={accept}>{busy === "ajout" ? "Ajout…" : "Ajouter au monde"}</button>
        </div>
      )}
      {error && <Banner kind="error">{error}</Banner>}
      {done && <Banner kind="ok">{done}</Banner>}
    </div>
  );
}

interface Sheet { cell: number; anims: Record<string, Record<string, { strip: string; flip: boolean }>>; strips: Record<string, { file: string; frames: number; fps: number }> }
const DIRS: [string, string][] = [["5", "↖"], ["7", "↗"], ["3", "↙"], ["1", "↘"]];

/** Plays the strips rendered by game/tools/anim_sheet.gd: every animation, every direction. */
export function AnimPreview({ job, preview }: { job: string; preview: Preview }) {
  const [sheet, setSheet] = useState<Sheet | null>(null);
  const [anim, setAnim] = useState("AnimStatique");
  const [dir, setDir] = useState("1");
  const [playing, setPlaying] = useState(true);
  const canvas = useRef<HTMLCanvasElement>(null);
  const base = preview.sheet.replace(/sheet\.json$/, "");
  useEffect(() => { fetch(api.aiFileUrl(job, preview.sheet)).then((r) => r.json()).then((s: Sheet) => { setSheet(s); if (!s.anims[anim]) setAnim(Object.keys(s.anims)[0] ?? ""); }); }, [job, preview.sheet]);
  useEffect(() => {
    const ref = sheet?.anims[anim]?.[dir] ?? Object.values(sheet?.anims[anim] ?? {})[0];
    const strip = ref && sheet?.strips[ref.strip];
    const c = canvas.current;
    if (!sheet || !ref || !strip || !c) return;
    const img = new Image();
    img.src = api.aiFileUrl(job, base + strip.file);
    let frame = 0, raf = 0, last = 0;
    const draw = (t: number) => {
      const ctx = c.getContext("2d");
      if (ctx && img.complete) {
        if (playing && t - last >= 1000 / strip.fps) { frame = (frame + 1) % strip.frames; last = t; }
        ctx.clearRect(0, 0, c.width, c.height);
        ctx.save();
        if (ref.flip) { ctx.translate(c.width, 0); ctx.scale(-1, 1); }
        ctx.drawImage(img, frame * sheet.cell, 0, sheet.cell, sheet.cell, 0, 0, c.width, c.height);
        ctx.restore();
      }
      raf = requestAnimationFrame(draw);
    };
    raf = requestAnimationFrame(draw);
    return () => cancelAnimationFrame(raf);
  }, [sheet, anim, dir, playing, job, base]);
  if (!sheet) return <p className="muted">Chargement de l'aperçu…</p>;
  return (
    <div className="anim-preview">
      <canvas ref={canvas} width={sheet.cell * 1.5} height={sheet.cell * 1.5} aria-label={`Aperçu : ${anim}, direction ${dir}`} />
      <div className="anim-controls">
        <select aria-label="Animation" value={anim} onChange={(e) => setAnim(e.target.value)}>{Object.keys(sheet.anims).sort().map((a) => <option key={a} value={a}>{a.replace(/^Anim/, "")}</option>)}</select>
        <div className="seg" role="radiogroup" aria-label="Direction">
          {DIRS.map(([d, arrow]) => <button key={d} role="radio" aria-checked={dir === d} className={dir === d ? "on" : ""} disabled={!sheet.anims[anim]?.[d]} onClick={() => setDir(d)}>{arrow}</button>)}
        </div>
        <button className="btn small-btn" onClick={() => setPlaying(!playing)}>{playing ? "Pause" : "Lecture"}</button>
        <p className="muted small">Pièces vues par l'IA : {preview.stats.seen.toLocaleString()} texels, complétées : {(preview.stats.filled + preview.stats.table).toLocaleString()}.</p>
      </div>
    </div>
  );
}
