const COLS = 14;
const ROWS = 40;

/** The 14 x 40 grid as a cell chooser: walls are dark, `taken` cells (other NPCs, doors...) are marked, the chosen one is highlighted. */
export function CellPicker({ value, onPick, blocked = [], taken = [], label }: { value: number; onPick: (cell: number) => void; blocked?: number[]; taken?: number[]; label: string }) {
  const wall = new Set(blocked);
  const busy = new Set(taken);
  return (
    <div className="mgrid" role="grid" aria-label={label}>
      {Array.from({ length: ROWS }, (_, r) => (
        <div className={"mrow" + (r % 2 ? " odd" : "")} key={r} role="row">
          {Array.from({ length: COLS }, (_, c) => {
            const cell = r * COLS + c;
            const cls = ["mcell", wall.has(cell) && "wall", busy.has(cell) && "door", cell === value && "start"].filter(Boolean).join(" ");
            return <button type="button" key={c} role="gridcell" className={cls} aria-label={`Cellule ${cell}`} aria-selected={cell === value} title={String(cell)} tabIndex={-1} onClick={() => onPick(cell)} />;
          })}
        </div>
      ))}
    </div>
  );
}
