// AI studio: re-skin projection, background clearing, ComfyUI workflow, and whole jobs with a fake generator
// (the real one, ComfyUI + Kontext, is only used by hand: docs/STUDIO_IA.md). The character job runs the real
// game tools (skin_probe.gd, anim_sheet.gd) when Godot and the Dofus content are on this computer.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import sharp from "sharp";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { ComfyClient, DEFAULT_AI_CONFIG, kontextWorkflow } from "../core/ai_client";
import { clearBackground, cutOut, opaqueBox } from "../core/ai_images";
import { AiStudio, characterPrompt, type Job } from "../core/ai_studio";
import { DEFAULT_GODOT } from "../core/gamecheck";
import { decodeUv, encodeUv, project, type Raw } from "../core/reskin";
import { WorldStore } from "../core/store";

const ROOT = path.resolve(__dirname, "..", "..");
const GODOT = process.env.GODOT_EXE ?? DEFAULT_GODOT;
const CONTENT = path.join(ROOT, "game", "content", "Content");

const raw = (width: number, height: number, fill: (x: number, y: number) => number[]): Raw => {
  const data = new Uint8Array(width * height * 4);
  for (let y = 0; y < height; y++) for (let x = 0; x < width; x++) data.set(fill(x, y), (y * width + x) * 4);
  return { width, height, data };
};
const px = (r: Raw, x: number, y: number) => [...r.data.subarray((y * r.width + x) * 4, (y * r.width + x) * 4 + 4)];

describe("codage des coordonnées d'atlas", () => {
  it("fait l'aller-retour pour toute position jusqu'à 4096 et 16 atlas", () => {
    for (const [slot, x, y] of [[0, 0, 0], [3, 1023, 2047], [15, 4095, 4095], [1, 256, 300]]) {
      const d = new Uint8Array(encodeUv(slot, x, y));
      expect(decodeUv(d, 0)).toEqual({ slot, x, y });
    }
    expect(decodeUv(new Uint8Array([1, 2, 3, 0]), 0)).toBeNull();
  });
});

describe("projection d'une planche repeinte sur l'atlas", () => {
  // atlas 16x8: island A (x 1..6) is drawn on the sheet, island B (x 9..14) never; both are the same grey
  const atlas = raw(16, 8, (x, y) => (y >= 1 && y <= 6 && ((x >= 1 && x <= 6) || (x >= 9 && x <= 14)) ? [120, 120, 120, 255] : [0, 0, 0, 0]));
  // sheet 12x12: texel (x,y) of island A drawn at (x+2, y+2), only its left half x 1..3
  const uv = raw(12, 12, (x, y) => { const tx = x - 2, ty = y - 2; return tx >= 1 && tx <= 3 && ty >= 1 && ty <= 6 ? encodeUv(0, tx, ty) : [0, 0, 0, 0]; });
  const template = raw(12, 12, () => [120, 120, 120, 255]);
  const red = raw(12, 12, () => [200, 30, 40, 255]);

  it("peint les texels vus, complète la pièce vue en partie et devine la pièce jamais vue", () => {
    const { atlases, stats } = project(uv, template, red, [atlas], 1);
    const out = atlases[0]!;
    expect(px(out, 2, 3)).toEqual([200, 30, 40, 255]); // seen (inner pixel)
    expect(px(out, 6, 6)).toEqual([200, 30, 40, 255]); // same island, never drawn: nearest seen texel
    expect(px(out, 12, 4)).toEqual([200, 30, 40, 255]); // other island: colour table grey -> red
    expect(px(out, 0, 0)).toEqual([0, 0, 0, 0]); // transparent stays transparent
    expect(stats.seen[0]).toBeGreaterThan(0);
    expect(stats.filled[0]).toBeGreaterThan(0);
    expect(stats.table[0]).toBe(36);
  });

  it("ignore le fond blanc de l'IA qui déborde sur la silhouette, et applique la retouche de teinte", () => {
    const white = raw(12, 12, () => [255, 255, 255, 255]);
    expect(project(uv, template, white, [atlas], 1).stats.pixels).toBe(0);
    const { atlases } = project(uv, template, red, [atlas], 1, { hue: 120 });
    const [r, g, b] = px(atlases[0]!, 2, 3);
    expect(g).toBeGreaterThan(r);
    expect(g).toBeGreaterThan(b);
  });

  it("refuse des planches de tailles différentes", () => {
    expect(() => project(uv, template, raw(10, 10, () => [0, 0, 0, 255]), [atlas], 1)).toThrow(/tailles/);
  });
});

