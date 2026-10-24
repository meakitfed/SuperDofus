// The worlds folder as the atelier sees it: list, create, rename, delete, validate, undo / redo.
// Only worlds in the registry are "managed" (checked and editable); the others (dofus, incarnam, test) are
// listed read-only so nothing hand-made is ever touched by mistake.
import fs from "node:fs";
import path from "node:path";
import { assetFile, deleteAsset, importImages, isCategory, listAssets, unzipImages, type AssetInfo, type Category, type ImportResult, type NamedFile } from "./assets";
import { History } from "./history";
import { diskList, diskProbe, loadWorld, saveWorld, type World } from "./io";
import type { Options, Problem } from "./problems";
import { collectIds, defaultRegistry, KINDS, nextSlot, rangesForSlot, type Kind, type RangeMap, type Registry } from "./ranges";
import { createSkeleton } from "./skeleton";
import type { MapVisual } from "./schemas";
import { validate } from "./validate";

export interface WorldSummary {
  id: string;
  name: string;
  managed: boolean;
  /** true for worlds the atelier created (the only ones it can delete) */
  created: boolean;
  maps: number;
  breeds: number;
  errors?: number;
  warnings?: number;
}

export interface WorldDetail {
  summary: WorldSummary;
  problems: Problem[];
  counts: Record<string, number>;
  ranges: RangeMap;
  journal: string[];
  canUndo: boolean;
  canRedo: boolean;
}

export class AtelierError extends Error {
  constructor(public status: number, message: string) { super(message); }
}

interface Session { world: World; history: History }

export class WorldStore {
  private sessions = new Map<string, Session>();

  constructor(
    readonly worldsDir: string,
    readonly registryPath: string,
    readonly templatesDir: string,
  ) {}

  // ---- registry ----
  registry(): Registry {
    const reg = defaultRegistry();
    if (fs.existsSync(this.registryPath)) Object.assign(reg, JSON.parse(fs.readFileSync(this.registryPath, "utf-8")).worlds ?? {});
    // ranges of a kind added after the world was created come from its slot
    for (const e of Object.values(reg)) if (e.slot > 0) e.ranges = { ...rangesForSlot(e.slot), ...e.ranges };
    return reg;
  }

  private saveRegistry(reg: Registry): void {
    const user: Registry = {};
    for (const [id, e] of Object.entries(reg)) if (e.created) user[id] = e;
    const tmp = this.registryPath + ".tmp";
    fs.writeFileSync(tmp, JSON.stringify({ worlds: user }, null, 2) + "\n", "utf-8");
    fs.renameSync(tmp, this.registryPath);
  }

  // ---- reading ----
  list(): WorldSummary[] {
    const reg = this.registry();
    const out: WorldSummary[] = [];
    for (const e of fs.readdirSync(this.worldsDir, { withFileTypes: true })) {
      const file = path.join(this.worldsDir, e.name, "world.json");
      if (!e.isDirectory() || !fs.existsSync(file)) continue;
      try {
        const j = JSON.parse(fs.readFileSync(file, "utf-8"));
        out.push({
          id: e.name, name: String(j.name ?? e.name), managed: e.name in reg, created: !!reg[e.name]?.created,
          maps: Array.isArray(j.maps) ? j.maps.length : 0, breeds: Array.isArray(j.breeds) ? j.breeds.length : 0,
        });
      } catch { /* unreadable world.json: not listed */ }
    }
    return out.sort((a, b) => a.id.localeCompare(b.id));
  }

  private managed(id: string): { dir: string; entry: Registry[string] } {
    const entry = this.registry()[id];
    if (!entry) throw new AtelierError(404, `monde « ${id} » inconnu ou non géré par l'atelier`);
    return { dir: path.join(this.worldsDir, id), entry };
  }

  private session(id: string): Session {
    let s = this.sessions.get(id);
    if (!s) {
      const { dir } = this.managed(id);
      const { world, issues } = loadWorld(dir);
      if (!world) throw new AtelierError(422, `monde illisible : ${issues.map((i) => `${i.file} (${i.message})`).join("; ")}`);
      s = { world, history: new History(world) };
      this.sessions.set(id, s);
    }
    return s;
  }

  /** Ids already taken by the other managed worlds, by kind. */
  private reservedFor(id: string): Options["reserved"] {
    const reserved: Partial<Record<Kind, Set<number>>> = {};
    for (const other of Object.keys(this.registry())) {
      if (other === id || !fs.existsSync(path.join(this.worldsDir, other, "world.json"))) continue;
      const { world } = loadWorld(path.join(this.worldsDir, other));
      if (!world) continue;
      const ids = collectIds(world);
      for (const k of KINDS) {
        const set = (reserved[k] ??= new Set());
        ids[k].forEach((i) => set.add(i));
      }
    }
    return reserved;
  }

  check(id: string): Problem[] {
    const { dir, entry } = this.managed(id);
    const { world } = this.session(id);
    return validate(world, diskProbe(dir), { ranges: entry.ranges, reserved: this.reservedFor(id), list: diskList(dir) });
  }

