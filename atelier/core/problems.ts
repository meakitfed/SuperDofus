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

/** What a world built on Dofus (world.json "base": "dofus", e.g. L'Ascension) may use without holding it:
 *  the global spells (game/data), the Dofus monsters it copies with their ids, the Dofus images (game/content). */
export interface BaseContent {
  spellIds: Set<number>;
  monsterIds: Set<number>;
  probe: ContentProbe;
}

export interface Options {
  /** The Dofus content the world builds on (see BaseContent). Absent: the world holds everything it uses. */
  base?: BaseContent;
  /** Id ranges the world is allowed to use, by kind ("item", "spell", ...). Absent: not checked. */
  ranges?: Partial<Record<Kind, [number, number]>>;
  /** Ids already taken elsewhere (other worlds, global data), by kind. Absent: not checked. */
  reserved?: Partial<Record<Kind, Set<number>>>;
  /** Files of a Content/ sub-folder ("Picto/Items"): lets the rules find images nothing uses. Absent: not checked. */
  list?: (dir: string) => string[];
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
