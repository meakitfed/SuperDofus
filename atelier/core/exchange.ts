// World archives: a world folder as a ZIP (with a manifest of its id ranges) and back. The ranges are what lets an
// imported world be moved into a free slot of this atelier, exactly like a duplicate.
import fs from "node:fs";
import path from "node:path";
import { unzipSync, zipSync } from "fflate";
import { AtelierError } from "./errors";
import { KINDS, type RangeMap } from "./ranges";

export const MANIFEST = "atelier_world.json";
export const ARCHIVE_LIMITS = { entries: 20000, total: 400 * 1024 * 1024 };
const SKIP = /\.(bak|tmp)$/;

function collect(dir: string, rel: string, out: Record<string, Uint8Array>): void {
  for (const e of fs.readdirSync(path.join(dir, rel), { withFileTypes: true })) {
    if (SKIP.test(e.name) || e.name === MANIFEST) continue;
    const r = rel ? `${rel}/${e.name}` : e.name;
    if (e.isDirectory()) collect(dir, r, out);
    else out[r] = new Uint8Array(fs.readFileSync(path.join(dir, r)));
  }
}

export function exportWorld(dir: string, id: string, ranges: RangeMap): Buffer {
  const files: Record<string, Uint8Array> = {};
  collect(dir, "", files);
  files[MANIFEST] = new TextEncoder().encode(JSON.stringify({ format: 1, id, ranges }));
  return Buffer.from(zipSync(files, { level: 6 }));
}

const isRange = (r: unknown): r is [number, number] => Array.isArray(r) && r.length === 2 && r.every((n) => Number.isInteger(n) && n >= 0) && r[0] <= r[1];

/** Unpacks an archive made by exportWorld into the empty folder `into`; returns the ranges its manifest declares. */
export function extractWorld(zip: Buffer, into: string): RangeMap {
  let total = 0, count = 0;
  let entries: Record<string, Uint8Array>;
  try {
    entries = unzipSync(new Uint8Array(zip), {
      filter: (f) => {
        if (f.name.endsWith("/")) return false;
        if (++count > ARCHIVE_LIMITS.entries) throw new Error("trop de fichiers dans l'archive");
        total += f.originalSize;
        if (total > ARCHIVE_LIMITS.total) throw new Error("archive trop volumineuse une fois décompressée");
        return true;
      },
    });
  } catch (e) {
    throw new AtelierError(400, `archive ZIP invalide (${(e as Error).message})`);
  }
  const raw = entries[MANIFEST];
  if (!raw) throw new AtelierError(400, `ce n'est pas une archive de l'atelier (il manque ${MANIFEST})`);
  let manifest: { format?: number; ranges?: Record<string, unknown> };
  try { manifest = JSON.parse(new TextDecoder().decode(raw)); } catch { throw new AtelierError(400, "manifeste de l'archive illisible"); }
  const ranges = {} as RangeMap;
  for (const k of KINDS) {
    const r = manifest.ranges?.[k];
    if (!isRange(r)) throw new AtelierError(400, `manifeste : plage « ${k} » absente ou invalide`);
    ranges[k] = r;
  }
  if (!entries["world.json"]) throw new AtelierError(400, "l'archive ne contient pas world.json");
  const root = path.resolve(into);
  for (const [name, data] of Object.entries(entries)) {
    if (name === MANIFEST) continue;
    const target = path.resolve(root, name);
    if (target !== root && !target.startsWith(root + path.sep)) throw new AtelierError(400, `chemin refusé dans l'archive : ${name}`);
    fs.mkdirSync(path.dirname(target), { recursive: true });
    fs.writeFileSync(target, data);
  }
  return ranges;
}