describe("détourage des icônes et décors", () => {
  it("rend transparent le fond blanc relié au bord et garde le dessin, même blanc à l'intérieur", () => {
    // white background, black ring, white inside the ring
    const img = raw(20, 20, (x, y) => { const d = Math.max(Math.abs(x - 10), Math.abs(y - 10)); return d <= 6 && d >= 4 ? [0, 0, 0, 255] : [255, 255, 255, 255]; });
    const out = clearBackground(img);
    expect(px(out, 0, 0)[3]).toBe(0);
    expect(px(out, 10, 4)[3]).toBe(255); // ring
    expect(px(out, 10, 10)[3]).toBe(255); // white inside the ring: not connected to the border
    expect(opaqueBox(out)).toEqual({ left: 4, top: 4, width: 13, height: 13 });
  });

  it("recadre autour du dessin et le met au carré pour une icône", async () => {
    const png = await sharp({ create: { width: 200, height: 100, channels: 3, background: "#ffffff" } })
      .composite([{ input: await sharp({ create: { width: 40, height: 20, channels: 3, background: "#c03020" } }).png().toBuffer(), left: 80, top: 40 }]).png().toBuffer();
    const meta = await sharp(await cutOut(png, 256, true)).metadata();
    expect([meta.width, meta.height, meta.hasAlpha]).toEqual([40, 40, true]);
  });
});

describe("workflow ComfyUI", () => {
  it("édite une image avec Kontext quand il y en a une, dessine à partir du texte sinon", () => {
    const edit = kontextWorkflow(DEFAULT_AI_CONFIG, "un golem", 7, "planche.png");
    expect(edit.image.inputs.image).toBe("planche.png");
    expect(edit.reference.class_type).toBe("ReferenceLatent");
    expect(edit.sampler.inputs).toMatchObject({ seed: 7, latent_image: ["latent", 0], positive: ["guidance", 0] });
    const t2i = kontextWorkflow(DEFAULT_AI_CONFIG, "un golem", 7, undefined, 768, 512);
    expect(t2i.image).toBeUndefined();
    expect(t2i.latent.inputs).toMatchObject({ width: 768, height: 512 });
    expect(characterPrompt("golem de cristal")).toMatch(/golem de cristal.*same pose/);
  });

  it("signale un moteur absent avec la commande pour le lancer", async () => {
    const down = new ComfyClient(DEFAULT_AI_CONFIG, (async () => { throw new Error("refused"); }) as unknown as typeof fetch);
    expect(await down.status()).toMatchObject({ ready: false, summary: expect.stringMatching(/start_ai\.bat/) });
  });
});

/** A ComfyClient that "generates" by shifting the hue of what it received (or drawing a red square). */
class FakeComfy extends ComfyClient {
  runs = 0;
  private last: Buffer | null = null;
  constructor() { super(DEFAULT_AI_CONFIG, (async () => { throw new Error("pas de réseau dans les tests"); }) as unknown as typeof fetch); }
  override async status() { return { ready: true, summary: "faux moteur" }; }
  override async upload(png: Buffer) { this.last = png; return "x.png"; }
  override async run() {
    this.runs++;
    if (this.last) return sharp(this.last).modulate({ hue: 150 }).png().toBuffer();
    return sharp({ create: { width: 1024, height: 1024, channels: 3, background: "#ffffff" } })
      .composite([{ input: await sharp({ create: { width: 300, height: 300, channels: 3, background: "#2050d0" } }).png().toBuffer(), left: 362, top: 362 }]).png().toBuffer();
  }
}

async function until(studio: AiStudio, job: Job): Promise<Job> {
  for (let i = 0; i < 600 && studio.job(job.id).status === "running"; i++) await new Promise((r) => setTimeout(r, 100));
  return studio.job(job.id);
}

