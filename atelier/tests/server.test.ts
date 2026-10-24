// The HTTP API end to end on a real socket (127.0.0.1, random port, temp worlds folder).
import fs from "node:fs";
import http from "node:http";
import os from "node:os";
import path from "node:path";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { WorldStore } from "../core/store";
import { startServer } from "../server/server";

let tmp: string, server: http.Server, base: string;
beforeAll(async () => {
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), "atelier-http-"));
  const web = path.join(tmp, "web");
  fs.mkdirSync(web);
  fs.writeFileSync(path.join(web, "index.html"), "<!doctype html><title>shell</title>");
  fs.mkdirSync(path.join(tmp, "worlds"));
  const store = new WorldStore(path.join(tmp, "worlds"), path.join(tmp, "r.json"), path.resolve(__dirname, "..", "templates"));
  server = await startServer(store, web, 0);
  base = `http://127.0.0.1:${(server.address() as any).port}`;
});
afterAll(() => { server.close(); fs.rmSync(tmp, { recursive: true, force: true }); });

const WRITE = { "content-type": "application/json", "x-atelier": "1" };
const call = (method: string, url: string, body?: unknown, headers: Record<string, string> = WRITE) =>
  fetch(base + url, { method, headers: method === "GET" ? undefined : headers, body: body === undefined ? undefined : JSON.stringify(body) });

const rawGet = (p: string, headers: Record<string, string> = {}) =>
  new Promise<number>((resolve) => {
    const port = (server.address() as any).port;
    http.get({ host: "127.0.0.1", port, path: p, headers }, (res) => { res.resume(); resolve(res.statusCode!); });
  });

describe("API", () => {
  it("crée, liste, détaille, renomme, annule, refait, supprime", async () => {
    let r = await call("POST", "/api/worlds", { id: "web_un", name: "Via le web" });
    expect(r.status).toBe(201);
    r = await call("GET", "/api/worlds");
    expect((await r.json()).map((w: any) => w.id)).toContain("web_un");
    r = await call("GET", "/api/worlds/web_un");
    const d = await r.json();
    expect(d.problems).toEqual([]);
    expect(d.counts.maps).toBe(1);
    r = await call("POST", "/api/worlds/web_un/rename", { name: "Renommé" });
    expect((await r.json()).summary.name).toBe("Renommé");
    r = await call("POST", "/api/worlds/web_un/undo", {});
    expect((await r.json()).summary.name).toBe("Via le web");
    r = await call("POST", "/api/worlds/web_un/undo", {});
    expect(r.status).toBe(409);
    r = await call("POST", "/api/worlds/web_un/redo", {});
    expect((await r.json()).summary.name).toBe("Renommé");
    r = await call("DELETE", "/api/worlds/web_un", { confirm: "non" });
    expect(r.status).toBe(400);
    r = await call("DELETE", "/api/worlds/web_un", { confirm: "web_un" });
    expect(r.status).toBe(200);
    expect(await (await call("GET", "/api/worlds")).json()).toEqual([]);
  });

  it("renvoie des erreurs lisibles", async () => {
    let r = await call("POST", "/api/worlds", { id: "Pas Bon", name: "x" });
    expect(r.status).toBe(400);
    expect((await r.json()).error).toMatch(/identifiant invalide/);
    r = await call("GET", "/api/worlds/inconnu");
    expect(r.status).toBe(404);
    r = await call("GET", "/api/nimportequoi");
    expect(r.status).toBe(404);
  });

  it("refuse une écriture sans l'en-tête x-atelier ou sans JSON (protection CSRF)", async () => {
    let r = await call("POST", "/api/worlds", { id: "csrf_a", name: "x" }, { "content-type": "application/json" });
    expect(r.status).toBe(403);
    r = await call("POST", "/api/worlds", { id: "csrf_a", name: "x" }, { "x-atelier": "1", "content-type": "text/plain" });
    expect(r.status).toBe(403);
    expect(fs.existsSync(path.join(tmp, "worlds", "csrf_a"))).toBe(false);
  });

  it("refuse un nom d'hôte étranger (DNS rebinding)", async () => {
    expect(await rawGet("/api/worlds", { host: "evil.example" })).toBe(403);
  });

  it("sert l'interface pour toute route, sans jamais sortir du dossier web", async () => {
    const r = await call("GET", "/mondes/abc");
    expect(await r.text()).toContain("<title>shell</title>");
    expect(await rawGet("/..%2f..%2fr")).toBe(200); // no extension -> the shell, never a file outside
    expect(await rawGet("/..%2f..%2fr.json")).toBe(404);
  });
});
