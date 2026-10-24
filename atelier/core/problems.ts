// A validation result: a stable code (tests and the UI key on it), a French message, and where it is.
import type { ContentProbe, World } from "./io";
import type { Kind } from "./ranges";

export type Severity = "error" | "warning";

export interface Problem {
  code: string;
  severity: Severity;
  message: string;
  /** Where to go to fix it: kind of element and its id (the UI turns this into a link). */
  ref?: { kind: string; id: string | number };
}

export interface Options {
  /** Id ranges the world is allowed to use, by kind ("item", "spell", ...). Absent: not checked. */
  ranges?: Partial<Record<Kind, [number, number]>>;
  /** Ids already taken elsewhere (other worlds, global data), by kind. Absent: not checked. */
  reserved?: Partial<Record<Kind, Set<number>>>;
}

export interface Ctx {
  w: World;
  probe: ContentProbe;
  opts: Options;
  report: (code: string, message: string, ref?: Problem["ref"]) => void;
  // lookups shared by the rules
  mapIds: Set<number>;
  spellIds: Set<number>;
  itemIds: Set<number>;
  setIds: Set<number>;
  mobIds: Set<number>;
  summonIds: Set<number>;
  npcIds: Set<number>;
  questIds: Set<number>;
}

export interface Rule {
  code: string;
  severity: Severity;
  /** One line: what is checked (shown in docs and in the coverage guard's failure). */
  doc: string;
  run: (c: Ctx) => void;
}
