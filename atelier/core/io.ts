// Reading and writing a world folder. The model is the parsed JSON itself: nothing is added or dropped, so
// load -> save is the identity on content, and the output format is stable (clean git diffs).
import fs from "node:fs";
import path from "node:path";
import { FILES, FileKey, MapJson, MapVisualJson, type MapData, type MapVisual, type Parsed } from "./schemas";

export type Files = { [K in FileKey]: Parsed<K> };

export interface World {
  /** Folder name = world id on disk. */
  dir: string;
  files: Files;
  /** maps/<id>.json by map id */
  maps: Map<number, MapData>;
  /** Content/Maps/<visual>.json by visual id (only those present on disk) */
  visuals: Map<number, MapVisual>;
}

export interface LoadIssue {
  file: string;
  message: string;
}

/** Existence probe on the world's Content/ layer ("Picto/Items/1.png"); a seam so tests need no disk. */
export type ContentProbe = (rel: string) => boolean;

export function diskProbe(dir: string): ContentProbe {
  return (rel) => fs.existsSync(path.join(dir, "Content", rel));
}

/** Canonical JSON: keys keep their order (data files are ordered on purpose), compact like the generators. */
export function stableStringify(value: unknown): string {
  return JSON.stringify(value);
}

type Reader = (rel: string) => string | undefined;

const diskReader = (dir: string): Reader => (rel) => {
  const f = path.join(dir, rel);
  return fs.existsSync(f) ? fs.readFileSync(f, "utf-8") : undefined;
};

const fmt = (e: { issues: { path: PropertyKey[]; message: string }[] }) =>
  e.issues.slice(0, 3).map((i) => `${i.path.map(String).join(".")}: ${i.message}`).join("; ");

function parseWorld(dir: string, read: Reader): { world: World | null; issues: LoadIssue[] } {
  const issues: LoadIssue[] = [];
  const files: Record<string, unknown> = {};
  const json = (rel: string): { ok: true; raw: unknown } | { ok: false; msg: string } | undefined => {
    const text = read(rel);
    if (text === undefined) return undefined;
    try { return { ok: true, raw: JSON.parse(text) }; } catch (e) { return { ok: false, msg: `JSON illisible (${(e as Error).message})` }; }
  };
  for (const [key, def] of Object.entries(FILES)) {
    const r = json(def.path);
    if (!r) { if (!def.optional) issues.push({ file: def.path, message: "fichier absent" }); continue; }
    if (!r.ok) { issues.push({ file: def.path, message: r.msg }); continue; }
    // the schema only validates: the raw JSON is kept so key order and unknown fields survive a save
    const parsed = def.schema.safeParse(r.raw);
    if (parsed.success) files[key] = r.raw;
    else issues.push({ file: def.path, message: fmt(parsed.error) });
  }
  if (issues.length) return { world: null, issues };

  const f = files as unknown as Files;
  const maps = new Map<number, MapData>();
  const visuals = new Map<number, MapVisual>();
  for (const mid of f.world.maps) {
    const rel = `maps/${mid}.json`;
    const r = json(rel);
    if (!r) { issues.push({ file: rel, message: "fichier absent" }); continue; }
    if (!r.ok) { issues.push({ file: rel, message: r.msg }); continue; }
    const p = MapJson.safeParse(r.raw);
    if (!p.success) { issues.push({ file: rel, message: fmt(p.error) }); continue; }
    maps.set(mid, r.raw as MapData);
    const vrel = `Content/Maps/${p.data.visual}.json`;
    const v = json(vrel);
    if (!v) continue;
    if (!v.ok) { issues.push({ file: vrel, message: v.msg }); continue; }
    if (MapVisualJson.safeParse(v.raw).success) visuals.set(p.data.visual, v.raw as MapVisual);
    else issues.push({ file: vrel, message: "visuel invalide" });
  }
  if (issues.length) return { world: null, issues };
  return { world: { dir, files: f, maps, visuals }, issues };
}

export function loadWorld(dir: string): { world: World | null; issues: LoadIssue[] } {
  return parseWorld(dir, diskReader(dir));
}

/** Rebuilds a world from `serializeWorld` output (undo / redo). */
export function loadFromTexts(dir: string, state: Map<string, string>): World {
  const { world, issues } = parseWorld(dir, (rel) => state.get(rel));
  if (!world) throw new Error(`état illisible : ${issues.map((i) => i.file).join(", ")}`);
  return world;
}

/** Every (relative path -> JSON text) a world is made of. */
export function serializeWorld(w: World): Map<string, string> {
  const out = new Map<string, string>();
  for (const [key, def] of Object.entries(FILES)) {
    const data = (w.files as Record<string, unknown>)[key];
    if (data !== undefined) out.set(def.path, stableStringify(data));
  }
  for (const [mid, m] of w.maps) out.set(`maps/${mid}.json`, stableStringify(m));
  for (const [vid, v] of w.visuals) out.set(`Content/Maps/${vid}.json`, stableStringify(v));
  return out;
}

/**
 * Atomic save: every file is first written next to its target as `.tmp`, then renamed over it. A failure
 * before the renames leaves the world untouched; the previous contents of replaced files go to `.bak`.
 */
export function saveWorld(w: World, hooks: { beforeRename?: () => void } = {}): string[] {
  const entries = serializeWorld(w);
  const written: string[] = [];
  const staged: [string, string][] = [];
  try {
    for (const [rel, text] of entries) {
      const target = path.join(w.dir, rel);
      if (fs.existsSync(target) && fs.readFileSync(target, "utf-8") === text) continue;
      fs.mkdirSync(path.dirname(target), { recursive: true });
      fs.writeFileSync(target + ".tmp", text, "utf-8");
      staged.push([target, rel]);
    }
    hooks.beforeRename?.();
  } catch (e) {
    for (const [target] of staged) fs.rmSync(target + ".tmp", { force: true });
    throw e;
  }
  for (const [target, rel] of staged) {
    if (fs.existsSync(target)) fs.copyFileSync(target, target + ".bak");
    fs.renameSync(target + ".tmp", target);
    written.push(rel);
  }
  return written;
}
