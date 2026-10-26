// The Dofus content already on this machine (game/content/Content, never committed): browse its icons and map
// tiles, and copy chosen ones into a world as ordinary imported images. Nothing is shared by reference: a world
// that took an image owns its copy, so it keeps working without the Dofus files.
import fs from "node:fs";
import path from "node:path";
import sharp from "sharp";
import { AtelierError } from "./errors";
import type { Category, NamedFile } from "./assets";

/** "bone" = the animated skeletons (a folder per id); the others are plain image folders. */
export type LibraryCategory = Category | "bone";
export const isLibraryCategory = (c: string): c is LibraryCategory => c === "bone" || c in DIRS;
const DIRS: Record<LibraryCategory, string> = { item: "Picto/Items", spell: "Picto/Spells", monster: "Picto/Monsters", tile: "Maps/Gfx", bone: "Characters/Bones" };
const EXT = /\.(webp|png)$/i;
export const PAGE = 60;
sharp.cache(false); // no open file handle kept on the Dofus files (Windows would refuse to delete them)

export interface LibraryPage { available: boolean; total: number; ids: number[] }

const dirOf = (root: string, cat: LibraryCategory) => path.join(root, DIRS[cat]);
const cache = new Map<string, number[]>();

function allIds(root: string, cat: LibraryCategory): number[] {
  const dir = dirOf(root, cat);
  const hit = cache.get(dir);
  if (hit) return hit;
  const ids = (cat === "bone"
    ? fs.readdirSync(dir, { withFileTypes: true }).filter((e) => e.isDirectory() && /^\d{1,12}$/.test(e.name)).map((e) => Number(e.name))
    : fs.readdirSync(dir).filter((n) => EXT.test(n)).map((n) => Number(n.replace(EXT, ""))).filter((n) => Number.isInteger(n) && n >= 0)
  ).sort((a, b) => a - b);
  cache.set(dir, ids);
  return ids;
}

/** One page of the ids of a category, optionally those whose number contains `query`. */
export function listLibrary(root: string, cat: LibraryCategory, query = "", offset = 0, limit = PAGE): LibraryPage {
  const q = query.trim();
  if (q && !/^\d{1,12}$/.test(q)) throw new AtelierError(400, "recherche : un numéro d'image (chiffres seulement)");
  if (!fs.existsSync(dirOf(root, cat))) return { available: false, total: 0, ids: [] };
  const all = allIds(root, cat);
  const hits = q ? all.filter((n) => String(n).includes(q)) : all;
  return { available: true, total: hits.length, ids: hits.slice(Math.max(0, offset), Math.max(0, offset) + Math.min(limit, 200)) };
}

function fileOf(root: string, cat: LibraryCategory, id: number): string {
  if (!Number.isInteger(id) || id < 0) throw new AtelierError(400, "numéro d'image invalide");
  for (const ext of [".webp", ".png"]) {
    const p = cat === "bone" ? path.join(dirOf(root, cat), String(id), `0${ext}`) : path.join(dirOf(root, cat), `${id}${ext}`);
    if (fs.existsSync(p)) return p;
  }
  throw new AtelierError(404, `image ${id} absente de la bibliothèque`);
}

/** A PNG of the image (resized down to `max` px for a thumbnail, whole when `max` is 0). */
export async function libraryPng(root: string, cat: LibraryCategory, id: number, max = 0): Promise<Buffer> {
  const img = sharp(fileOf(root, cat, id));
  return (max > 0 ? img.resize(max, max, { fit: "inside", withoutEnlargement: true }) : img).png().toBuffer();
}

export async function libraryFiles(root: string, cat: Category, ids: number[]): Promise<NamedFile[]> {
  if (!Array.isArray(ids) || ids.length < 1 || ids.length > 100) throw new AtelierError(400, "choisis de 1 à 100 images");
  const out: NamedFile[] = [];
  for (const id of ids) out.push({ name: `dofus-${id}.png`, data: await libraryPng(root, cat, Number(id)) });
  return out;
}

/** Copies a skeleton of the Dofus content into a world (its folder, whole). */
export function copyLibraryBone(root: string, worldDir: string, id: number): void {
  if (!Number.isInteger(id) || id < 0 || !fs.existsSync(path.join(dirOf(root, "bone"), String(id)))) throw new AtelierError(404, `squelette ${id} absent de la bibliothèque`);
  const dest = path.join(worldDir, "Content", "Characters", "Bones", String(id));
  if (fs.existsSync(dest)) throw new AtelierError(409, `squelette ${id} déjà présent`);
  fs.cpSync(path.join(dirOf(root, "bone"), String(id)), dest, { recursive: true });
}
