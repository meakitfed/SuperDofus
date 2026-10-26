// Real Dofus maps as a starting point: find one by its map number or its world coordinates, then copy its grid (walls,
// line of sight, fight placement) and its decor into a world, with the tile images the decor uses.
import fs from "node:fs";
import path from "node:path";
import { AtelierError } from "./errors";
import { readI18n } from "./dofus_text";
import type { MapVisual } from "./schemas";

export const MAP_TEMPLATE_LIMIT = 24;
type Raw = Record<string, any>;

export interface MapTemplate {
  source: number;
  coords: [number, number];
  outdoor: boolean;
  /** the place's name in the client's texts, when it has one */
  place: string;
  blocked: number[];
  elements: number;
}

const mapFile = (dofusDir: string, id: number) => path.join(dofusDir, "maps", `${id}.json`);
const readJson = (f: string) => JSON.parse(fs.readFileSync(f, "utf-8")) as Raw;

/** Map numbers matching "x,y" (world coordinates) or a map number. */
function findIds(dofusDir: string, query: string): number[] {
  const q = query.trim();
  const xy = /^(-?\d{1,3})\s*[, ]\s*(-?\d{1,3})$/.exec(q);
  if (xy) {
    const file = path.join(dofusDir, "coords.json");
    if (!fs.existsSync(file)) throw new AtelierError(404, "les maps du jeu ne sont pas sur cet ordinateur (game/worlds/dofus)");
    const entry = (readJson(file)[`${Number(xy[1])},${Number(xy[2])}`] ?? []) as unknown[][];
    return entry.map((e) => Number(e[0])).filter((n) => Number.isInteger(n) && n >= 0);
  }
  if (/^\d{1,12}$/.test(q)) return fs.existsSync(mapFile(dofusDir, Number(q))) ? [Number(q)] : [];
  throw new AtelierError(400, "recherche : des coordonnées (ex. -3,5) ou un numéro de map");
}

export function searchDofusMaps(dofusDir: string, contentRoot: string, query: string): MapTemplate[] {
  if (!fs.existsSync(path.join(dofusDir, "maps"))) throw new AtelierError(404, "les maps du jeu ne sont pas sur cet ordinateur (game/worlds/dofus)");
  const i18n = path.join(contentRoot, "I18n", "fr.bin");
  const text = fs.existsSync(i18n) ? readI18n(i18n) : () => "";
  const out: MapTemplate[] = [];
  for (const id of findIds(dofusDir, query).slice(0, MAP_TEMPLATE_LIMIT)) {
    const f = mapFile(dofusDir, id);
    if (!fs.existsSync(f)) continue;
    const m = readJson(f);
    const vf = path.join(contentRoot, "Maps", `${m.visual ?? id}.json`);
    let elements = 0;
    if (fs.existsSync(vf)) {
      const v = readJson(vf);
      elements = Object.values((v.layers ?? {}) as Record<string, unknown[]>).reduce((n, l) => n + l.length, 0);
    }
    out.push({
      source: id, coords: [Number(m.coords?.[0] ?? 0), Number(m.coords?.[1] ?? 0)], outdoor: !!m.outdoor,
      place: text(Number(m.subarea_name_id)) || text(Number(m.area_name_id)) || "", blocked: (m.blocked ?? []) as number[], elements,
    });
  }
  return out;
}

export interface DofusMap { map: Raw; visual: MapVisual; gfx: number[] }

/** The map and decor of Dofus map `id`. */
export function loadDofusMap(dofusDir: string, contentRoot: string, id: number): DofusMap {
  if (!Number.isInteger(id) || id < 0 || !fs.existsSync(mapFile(dofusDir, id))) throw new AtelierError(404, `map ${id} absente du jeu`);
  const map = readJson(mapFile(dofusDir, id));
  const vf = path.join(contentRoot, "Maps", `${map.visual ?? id}.json`);
  if (!fs.existsSync(vf)) throw new AtelierError(404, `le décor de la map ${id} n'est pas dans le contenu du jeu`);
  const visual = readJson(vf) as MapVisual;
  const layers = (visual as Raw).layers as Record<string, Raw[]>;
  const gfx = [...new Set(Object.values(layers).flatMap((l) => l.map((e) => Number(e.g))))].filter((g) => Number.isInteger(g));
  return { map, visual, gfx };
}

/** Copies the tile images of `gfx` into the world; returns the ids that could not be found in the game content. */
export function copyGfx(contentRoot: string, worldDir: string, gfx: number[]): number[] {
  const dest = path.join(worldDir, "Content", "Maps", "Gfx");
  fs.mkdirSync(dest, { recursive: true });
  const missing: number[] = [];
  for (const g of gfx) {
    const have = [".webp", ".png"].some((e) => fs.existsSync(path.join(dest, `${g}${e}`)));
    if (have) continue;
    const src = [".webp", ".png"].map((e) => path.join(contentRoot, "Maps", "Gfx", `${g}${e}`)).find((p) => fs.existsSync(p));
    if (!src) { missing.push(g); continue; }
    fs.copyFileSync(src, path.join(dest, path.basename(src)));
  }
  return missing;
}
