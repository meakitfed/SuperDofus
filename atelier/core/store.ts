// The worlds folder as the atelier sees it: list, create, rename, delete, validate, undo / redo.
// Only worlds in the registry are "managed" (checked and editable); the others (dofus, incarnam, test) are
// listed read-only so nothing hand-made is ever touched by mistake.
import fs from "node:fs";
import sharp from "sharp";
import os from "node:os";
import path from "node:path";
import { CATEGORIES, assetFile, deleteAsset, importImages, isCategory, listAssets, unzipImages, type AssetInfo, type Category, type ImportResult, type NamedFile } from "./assets";
import { AtelierError } from "./errors";
import * as ed from "./editors";
import * as sp from "./editors_spells";
import { copyBone, listBones, type BoneLibrary } from "./bones";
import * as cl from "./editors_classes";
import * as mp from "./editors_maps";
import * as np from "./editors_npcs";
import * as qu from "./editors_quests";
import { copyGfx, loadDofusMap, searchDofusMaps } from "./library_maps";
import { searchDofusMonsters } from "./library_monsters";
import { searchDofusItems } from "./library_items";
import { copyLibraryBone, isLibraryCategory, libraryFiles, libraryPng, listLibrary, type LibraryCategory } from "./library";
import { exportWorld, extractWorld } from "./exchange";
import { cloneWorldDir } from "./clone";
import * as vi from "./editors_visual";
import { playableReport, type Check } from "./playable";
import { workflows, type Workflow } from "./workflows";
import { runGameCheck, type GameCheck } from "./gamecheck";
import * as mo from "./editors_monsters";
import { History } from "./history";
import { diskList, diskProbe, loadWorld, removeStale, saveWorld, type World } from "./io";
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

export { AtelierError };

interface Session { world: World; history: History }

export class WorldStore {
  private sessions = new Map<string, Session>();

  constructor(
    readonly worldsDir: string,
    readonly registryPath: string,
    readonly templatesDir: string,
  ) {
    this.contentRoot = path.join(path.dirname(worldsDir), "content", "Content");
    this.dataRoot = path.join(path.dirname(worldsDir), "data");
  }

  /** The game's generated data folder (game/data); tests point it elsewhere. */
  dataRoot: string;

  /** The Dofus content of this machine (game/content/Content); tests point it elsewhere. */
  contentRoot: string;

  // ---- Dofus library: browse, then copy into a world as ordinary imported images ----
  private libCategory(c: string): LibraryCategory {
    if (!isLibraryCategory(c)) throw new AtelierError(400, `catégorie d'image inconnue : ${c}`);
    return c;
  }
  library(cat: string, query: string, offset: number, limit: number) { return listLibrary(this.contentRoot, this.libCategory(cat), query, offset, limit); }
  libraryPng(cat: string, id: number, max: number) { return libraryPng(this.contentRoot, this.libCategory(cat), id, max); }
  /** Dofus items matching a name or number, as ready-to-edit templates (game/data/items.json). */
  libraryItems(query: string) { return searchDofusItems(path.join(this.dataRoot, "items.json"), query); }
  /** Dofus monsters matching a name or number as templates (stats and look; no spells or drops). */
  libraryMonsters(query: string) { return searchDofusMonsters(path.join(this.worldsDir, "dofus", "monsters.json"), path.join(this.contentRoot, "I18n", "fr.bin"), query); }
  /** Dofus maps by number or world coordinates, with a little of what each one holds. */
  libraryMaps(query: string) { return searchDofusMaps(path.join(this.worldsDir, "dofus"), this.contentRoot, query); }
  /** Copies a Dofus map (grid + decor + the tile images the decor needs) into a world as a new map. */
  importDofusMap(id: string, name: string, source: number): { id: number; dropped: number; missing: number } {
    const { dir, entry } = this.managed(id);
    const src = loadDofusMap(path.join(this.worldsDir, "dofus"), this.contentRoot, source);
    const missing = new Set(copyGfx(this.contentRoot, dir, src.gfx));
    let out = { id: 0, dropped: 0 };
    this.edit(id, `copier la map ${source} du jeu`, (w) => { out = mp.createMapFromDofus(w, entry.ranges, name, src.map, src.visual, missing); });
    return { ...out, missing: missing.size };
  }
  async importFromLibrary(id: string, cat: string, ids: number[]): Promise<ImportResult[]> {
    const c = this.category(cat);
    this.managed(id);
    return this.importAssets(id, c, { files: await libraryFiles(this.contentRoot, c, ids) });
  }

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

