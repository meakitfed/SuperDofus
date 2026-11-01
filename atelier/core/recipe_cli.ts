// npm run recipe -- <recette.json> [--force]   (builds game/worlds/<id> from the recipe; exit 1 on errors)
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { buildRecipe, type Recipe } from "./recipe";
import { WorldStore } from "./store";

const args = process.argv.slice(2);
const file = args.find((a) => !a.startsWith("--"));
if (!file) {
  console.error("usage : npm run recipe -- <recette.json> [--force]");
  process.exit(2);
}
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const worlds = process.env.ATELIER_WORLDS ?? path.resolve(root, "..", "game", "worlds");
const store = new WorldStore(worlds, path.join(root, "world_ranges.json"), path.join(root, "templates"));
const recipe = JSON.parse(fs.readFileSync(file, "utf-8")) as Recipe;
try {
  const r = buildRecipe(store, recipe, { force: args.includes("--force") });
  r.floors.forEach((f, i) => console.log(`étage ${i + 1} : ${f.maps.length} maps, arrivée map ${f.hub} case ${f.arrive_cell}, gardien ${f.npc} case ${f.npc_cell}`));
  const errors = r.problems.filter((p) => p.severity === "error");
  console.log(`${errors.length} erreur(s), ${r.problems.length - errors.length} avertissement(s)`);
  for (const p of r.problems) console.log(` - [${p.code}] ${p.message}`);
  process.exit(errors.length ? 1 : 0);
} catch (e) {
  console.error((e as Error).message);
  process.exit(1);
}
