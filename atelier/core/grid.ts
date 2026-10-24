// Map grid: 14 columns x 40 rows = 560 cells, id = row * 14 + col. Only the four diagonal moves are used
// for connectivity (the strictest: if a cell is reachable that way it is reachable with any movement).
export const COLS = 14;
export const ROWS = 40;
export const CELLS = COLS * ROWS;

export const validCell = (c: number): boolean => Number.isInteger(c) && c >= 0 && c < CELLS;

export function neighbors(c: number): number[] {
  const col = c % COLS;
  const row = Math.floor(c / COLS);
  const odd = row % 2;
  const out: number[] = [];
  for (const dr of [-1, 1]) {
    for (const dc of odd ? [0, 1] : [-1, 0]) {
      const cc = col + dc;
      const rr = row + dr;
      if (cc >= 0 && cc < COLS && rr >= 0 && rr < ROWS) out.push(rr * COLS + cc);
    }
  }
  return out;
}

/** Cells reachable from the first free cell (same convention as the Python validator). */
export function reachableFromFirstFree(blocked: Set<number>): Set<number> {
  let start = -1;
  for (let c = 0; c < CELLS; c++) if (!blocked.has(c)) { start = c; break; }
  const seen = new Set<number>();
  if (start < 0) return seen;
  seen.add(start);
  const queue = [start];
  while (queue.length) {
    const c = queue.shift()!;
    for (const n of neighbors(c)) if (!blocked.has(n) && !seen.has(n)) { seen.add(n); queue.push(n); }
  }
  return seen;
}
