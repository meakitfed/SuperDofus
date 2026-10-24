// NPC editor: placement on a map, look, shop, bank, and the dialogue tree. An NPC occupies its cell (the
// editor blocks it, like the generated worlds do). A dialogue never offers an action its NPC cannot perform
// (a shop reply needs a shop, a bank reply needs a banker) and never points at a node, map or item that is gone.
import { AtelierError } from "./errors";
import type { World } from "./io";
import { addText } from "./editors";
import { validCell } from "./grid";
import { nextId, type RangeMap } from "./ranges";
import { criteriaRefs } from "./rules_story";
import { textUsages, type Ref } from "./usage";

export interface NpcInput {
  map: number;
  cell: number;
  /** facing, 0..7 */
  dir: number;
  name: string;
  bone: number;
  size: number;
  banker: boolean;
  /** item ids sold, or null for no shop */
  shop: number[] | null;
}

export interface NpcRow extends NpcInput {
  id: number;
  hasDialog: boolean;
  usedBy: Ref[];
}

export type ReplyAction =
  | { type: "shop" }
  | { type: "bank" }
  | { type: "teleport"; map: number; cell: number }
  | { type: "give_item"; item: number; qty: number };

export interface ReplyInput { id?: number; text: string; next?: string | null; criteria?: string; action?: ReplyAction }
export interface DialogInput { start: string; nodes: Record<string, { text: string; replies: ReplyInput[] }> }

type Raw = Record<string, any>;
const bad = (m: string) => new AtelierError(400, m);
const npcLists = (w: World) => w.files.npcs.maps as Record<string, Raw[]>;
const mapRaw = (w: World, id: number) => w.maps.get(id) as Raw | undefined;

const parseLook = (look: string | undefined) => {
  const [b, , , s] = (look ?? "{0|||100}").replace(/[{}]/g, "").split("|");
  return { bone: Number(b) || 0, size: Number(s) || 100 };
};

function locate(w: World, id: number): [string, Raw] | undefined {
  for (const [mid, l] of Object.entries(npcLists(w))) { const n = l.find((x) => x.npc === id); if (n) return [mid, n]; }
  return undefined;
}

/** npc id -> who needs it. */
export function npcUsages(w: World): Map<number, Ref[]> {
  const out = new Map<number, Ref[]>();
  const add = (n: number, r: Ref) => { const l = out.get(n) ?? []; l.push(r); out.set(n, l); };
  for (const [qid, q] of Object.entries(w.files.quests.quests)) {
    add(q.start.npc, { kind: "quest", id: qid });
    for (const st of q.steps) for (const o of st.objectives) if ([1, 9, 3].includes(o.type)) add(o.params[0], { kind: "quest", id: qid });
  }
  return out;
}

export function listNpcs(w: World): NpcRow[] {
  const used = npcUsages(w);
  const out: NpcRow[] = [];
  for (const [mid, l] of Object.entries(npcLists(w)))
    for (const n of l) {
      const { bone, size } = parseLook(n.look);
      out.push({
        id: n.npc, map: Number(mid), cell: n.cell, dir: n.dir ?? 3, name: w.files.texts[String(n.name_id)] ?? "", bone, size,
        banker: ((w.files.bank as Raw | undefined)?.bankers ?? []).includes(n.npc), shop: (w.files.shops.shops as Raw)[String(n.npc)]?.items ?? null,
        hasDialog: String(n.npc) in w.files.dialogs.dialogs, usedBy: used.get(n.npc) ?? [],
      });
    }
  return out.sort((a, b) => a.id - b.id);
}

function check(w: World, i: NpcInput, self?: number) {
  const name = typeof i.name === "string" ? i.name.trim() : "";
  if (!name) throw bad("nom : valeur vide");
  if (name.length > 60) throw bad("nom : 60 caractères au maximum");
  const map = mapRaw(w, i.map);
  if (!map) throw bad(`map ${i.map} inconnue`);
  if (!validCell(i.cell)) throw bad(`cellule ${i.cell} hors de la grille`);
  if (!Number.isInteger(i.dir) || i.dir < 0 || i.dir > 7) throw bad("orientation : entier entre 0 et 7 attendu");
  if (!Number.isInteger(i.bone) || i.bone < 1) throw bad("squelette : requis");
  if (!Number.isInteger(i.size) || i.size < 20 || i.size > 400) throw bad("taille : entier entre 20 et 400 attendu");
  const occupied = [...(npcLists(w)[String(i.map)] ?? []).filter((n) => n.npc !== self).map((n) => n.cell), ...(w.files.interactives.maps[String(i.map)] ?? []).map((e) => e.cell)];
  if (occupied.includes(i.cell)) throw new AtelierError(409, `la cellule ${i.cell} est déjà occupée`);
  if ((map.triggers ?? []).some((t: Raw) => t.cell === i.cell)) throw new AtelierError(409, `la cellule ${i.cell} est une porte`);
  if (w.files.world.start_map === i.map && w.files.world.start_cell === i.cell) throw new AtelierError(409, "la cellule de départ du monde ne peut pas porter un PNJ");
  if (map.phoenix === i.cell) throw new AtelierError(409, "la cellule de renaissance ne peut pas porter un PNJ");
  const itemIds = new Set(w.files.items.items.map((x) => x.id));
  let shop: number[] | null = null;
  if (i.shop !== null) {
    if (!Array.isArray(i.shop) || i.shop.length < 1 || i.shop.length > 60) throw bad("boutique : 1 à 60 objets");
    for (const it of i.shop) if (!itemIds.has(it)) throw bad(`boutique : objet ${it} inconnu`);
    shop = [...new Set(i.shop)];
  }
  return { name, shop };
}

