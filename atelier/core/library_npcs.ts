// The Dofus NPCs (game/data/tables/npcs.json, names from the client's texts) as templates: name and look come along;
// the dialogue, shop and place do not, since they would point at things that are not in the new world.
import fs from "node:fs";
import { AtelierError } from "./errors";
import { readI18n } from "./dofus_text";

export interface NpcTemplate { source: number; name: string; bone: number; size: number }
export const NPC_TEMPLATE_LIMIT = 30;
const fold = (s: string) => s.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();

interface Row { id: number; name: string; key: string; bone: number; size: number }
let cache: { file: string; rows: Row[] } | null = null;

/** "{954}" or "{954|||120}": the look of a NPC. */
const parseLook = (s: unknown) => { const [b, , , size] = String(s ?? "").replace(/[{}]/g, "").split("|"); return { bone: Number(b) || 0, size: Number(size) || 100 }; };

function rowsOf(npcsFile: string, i18nFile: string): Row[] {
  if (cache?.file === npcsFile) return cache.rows;
  if (!fs.existsSync(npcsFile) || !fs.existsSync(i18nFile)) throw new AtelierError(404, "les PNJ du jeu ne sont pas sur cet ordinateur (game/data et game/content)");
  const text = readI18n(i18nFile);
  const data = JSON.parse(fs.readFileSync(npcsFile, "utf-8")) as { objectsById: Record<string, { nameId: number; look: string }> };
  const rows: Row[] = [];
  for (const [id, n] of Object.entries(data.objectsById)) {
    const name = text(n.nameId);
    const { bone, size } = parseLook(n.look);
    if (name && bone > 0) rows.push({ id: Number(id), name, key: fold(name), bone, size });
  }
  cache = { file: npcsFile, rows };
  return rows;
}

export function searchDofusNpcs(npcsFile: string, i18nFile: string, query: string): NpcTemplate[] {
  const q = fold(query.trim());
  if (q.length < 2) throw new AtelierError(400, "recherche : au moins 2 caractères (un nom de PNJ, ou un numéro)");
  const byNumber = /^\d+$/.test(q);
  const hits = rowsOf(npcsFile, i18nFile).filter((r) => (byNumber ? String(r.id) === q : r.key.includes(q)));
  hits.sort((a, b) => (a.key.startsWith(q) === b.key.startsWith(q) ? a.name.localeCompare(b.name) : a.key.startsWith(q) ? -1 : 1));
  return hits.slice(0, NPC_TEMPLATE_LIMIT).map((r) => ({ source: r.id, name: r.name, bone: r.bone, size: Math.max(20, Math.min(400, r.size)) }));
}
