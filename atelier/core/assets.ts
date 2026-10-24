// The image library of a world: icons and map tiles under Content/. Importing re-encodes every image to a clean
// PNG (no metadata, bounded size), so what lands in the world is never the raw upload.
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { unzipSync } from "fflate";
import sharp, { type Metadata } from "sharp";
import { CATEGORIES, usages, type Category } from "./asset_usage";
import type { World } from "./io";

export { CATEGORIES, isCategory, usages, type Category } from "./asset_usage";

export const LIMITS = { file: 8 * 1024 * 1024, zipEntries: 300, zipTotal: 120 * 1024 * 1024, tileSide: 4096 };
const META = "atelier_assets.json";

export interface AssetInfo {
  id: number;
  name: string;
  width: number;
  height: number;
  bytes: number;
  usedBy: { kind: string; id: string | number }[];
}
export interface ImportResult {
  name: string;
  status: "imported" | "duplicate" | "rejected";
  id?: number;
  reason?: string;
}

interface Meta { assets: Record<string, { name: string; sha: string }> }

function readMeta(dir: string): Meta {
  try { return JSON.parse(fs.readFileSync(path.join(dir, META), "utf-8")); } catch { return { assets: {} }; }
}
function writeMeta(dir: string, m: Meta): void {
  const f = path.join(dir, META);
  fs.writeFileSync(f + ".tmp", JSON.stringify(m, null, 1), "utf-8");
  fs.renameSync(f + ".tmp", f);
}

const folder = (dir: string, cat: Category) => path.join(dir, "Content", CATEGORIES[cat].dir);

function idsOnDisk(dir: string, cat: Category): number[] {
  const d = folder(dir, cat);
  if (!fs.existsSync(d)) return [];
  return fs.readdirSync(d).filter((f) => /^\d+\.png$/.test(f)).map((f) => Number(f.slice(0, -4)));
}

export async function listAssets(dir: string, w: World, cat: Category): Promise<AssetInfo[]> {
  const meta = readMeta(dir).assets;
  const used = usages(w, cat);
  const out: AssetInfo[] = [];
  for (const id of idsOnDisk(dir, cat).sort((a, b) => a - b)) {
    const file = path.join(folder(dir, cat), `${id}.png`);
    let width = 0, height = 0;
    try { ({ width = 0, height = 0 } = await sharp(file).metadata()); } catch { /* unreadable: shown with 0x0 */ }
    out.push({ id, name: meta[`${cat}/${id}`]?.name ?? "", width, height, bytes: fs.statSync(file).size, usedBy: used.get(id) ?? [] });
  }
  return out;
}

const cleanName = (n: string) => path.basename(n).replace(/\.[^.]+$/, "").replace(/[^\p{L}\p{N} _.-]/gu, "").slice(0, 60) || "image";

/** Re-encodes one upload; returns the PNG bytes and its size, or throws a French reason. */
export async function normalize(cat: Category, data: Buffer): Promise<{ png: Buffer; width: number; height: number }> {
  if (data.length > LIMITS.file) throw new Error("fichier trop gros (8 Mo maximum)");
  let meta: Metadata;
  try { meta = await sharp(data, { limitInputPixels: LIMITS.tileSide * LIMITS.tileSide }).metadata(); } catch { throw new Error("ce n'est pas une image lisible (PNG, JPEG ou WebP)"); }
  if (!["png", "jpeg", "webp"].includes(meta.format ?? "")) throw new Error(`format ${meta.format} non pris en charge (PNG, JPEG ou WebP)`);
  const { width = 0, height = 0 } = meta;
  if (width < 1 || height < 1) throw new Error("image vide");
  const size = CATEGORIES[cat].size;
  let img = sharp(data, { limitInputPixels: LIMITS.tileSide * LIMITS.tileSide }).rotate(); // honour EXIF orientation, then drop it
  if (size) img = img.resize(size, size, { fit: "contain", background: { r: 0, g: 0, b: 0, alpha: 0 } }).ensureAlpha();
  else if (width > LIMITS.tileSide || height > LIMITS.tileSide) throw new Error(`image trop grande (${LIMITS.tileSide} px maximum par côté)`);
  const png = await img.png().toBuffer();
  const out = await sharp(png).metadata();
  return { png, width: out.width ?? width, height: out.height ?? height };
}