  /** Copies a world the atelier manages into a new one whose ids all move to a new slot. Checked before it is kept. */
  clone(id: string, newId: string, name: string): WorldSummary {
    const { dir, entry } = this.managed(id);
    if (entry.slot < 1) throw new AtelierError(400, "ce monde a ses propres numéros (comme La Vertèbre) : seuls les mondes créés par l'atelier se dupliquent");
    const srcName = this.session(id).world.files.world.name;
    return this.adopt(dir, entry.ranges, srcName, this.detail(id).problems, newId, name);
  }

  /** The world of an archive made by `exportWorld`, moved into a free slot like a duplicate. */
  importWorld(zip: Buffer, newId: string, name: string): WorldSummary {
    this.checkNewWorld(newId, name);
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "atelier-import-"));
    try {
      const ranges = extractWorld(zip, tmp);
      const { world, issues } = loadWorld(tmp);
      if (!world) throw new AtelierError(400, `l'archive ne contient pas un monde lisible (${issues[0]?.file ?? "world.json"} : ${issues[0]?.message ?? "?"})`);
      const problems = validate(world, diskProbe(tmp), { list: diskList(tmp) });
      return this.adopt(tmp, ranges, world.files.world.name, problems, newId, name);
    } finally {
      fs.rmSync(tmp, { recursive: true, force: true });
    }
  }

  exportWorld(id: string): Buffer {
    const { dir, entry } = this.managed(id);
    if (entry.slot < 1) throw new AtelierError(400, "ce monde a ses propres numéros (comme La Vertèbre) : il ne s'exporte pas");
    return exportWorld(dir, id, entry.ranges);
  }

  private checkNewWorld(newId: string, name: string): void {
    if (!/^[a-z][a-z0-9_]{1,31}$/.test(newId)) throw new AtelierError(400, "identifiant invalide : minuscules, chiffres et _ (2 à 32 caractères, commence par une lettre)");
    if (!name.trim()) throw new AtelierError(400, "le nom est vide");
    if (fs.existsSync(path.join(this.worldsDir, newId))) throw new AtelierError(409, `le dossier « ${newId} » existe déjà`);
  }

  /** Copies `srcDir` (whose ids live in `from`) into a new world in a free slot; kept only if it is as coherent as the source. */
  private adopt(srcDir: string, from: RangeMap, srcName: string, srcProblems: Problem[], newId: string, name: string): WorldSummary {
    this.checkNewWorld(newId, name);
    const target = path.join(this.worldsDir, newId);
    const reg = this.registry();
    const slot = nextSlot(reg);
    const ranges = rangesForSlot(slot);
    const count = (ps: Problem[]) => [ps.filter((p) => p.severity === "error").length, ps.length];
    const before = count(srcProblems);
    try {
      cloneWorldDir(srcDir, target, from, ranges, newId, name.trim());
      const { world } = loadWorld(target);
      if (!world) throw new AtelierError(500, "la copie ne se relit pas");
      for (const [k, v] of Object.entries(world.files.texts)) if (v === srcName) world.files.texts[k] = name.trim();
      saveWorld(world);
      reg[newId] = { slot, ranges, created: true };
      this.saveRegistry(reg);
      const after = count(this.detail(newId).problems);
      if (after[0] !== before[0] || after[1] !== before[1]) throw new AtelierError(500, `la copie n'est pas identique à l'original (problèmes : ${before[1]} avant, ${after[1]} après) : abandonnée`);
    } catch (e) {
      fs.rmSync(target, { recursive: true, force: true });
      delete reg[newId];
      this.saveRegistry(reg);
      this.sessions.delete(newId);
      throw e;
    }
    return { id: newId, name: name.trim(), managed: true, created: true, maps: this.session(newId).world.maps.size, breeds: this.session(newId).world.files.world.breeds.length };
  }

  /** Applies an edit, saves it, and records it as one undo step. */
  edit(id: string, label: string, fn: (w: World) => void): void {
    const s = this.session(id);
    const before = structuredClone(s.world);
    try {
      fn(s.world);
      saveWorld(s.world);
      removeStale(s.world.dir, before, s.world);
      s.history.commit(s.world, label);
    } catch (e) {
      s.world = before;
      throw e;
    }
  }

  private visualTemplate(): MapVisual {
    return JSON.parse(fs.readFileSync(path.join(this.templatesDir, "map_visual_empty.json"), "utf-8")) as MapVisual;
  }

  // ---- data editors (each call is one undo step) ----
  rowsOf(id: string, kind: string) {
    const w = this.session(id).world;
    const f = { texts: ed.listTexts, items: ed.listItems, sets: ed.listSets, spells: sp.listSpells, monsters: mo.listMonsters, zones: mo.listZones, classes: cl.listClasses, maps: mp.listMaps, npcs: np.listNpcs, quests: qu.listQuests }[kind];
    if (!f) throw new AtelierError(404, `données inconnues : ${kind}`);
    return f(w);
  }

  report(id: string): Check[] { return playableReport(this.session(id).world); }
  /** Guided workflows with their live state (read from the data, nothing stored). */
  async workflows(id: string): Promise<Workflow[]> {
    const images: Record<string, number> = {};
    for (const c of Object.keys(CATEGORIES)) images[c] = (await this.assets(id, c)).length;
    return workflows(this.session(id).world, { ownBones: this.bones(id).own.length, images });
  }
  /** Boots the saved world in the real headless game (edits are saved on every change, so disk = what you see). */
  async gameCheck(id: string): Promise<GameCheck> {
    this.session(id); // unknown or unmanaged id -> the usual 404
    const game = path.dirname(this.worldsDir);
    if (!fs.existsSync(path.join(game, "project.godot"))) return { status: "unavailable", summary: "Ce dossier de mondes n'est pas dans un projet Godot : rien à lancer.", lines: [], ms: 0 };
    return runGameCheck(game, id);
  }

  visualOf(id: string, map: number): vi.VisualRow { return vi.getVisual(this.session(id).world, map, this.visualTemplate()); }
  dialogOf(id: string, npc: number) { return np.getDialog(this.session(id).world, npc); }

  /** Creates a row; returns its id. */
  dataCreate(id: string, kind: string, body: any): number {
    const ranges = this.managed(id).entry.ranges;
    const ops: Record<string, [string, (w: World) => number]> = {
      texts: ["ajouter un texte", (w) => ed.addText(w, ranges, body?.text)],
      items: [`créer l'objet « ${body?.name} »`, (w) => ed.createItem(w, ranges, body)],
      sets: [`créer la panoplie « ${body?.name} »`, (w) => ed.createSet(w, ranges, body?.name)],
      spells: [`créer le sort « ${body?.name} »`, (w) => sp.createSpell(w, ranges, body)],
      monsters: [`créer le monstre « ${body?.name} »`, (w) => mo.createMonster(w, ranges, body)],
      classes: [`créer la classe « ${body?.name} »`, (w) => cl.createClass(w, ranges, body)],
      quests: [`créer la quête « ${body?.name} »`, (w) => qu.createQuest(w, ranges, body)],
      npcs: [`placer le PNJ « ${body?.name} »`, (w) => np.createNpc(w, ranges, body)],
      maps: [`créer la map « ${body?.name} »`, (w) => mp.createMap(w, ranges, body?.name, this.visualTemplate(), body?.copyOf)],
      zones: ["créer une zone de monstres", (w) => Number(mo.createZone(w, ranges, body?.level))],
    };
    const op = ops[kind];
    if (!op) throw new AtelierError(404, `données inconnues : ${kind}`);
    let out = 0;
    this.edit(id, op[0], (w) => { out = op[1](w); });
    return out;
  }

  dataUpdate(id: string, kind: string, rowId: number, body: any): void {
    const ranges = this.managed(id).entry.ranges;
    const ops: Record<string, [string, (w: World) => void]> = {
      texts: [`modifier le texte ${rowId}`, (w) => ed.setText(w, rowId, body?.text)],
      items: [`modifier l'objet ${rowId}`, (w) => ed.updateItem(w, ranges, rowId, body)],
      sets: [`renommer la panoplie ${rowId}`, (w) => ed.renameSet(w, rowId, body?.name)],
      spells: [`modifier le sort ${rowId}`, (w) => sp.updateSpell(w, ranges, rowId, body)],
      monsters: [`modifier le monstre ${rowId}`, (w) => mo.updateMonster(w, rowId, body)],
      quests: [`modifier la quête ${rowId}`, (w) => qu.updateQuest(w, ranges, rowId, body)],
      npcs: [`modifier le PNJ ${rowId}`, (w) => np.updateNpc(w, ranges, rowId, body)],
      visuals: [`modifier le décor de la map ${rowId}`, (w) => vi.updateVisual(w, diskProbe(this.managed(id).dir), rowId, body, this.visualTemplate())],
      dialogs: [`modifier le dialogue du PNJ ${rowId}`, (w) => np.setDialog(w, rowId, body)],
      maps: body?.start
        ? [`départ du monde sur la map ${rowId}`, (w) => mp.setStart(w, rowId, Number(body.start))]
        : [`modifier la map ${rowId}`, (w) => mp.updateMap(w, ranges, rowId, body)],
      classes: body?.makeDefault === true
        ? [`classe ${rowId} par défaut`, (w) => cl.setDefaultClass(w, rowId)]
        : [`modifier la classe ${rowId}`, (w) => cl.updateClass(w, ranges, rowId, body)],
    };
    const op = ops[kind];
    if (!op) throw new AtelierError(404, `données inconnues : ${kind}`);
    this.edit(id, op[0], op[1]);
  }

  dataDelete(id: string, kind: string, rowId: number): void {
    const ops: Record<string, [string, (w: World) => void]> = {
      texts: [`supprimer le texte ${rowId}`, (w) => ed.deleteText(w, rowId)],
      items: [`supprimer l'objet ${rowId}`, (w) => ed.deleteItem(w, rowId)],
      sets: [`supprimer la panoplie ${rowId}`, (w) => ed.deleteSet(w, rowId)],
      spells: [`supprimer le sort ${rowId}`, (w) => sp.deleteSpell(w, rowId)],
      monsters: [`supprimer le monstre ${rowId}`, (w) => mo.deleteMonster(w, rowId)],
      quests: [`supprimer la quête ${rowId}`, (w) => qu.deleteQuest(w, rowId)],
      npcs: [`retirer le PNJ ${rowId}`, (w) => np.deleteNpc(w, rowId)],
      dialogs: [`supprimer le dialogue du PNJ ${rowId}`, (w) => np.deleteDialog(w, rowId)],
      maps: [`supprimer la map ${rowId}`, (w) => mp.deleteMap(w, rowId)],
      classes: [`supprimer la classe ${rowId}`, (w) => cl.deleteClass(w, rowId)],
      zones: [`supprimer la zone ${rowId}`, (w) => mo.deleteZone(w, String(rowId))],
    };
    const op = ops[kind];
    if (!op) throw new AtelierError(404, `données inconnues : ${kind}`);
    this.edit(id, op[0], op[1]);
  }

  // ---- skeletons (files: outside undo / redo, like images) ----
  private otherDirs(id: string): Record<string, string> {
    const out: Record<string, string> = {};
    for (const o of Object.keys(this.registry())) if (o !== id && fs.existsSync(path.join(this.worldsDir, o, "world.json"))) out[o] = path.join(this.worldsDir, o);
    return out;
  }
  bones(id: string): BoneLibrary { return listBones(this.managed(id).dir, this.otherDirs(id)); }
  /** Preview image (frame 0) of a skeleton, from this world or from another one (`from`). */
  bonePreview(id: string, boneId: number, from?: string): string {
    const dir = from ? this.otherDirs(id)[from] : this.managed(id).dir;
    const f = dir && path.join(dir, "Content", "Characters", "Bones", String(boneId), "0.png");
    if (!f || !fs.existsSync(f)) throw new AtelierError(404, "aperçu introuvable");
    return f;
  }
  importBone(id: string, from: string, boneId: number): void {
    if (from === "dofus") return copyLibraryBone(this.contentRoot, this.managed(id).dir, boneId);
    const others = this.otherDirs(id);
    if (!(from in others)) throw new AtelierError(404, `monde source « ${from} » inconnu`);
    copyBone(this.managed(id).dir, others[from], boneId);
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

  /** PNG bytes of an image of the world. A tile copied from the Dofus content is a WebP: it is converted on the way out. */
  async assetBytes(id: string, cat: string, assetId: number): Promise<Buffer> {
    const { dir } = this.managed(id);
    const c = this.category(cat);
    const png = assetFile(dir, c, assetId);
    if (png) return fs.readFileSync(png);
    const webp = c === "tile" ? path.join(dir, "Content", "Maps", "Gfx", `${assetId}.webp`) : "";
    if (webp && fs.existsSync(webp)) return sharp(webp).png().toBuffer();
    throw new AtelierError(404, "image introuvable");
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
    removeStale(w.dir, s.world, w);
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
