// Image helpers of the AI studio: the generator works on opaque images over a white background; icons and decor
// need a transparent background cut tight around the drawing.
import sharp from "sharp";
import type { Raw } from "./reskin";

/** The image over white, fitted inside width x height (centred), as the PNG the generator receives. */
export async function onWhite(img: Buffer, width: number, height: number): Promise<Buffer> {
  const fitted = await sharp(img).resize(width, height, { fit: "contain", background: { r: 255, g: 255, b: 255, alpha: 0 }, kernel: "lanczos3" }).png().toBuffer();
  return sharp({ create: { width, height, channels: 4, background: { r: 255, g: 255, b: 255, alpha: 1 } } }).composite([{ input: fitted }]).flatten({ background: "#ffffff" }).png().toBuffer();
}

/**
 * Clears the background: every pixel connected to the border whose colour is close to the border colour (the
 * generator's plain background) becomes transparent; pixels just a little further get a partial alpha (soft edge).
 */
export function clearBackground(img: Raw, tolerance = 28): Raw {
  const { width: W, height: H } = img;
  const d = new Uint8Array(img.data);
  // background colour = median of the border pixels
  const border: number[][] = [];
  for (let x = 0; x < W; x++) border.push([x, 0], [x, H - 1]);
  for (let y = 0; y < H; y++) border.push([0, y], [W - 1, y]);
  const med = [0, 1, 2].map((c) => { const v = border.map(([x, y]) => d[(y * W + x) * 4 + c]).sort((a, b) => a - b); return v[v.length >> 1]; });
  const dist = (k: number) => Math.max(Math.abs(d[k * 4] - med[0]), Math.abs(d[k * 4 + 1] - med[1]), Math.abs(d[k * 4 + 2] - med[2]));
  const seen = new Uint8Array(W * H);
  let queue: number[] = [];
  for (const [x, y] of border) { const k = y * W + x; if (!seen[k] && dist(k) <= tolerance) { seen[k] = 1; queue.push(k); } }
  while (queue.length) {
    const next: number[] = [];
    for (const k of queue) {
      d[k * 4 + 3] = 0;
      const x = k % W, y = (k - x) / W;
      for (const [X, Y] of [[x + 1, y], [x - 1, y], [x, y + 1], [x, y - 1]]) {
        if (X < 0 || Y < 0 || X >= W || Y >= H) continue;
        const j = Y * W + X;
        if (seen[j]) continue;
        const e = dist(j);
        if (e <= tolerance) { seen[j] = 1; next.push(j); }
        else if (e <= tolerance * 2.5) { seen[j] = 2; d[j * 4 + 3] = Math.min(d[j * 4 + 3], Math.round(255 * (e - tolerance) / (tolerance * 1.5))); }
      }
    }
    queue = next;
  }
  return { width: W, height: H, data: d };
}

/** The opaque part's bounding box, or null when everything is transparent. */
export function opaqueBox(img: Raw): { left: number; top: number; width: number; height: number } | null {
  let x0 = img.width, y0 = img.height, x1 = -1, y1 = -1;
  for (let y = 0; y < img.height; y++) for (let x = 0; x < img.width; x++) {
    if (img.data[(y * img.width + x) * 4 + 3] > 8) { x0 = Math.min(x0, x); x1 = Math.max(x1, x); y0 = Math.min(y0, y); y1 = Math.max(y1, y); }
  }
  return x1 < 0 ? null : { left: x0, top: y0, width: x1 - x0 + 1, height: y1 - y0 + 1 };
}

/** Generated image -> transparent PNG cut around the drawing, fitted inside `max` px (square icons are padded square). */
export async function cutOut(png: Buffer, max: number, square: boolean): Promise<Buffer> {
  const { data, info } = await sharp(png).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  const raw = clearBackground({ width: info.width, height: info.height, data: new Uint8Array(data) });
  const box = opaqueBox(raw) ?? { left: 0, top: 0, width: info.width, height: info.height };
  let img = sharp(Buffer.from(raw.data), { raw: { width: info.width, height: info.height, channels: 4 } }).extract(box);
  if (square) {
    const side = Math.max(box.width, box.height);
    img = sharp(await img.png().toBuffer()).resize(side, side, { fit: "contain", background: { r: 0, g: 0, b: 0, alpha: 0 } });
  }
  return sharp(await img.png().toBuffer()).resize(max, max, { fit: "inside", withoutEnlargement: true, kernel: "lanczos3" }).png().toBuffer();
}
