// npm run recipe -- <recette.json> [--force | --monsters]   (builds game/worlds/<id> from the recipe; --monsters only
// rewrites the monsters of the existing world; exit 1 on errors)
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { buildRecipe, rebuildMonsters, type Recipe } from "./recipe";
import type { MonstersResult } from "./recipe_monsters";
import { WorldStore } from "./store";

const args = process.argv.slice(2);
const file = args.find((a) => !a.startsWith("--"));
if (!file) {
  console.error("usage : npm run recipe -- <recette.json> [--force | --monsters]");
  process.exit(2);
}
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const worlds = process.env.ATELIER_WORLDS ?? path.resolve(root, "..", "game", "worlds");
const store = new WorldStore(worlds, path.join(root, "world_ranges.json"), path.join(root, "templates"));
const recipe = JSON.parse(fs.readFileSync(file, "utf-8")) as Recipe;
try {
  const showMonsters = (m?: MonstersResult) => {
    if (!m) return;
    m.floors.forEach((f, i) => console.log(`étage ${i + 1} : ${f.zones.map((z) => `anneau ${z.ring} niv. ${z.levels[0]}-${z.levels[1]} (${z.maps.length} maps, ${z.monsters} monstres, ${z.bosses} boss)`).join(" ; ")}`));
    console.log(`${m.monsters} monstres, ${m.bosses} boss copiés de Dofus` + (m.left_out.length ? ` (${m.left_out.length} écartés, squelette absent : ${m.left_out.join(", ")})` : ""));
  };
  let r: { problems: import("./problems").Problem[] };
  if (args.includes("--monsters")) {
    const m = rebuildMonsters(store, recipe);
    showMonsters(m.monsters);
    r = m;
  } else {
    const b = buildRecipe(store, recipe, { force: args.includes("--force") });
    b.floors.forEach((f, i) => console.log(`étage ${i + 1} : ${f.maps.length} maps, arrivée map ${f.hub} case ${f.arrive_cell}, gardien ${f.npc} case ${f.npc_cell}`));
    showMonsters(b.monsters);
    r = b;
  }
  const errors = r.problems.filter((p) => p.severity === "error");
  console.log(`${errors.length} erreur(s), ${r.problems.length - errors.length} avertissement(s)`);
  for (const p of r.problems) console.log(` - [${p.code}] ${p.message}`);
  process.exit(errors.length ? 1 : 0);
} catch (e) {
  console.error((e as Error).message);
  process.exit(1);
}
