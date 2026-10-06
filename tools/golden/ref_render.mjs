// Reference render with PyDofus/d3-ts-renderer (headless-gl). Copied into the reference
// checkout by compare.py:
//   node ref_render.mjs <contentRoot> <look> <animFullName> <frames comma> <outPrefix> [boneName]
import { existsSync, readdirSync } from 'node:fs';
import { configure, decodeImage, createCanvas, saveToPng, DofusSprite, Look } from './dist/node.js';

const [root, lookStr, anim, frames, out, boneName] = process.argv.slice(2);
const base = root.endsWith('/') ? root : root + '/';
// the extractor writes PNG or lossless WebP (--webp / compact.py): detect which
const skinsDir = base + 'Content/Characters/Skins';
const sample = existsSync(skinsDir) ? readdirSync(skinsDir)[0] : undefined;
const ext = sample && existsSync(`${skinsDir}/${sample}/0.webp`) ? 'webp' : 'png';
configure({ strategy: 'fs', basePath: base, decodeImage, ImageExtension: ext });

const look = await Look.fromStringAsync(lookStr, true);
const canvas = createCanvas();
const sprite = await DofusSprite.create(look, canvas, { boneName: boneName || undefined });
const n = await sprite.prepareAnimation(anim, 2, true, false, true);
for (const f of frames.split(',').map(Number)) {
  sprite.renderFrame(f);
  await saveToPng(canvas, `${out}_${f}.png`);
}
console.log('frames', n);
