// AI re-skin of an animated look (docs/STUDIO_IA.md): the game renders views of the template twice
// (game/tools/skin_probe.gd): in colour, and with "coordinate atlases" telling which texel of which atlas each
// pixel shows. The AI repaints the colour sheet; `project` carries every repainted pixel back to its texel, so
// the new atlas re-skins every animation and direction of the skeleton at once.
//   seen texels: mean of the views; texels of a partly seen piece (atlas island): nearest seen texel of the
//   piece; pieces never seen: a colour table learnt from the views (template colour -> generated colour).
import fs from "node:fs";
import path from "node:path";
import sharp from "sharp";
import { AtelierError } from "./errors";

/** RGBA pixels. */
export interface Raw { width: number; height: number; data: Uint8Array }
export interface ProbeView { anim: string; dir: number; frame: number; played: string; flipped: boolean; frames: number; rect: number[] }
/** game/tools/skin_probe.gd views.json */
export interface ProbeInfo { look: string; width: number; height: number; cols: number; cell: number[]; zoom: number; views: ProbeView[]; slots: string[] }
export interface Adjust { hue?: number; saturation?: number; brightness?: number }
export interface ProjectStats { pixels: number; seen: number[]; filled: number[]; table: number[] }

// same encoding as DofusContent._probe_atlas
export function encodeUv(slot: number, x: number, y: number): [number, number, number, number] {
  return [x & 255, y & 255, (x >> 8) | ((y >> 8) << 4), 255 - 8 * slot];
}
export function decodeUv(d: Uint8Array, i: number): { slot: number; x: number; y: number } | null {
  const a = d[i + 3];
  if (a < 128) return null;
  return { slot: Math.round((255 - a) / 8), x: d[i] | ((d[i + 2] & 15) << 8), y: d[i + 1] | ((d[i + 2] >> 4) << 8) };
}

const BINS = 16; // colour table: 16 levels per channel
const binOf = (r: number, g: number, b: number) => ((r >> 4) * BINS + (g >> 4)) * BINS + (b >> 4);

/** Colour table template -> generated, its empty bins filled from the nearest filled bin. */
function colourTable(pairs: { from: number; r: number; g: number; b: number }[]): Float32Array {
  const n = BINS ** 3;
  const sum = new Float32Array(n * 3), cnt = new Uint32Array(n);
  for (const p of pairs) { sum[p.from * 3] += p.r; sum[p.from * 3 + 1] += p.g; sum[p.from * 3 + 2] += p.b; cnt[p.from]++; }
  const out = new Float32Array(n * 3).fill(-1);
  let queue: number[] = [];
  for (let k = 0; k < n; k++) if (cnt[k]) { for (let c = 0; c < 3; c++) out[k * 3 + c] = sum[k * 3 + c] / cnt[k]; queue.push(k); }
  if (!queue.length) { for (let k = 0; k < n; k++) { const r = Math.floor(k / BINS / BINS), g = Math.floor(k / BINS) % BINS, b = k % BINS; out.set([r * 16 + 8, g * 16 + 8, b * 16 + 8], k * 3); } return out; }
  while (queue.length) {
    const next: number[] = [];
    for (const k of queue) {
      const r = Math.floor(k / BINS / BINS), g = Math.floor(k / BINS) % BINS, b = k % BINS;
      for (const [dr, dg, db] of [[1, 0, 0], [-1, 0, 0], [0, 1, 0], [0, -1, 0], [0, 0, 1], [0, 0, -1]]) {
        const R = r + dr, G = g + dg, B = b + db;
        if (R < 0 || G < 0 || B < 0 || R >= BINS || G >= BINS || B >= BINS) continue;
        const j = (R * BINS + G) * BINS + B;
        if (out[j * 3] >= 0) continue;
        out.set(out.subarray(k * 3, k * 3 + 3), j * 3);
        next.push(j);
      }
    }
    queue = next;
  }
  return out;
}

