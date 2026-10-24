// A brand new world: valid from the first second (0 error), with one empty map to start from.
// It offers no class of its own (`breeds: []`): the engine then offers the classes no other world claims.
import type { World } from "./io";
import { rangesForSlot, type RangeMap } from "./ranges";
import type { MapVisual } from "./schemas";

export const WORLD_ID = /^[a-z][a-z0-9_]{1,31}$/;

export function createSkeleton(id: string, name: string, slot: number, visualTemplate: MapVisual): { world: World; ranges: RangeMap } {
  if (!WORLD_ID.test(id)) throw new Error("identifiant invalide : minuscules, chiffres et _ (2 à 32 caractères, commence par une lettre)");
  const ranges = rangesForSlot(slot);
  const mapId = ranges.map[0];
  const nameText = ranges.text[0];
  const mapNameText = ranges.text[0] + 1;
  const files = {
    world: {
      id, name, start_map: mapId, start_cell: 300, wander_ms: [7000, 16000], max_groups: 3, challenges: true,
      breeds: [] as number[], maps: [mapId], phoenixes: [mapId],
    },
    spells: { _doc: "", classes: {}, grades: {}, spells: [], summons: {} },
    items: { items: [], sets: [] },
    breeds: { objectsById: {} },
    skills: { objectsById: {} },
    monsters: { subareas: {}, monsters: {}, bosses: {} },
    quests: { quests: {} },
    dialogs: { dialogs: {} },
    npcs: { maps: {} },
    shops: { shops: {} },
    interactives: { maps: {} },
    bank: { bankers: [], placed: {} },
    dungeons: { dungeons: {} },
    texts: { [String(nameText)]: name, [String(mapNameText)]: "Départ" },
  };
  const map = {
    id: mapId, name: "Départ", name_id: mapNameText, coords: [0, 0] as [number, number], visual: mapId, outdoor: true,
    blocked: [] as number[], fight_blocked: [] as number[], los_blocked: [] as number[],
    placement: { red: [] as number[], blue: [] as number[] },
    neighbors: {}, triggers: [], monster_spawn: false, phoenix: 300,
  };
  const visual = { ...structuredClone(visualTemplate), id: mapId } as MapVisual;
  return {
    ranges,
    world: {
      dir: "",
      files: files as unknown as World["files"],
      maps: new Map([[mapId, map]]) as World["maps"],
      visuals: new Map([[mapId, visual]]),
    },
  };
}
