// The AI studio (docs/STUDIO_IA.md): new looks, icons and decor drawn by the local generator from a template.
//   character: the game renders views of a template look (skin_probe.gd) -> the generator repaints the sheet
//     (one call per variant: all views at once, so they agree) -> the chosen variant is projected on the
//     template's atlases (reskin.ts) -> preview of every animation (anim_sheet.gd) -> new skeleton in the world.
//   image: a reference image (or none) + a text -> variants -> background cleared -> imported as a world image.
// Jobs live in memory and in a temporary folder; nothing reaches the world before `accept`.
import { spawn } from "node:child_process";
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import sharp from "sharp";
import { ComfyClient, kontextWorkflow, type AiStatus } from "./ai_client";
import { cutOut, onWhite } from "./ai_images";
import { CATEGORIES, isCategory, type Category } from "./asset_usage";
import { AtelierError } from "./errors";
import { DEFAULT_GODOT } from "./gamecheck";
import { reskinFromProbe, writeReskin, type Adjust } from "./reskin";
import type { WorldStore } from "./store";

export type JobKind = "character" | "image";
export interface Job {
  id: string;
  kind: JobKind;
  world: string;
  prompt: string;
  status: "running" | "ready" | "failed";
  step: string;
  error?: string;
  /** file names in the job folder, null while not generated */
  variants: (string | null)[];
  /** character: the template sheet the generator received */
  sheet?: string;
  look?: string;
  category?: Category;
}
export interface Preview { look: string; sheet: string; stats: { seen: number; filled: number; table: number } }

export const MAX_VARIANTS = 4;
const STYLE = "2D cartoon game art like Dofus: clean dark outlines, soft cel shading, vivid colours";

export function characterPrompt(description: string): string {
  return `Repaint every character of this sheet as ${description.trim()}. Keep exactly the same pose, silhouette, proportions, `
    + `body parts and place of each figure; only change colours, materials and surface details, the same way on every figure. ${STYLE}. Plain white background.`;
}
export function imagePrompt(description: string, category: Category, withReference: boolean): string {
  const what = category === "tile" ? "map decoration seen in the game's isometric view" : category === "monster" ? "creature portrait" : category === "spell" ? "spell icon" : "item icon";
  return withReference
    ? `Turn this ${what} into ${description.trim()}. Keep the same framing, size, perspective, outline and painting style. ${STYLE}. Plain white background.`
    : `A single ${what}: ${description.trim()}. Centred, whole, nothing else. ${STYLE}. Plain white background.`;
}

interface Run { ok: boolean; out: string }
function runGodot(godot: string, gameDir: string, script: string, args: string[], timeoutMs = 180_000): Promise<Run> {
  return new Promise((resolve) => {
    // not headless: these tools render
    const child = spawn(godot, ["--path", gameDir, "-s", script, "--", ...args], { cwd: path.dirname(gameDir), windowsHide: true });
    let out = "";
    const timer = setTimeout(() => child.kill(), timeoutMs);
    child.stdout.on("data", (d) => { out += d; });
    child.stderr.on("data", (d) => { out += d; });
    child.on("error", () => { clearTimeout(timer); resolve({ ok: false, out: "Godot introuvable" }); });
    child.on("close", (code) => { clearTimeout(timer); resolve({ ok: code === 0, out }); });
  });
}

const randomSeed = () => crypto.randomInt(1, 2 ** 31);

export class AiStudio {
  private jobs = new Map<string, Job>();

  readonly client: ComfyClient;
  readonly godot: string;
  readonly jobsDir: string;
  /** the Godot project that renders (game/); defaults to the parent of the worlds folder */
  readonly gameDir: string;

  constructor(private readonly store: WorldStore, opts: { client?: ComfyClient; godot?: string; jobsDir?: string; gameDir?: string } = {}) {
    this.client = opts.client ?? new ComfyClient();
    this.godot = opts.godot ?? process.env.GODOT_EXE ?? DEFAULT_GODOT;
    this.jobsDir = opts.jobsDir ?? path.join(os.tmpdir(), "atelier-ai");
    this.gameDir = opts.gameDir ?? path.dirname(store.worldsDir);
    fs.rmSync(this.jobsDir, { recursive: true, force: true });
  }