export interface NamedFile { name: string; data: Buffer }

/** Expands a ZIP into images, with hard limits against zip bombs; skips folders, hidden and non-image entries. */
export function unzipImages(zip: Buffer): { files: NamedFile[]; skipped: ImportResult[] } {
  const skipped: ImportResult[] = [];
  let total = 0, count = 0;
  let entries: Record<string, Uint8Array>;
  try {
    entries = unzipSync(new Uint8Array(zip), {
      filter: (f) => {
        if (f.name.endsWith("/")) return false;
        const base = path.basename(f.name);
        if (base.startsWith(".") || f.name.startsWith("__MACOSX/") || !/\.(png|jpe?g|webp)$/i.test(base)) {
          skipped.push({ name: f.name, status: "rejected", reason: "ignoré (pas une image PNG, JPEG ou WebP)" });
          return false;
        }
        if (++count > LIMITS.zipEntries) throw new Error(`l'archive contient plus de ${LIMITS.zipEntries} images`);
        total += f.originalSize;
        if (f.originalSize > LIMITS.file) { skipped.push({ name: f.name, status: "rejected", reason: "fichier trop gros (8 Mo maximum)" }); return false; }
        if (total > LIMITS.zipTotal) throw new Error("l'archive est trop volumineuse une fois décompressée");
        return true;
      },
    });
  } catch (e) {
    throw new Error(`archive ZIP invalide ou trop volumineuse (${(e as Error).message})`);
  }
  return { files: Object.entries(entries).map(([name, d]) => ({ name, data: Buffer.from(d) })), skipped };
}

export async function importImages(dir: string, cat: Category, files: NamedFile[], range: [number, number]): Promise<ImportResult[]> {
  const meta = readMeta(dir);
  const results: ImportResult[] = [];
  const target = folder(dir, cat);
  const taken = new Set([...idsOnDisk(dir, cat), ...Object.keys(meta.assets).filter((k) => k.startsWith(cat + "/")).map((k) => Number(k.split("/")[1]))]);
  let next = Math.max(range[0] - 1, ...[...taken].filter((i) => i >= range[0] && i <= range[1])) + 1;
  fs.mkdirSync(target, { recursive: true });
  for (const f of files) {
    const name = cleanName(f.name);
    try {
      const { png } = await normalize(cat, f.data);
      const sha = crypto.createHash("sha256").update(png).digest("hex");
      const dup = Object.entries(meta.assets).find(([k, v]) => k.startsWith(cat + "/") && v.sha === sha);
      if (dup) { results.push({ name, status: "duplicate", id: Number(dup[0].split("/")[1]) }); continue; }
      if (next > range[1]) throw new Error("plus d'identifiant d'image libre dans la tranche du monde");
      const id = next++;
      const file = path.join(target, `${id}.png`);
      fs.writeFileSync(file + ".tmp", png);
      fs.renameSync(file + ".tmp", file);
      meta.assets[`${cat}/${id}`] = { name, sha };
      results.push({ name, status: "imported", id });
    } catch (e) {
      results.push({ name, status: "rejected", reason: (e as Error).message });
    }
  }
  writeMeta(dir, meta);
  return results;
}

/** Deletes an unused asset; refuses when something still points at it. */
export function deleteAsset(dir: string, w: World, cat: Category, id: number): void {
  const by = usages(w, cat).get(id) ?? [];
  if (by.length) throw new Error(`image utilisée par ${by.length} élément(s) : ${by.slice(0, 3).map((u) => `${u.kind} ${u.id}`).join(", ")}`);
  const file = path.join(folder(dir, cat), `${id}.png`);
  if (!fs.existsSync(file)) throw new Error("image introuvable");
  fs.rmSync(file);
  const meta = readMeta(dir);
  delete meta.assets[`${cat}/${id}`];
  writeMeta(dir, meta);
}

export function assetFile(dir: string, cat: Category, id: number): string | null {
  const f = path.join(folder(dir, cat), `${id}.png`);
  return fs.existsSync(f) ? f : null;
}
