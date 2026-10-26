// Undo / redo of a world being edited: a stack of serialized states (path -> JSON text). Cheap because
// worlds are small JSON; each `commit` is one user-visible step with a label for the journal.
import { loadFromTexts, serializeWorld, type World } from "./io";

interface Step { label: string; state: Map<string, string> }

/** Steps kept for undo: the oldest are forgotten beyond this. */
export const MAX_STEPS = 200;

export class History {
  private past: Step[] = [];
  private future: Step[] = [];
  private current: Step;

  constructor(initial: World) {
    this.current = { label: "ouverture", state: serializeWorld(initial) };
  }

  /** Records the world as it is now as a new step. Returns false when nothing changed. */
  commit(w: World, label: string): boolean {
    const state = serializeWorld(w);
    if (sameState(state, this.current.state)) return false;
    // a file that did not change keeps the very same string as the previous step: steps then cost only what changed
    for (const [k, v] of state) { const before = this.current.state.get(k); if (before === v) state.set(k, before); }
    this.past.push(this.current);
    if (this.past.length > MAX_STEPS) this.past.shift();
    this.current = { label, state };
    this.future = [];
    return true;
  }

  get canUndo(): boolean { return this.past.length > 0; }
  get canRedo(): boolean { return this.future.length > 0; }
  /** Labels, oldest first, ending with the current step. */
  get journal(): string[] { return [...this.past.map((s) => s.label), this.current.label]; }

  undo(dir: string): World | null {
    const prev = this.past.pop();
    if (!prev) return null;
    this.future.push(this.current);
    this.current = prev;
    return loadFromTexts(dir, prev.state);
  }

  redo(dir: string): World | null {
    const next = this.future.pop();
    if (!next) return null;
    this.past.push(this.current);
    this.current = next;
    return loadFromTexts(dir, next.state);
  }
}

function sameState(a: Map<string, string>, b: Map<string, string>): boolean {
  if (a.size !== b.size) return false;
  for (const [k, v] of a) if (b.get(k) !== v) return false;
  return true;
}
