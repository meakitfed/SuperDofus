// Typed client of the atelier API. Writes carry the `x-atelier` header the server requires.
import type { Problem } from "../../core/problems";
import type { RangeMap } from "../../core/ranges";
import type { AssetInfo, Category, ImportResult } from "../../core/assets";
import type { ItemInput, ItemRow, SetRow, TextRow } from "../../core/editors";
import type { EffectInput, SpellInput, SpellRow } from "../../core/editors_spells";
import type { GradeInput, MonsterInput, MonsterRow, ZoneRow } from "../../core/editors_monsters";
import type { ClassInput, ClassRow } from "../../core/editors_classes";
import type { Check } from "../../core/playable";
import type { VisualRow } from "../../core/editors_visual";
import type { Workflow } from "../../core/workflows";
import type { GameCheck } from "../../core/gamecheck";
import type { ObjectiveInput, QuestInput, QuestRow, StepInput } from "../../core/editors_quests";
import type { DialogInput, NpcInput, NpcRow, ReplyInput } from "../../core/editors_npcs";
import type { MapInput, MapRow } from "../../core/editors_maps";
import type { BoneLibrary } from "../../core/bones";
import type { WorldDetail, WorldSummary } from "../../core/store";

export type { Check, ObjectiveInput, QuestInput, QuestRow, StepInput, DialogInput, NpcInput, NpcRow, ReplyInput, MapInput, MapRow, ClassInput, ClassRow, BoneLibrary, GradeInput, MonsterInput, MonsterRow, ZoneRow, EffectInput, SpellInput, SpellRow, ItemInput, ItemRow, SetRow, TextRow, AssetInfo, Category, ImportResult, Problem, RangeMap, WorldDetail, WorldSummary };
export { CATEGORY_LABELS } from "./categories";

export type DataKind = "texts" | "items" | "sets" | "spells" | "monsters" | "zones" | "classes" | "maps" | "npcs" | "dialogs" | "quests" | "visuals";

export class ApiError extends Error {
  constructor(public status: number, message: string) { super(message); }
}

async function call<T>(method: string, url: string, body?: unknown): Promise<T> {
  const r = await fetch(url, {
    method,
    headers: method === "GET" ? undefined : { "content-type": "application/json", "x-atelier": "1" },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const data = await r.json().catch(() => ({}));
  if (!r.ok && !(r.status === 409 && "summary" in data)) throw new ApiError(r.status, data.error ?? `erreur ${r.status}`);
  return data as T;
}

export const api = {
  list: () => call<WorldSummary[]>("GET", "/api/worlds"),
  detail: (id: string) => call<WorldDetail>("GET", `/api/worlds/${id}`),
  create: (id: string, name: string) => call<WorldSummary>("POST", "/api/worlds", { id, name }),
  clone: (id: string, newId: string, name: string) => call<WorldSummary>("POST", `/api/worlds/${id}/clone`, { id: newId, name }),
  importWorld: (zip: string, id: string, name: string) => call<WorldSummary>("POST", "/api/import", { zip, id, name }),
  exportUrl: (id: string) => `/api/worlds/${id}/export`,
  rename: (id: string, name: string) => call<WorldDetail>("POST", `/api/worlds/${id}/rename`, { name }),
  undo: (id: string) => call<WorldDetail>("POST", `/api/worlds/${id}/undo`, {}),
  redo: (id: string) => call<WorldDetail>("POST", `/api/worlds/${id}/redo`, {}),
  reload: (id: string) => call<WorldDetail>("POST", `/api/worlds/${id}/reload`, {}),
  remove: (id: string, confirm: string) => call<{ ok: true }>("DELETE", `/api/worlds/${id}`, { confirm }),
  assets: (id: string, cat: Category) => call<AssetInfo[]>("GET", `/api/worlds/${id}/assets/${cat}`),
  importAssets: (id: string, cat: Category, body: { files?: { name: string; data: string }[]; zip?: string }) =>
    call<ImportResult[]>("POST", `/api/worlds/${id}/assets/${cat}`, body),
  removeAsset: (id: string, cat: Category, assetId: number) => call<{ ok: true }>("DELETE", `/api/worlds/${id}/assets/${cat}/${assetId}.png`),
  rows: <T,>(id: string, kind: DataKind) => call<T[]>("GET", `/api/worlds/${id}/data/${kind}`),
  addRow: (id: string, kind: DataKind, body: unknown) => call<{ id: number }>("POST", `/api/worlds/${id}/data/${kind}`, body),
  setRow: (id: string, kind: DataKind, row: number, body: unknown) => call<{ ok: true }>("PUT", `/api/worlds/${id}/data/${kind}/${row}`, body),
  delRow: (id: string, kind: DataKind, row: number) => call<{ ok: true }>("DELETE", `/api/worlds/${id}/data/${kind}/${row}`, {}),
  report: (id: string) => call<Check[]>("GET", `/api/worlds/${id}/report`),
  workflows: (id: string) => call<Workflow[]>("GET", `/api/worlds/${id}/workflows`),
  gameCheck: (id: string) => call<GameCheck>("POST", `/api/worlds/${id}/gamecheck`, {}),
  visual: (id: string, map: number) => call<VisualRow>("GET", `/api/worlds/${id}/data/visuals/${map}`),
  dialog: (id: string, npc: number) => call<DialogInput | null>("GET", `/api/worlds/${id}/data/dialogs/${npc}`),
  bones: (id: string) => call<BoneLibrary>("GET", `/api/worlds/${id}/bones`),
  importBone: (id: string, from: string, boneId: number) => call<BoneLibrary>("POST", `/api/worlds/${id}/bones`, { from, id: boneId }),
  boneUrl: (id: string, boneId: number, from?: string) => `/api/worlds/${id}/bones/${boneId}.png${from ? `?from=${from}` : ""}`,
  assetUrl: (id: string, cat: Category, assetId: number) => `/api/worlds/${id}/assets/${cat}/${assetId}.png`,
};

export const toBase64 = (file: File): Promise<string> =>
  new Promise((resolve, reject) => {
    const r = new FileReader();
    r.onload = () => resolve(String(r.result).split(",")[1] ?? "");
    r.onerror = () => reject(new Error(`lecture de ${file.name} impossible`));
    r.readAsDataURL(file);
  });