  /** Content folders a look is read from, first wins: the world, the game's mods, the Dofus content. */
  private roots(world: string): string[] {
    const out = [this.store.place(world).dir];
    const project = path.join(this.gameDir, "project.godot");
    const m = fs.existsSync(project) ? /content_overlays=PackedStringArray\(([^)]*)\)/.exec(fs.readFileSync(project, "utf-8")) : null;
    for (const o of m ? m[1].split(",") : []) out.push(path.join(this.gameDir, o.trim().replace(/^"|"$/g, "").replace(/^res:\/\//, "")));
    out.push(path.dirname(this.store.contentRoot));
    return out;
  }

  async status(): Promise<AiStatus & { godot: boolean }> {
    return { ...(await this.client.status()), godot: fs.existsSync(this.godot) };
  }

  job(id: string): Job {
    const j = this.jobs.get(id);
    if (!j) throw new AtelierError(404, "tâche inconnue (l'atelier a peut-être redémarré)");
    return j;
  }
  private dir(id: string) { return path.join(this.jobsDir, id); }

  /** A file of a job folder (variants, sheets, preview strips). */
  file(id: string, rel: string): string {
    this.job(id);
    if (!/^[\w-]+(\/[\w%-]+)*\.(png|json)$/.test(rel)) throw new AtelierError(400, "fichier invalide");
    const f = path.join(this.dir(id), ...rel.split("/"));
    if (!fs.existsSync(f)) throw new AtelierError(404, "fichier introuvable");
    return f;
  }

  private create(kind: JobKind, world: string, prompt: string, count: number, extra: Partial<Job>): Job {
    this.store.place(world);
    if (!prompt.trim()) throw new AtelierError(400, "décris ce que tu veux obtenir");
    const n = Math.max(1, Math.min(MAX_VARIANTS, Math.floor(count) || 1));
    const job: Job = { id: crypto.randomUUID().slice(0, 8), kind, world, prompt: prompt.trim(), status: "running", step: "préparation", variants: Array(n).fill(null), ...extra };
    fs.mkdirSync(this.dir(job.id), { recursive: true });
    this.jobs.set(job.id, job);
    return job;
  }

  private async generate(job: Job, prompt: string, input: Buffer | null, size: { width: number; height: number }, post: (png: Buffer) => Promise<Buffer>) {
    const image = input ? await this.client.upload(input, `atelier_${job.id}.png`) : undefined;
    for (let k = 0; k < job.variants.length; k++) {
      job.step = `génération ${k + 1} / ${job.variants.length}`;
      const png = await this.client.run(kontextWorkflow(this.client.config, prompt, randomSeed(), image, size.width, size.height));
      fs.writeFileSync(path.join(this.dir(job.id), `raw_${k}.png`), png);
      fs.writeFileSync(path.join(this.dir(job.id), `variant_${k}.png`), await post(png));
      job.variants[k] = `variant_${k}.png`;
    }
  }

  private launch(job: Job, work: () => Promise<void>): Job {
    work().then(() => { job.status = "ready"; job.step = "terminé"; }, (e) => { job.status = "failed"; job.error = (e as Error).message; });
    return job;
  }

  // ---- characters ----
  startCharacter(world: string, look: string, description: string, count = 3): Job {
    if (!/^\{\d+\|/.test(look.trim())) throw new AtelierError(400, "apparence invalide (attendu : {squelette|skins|…})");
    const job = this.create("character", world, description, count, { look: look.trim() });
    return this.launch(job, async () => {
      if (!(await this.client.status()).ready) throw new Error("le moteur d'images n'est pas lancé (tools\\ai\\start_ai.bat)");
      job.step = "rendu des vues du modèle";
      const probe = path.join(this.dir(job.id), "probe");
      const r = await runGodot(this.godot, this.gameDir, "res://tools/skin_probe.gd", [`--look=${job.look}`, `--out=${probe}`, `--world=${this.store.place(world).dir}`]);
      if (!fs.existsSync(path.join(probe, "views.json"))) throw new Error(`le rendu des vues a échoué : ${r.out.split(/\r?\n/).filter((l) => /error/i.test(l)).slice(0, 3).join(" ") || "sans message"}`);
      const meta = await sharp(path.join(probe, "color.png")).metadata();
      const size = { width: meta.width ?? 1008, height: meta.height ?? 1024 };
      const sheet = await onWhite(fs.readFileSync(path.join(probe, "color.png")), size.width, size.height);
      fs.writeFileSync(path.join(this.dir(job.id), "sheet.png"), sheet);
      job.sheet = "sheet.png";
      await this.generate(job, characterPrompt(description), sheet, size, (png) => sharp(png).resize(size.width, size.height, { fit: "fill" }).png().toBuffer());
    });
  }

  private variantFile(job: Job, variant: number): string {
    const name = job.variants[variant];
    if (!name) throw new AtelierError(409, "variante pas encore prête");
    return path.join(this.dir(job.id), name);
  }

  /** Projects a variant on a scratch copy and renders every animation of it. */
  async preview(id: string, variant: number, adjust: Adjust = {}, bake = true): Promise<Preview> {
    const job = this.job(id);
    if (job.kind !== "character") throw new AtelierError(400, "aperçu animé : seulement pour un personnage");
    const roots = this.roots(job.world);
    const r = await reskinFromProbe(path.join(this.dir(id), "probe"), this.variantFile(job, variant), roots, adjust);
    const stage = path.join(this.dir(id), "stage");
    fs.rmSync(stage, { recursive: true, force: true });
    const w = await writeReskin(stage, roots, r.info, r.atlases, this.store.place(job.world).entry.ranges.asset, bake);
    const out = `preview_${variant}_${Date.now() % 1e6}`;
    const run = await runGodot(this.godot, this.gameDir, "res://tools/anim_sheet.gd", [`--look=${w.look}`, `--out=${path.join(this.dir(id), out)}`, `--world=${stage},${roots[0]}`]); // the tool adds the mods and the Dofus content
    if (!fs.existsSync(path.join(this.dir(id), out, "sheet.json"))) throw new AtelierError(500, `l'aperçu animé a échoué : ${run.out.slice(-300)}`);
    const sum = (a: number[]) => a.reduce((x, y) => x + y, 0);
    return { look: w.look, sheet: `${out}/sheet.json`, stats: { seen: sum(r.stats.seen), filled: sum(r.stats.filled), table: sum(r.stats.table) } };
  }

  // ---- icons and decor ----
  async startImage(world: string, category: string, description: string, count = 4, reference?: { from: "library" | "world"; cat: string; id: number }): Promise<Job> {
    if (!isCategory(category)) throw new AtelierError(400, `catégorie d'image inconnue : ${category}`);
    const ref = reference ? (reference.from === "library" ? await this.store.libraryPng(reference.cat, Number(reference.id), 0) : await this.store.assetBytes(world, reference.cat, Number(reference.id))) : null;
    const job = this.create("image", world, description, count, { category });
    const refMeta = ref ? await sharp(ref).metadata() : null;
    const icon = CATEGORIES[category].size > 0;
    // decor keeps about the reference's size; icons are fitted to 96 px on import
    const max = icon ? 256 : Math.max(64, Math.min(1024, Math.max(refMeta?.width ?? 0, refMeta?.height ?? 0) || 512));
    return this.launch(job, async () => {
      if (!(await this.client.status()).ready) throw new Error("le moteur d'images n'est pas lancé (tools\\ai\\start_ai.bat)");
      const input = ref ? await onWhite(ref, 1024, 1024) : null;
      if (input) { fs.writeFileSync(path.join(this.dir(job.id), "sheet.png"), input); job.sheet = "sheet.png"; }
      await this.generate(job, imagePrompt(description, category, !!ref), input, { width: 1024, height: 1024 }, (png) => cutOut(png, max, icon));
    });
  }

  // ---- into the world ----
  async accept(id: string, variant: number, opts: { adjust?: Adjust; bake?: boolean; name?: string } = {}): Promise<{ look?: string; bones?: number[]; skins?: number[]; asset?: number }> {
    const job = this.job(id);
    const file = this.variantFile(job, variant);
    if (job.kind === "character") {
      const roots = this.roots(job.world);
      const r = await reskinFromProbe(path.join(this.dir(id), "probe"), file, roots, opts.adjust ?? {});
      const place = this.store.place(job.world);
      return writeReskin(place.dir, roots, r.info, r.atlases, place.entry.ranges.asset, opts.bake ?? true);
    }
    const name = (opts.name ?? job.prompt).slice(0, 60) || "image IA";
    const [res] = await this.store.importAssets(job.world, job.category!, { files: [{ name: `${name}.png`, data: fs.readFileSync(file) }] });
    if (res.status === "rejected") throw new AtelierError(400, res.reason ?? "image refusée");
    return { asset: res.id };
  }
}
