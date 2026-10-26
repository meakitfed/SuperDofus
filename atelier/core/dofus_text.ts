// Dofus texts: game/content/Content/I18n/fr.bin (a count, a table of (id, offset) pairs, then length-prefixed UTF-8).
import fs from "node:fs";

export type TextLookup = (id: number) => string;
const cache = new Map<string, TextLookup>();

export function readI18n(file: string): TextLookup {
  const hit = cache.get(file);
  if (hit) return hit;
  const b = fs.readFileSync(file);
  const n = b[0];
  const count = b.readInt32LE(1 + n);
  const table = 1 + n + 4;
  const index = new Map<number, number>();
  for (let i = 0; i < count; i++) index.set(b.readInt32LE(table + i * 8), b.readInt32LE(table + i * 8 + 4));
  const lookup: TextLookup = (id) => {
    let off = index.get(id);
    if (off === undefined) return "";
    let len = 0, shift = 0, c: number;
    do { c = b[off++]; len |= (c & 0x7f) << shift; shift += 7; } while (c >= 0x80);
    return b.toString("utf-8", off, off + len);
  };
  cache.set(file, lookup);
  return lookup;
}
