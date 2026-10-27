// A minimal valid world, in memory: the starting point of every mutation test.
import type { ContentProbe, World } from "../core/io";

export const MINI_CONTENT = new Set([
  "Picto/Items/9100001.png",
  "Characters/Bones/950001",
  "Picto/Monsters/950001.png",
  "Maps/1.json",
  "Maps/2.json",
  "Maps/Gfx/7.png",
]);

export const miniProbe: ContentProbe = (rel) => MINI_CONTENT.has(rel);

/** Folder listing of the mini content: every image of MINI_CONTENT that is a numbered png. */
export const miniList = (dir: string): string[] =>
  [...MINI_CONTENT].filter((p) => p.startsWith(dir + "/") && p.split("/").length === dir.split("/").length + 1).map((p) => p.slice(dir.length + 1));

const T = (n: number) => 9000000 + n;

export function makeMini(): World {
  const files = {
    world: { id: "mini", name: "Mini", start_map: 1, start_cell: 100, breeds: [901], default_breed: 901, maps: [1, 2], phoenixes: [1] },
    spells: {
      classes: { "901": { pairs: [[900001, 900001]] } },
      grades: { "900001": [900101] },
      spells: [
        { id: 900101, name_id: T(1), effects: [{ kind: "damage" }], crit_effects: [] },
        { id: 900102, name_id: T(2), effects: [{ kind: "summon", monster: 5 }, { kind: "cast", spell: 900101 }], crit_effects: [] },
      ],
      summons: { "5": { name_id: T(3), look: "{950001|||100}", grades: [{ spells: [900101] }] } },
    },
    items: {
      items: [{ id: 9100001, name_id: T(4), description_id: T(5), icon: 9100001, type: 16, level: 1, effects: [[125, 10, 0, 0]], set: 9101 }],
      sets: [{ id: 9101, name_id: T(6), items: [9100001] }],
    },
    breeds: { objectsById: { "901": { id: 901 } } },
    skills: { objectsById: { "9501": { id: 9501, gatheredRessourceItem: 9100001 } } },
    monsters: {
      subareas: { "1": { monsters: [910001] } },
      monsters: {
        "910001": { name_id: T(7), grades: [{ look: "{950001|||100}", portrait: 950001, level: 1, spells: [900101], drops: [{ item: 9100001, pct: 10 }] }] },
      },
      bosses: {},
    },
    quests: {
      quests: {
        "930001": {
          id: 930001, name_id: T(8), start: { npc: 920001, map: 1 },
          steps: [{
            id: 931001, name_id: T(9), desc_id: T(10),
            objectives: [{ id: 932001, type: 14, map: 0, params: [910001, 1], args: [{ t: T(11) }] }],
            rewards: [{ items: [[9100001, 1]] }],
          }],
        },
      },
    },
    dialogs: {
      dialogs: {
        "920001": {
          start: "0",
          nodes: {
            "0": {
              text: "Bonjour.",
              replies: [
                { id: 1, text: "Parle-moi.", next: "a", criteria: "Qf=930001&PO=9100001" },
                { id: 2, text: "Emmène-moi.", action: { type: "teleport", map: 2 } },
                { id: 3, text: "Un cadeau ?", action: { type: "give_item", item: 9100001 } },
              ],
            },
            a: { text: "Voilà.", replies: [] },
          },
        },
      },
    },
    npcs: { maps: { "1": [{ npc: 920001, cell: 202, name_id: T(12) }] } },
    shops: { shops: { "920001": { items: [9100001] } } },
    interactives: { maps: { "1": [{ e: 933001, cell: 35, skill: 9501 }] } },
    bank: { bankers: [] },
    dungeons: { dungeons: { "933500": { id: 933500, name: "Cave", level: 5, min_level: 1, difficulty: 1, maps: [2], entrance_map: 1, exit_map: 1, keys: [{ item: 9100001, qty: 1 }], bosses: [] } } },
    texts: Object.fromEntries(Array.from({ length: 12 }, (_, i) => [String(T(i + 1)), `texte ${i + 1}`])),
  };
  const map = (id: number, neighbors: Record<string, number>, blocked: number[]) => ({
    id, name: `Map ${id}`, coords: [id, 0] as [number, number], visual: id, outdoor: true,
    blocked, fight_blocked: blocked, los_blocked: [],
    placement: { red: [60, 61], blue: [90, 91] },
    neighbors,
    triggers: [{ cell: 150, to_map: id === 1 ? 2 : 1, to_cell: 150 }],
    phoenix: 100,
  });
  const visual = (id: number) => ({ id, layers: { background: [{ g: 7 }], sortable: [] } });
  return {
    dir: "(mem)",
    files: files as unknown as World["files"],
    maps: new Map([[1, map(1, { right: 2 }, [35, 207])], [2, Object.assign(map(2, { left: 1 }, []), { subarea: 1 })]]) as World["maps"], // the room of the mini dungeon: a zone with monsters
    visuals: new Map([[1, visual(1)], [2, visual(2)]]) as World["visuals"],
  };
}
