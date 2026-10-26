// Visual layers of a map (Content/Maps/<visual>.json): the floor image, the props that stand on cells, the foreground.
// An element is an image of the tile library placed by the centre of its sprite, in map pixels (cell 0 centre = 0,0).
// The editor never invents a missing image: every `g` must be a tile of the world (E_MAP_GFX would flag it anyway).
import { AtelierError } from "./errors";
import type { ContentProbe, World } from "./io";
import { validCell } from "./grid";
import type { MapVisual } from "./schemas";

export const LAYERS = ["background", "sortable", "foreground"] as const;
export type Layer = (typeof LAYERS)[number];

/** Pixel size of a cell step and of the whole map area: same convention as the game (86 x 21.5 per half row). */
export const CELL_W = 86;
export const CELL_H = 21.5;
export const MAP_W = 14 * CELL_W + CELL_W / 2;
export const MAP_H = 39 * CELL_H;
const LIMITS = { minX: -400, maxX: MAP_W + 400, minY: -300, maxY: MAP_H + 300, perLayer: 4000 };

export interface ElementInput {
  g: number; x: number; y: number;
  /** sortable only: the cell the prop stands on */
  cell?: number;
  /** the 2x2 part of the transform [a, b, c, d] (scale, flip, rotation); absent = identity */
  m?: [number, number, number, number];
  /** ARGB tint; absent = neutral grey */
  tint?: number;
}
export interface VisualInput { bg: number; background: ElementInput[]; sortable: ElementInput[]; foreground: ElementInput[] }
export interface VisualRow extends VisualInput { map: number; visual: number; shared: boolean }

type Raw = Record<string, any>;
const GREY = 0xff808080; // neutral tint: the image is drawn as it is

/** Centre of cell `c` in map pixels. */
export function cellXY(c: number): [number, number] {
  const row = Math.floor(c / 14);
  return [(c % 14) * CELL_W + (row % 2 ? CELL_W / 2 : 0), row * CELL_H];
}

const IDENTITY = [1, 0, 0, 1];
const isIdentity = (m: number[]) => m.every((v, i) => v === IDENTITY[i]);
const toElement = (e: Raw): ElementInput => ({
  g: e.g, x: e.t?.[4] ?? 0, y: e.t?.[5] ?? 0,
  ...(typeof e.cell === "number" ? { cell: e.cell } : {}),
  ...(Array.isArray(e.t) && !isIdentity(e.t.slice(0, 4)) ? { m: e.t.slice(0, 4) as [number, number, number, number] } : {}),
  ...(typeof e.c === "number" && e.c !== GREY ? { tint: e.c } : {}),
});

function mapOf(w: World, mapId: number): Raw {
  const m = w.maps.get(mapId) as Raw | undefined;
  if (!m) throw new AtelierError(404, `map ${mapId} inconnue`);
  return m;
}

export function getVisual(w: World, mapId: number, template: MapVisual): VisualRow {
  const m = mapOf(w, mapId);
  const v = (w.visuals.get(m.visual) ?? template) as Raw;
  const layer = (k: Layer) => ((v.layers?.[k] ?? []) as Raw[]).map(toElement);
  return {
    map: mapId, visual: m.visual, bg: v.bg ?? 0xff000000, background: layer("background"), sortable: layer("sortable"), foreground: layer("foreground"),
    shared: [...w.maps.values()].filter((o) => (o as Raw).visual === m.visual).length > 1,
  };
}

function clean(layer: Layer, list: unknown, probe: ContentProbe): ElementInput[] {
  if (!Array.isArray(list)) throw new AtelierError(400, `couche ${layer} : liste attendue`);
  if (list.length > LIMITS.perLayer) throw new AtelierError(400, `couche ${layer} : ${LIMITS.perLayer} éléments au plus`);
  return list.map((e: Raw, i: number) => {
    const where = `couche ${layer}, élément ${i + 1}`;
    if (!Number.isInteger(e?.g) || e.g <= 0) throw new AtelierError(400, `${where} : image manquante`);
    if (!probe(`Maps/Gfx/${e.g}.png`) && !probe(`Maps/Gfx/${e.g}.webp`)) throw new AtelierError(400, `${where} : l'image ${e.g} n'existe pas dans les tuiles de ce monde`);
    if (!Number.isFinite(e.x) || !Number.isFinite(e.y) || e.x < LIMITS.minX || e.x > LIMITS.maxX || e.y < LIMITS.minY || e.y > LIMITS.maxY)
      throw new AtelierError(400, `${where} : position hors de la map`);
    if (layer === "sortable" && !validCell(e.cell)) throw new AtelierError(400, `${where} : cellule invalide`);
    if (e.m !== undefined && !(Array.isArray(e.m) && e.m.length === 4 && e.m.every((n: unknown) => Number.isFinite(n) && Math.abs(n as number) <= 100))) throw new AtelierError(400, `${where} : transformation invalide`);
    if (e.tint !== undefined && !(Number.isInteger(e.tint) && e.tint >= 0 && e.tint <= 0xffffffff)) throw new AtelierError(400, `${where} : teinte invalide`);
    return {
      g: e.g, x: Math.round(e.x * 10) / 10, y: Math.round(e.y * 10) / 10,
      ...(layer === "sortable" ? { cell: e.cell } : {}), ...(e.m ? { m: e.m } : {}), ...(e.tint !== undefined ? { tint: e.tint } : {}),
    };
  });
}

export function updateVisual(w: World, probe: ContentProbe, mapId: number, input: VisualInput, template: MapVisual): void {
  const m = mapOf(w, mapId);
  if (!Number.isInteger(input?.bg) || input.bg < 0 || input.bg > 0xffffffff) throw new AtelierError(400, "couleur de fond invalide");
  const next = Object.fromEntries(LAYERS.map((k) => [k, clean(k, input[k] ?? [], probe)])) as Record<Layer, ElementInput[]>;
  const v = (w.visuals.get(m.visual) ?? { ...structuredClone(template), id: m.visual }) as Raw;
  v.bg = input.bg;
  v.layers = v.layers ?? {};
  for (const k of LAYERS) {
    const old = (v.layers[k] ?? []) as Raw[];
    const occupied = new Map<number, number>();
    // an element keeps the fields the editor does not know (tint, flags) from the one that was at its rank
    v.layers[k] = next[k].map((e, i) => {
      const out: Raw = { ...(old[i] ?? {}), g: e.g, c: e.tint ?? GREY };
      out.t = [...(e.m ?? IDENTITY), e.x, e.y];
      if (k === "sortable") {
        out.cell = e.cell;
        out.o = occupied.get(e.cell!) ?? 0;
        occupied.set(e.cell!, out.o + 1);
      }
      return out;
    });
  }
  w.visuals.set(m.visual, v as MapVisual);
}