  detail(id: string): WorldDetail {
    const { entry } = this.managed(id);
    const s = this.session(id);
    const problems = this.check(id);
    const errors = problems.filter((p) => p.severity === "error").length;
    const f = s.world.files;
    return {
      summary: {
        id, name: f.world.name, managed: true, created: entry.created, maps: s.world.maps.size, breeds: f.world.breeds.length,
        errors, warnings: problems.length - errors,
      },
      problems,
      counts: {
        maps: s.world.maps.size,
        items: f.items.items.length,
        spells: f.spells.spells.length,
        monsters: Object.keys(f.monsters.monsters).length + Object.keys(f.monsters.bosses).length,
        npcs: collectIds(s.world).npc.length,
        quests: Object.keys(f.quests.quests).length,
        dialogs: Object.keys(f.dialogs.dialogs).length,
      },
      ranges: entry.ranges,
      journal: s.history.journal,
      canUndo: s.history.canUndo,
      canRedo: s.history.canRedo,
    };
  }

  // ---- writing ----
  create(id: string, name: string): WorldSummary {
    const dir = path.join(this.worldsDir, id);
    if (!/^[a-z][a-z0-9_]{1,31}$/.test(id)) throw new AtelierError(400, "identifiant invalide : minuscules, chiffres et _ (2 à 32 caractères, commence par une lettre)");
    if (fs.existsSync(dir)) throw new AtelierError(409, `le dossier « ${id} » existe déjà`);
    if (!name.trim()) throw new AtelierError(400, "le nom est vide");
    const reg = this.registry();
    const slot = nextSlot(reg);
    const template = JSON.parse(fs.readFileSync(path.join(this.templatesDir, "map_visual_empty.json"), "utf-8")) as MapVisual;
    const { world, ranges } = createSkeleton(id, name.trim(), slot, template);
    world.dir = dir;
    try {
      saveWorld(world);
      reg[id] = { slot, ranges, created: true };
      this.saveRegistry(reg);
    } catch (e) {
      fs.rmSync(dir, { recursive: true, force: true });
      throw e;
    }
    return { id, name: name.trim(), managed: true, created: true, maps: 1, breeds: 0 };
  }

  /** Applies an edit, saves it, and records it as one undo step. */
  edit(id: string, label: string, fn: (w: World) => void): void {
    const s = this.session(id);
    const before = structuredClone(s.world);
    try {
      fn(s.world);
      saveWorld(s.world);
      s.history.commit(s.world, label);
    } catch (e) {
      s.world = before;
      throw e;
    }
  }

  rename(id: string, name: string): void {
    if (!name.trim()) throw new AtelierError(400, "le nom est vide");
    this.edit(id, `renommer en « ${name.trim()} »`, (w) => {
      const old = w.files.world.name;
      w.files.world.name = name.trim();
      // keep the i18n entry that holds the name in step with it, when there is one
      for (const [k, v] of Object.entries(w.files.texts)) if (v === old) w.files.texts[k] = name.trim();
    });
  }

  // ---- image library (not part of undo / redo: files are written at once) ----
  private category(c: string): Category {
    if (!isCategory(c)) throw new AtelierError(400, `catégorie d'image inconnue : ${c}`);
    return c;
  }

  async assets(id: string, cat: string): Promise<AssetInfo[]> {
    const { dir } = this.managed(id);
    return listAssets(dir, this.session(id).world, this.category(cat));
  }

  async importAssets(id: string, cat: string, input: { files?: NamedFile[]; zip?: Buffer }): Promise<ImportResult[]> {
    const { dir, entry } = this.managed(id);
    const c = this.category(cat);
    let files = input.files ?? [];
    const results: ImportResult[] = [];
    if (input.zip) {
      try {
        const z = unzipImages(input.zip);
        files = [...files, ...z.files];
        results.push(...z.skipped);
      } catch (e) {
        throw new AtelierError(400, (e as Error).message);
      }
    }
    if (!files.length && !results.length) throw new AtelierError(400, "aucune image reçue");
    return [...(await importImages(dir, c, files, entry.ranges.asset)), ...results];
  }

  removeAsset(id: string, cat: string, assetId: number): void {
    const { dir } = this.managed(id);
    try { deleteAsset(dir, this.session(id).world, this.category(cat), assetId); } catch (e) {
      throw e instanceof AtelierError ? e : new AtelierError(409, (e as Error).message);
    }
  }

  assetPath(id: string, cat: string, assetId: number): string {
    const { dir } = this.managed(id);
    const f = assetFile(dir, this.category(cat), assetId);
    if (!f) throw new AtelierError(404, "image introuvable");
    return f;
  }

  /** Forgets the in-memory copy (and its undo history) and reads the folder again: after a hand edit or a git pull. */
  reload(id: string): void {
    this.managed(id);
    this.sessions.delete(id);
  }

  undo(id: string): boolean { return this.travel(id, "undo"); }
  redo(id: string): boolean { return this.travel(id, "redo"); }

  private travel(id: string, dir: "undo" | "redo"): boolean {
    const s = this.session(id);
    const w = dir === "undo" ? s.history.undo(s.world.dir) : s.history.redo(s.world.dir);
    if (!w) return false;
    saveWorld(w);
    s.world = w;
    return true;
  }

  remove(id: string, confirm: string): void {
    const { dir, entry } = this.managed(id);
    if (!entry.created) throw new AtelierError(403, "ce monde n'a pas été créé par l'atelier : suppression refusée");
    if (confirm !== id) throw new AtelierError(400, "confirmation incorrecte : retape l'identifiant du monde");
    fs.rmSync(dir, { recursive: true, force: true });
    const reg = this.registry();
    delete reg[id];
    this.saveRegistry(reg);
    this.sessions.delete(id);
  }
}