function rgbToHsl(r: number, g: number, b: number): [number, number, number] {
  r /= 255; g /= 255; b /= 255;
  const max = Math.max(r, g, b), min = Math.min(r, g, b), l = (max + min) / 2;
  if (max === min) return [0, 0, l];
  const d = max - min, s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
  const h = max === r ? (g - b) / d + (g < b ? 6 : 0) : max === g ? (b - r) / d + 2 : (r - g) / d + 4;
  return [h / 6, s, l];
}
function hslToRgb(h: number, s: number, l: number): [number, number, number] {
  if (s === 0) return [l * 255, l * 255, l * 255];
  const q = l < 0.5 ? l * (1 + s) : l + s - l * s, p = 2 * l - q;
  const f = (t: number) => { t = (t + 1) % 1; return t < 1 / 6 ? p + (q - p) * 6 * t : t < 1 / 2 ? q : t < 2 / 3 ? p + (q - p) * (2 / 3 - t) * 6 : p; };
  return [f(h + 1 / 3) * 255, f(h) * 255, f(h - 1 / 3) * 255];
}
/** hue in degrees, saturation and brightness as factors (1 = unchanged). */
export function adjustColour(r: number, g: number, b: number, a: Adjust): [number, number, number] {
  if (!a.hue && (a.saturation ?? 1) === 1 && (a.brightness ?? 1) === 1) return [r, g, b];
  const [h, s, l] = rgbToHsl(r, g, b);
  return hslToRgb((h + (a.hue ?? 0) / 360 + 1) % 1, Math.min(1, s * (a.saturation ?? 1)), Math.min(1, l * (a.brightness ?? 1)));
}

/**
 * Pure projection. `uv`, `template` and `generated` share the sheet size; `atlases[slot]` are the template atlases
 * (their alpha is kept). Returns the repainted atlases.
 */