let tmp: string;
let store: WorldStore;
let studio: AiStudio;
let fake: FakeComfy;
beforeEach(() => {
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), "atelier-studio-"));
  store = new WorldStore(path.join(tmp, "worlds"), path.join(tmp, "r.json"), path.resolve(__dirname, "..", "templates"));
  fs.mkdirSync(store.worldsDir);
  store.contentRoot = CONTENT;
  store.create("monde_a", "A");
  fake = new FakeComfy();
  studio = new AiStudio(store, { client: fake, jobsDir: path.join(tmp, "jobs"), gameDir: path.join(ROOT, "game") });
});
afterEach(() => fs.rmSync(tmp, { recursive: true, force: true }));

describe("tâches du studio", () => {
  it("icône sans référence : variantes détourées, puis l'image choisie entre dans la bibliothèque du monde", async () => {
    const job = await until(studio, await studio.startImage("monde_a", "item", "épée de glace", 2));
    expect(job).toMatchObject({ status: "ready", variants: ["variant_0.png", "variant_1.png"] });
    expect(fake.runs).toBe(2);
    const meta = await sharp(studio.file(job.id, "variant_0.png")).metadata();
    expect([meta.width, meta.height, meta.hasAlpha]).toEqual([256, 256, true]);
    const r = await studio.accept(job.id, 1, { name: "Épée de glace" });
    expect(r.asset).toBe(store.detail("monde_a").ranges.asset[0]);
    expect((await store.assets("monde_a", "item"))[0]).toMatchObject({ name: "Épée de glace", width: 96 });
  });

  it("refuse un monde inconnu, une description vide, une apparence illisible et un fichier hors de la tâche", async () => {
    await expect(studio.startImage("inconnu", "item", "x")).rejects.toThrow(/inconnu/);
    await expect(studio.startImage("monde_a", "item", "  ")).rejects.toThrow(/décris/);
    expect(() => studio.startCharacter("monde_a", "pas un look", "golem")).toThrow(/apparence/);
    const job = await until(studio, await studio.startImage("monde_a", "tile", "rocher", 1));
    expect(() => studio.file(job.id, "../r.json")).toThrow(/invalide/);
  });

  it.skipIf(!fs.existsSync(GODOT) || !fs.existsSync(path.join(CONTENT, "Characters", "Bones", "104")))(
    "personnage : vues du modèle, variante repeinte, aperçu de toutes les animations, nouveau squelette dans le monde", async () => {
      const job = await until(studio, studio.startCharacter("monde_a", "{104|||100}", "golem de glace", 1));
      expect(job.error).toBeUndefined();
      expect(job.status).toBe("ready");
      const preview = await studio.preview(job.id, 0);
      expect(preview.look).toMatch(/^\{\d+\|\|\|100\}$/);
      expect(preview.stats.seen).toBeGreaterThan(10_000);
      const sheet = JSON.parse(fs.readFileSync(studio.file(job.id, preview.sheet), "utf-8"));
      expect(Object.keys(sheet.anims)).toEqual(expect.arrayContaining(["AnimStatique", "AnimMarche"]));
      expect(sheet.anims.AnimMarche["3"]).toEqual({ strip: "AnimMarche_1", flip: true });

      const r = await studio.accept(job.id, 0);
      const bone = store.detail("monde_a").ranges.asset[0];
      expect(r).toMatchObject({ look: `{${bone}|||100}`, bones: [bone], skins: [] });
      const dir = path.join(store.worldsDir, "monde_a", "Content", "Characters", "Bones", String(bone));
      expect(JSON.parse(fs.readFileSync(path.join(dir, "bone.json"), "utf-8")).m_Name).toBe(String(bone));
      expect(fs.existsSync(path.join(dir, "0.png"))).toBe(true);
      expect(fs.existsSync(path.join(dir, "AnimMarche_1.dat"))).toBe(true);
      // the repainted atlas: hue shifted, the alpha of the template kept
      const [a, b] = await Promise.all([sharp(path.join(dir, "0.png")).raw().toBuffer(), sharp(path.join(CONTENT, "Characters", "Bones", "104", "0.webp")).ensureAlpha().raw().toBuffer()]);
      let alphaDiff = 0, changed = 0;
      for (let i = 0; i < a.length; i += 4) { alphaDiff += Math.abs(a[i + 3] - b[i + 3]); if (b[i + 3] && Math.abs(a[i] - b[i]) > 20) changed++; }
      expect(alphaDiff).toBe(0);
      expect(changed).toBeGreaterThan(1000);
      expect(store.bones("monde_a").own).toContain(bone);
    });
});