function placeAt(w: World, id: number, i: NpcInput, entry: Raw): void {
  const m = mapRaw(w, i.map)!;
  // the NPC occupies its cell, as in the generated worlds
  for (const k of ["blocked", "fight_blocked"]) if (Array.isArray(m[k]) && !m[k].includes(i.cell)) m[k] = [...m[k], i.cell].sort((a: number, b: number) => a - b);
  for (const side of ["red", "blue"]) if (m.placement?.[side]) m.placement[side] = m.placement[side].filter((c: number) => c !== i.cell);
  Object.assign(entry, { npc: id, cell: i.cell, dir: i.dir, look: `{${i.bone}|||${i.size}}` });
}

function setBanker(w: World, id: number, on: boolean): void {
  const bank = ((w.files as Raw).bank ??= { bankers: [], placed: {} }) as Raw;
  bank.bankers = (bank.bankers as number[]).filter((b) => b !== id);
  if (on) bank.bankers.push(id);
}

function setShop(w: World, id: number, shop: number[] | null): void {
  const shops = w.files.shops.shops as Raw;
  if (shop) shops[String(id)] = { ...(shops[String(id)] ?? {}), items: shop }; else delete shops[String(id)];
}

export function createNpc(w: World, ranges: RangeMap, input: NpcInput): number {
  const v = check(w, input);
  const id = nextId(w, "npc", ranges.npc);
  const entry: Raw = { npc: id, name_id: addText(w, ranges, v.name) };
  placeAt(w, id, input, entry);
  (npcLists(w)[String(input.map)] ??= []).push(entry);
  setShop(w, id, v.shop);
  setBanker(w, id, input.banker);
  return id;
}

export function updateNpc(w: World, ranges: RangeMap, id: number, input: NpcInput): void {
  const at = locate(w, id);
  if (!at) throw new AtelierError(404, `PNJ ${id} inconnu`);
  const v = check(w, input, id);
  const tree = w.files.dialogs.dialogs[String(id)];
  const actions = tree ? Object.values(tree.nodes).flatMap((n) => n.replies.map((r) => (r.action as Raw | undefined)?.type)) : [];
  if (actions.includes("shop") && !v.shop) throw new AtelierError(409, "le dialogue propose la boutique : retire cette réponse avant de supprimer la boutique");
  if (actions.includes("bank") && !input.banker) throw new AtelierError(409, "le dialogue propose la banque : retire cette réponse avant");
  const [oldMap, entry] = at;
  if (String(input.map) !== oldMap) {
    npcLists(w)[oldMap] = npcLists(w)[oldMap].filter((n) => n !== entry);
    if (!npcLists(w)[oldMap].length) delete npcLists(w)[oldMap];
    (npcLists(w)[String(input.map)] ??= []).push(entry);
  }
  const nameKey = String(entry.name_id);
  if (entry.name_id && nameKey in w.files.texts) w.files.texts[nameKey] = v.name; else entry.name_id = addText(w, ranges, v.name);
  placeAt(w, id, input, entry);
  setShop(w, id, v.shop);
  setBanker(w, id, input.banker);
}

export function deleteNpc(w: World, id: number): void {
  const at = locate(w, id);
  if (!at) throw new AtelierError(404, `PNJ ${id} inconnu`);
  const refs = npcUsages(w).get(id) ?? [];
  if (refs.length) throw new AtelierError(409, `PNJ ${id} utilisé par ${refs.slice(0, 3).map((r) => `${r.kind} ${r.id}`).join(", ")} : retire d'abord ces références`);
  const [mid, entry] = at;
  npcLists(w)[mid] = npcLists(w)[mid].filter((n) => n !== entry);
  if (!npcLists(w)[mid].length) delete npcLists(w)[mid];
  delete w.files.dialogs.dialogs[String(id)];
  setShop(w, id, null);
  setBanker(w, id, false);
  if (entry.name_id && !textUsages(w).get(entry.name_id)?.length) delete w.files.texts[String(entry.name_id)];
}

