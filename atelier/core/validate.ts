// The coherence check of a world: every rule, one report. Pure (no disk) except through `probe`.
import { diskList, diskProbe, loadWorld, type ContentProbe, type World } from "./io";
import type { Ctx, Options, Problem, Rule } from "./problems";
import { contentRules } from "./rules_content";
import { mapRules } from "./rules_maps";
import { storyRules } from "./rules_story";

export const RULES: Rule[] = [...contentRules, ...mapRules, ...storyRules];

export function validate(w: World, probe: ContentProbe, opts: Options = {}): Problem[] {
  const problems: Problem[] = [];
  const f = w.files;
  const monsterKeys = [...Object.keys(f.monsters.monsters), ...Object.keys(f.monsters.bosses)];
  const base = {
    w, probe, opts,
    mapIds: new Set(f.world.maps),
    spellIds: new Set(f.spells.spells.map((s) => s.id)),
    itemIds: new Set(f.items.items.map((i) => i.id)),
    setIds: new Set(f.items.sets.map((s) => s.id)),
    mobIds: new Set(monsterKeys.map(Number)),
    summonIds: new Set(Object.keys(f.spells.summons).map(Number)),
    npcIds: new Set(Object.values(f.npcs.maps).flatMap((l) => l.map((n) => n.npc))),
    questIds: new Set(Object.keys(f.quests.quests).map(Number)),
  };
  for (const rule of RULES) {
    const ctx: Ctx = {
      ...base,
      report: (code, message, ref) => problems.push({ code, severity: rule.severity, message, ref }),
    };
    rule.run(ctx);
  }
  return problems;
}

/** Load a world folder from disk and check it; unreadable files come back as LOAD problems. */
export function validateDir(dir: string, opts: Options = {}): Problem[] {
  const { world, issues } = loadWorld(dir);
  if (!world) return issues.map((i) => ({ code: "E_LOAD", severity: "error" as const, message: `${i.file} : ${i.message}` }));
  return validate(world, diskProbe(dir), { list: diskList(dir), ...opts });
}
