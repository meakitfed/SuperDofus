// World cloning: copy a world folder into a new one and move every id it owns into the new world's slot.
// Ids of a slot are all >= 1e9 and the slots' ranges never overlap each other nor the Dofus ids (< 4e8) nor ARGB
// colours (> 2^31), so a number, an object key or a 10-digit run inside a string that falls in a source range is an
// id of that world and nothing else: it is shifted by the same offset as its range. File names that are ids
// (Maps/<id>.json, Picto/.../<id>.png, Bones/<id>/) follow. The caller validates the result.
import fs from "node:fs";
import path from "node:path";
import { KINDS, type RangeMap } from "./ranges";

export function makeRemap(from: RangeMap, to: RangeMap): (n: number) => number {
  return (n) => {
    for (const k of KINDS) if (n >= from[k][0] && n <= from[k][1]) return n - from[k][0] + to[k][0];
    return n;
  };
}

function remapDeep(v: unknown, id: (n: number) => number): unknown {
  if (typeof v === "number") return Number.isInteger(v) ? id(v) : v;
  if (typeof v === "string") return remapString(v, id);
  if (Array.isArray(v)) return v.map((x) => remapDeep(x, id));
  if (v && typeof v === "object") return Object.fromEntries(Object.entries(v).map(([k, x]) => [remapString(k, id), remapDeep(x, id)]));
  return v;
}
const remapString = (s: string, id: (n: number) => number) => s.replace(/\d{10}/g, (m) => String(id(Number(m))));

const SKIP = /\.(bak|tmp)$/;

function copyRemapped(src: string, dst: string, id: (n: number) => number): void {
  fs.mkdirSync(dst, { recursive: true });
  for (const e of fs.readdirSync(src, { withFileTypes: true })) {
    if (SKIP.test(e.name)) continue;
    const from = path.join(src, e.name);
    const base = e.isDirectory() ? e.name : e.name.replace(/\.[^.]+$/, "");
    const ext = e.isDirectory() ? "" : e.name.slice(base.length);
    const renamed = /^\d{10}$/.test(base) ? String(id(Number(base))) + ext : e.name;
    const to = path.join(dst, renamed);
    if (e.isDirectory()) copyRemapped(from, to, id);
    else if (e.name.endsWith(".json")) fs.writeFileSync(to, JSON.stringify(remapDeep(JSON.parse(fs.readFileSync(from, "utf-8")), id)));
    else fs.copyFileSync(from, to);
  }
}

export function cloneWorldDir(srcDir: string, dstDir: string, from: RangeMap, to: RangeMap, newId: string, newName: string): void {
  copyRemapped(srcDir, dstDir, makeRemap(from, to));
  const file = path.join(dstDir, "world.json");
  const w = JSON.parse(fs.readFileSync(file, "utf-8"));
  w.id = newId;
  w.name = newName;
  fs.writeFileSync(file, JSON.stringify(w));
}