export function project(uv: Raw, template: Raw, generated: Raw, atlases: (Raw | null)[], zoom: number, adjust: Adjust = {}): { atlases: (Raw | null)[]; stats: ProjectStats } {
  const { width: W, height: H } = uv;
  if (template.width !== W || template.height !== H || generated.width !== W || generated.height !== H) throw new AtelierError(400, "planches de tailles différentes");
  const tol = Math.ceil(2 / Math.max(zoom, 0.05)) + 1;
  const sums = atlases.map((a) => (a ? new Float32Array(a.width * a.height * 3) : null));
  const counts = atlases.map((a) => (a ? new Uint16Array(a.width * a.height) : null));
  const pairs: { from: number; r: number; g: number; b: number }[] = [];
  const stats: ProjectStats = { pixels: 0, seen: atlases.map(() => 0), filled: atlases.map(() => 0), table: atlases.map(() => 0) };
  const ud = uv.data, td = template.data, gd = generated.data;
  for (let y = 1; y < H - 1; y++) {
    for (let x = 1; x < W - 1; x++) {
      const i = (y * W + x) * 4;
      const t = decodeUv(ud, i);
      if (!t || !atlases[t.slot]) continue;
      // inner pixels only: the 4 neighbours show the same atlas, near the same texel (no seam, no silhouette edge)
      let inner = true;
      for (const o of [-4, 4, -W * 4, W * 4]) {
        const n = decodeUv(ud, i + o);
        if (!n || n.slot !== t.slot || Math.abs(n.x - t.x) > tol || Math.abs(n.y - t.y) > tol) { inner = false; break; }
      }
      if (!inner) continue;
      const [r, g, b] = [gd[i], gd[i + 1], gd[i + 2]];
      // the AI's white background bleeding over the silhouette
      if (Math.min(r, g, b) > 245 && Math.min(td[i], td[i + 1], td[i + 2]) < 225) continue;
      const atlas = atlases[t.slot]!;
      if (t.x >= atlas.width || t.y >= atlas.height) continue;
      const k = t.y * atlas.width + t.x;
      const s = sums[t.slot]!;
      s[k * 3] += r; s[k * 3 + 1] += g; s[k * 3 + 2] += b;
      counts[t.slot]![k]++;
      stats.pixels++;
      if (td[i + 3] > 250) pairs.push({ from: binOf(td[i], td[i + 1], td[i + 2]), r, g, b });
    }
  }
  const table = colourTable(pairs);
  const out = atlases.map((a, slot) => {
    if (!a) return null;
    const n = a.width * a.height, s = sums[slot]!, c = counts[slot]!;
    const res = new Uint8Array(a.data);
    const done = new Uint8Array(n);
    let queue: number[] = [];
    for (let k = 0; k < n; k++) {
      if (!c[k] || a.data[k * 4 + 3] === 0) continue;
      for (let ch = 0; ch < 3; ch++) res[k * 4 + ch] = Math.round(s[k * 3 + ch] / c[k]);
      done[k] = 1;
      queue.push(k);
      stats.seen[slot]++;
    }
    // nearest seen texel inside the same piece (8-connected opaque island)
    while (queue.length) {
      const next: number[] = [];
      for (const k of queue) {
        const x = k % a.width, y = (k - x) / a.width;
        for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) {
          const X = x + dx, Y = y + dy;
          if ((!dx && !dy) || X < 0 || Y < 0 || X >= a.width || Y >= a.height) continue;
          const j = Y * a.width + X;
          if (done[j] || a.data[j * 4 + 3] === 0) continue;
          res.set(res.subarray(k * 4, k * 4 + 3), j * 4);
          done[j] = 1;
          next.push(j);
          stats.filled[slot]++;
        }
      }
      queue = next;
    }
    for (let k = 0; k < n; k++) {
      if (a.data[k * 4 + 3] === 0) continue;
      if (!done[k]) {
        const bin = binOf(a.data[k * 4], a.data[k * 4 + 1], a.data[k * 4 + 2]);
        for (let ch = 0; ch < 3; ch++) res[k * 4 + ch] = Math.round(table[bin * 3 + ch]);
        stats.table[slot]++;
      }
      const [r, g, b] = adjustColour(res[k * 4], res[k * 4 + 1], res[k * 4 + 2], adjust);
      res[k * 4] = Math.round(r); res[k * 4 + 1] = Math.round(g); res[k * 4 + 2] = Math.round(b);
    }
    return { width: a.width, height: a.height, data: res };
  });
  return { atlases: out, stats };
}

export async function readRaw(file: string | Buffer, size?: { width: number; height: number }): Promise<Raw> {
  let img = sharp(file).ensureAlpha();
  if (size) img = img.resize(size.width, size.height, { fit: "fill" });
  const { data, info } = await img.raw().toBuffer({ resolveWithObject: true });
  return { width: info.width, height: info.height, data: new Uint8Array(data.buffer, data.byteOffset, data.length) };
}

/** The file of an atlas path ("Content/Characters/Bones/104/0") in the first content root that has it. */
export function atlasFile(roots: string[], atlas: string): string | null {
  for (const r of roots) for (const ext of [".png", ".webp"]) {
    const f = path.join(r, ...atlas.split("/")) + ext;
    if (fs.existsSync(f)) return f;
  }
  return null;
}

/** Projects a generated sheet (any size: it is fitted to the probe sheet) using a probe folder. */
export async function reskinFromProbe(probeDir: string, generated: string | Buffer, roots: string[], adjust: Adjust = {}) {
  const info: ProbeInfo = JSON.parse(fs.readFileSync(path.join(probeDir, "views.json"), "utf-8"));
  const size = { width: info.width, height: info.height };
  const [uv, template, gen] = await Promise.all([readRaw(path.join(probeDir, "uv.png")), readRaw(path.join(probeDir, "color.png")), readRaw(generated, size)]);
  const atlases = await Promise.all(info.slots.map(async (s) => { const f = atlasFile(roots, s); return f ? readRaw(f) : null; }));
  return { info, ...project(uv, template, gen, atlases, info.zoom, adjust) };
}

