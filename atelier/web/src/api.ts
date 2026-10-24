// Typed client of the atelier API. Writes carry the `x-atelier` header the server requires.
import type { Problem } from "../../core/problems";
import type { RangeMap } from "../../core/ranges";
import type { WorldDetail, WorldSummary } from "../../core/store";

export type { Problem, RangeMap, WorldDetail, WorldSummary };

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
};