// ---- dialogue ----
export function getDialog(w: World, npc: number): DialogInput | null {
  const t = w.files.dialogs.dialogs[String(npc)];
  return t ? (structuredClone(t) as unknown as DialogInput) : null;
}

const KEY = /^[a-z0-9_]{1,24}$/;
const CRIT = /^[A-Za-z]{1,3}=[\w.,-]{1,40}$/;

function checkDialog(w: World, npc: number, d: DialogInput) {
  const entries = Object.entries(d?.nodes ?? {});
  if (entries.length < 1 || entries.length > 60) throw bad("1 à 60 nœuds attendus");
  if (!(d.start in d.nodes)) throw bad(`nœud de départ « ${d.start} » absent`);
  const row = listNpcs(w).find((n) => n.id === npc)!;
  const itemIds = new Set(w.files.items.items.map((x) => x.id));
  const questIds = new Set(Object.values(w.files.quests.quests).map((q) => q.id));
  const nodes: Record<string, { text: string; replies: Raw[] }> = {};
  let nextReply = 1 + Math.max(0, ...entries.flatMap(([, n]) => n.replies.map((r) => r.id ?? 0)));
  for (const [key, node] of entries) {
    if (!KEY.test(key)) throw bad(`nœud « ${key} » : minuscules, chiffres et _ (24 caractères maximum)`);
    const text = typeof node.text === "string" ? node.text.trim() : "";
    if (!text || text.length > 1500) throw bad(`nœud « ${key} » : texte de 1 à 1500 caractères`);
    if (node.replies.length > 8) throw bad(`nœud « ${key} » : 8 réponses au maximum`);
    const used = new Set<number>();
    const replies = node.replies.map((r) => {
      const rt = typeof r.text === "string" ? r.text.trim() : "";
      if (!rt || rt.length > 300) throw bad(`nœud « ${key} » : une réponse de 1 à 300 caractères est attendue`);
      if (r.next && !(r.next in d.nodes)) throw bad(`nœud « ${key} » : la réponse « ${rt} » mène au nœud inconnu « ${r.next} »`);
      const out: Raw = { id: r.id && !used.has(r.id) ? r.id : nextReply++, text: rt };
      used.add(out.id);
      if (r.next) out.next = r.next;
      const crit = r.criteria?.trim();
      if (crit) {
        for (const part of crit.replace(/\|/g, "&").split("&")) if (!CRIT.test(part.trim())) throw bad(`critère « ${part} » invalide (ex. Qf=930001&PO=9100001)`);
        for (const [k, v] of criteriaRefs(crit)) {
          if (k === "Qf" && !questIds.has(v)) throw bad(`critère : quête ${v} inconnue`);
          if (k === "PO" && !itemIds.has(v)) throw bad(`critère : objet ${v} inconnu`);
        }
        out.criteria = crit;
      }
      const a = r.action;
      if (a) {
        if (a.type === "shop") { if (!row.shop) throw bad(`« ${rt} » ouvre la boutique, mais ce PNJ n'en a pas`); out.action = { type: "shop" }; }
        else if (a.type === "bank") { if (!row.banker) throw bad(`« ${rt} » ouvre la banque, mais ce PNJ n'est pas banquier`); out.action = { type: "bank" }; }
        else if (a.type === "teleport") {
          const target = mapRaw(w, a.map);
          if (!target) throw bad(`« ${rt} » : map ${a.map} inconnue`);
          if (!validCell(a.cell) || (target.blocked as number[]).includes(a.cell)) throw bad(`« ${rt} » : cellule d'arrivée ${a.cell} invalide ou bloquée`);
          out.action = { type: "teleport", map: a.map, cell: a.cell };
        } else if (a.type === "give_item") {
          if (!itemIds.has(a.item)) throw bad(`« ${rt} » : objet ${a.item} inconnu`);
          if (!Number.isInteger(a.qty) || a.qty < 1 || a.qty > 999) throw bad(`« ${rt} » : quantité entre 1 et 999`);
          out.action = { type: "give_item", item: a.item, qty: a.qty };
        } else throw bad(`« ${rt} » : action « ${(a as Raw).type} » inconnue`);
      }
      return out;
    });
    nodes[key] = { text, replies };
  }
  return { start: d.start, nodes };
}

export function setDialog(w: World, npc: number, d: DialogInput): void {
  if (!locate(w, npc)) throw new AtelierError(404, `PNJ ${npc} inconnu`);
  const clean = checkDialog(w, npc, d);
  const cur = (w.files.dialogs.dialogs as Raw)[String(npc)];
  (w.files.dialogs.dialogs as Raw)[String(npc)] = { ...(cur ?? {}), ...clean };
}

export function deleteDialog(w: World, npc: number): void {
  if (!(String(npc) in w.files.dialogs.dialogs)) throw new AtelierError(404, `le PNJ ${npc} n'a pas de dialogue`);
  delete w.files.dialogs.dialogs[String(npc)];
}
