// Typed client of the atelier API. Writes carry the `x-atelier` header the server requires.
import type { Problem } from "../../core/problems";
import type { RangeMap } from "../../core/ranges";
import type { AssetInfo, Category, ImportResult } from "../../core/assets";
import type { ItemInput, ItemRow, SetRow, TextRow } from "../../core/editors";
import type { EffectInput, SpellInput, SpellRow } from "../../core/editors_spells";
import type { WorldDetail, WorldSummary } from "../../core/store";

export type { EffectInput, SpellInput, SpellRow, ItemInput, ItemRow, SetRow, TextRow, AssetInfo, Category, ImportResult, Problem, RangeMap, WorldDetail, WorldSummary };
export { CATEGORY_LABELS } from "./categories";

export type DataKind = "texts" | "items" | "sets" | "spells";

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
  assetUrl: (id: string, cat: Category, assetId: number) => `/api/worlds/${id}/assets/${cat}/${assetId}.png`,
};

export const toBase64 = (file: File): Promise<string> =>
  new Promise((resolve, reject) => {
    const r = new FileReader();
    r.onload = () => resolve(String(r.result).split(",")[1] ?? "");
    r.onerror = () => reject(new Error(`lecture de ${file.name} impossible`));
    r.readAsDataURL(file);
  });
