// npm run validate -- <dossier du monde>   (exit 1 s'il y a des erreurs ; les avertissements n'échouent pas)
import { validateDir } from "./validate";

const dir = process.argv[2];
if (!dir) {
  console.error("usage : npm run validate -- <game/worlds/id>");
  process.exit(2);
}
const problems = validateDir(dir);
const errors = problems.filter((p) => p.severity === "error");
console.log(`${errors.length} erreur(s), ${problems.length - errors.length} avertissement(s)`);
for (const p of problems) console.log(` - [${p.code}] ${p.message}`);
process.exit(errors.length ? 1 : 0);
