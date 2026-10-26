import { useState } from "react";
import { api, type BoneLibrary } from "./api";
import { DofusBoneDialog } from "./pages/LibraryDialog";

/** Skeleton chooser shared by the monster and class editors; skeletons of other worlds can be copied in. */
export function BonePicker({ worldId, value, onChange, disabled, bones, setBones, onError }: {
  worldId: string; value: number; onChange: (id: number) => void; disabled?: boolean;
  bones: BoneLibrary; setBones: (b: BoneLibrary) => void; onError: (m: string) => void;
}) {
  const [dofus, setDofus] = useState(false);
  async function copy(from: string, id: number) {
    onError("");
    try { setBones(await api.importBone(worldId, from, id)); onChange(id); } catch (e) { onError((e as Error).message); }
  }
  return (
    <fieldset className="icon-pick">
      <legend className="field-label">Squelette (apparence en combat)</legend>
      <div className="icons" role="radiogroup" aria-label="Squelette">
        {bones.own.map((id) => (
          <button type="button" key={id} role="radio" aria-checked={id === value} aria-label={`Squelette ${id}`} className={"icon-btn" + (id === value ? " on" : "")} onClick={() => onChange(id)} disabled={disabled}>
            <img src={api.boneUrl(worldId, id)} alt="" loading="lazy" />
          </button>
        ))}
      </div>
      {bones.own.length === 0 && <p className="muted small">Ce monde n'a aucun squelette : copie-en un depuis un autre monde ci-dessous.</p>}
      {!disabled && <button type="button" className="btn small-btn" onClick={() => setDofus(true)}>Squelettes du jeu Dofus…</button>}
      {dofus && <DofusBoneDialog worldId={worldId} onClose={() => setDofus(false)} onCopied={async (id) => { setDofus(false); try { setBones(await api.bones(worldId)); onChange(id); } catch (e) { onError((e as Error).message); } }} />}
      {bones.library.length > 0 && !disabled && (
        <details>
          <summary className="small">Copier un squelette d'un autre monde ({bones.library.length} disponibles)</summary>
          <div className="icons">
            {bones.library.map((b) => (
              <button type="button" key={`${b.world}/${b.id}`} className="icon-btn" aria-label={`Copier le squelette ${b.id} de ${b.world}`} title={`Copier depuis ${b.world}`} onClick={() => copy(b.world, b.id)}>
                <img src={api.boneUrl(worldId, b.id, b.world)} alt="" loading="lazy" />
              </button>
            ))}
          </div>
        </details>
      )}
    </fieldset>
  );
}
