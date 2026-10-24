// npm start : the atelier on http://127.0.0.1:5174 (ATELIER_PORT to change it).
import path from "node:path";
import { fileURLToPath } from "node:url";
import { WorldStore } from "../core/store";
import { startServer } from "./server";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "..");
const worlds = process.env.ATELIER_WORLDS ?? path.resolve(root, "..", "game", "worlds");
const port = Number(process.env.ATELIER_PORT ?? 5174);
const store = new WorldStore(worlds, path.join(root, "world_ranges.json"), path.join(root, "templates"));
await startServer(store, path.join(root, "web", "dist"), port);
console.log(`Atelier de mondes : http://127.0.0.1:${port}  (mondes : ${worlds})`);
