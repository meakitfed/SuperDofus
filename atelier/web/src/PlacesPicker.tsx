import { useEffect, useState } from "react";
import { api, type AssetInfo, type MapRow } from "./api";
import { CellPicker } from "./CellPicker";
import { Field } from "./components";

export interface PlaceValue { map: number; cell: number }

/**
 * The picture of an element standing on maps, and the places it stands at: used by resources and workshops.
 * `takenBy(map)` lists the cells that other elements already occupy on a map.
 */
export function PlacesPicker({ worldId, maps, gfx, places, takenBy, onGfx, onPlaces }: {
  worldId: string; maps: MapRow[]; gfx: number; places: PlaceValue[]; takenBy: (map: number) => number[]; onGfx: (id: number) => void; onPlaces: (p: PlaceValue[]) => void;
}) {
  const [tiles, setTiles] = useState<AssetInfo[]>([]);
  const [pickMap, setPickMap] = useState(maps[0]?.id ?? 0);
  const [cell, setCell] = useState(150);
  useEffect(() => {
    api.assets(worldId, "tile").then((a) => { setTiles(a); if (!gfx && a[0]) onGfx(a[0].id); }).catch(() => {});
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [worldId]);
  const map = maps.find((m) => m.id === pickMap);
  const taken = [...takenBy(pickMap), ...places.filter((p) => p.map === pickMap).map((p) => p.cell), ...(map?.isStart ? [map.startCell] : []), ...(map?.doors.map((d) => d.cell) ?? [])];
  const mapName = (id: number) => maps.find((m) => m.id === id)?.name ?? `map ${id}`;
  const add = () => { if (!places.some((p) => p.map === pickMap && p.cell === cell)) onPlaces([...places, { map: pickMap, cell }]); };

  return (
    <>
      <fieldset className="icon-pick">
        <legend className="field-label">Image sur la map</legend>
        {tiles.length === 0 ? <p className="muted small">Aucune image de tuile : importe-en dans l'onglet Images (catégorie Tuiles).</p> : (
          <div className="icons" role="radiogroup" aria-label="Image sur la map">
            {tiles.map((a) => (
              <button type="button" key={a.id} role="radio" aria-checked={a.id === gfx} aria-label={`Tuile ${a.name || a.id}`} className={"icon-btn" + (a.id === gfx ? " on" : "")} onClick={() => onGfx(a.id)}>
                <img src={api.assetUrl(worldId, "tile", a.id)} alt="" loading="lazy" />
              </button>
            ))}
          </div>
        )}
      </fieldset>

      <fieldset className="icon-pick">
        <legend className="field-label">Emplacements ({places.length})</legend>
        {places.length > 0 && (
          <ul className="tpl-list" aria-label="Emplacements choisis">
            {places.map((p) => (
              <li key={`${p.map}/${p.cell}`}>
                <button type="button" className="btn small-btn" aria-label={`Retirer l'emplacement ${mapName(p.map)} cellule ${p.cell}`} onClick={() => onPlaces(places.filter((x) => x !== p))}>{mapName(p.map)} · cellule {p.cell} ✕</button>
              </li>
            ))}
          </ul>
        )}
        <div className="form-grid">
          <Field label="Map"><select value={pickMap} onChange={(e) => setPickMap(Number(e.target.value))}>{maps.map((m) => <option key={m.id} value={m.id}>{m.name}</option>)}</select></Field>
        </div>
        <div className="picker-wrap"><CellPicker label="Choisir la cellule" value={cell} onPick={setCell} blocked={map?.blocked} taken={taken} /></div>
        <p className="muted small">Cellule choisie : {cell}. Sombre : obstacle. Jaune : déjà prise. La cellule devient un obstacle ; si tu retires l'emplacement plus tard, libère-la dans la map.</p>
        <button type="button" className="btn small-btn" onClick={add}>Ajouter cet emplacement</button>
      </fieldset>
    </>
  );
}
