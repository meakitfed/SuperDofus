// "Playable world" report: the valid mini world passes every check; one break per check makes exactly that check fail.
// A guard fails if a check of the report has no test here.
import { describe, expect, it } from "vitest";
import { playableReport } from "../core/playable";
import { makeMini } from "./mini";

type Files = any;
/** The reference-valid mini world, made playable: a level 1 spell, a monster zone on a spawning map, an NPC that opens its shop. */
function makePlayable() {
  const w = makeMini();
  const f: Files = w.files;
  for (const s of f.spells.spells) s.level = 1;
  Object.assign(w.maps.get(1) as any, { subarea: 1, monster_spawn: true });
  f.monsters.subareas["1"].level = 1;
  f.dialogs.dialogs["920001"].nodes["0"].replies.push({ id: 4, text: "Voir la boutique", action: { type: "shop" } });
  return w;
}
const run = (mutate: (w: ReturnType<typeof makeMini>, f: Files) => void) => {
  const w = makePlayable();
  mutate(w, w.files);
  return playableReport(w);
};
const failing = (checks: ReturnType<typeof playableReport>) => checks.filter((c) => c.status !== "ok").map((c) => c.code);

/** Checks that legitimately fail together (a monster nobody can meet also makes its quest and its zone fail). */
const ALSO: Record<string, string[]> = {
  P_MONSTER_REACHABLE: ["P_ZONE_USED", "P_QUEST_TARGETS"],
  P_ZONE_USED: ["P_MONSTER_REACHABLE", "P_QUEST_TARGETS"],
};

const BREAKS: Record<string, (w: ReturnType<typeof makeMini>, f: Files) => void> = {
  P_CLASS_STARTER: (_, f) => { f.spells.spells[0].level = 5; },
  P_MONSTER_REACHABLE: (w) => { (w.maps.get(1) as any).monster_spawn = false; (w.maps.get(2) as any).monster_spawn = false; },
  P_ZONE_USED: (w) => { for (const m of w.maps.values()) delete (m as any).subarea; },
  P_SHOP_OPENABLE: (_, f) => { f.shops.shops["920001"] = { items: [9100001] }; f.dialogs.dialogs["920001"].nodes["0"].replies = f.dialogs.dialogs["920001"].nodes["0"].replies.filter((r: any) => r.action?.type !== "shop"); },
  P_QUEST_GIVER: (_, f) => { f.quests.quests["930001"].start.npc = 777; },
  P_QUEST_TARGETS: (_, f) => { f.quests.quests["930001"].steps[0].objectives[0].params = [424242, 1]; },
  P_QUEST_LEVELS: (_, f) => { f.quests.quests["930001"].steps.push({ ...f.quests.quests["930001"].steps[0], id: 931002, level: 1, objectives: f.quests.quests["930001"].steps[0].objectives.map((o: any) => ({ ...o, id: 932002 })) }); f.quests.quests["930001"].steps[0].level = 5; },
  P_ITEM_OBTAINABLE: (_, f) => { f.items.items.push({ id: 9100002, name_id: 9000004, icon: 9100001, type: 16, level: 1 }); },
};

describe("rapport de monde jouable", () => {
  it("le mini-monde valide réussit toutes les vérifications", () => {
    const baseline = run(() => {});
    expect(failing(baseline), JSON.stringify(baseline.filter((c) => c.status !== "ok"), null, 1)).toEqual([]);
  });
  for (const [code, mutate] of Object.entries(BREAKS)) {
    it(`${code} : la casse est détectée, seule`, () => {
      const out = run(mutate);
      expect(failing(out).sort(), JSON.stringify(out.filter((c) => c.status !== "ok"), null, 1)).toEqual([code, ...(ALSO[code] ?? [])].sort());
      expect(out.find((c) => c.code === code)!.items.length).toBeGreaterThan(0);
    });
  }
  it("garde : chaque vérification du rapport a son test", () => {
    const codes = playableReport(makePlayable()).map((c) => c.code);
    expect(codes.filter((c) => !(c in BREAKS))).toEqual([]);
  });
});
