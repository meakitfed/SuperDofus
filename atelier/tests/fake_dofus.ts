// A tiny stand-in for the client's text table (I18n/fr.bin) so tests never need the real Dofus files.
import fs from "node:fs";
import path from "node:path";

export function writeFakeI18n(file: string, texts: Record<number, string>): void {
  const strings = Object.entries(texts).map(([id, t]) => [Number(id), Buffer.from(t, "utf-8")] as const);
  const header = 1 + 4;
  const tableSize = strings.length * 8;
  let off = header + tableSize;
  const table = Buffer.alloc(tableSize);
  const bodies: Buffer[] = [];
  strings.forEach(([id, b], i) => {
    table.writeInt32LE(id, i * 8);
    table.writeInt32LE(off, i * 8 + 4);
    const body = Buffer.concat([Buffer.from([b.length]), b]);
    bodies.push(body);
    off += body.length;
  });
  const head = Buffer.alloc(header);
  head.writeInt32LE(strings.length, 1);
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, Buffer.concat([head, table, ...bodies]));
}

export const fakeGrade = (level: number) => ({
  level, hp: 90 + level, ap: 5, mp: 2, xp: 2000, look: "{4907|||130}", portrait: 1,
  stats: { strength: 64, intelligence: 64, chance: 64, agility: 64, wisdom: 48, ap_dodge: 0, mp_dodge: 0 },
  res: { earth: 6, fire: 6, water: -9, air: -9, neutral: 1 }, spells: [1036070], drops: [{ item: 362, pct: 55 }], kamas: [32, 70],
  aggro: { zone: 3, level_diff: 50, immunity: "PO=9910", delay: 10000 },
});
