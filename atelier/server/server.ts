// Local HTTP server of the atelier: JSON API under /api, the built web app everywhere else.
// Listens on 127.0.0.1 only. Every write needs the `x-atelier: 1` header and a JSON body: a page on another
// site cannot send that header without a CORS preflight, which this server never grants.
import fs from "node:fs";
import http from "node:http";
import path from "node:path";
import { AtelierError, WorldStore } from "../core/store";

const MIME: Record<string, string> = {
  ".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8", ".css": "text/css; charset=utf-8",
  ".svg": "image/svg+xml", ".png": "image/png", ".json": "application/json; charset=utf-8", ".ico": "image/x-icon",
};

const send = (res: http.ServerResponse, status: number, body: unknown) => {
  res.writeHead(status, { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" });
  res.end(JSON.stringify(body));
};

async function readBody(req: http.IncomingMessage, limit = 1_000_000): Promise<any> {
  const chunks: Buffer[] = [];
  let size = 0;
  for await (const c of req) {
    size += (c as Buffer).length;
    if (size > limit) throw new AtelierError(413, "requête trop grande");
    chunks.push(c as Buffer);
  }
  if (!chunks.length) return {};
  try { return JSON.parse(Buffer.concat(chunks).toString("utf-8")); } catch { throw new AtelierError(400, "JSON invalide"); }
}

export function handler(store: WorldStore, webDir: string) {
  return async (req: http.IncomingMessage, res: http.ServerResponse) => {
    try {
      const host = (req.headers.host ?? "").replace(/:\d+$/, "");
      if (host !== "127.0.0.1" && host !== "localhost") throw new AtelierError(403, "hôte refusé");
      const url = new URL(req.url ?? "/", "http://localhost");
      const method = req.method ?? "GET";
      if (!url.pathname.startsWith("/api/")) return serveStatic(res, webDir, url.pathname);
      if (method !== "GET") {
        if (req.headers["x-atelier"] !== "1" || !String(req.headers["content-type"] ?? "").startsWith("application/json"))
          throw new AtelierError(403, "en-tête x-atelier et JSON requis");
      }
      const parts = url.pathname.split("/").filter(Boolean).slice(1).map(decodeURIComponent); // after "api"
      const [root, id, action] = parts;
      if (root !== "worlds") throw new AtelierError(404, "route inconnue");

      if (id && action === "data") return await dataRoute(store, req, res, method, id, parts.slice(3));
      if (id && action === "assets") return await assetRoute(store, req, res, method, id, parts.slice(3));
      if (!id) {
        if (method === "GET") return send(res, 200, store.list());
        if (method === "POST") {
          const b = await readBody(req);
          return send(res, 201, store.create(String(b.id ?? ""), String(b.name ?? "")));
        }
      } else if (!action) {
        if (method === "GET") return send(res, 200, store.detail(id));
        if (method === "DELETE") {
          const b = await readBody(req);
          store.remove(id, String(b.confirm ?? ""));
          return send(res, 200, { ok: true });
        }
      } else if (method === "POST") {
        if (action === "rename") { store.rename(id, String((await readBody(req)).name ?? "")); return send(res, 200, store.detail(id)); }
        if (action === "reload") { store.reload(id); return send(res, 200, store.detail(id)); }
        if (action === "undo") { const ok = store.undo(id); return send(res, ok ? 200 : 409, store.detail(id)); }
        if (action === "redo") { const ok = store.redo(id); return send(res, ok ? 200 : 409, store.detail(id)); }
      }
      throw new AtelierError(404, "route inconnue");
    } catch (e) {
      if (e instanceof AtelierError) return send(res, e.status, { error: e.message });
      console.error(e);
      send(res, 500, { error: (e as Error).message });
    }
  };
}

/** /api/worlds/:id/data/<texts|items|sets>[/<rowId>] */
async function dataRoute(store: WorldStore, req: http.IncomingMessage, res: http.ServerResponse, method: string, id: string, rest: string[]) {
  const [kind, row] = rest;
  if (!kind) throw new AtelierError(404, "route inconnue");
  if (!row) {
    if (method === "GET") return send(res, 200, store.rowsOf(id, kind));
    if (method === "POST") return send(res, 201, { id: store.dataCreate(id, kind, await readBody(req)) });
  } else if (/^\d{1,12}$/.test(row)) {
    if (method === "PUT") { store.dataUpdate(id, kind, Number(row), await readBody(req)); return send(res, 200, { ok: true }); }
    if (method === "DELETE") { store.dataDelete(id, kind, Number(row)); return send(res, 200, { ok: true }); }
  }
  throw new AtelierError(404, "route inconnue");
}

const UPLOAD_LIMIT = 120 * 1024 * 1024;
const b64 = (v: unknown, what: string): Buffer => {
  if (typeof v !== "string") throw new AtelierError(400, `${what} : données manquantes`);
  return Buffer.from(v, "base64");
};

/** /api/worlds/:id/assets/<category>[/<assetId>.png] */
async function assetRoute(store: WorldStore, req: http.IncomingMessage, res: http.ServerResponse, method: string, id: string, rest: string[]) {
  const [cat, file] = rest;
  if (!cat) throw new AtelierError(404, "route inconnue");
  if (!file) {
    if (method === "GET") return send(res, 200, await store.assets(id, cat));
    if (method === "POST") {
      const b = await readBody(req, UPLOAD_LIMIT);
      const files = Array.isArray(b.files) ? b.files.map((f: any) => ({ name: String(f?.name ?? "image"), data: b64(f?.data, String(f?.name)) })) : [];
      const zip = b.zip === undefined ? undefined : b64(b.zip, "archive");
      return send(res, 200, await store.importAssets(id, cat, { files, zip }));
    }
  } else {
    const m = /^(\d{1,12})\.png$/.exec(file);
    if (!m) throw new AtelierError(404, "route inconnue");
    if (method === "GET") {
      const p = store.assetPath(id, cat, Number(m[1]));
      res.writeHead(200, { "content-type": "image/png", "cache-control": "no-cache" });
      return fs.createReadStream(p).pipe(res);
    }
    if (method === "DELETE") { store.removeAsset(id, cat, Number(m[1])); return send(res, 200, { ok: true }); }
  }
  throw new AtelierError(404, "route inconnue");
}

function serveStatic(res: http.ServerResponse, webDir: string, pathname: string) {
  let rel = decodeURIComponent(pathname);
  if (rel === "/" || !path.extname(rel)) rel = "/index.html"; // single-page app: any route serves the shell
  const file = path.normalize(path.join(webDir, rel));
  if (!file.startsWith(path.normalize(webDir)) || !fs.existsSync(file)) {
    res.writeHead(404, { "content-type": "text/plain; charset=utf-8" });
    return res.end("introuvable (l'interface est-elle construite ? npm run build)");
  }
  res.writeHead(200, { "content-type": MIME[path.extname(file)] ?? "application/octet-stream" });
  fs.createReadStream(file).pipe(res);
}

export function startServer(store: WorldStore, webDir: string, port: number): Promise<http.Server> {
  return new Promise((resolve, reject) => {
    const server = http.createServer(handler(store, webDir));
    server.once("error", reject);
    server.listen(port, "127.0.0.1", () => resolve(server));
  });
}