export const toPng = (r: Raw) => sharp(Buffer.from(r.data), { raw: { width: r.width, height: r.height, channels: 4 } }).png({ compressionLevel: 9 }).toBuffer();

// ── writing the new look into a world ─────────────────────────────────────────

const LOOK = /^\{(\d+)\|([^|{}]*)/;
const FOLDER = /^Content\/Characters\/(Bones|Skins)\/(\d+)\/(\d+)$/;

function nextFolderId(dir: string, range: [number, number]): number {
  const ids = fs.existsSync(dir) ? fs.readdirSync(dir).filter((n) => /^\d+$/.test(n)).map(Number).filter((n) => n >= range[0] && n <= range[1]) : [];
  const id = Math.max(range[0] - 1, ...ids) + 1;
  if (id > range[1]) throw new AtelierError(409, "plus d'identifiant libre dans la tranche d'images du monde");
  return id;
}

/** Template palette slots would tint the repainted parts a second time: `bake` removes them (vertex pos.z). */
function patchSkinJson(file: string, bake: boolean): void {
  if (!bake) return;
  const skin = JSON.parse(fs.readFileSync(file, "utf-8"));
  for (const v of skin.vertices ?? []) if (v?.pos) v.pos.z = 0;
  fs.writeFileSync(file, JSON.stringify(skin), "utf-8");
}

/**
 * Writes the repainted atlases as new bones / skins of the world (copies of the template's folders) and returns
 * the new look. Atlases of split bones (player bone families) are left as they are.
 */
export async function writeReskin(worldDir: string, roots: string[], info: ProbeInfo, atlases: (Raw | null)[], range: [number, number], bake = true): Promise<{ look: string; bones: number[]; skins: number[] }> {
  const m = LOOK.exec(info.look);
  if (!m) throw new AtelierError(400, `apparence illisible : ${info.look}`);
  const newIds = new Map<string, number>(); // "Bones/104" -> new id
  const created = { bones: [] as number[], skins: [] as number[] };
  for (let slot = 0; slot < info.slots.length; slot++) {
    const atlas = atlases[slot];
    const f = FOLDER.exec(info.slots[slot]);
    if (!atlas || !f) continue;
    const [, kind, id, index] = f;
    const key = `${kind}/${id}`;
    const base = path.join(worldDir, "Content", "Characters", kind);
    let nid = newIds.get(key);
    if (nid === undefined) {
      const src = roots.map((r) => path.join(r, "Content", "Characters", kind, id)).find((d) => fs.existsSync(d));
      if (!src) continue;
      nid = nextFolderId(base, range);
      const dest = path.join(base, String(nid));
      fs.cpSync(src, dest, { recursive: true });
      patchSkinJson(path.join(dest, "skin.json"), bake);
      const boneJson = path.join(dest, "bone.json");
      if (fs.existsSync(boneJson)) { // the game finds the animation clips by this name
        const b = JSON.parse(fs.readFileSync(boneJson, "utf-8"));
        b.m_Name = String(nid);
        fs.writeFileSync(boneJson, JSON.stringify(b), "utf-8");
      }
      newIds.set(key, nid);
      (kind === "Bones" ? created.bones : created.skins).push(nid);
    }
    const dest = path.join(base, String(nid));
    for (const ext of [".png", ".webp"]) fs.rmSync(path.join(dest, index + ext), { force: true });
    fs.writeFileSync(path.join(dest, index + ".png"), await toPng(atlas)); // PNG: the atelier previews a skeleton by its 0.png
  }
  const bone = newIds.get(`Bones/${m[1]}`) ?? Number(m[1]);
  const skins = m[2].split(",").filter(Boolean).map((s) => String(newIds.get(`Skins/${s}`) ?? s)).join(",");
  return { look: info.look.replace(LOOK, `{${bone}|${skins}`), ...created };
}
