// Schemas of every file of a world (game/worlds/<id>/). Strict on the fields the engine and the validator
// rely on, loose (passthrough) on the rest, so that reading then writing a file never drops a field.
import { z } from "zod";

const id = z.number().int();
const cell = z.number().int();
const loose = <T extends z.ZodRawShape>(shape: T) => z.object(shape).passthrough();

export const WorldJson = loose({
  id: z.string(),
  name: z.string(),
  start_map: id,
  start_cell: cell,
  breeds: z.array(id),
  default_breed: id.optional(),
  maps: z.array(id),
  phoenixes: z.array(id).optional(),
});

export const MapJson = loose({
  id,
  name: z.string(),
  coords: z.tuple([z.number(), z.number()]),
  visual: id,
  blocked: z.array(cell),
  fight_blocked: z.array(cell).optional(),
  los_blocked: z.array(cell).optional(),
  placement: loose({ red: z.array(cell), blue: z.array(cell) }).optional(),
  neighbors: z.record(z.string(), id).optional(),
  triggers: z.array(loose({ cell, to_map: id, to_cell: cell })).optional(),
  phoenix: cell.optional(),
});

export const MapVisualJson = loose({
  id,
  layers: loose({
    background: z.array(loose({ g: id })),
    sortable: z.array(loose({ g: id })),
  }),
});

const effect = loose({
  kind: z.string(),
  spell: id.optional(),
  monster: id.optional(),
});
export const SpellsJson = loose({
  classes: z.record(z.string(), loose({ pairs: z.array(z.array(id)) })),
  grades: z.record(z.string(), z.array(id)),
  spells: z.array(loose({
    id,
    name_id: id,
    effects: z.array(effect),
    crit_effects: z.array(effect).optional(),
  })),
  summons: z.record(z.string(), loose({
    name_id: id.optional(),
    look: z.string().optional(),
    grades: z.array(loose({ spells: z.array(id), start: id.optional() })),
  })),
});

const effectRow = z.array(z.number());
export const ItemsJson = loose({
  items: z.array(loose({
    id,
    name_id: id,
    description_id: id.optional(),
    icon: id,
    type: id,
    level: z.number(),
    effects: z.array(effectRow).optional(),
    set: id.nullish(),
  })),
  sets: z.array(loose({ id, name_id: id.optional(), items: z.array(id) })),
});

const row = loose({ id });
export const TableJson = loose({ objectsById: z.record(z.string(), row) });
export const SkillsJson = loose({
  objectsById: z.record(z.string(), loose({ id, gatheredRessourceItem: id })),
});

const monsterGrade = loose({
  look: z.string(),
  portrait: id.optional(),
  level: z.number(),
  spells: z.array(id),
  drops: z.array(loose({ item: id, pct: z.number() })),
});
const monster = loose({ name_id: id.optional(), grades: z.array(monsterGrade) });
export const MonstersJson = loose({
  subareas: z.record(z.string(), loose({ monsters: z.array(id) })),
  monsters: z.record(z.string(), monster),
  bosses: z.record(z.string(), monster),
});

export const NpcsJson = loose({
  maps: z.record(z.string(), z.array(loose({ npc: id, cell, name_id: id }))),
});

const reply = loose({
  id: z.number().optional(),
  text: z.string(),
  next: z.string().nullish(),
  criteria: z.string().optional(),
  action: loose({ type: z.string() }).optional(),
});
export const DialogsJson = loose({
  dialogs: z.record(z.string(), loose({
    start: z.string(),
    nodes: z.record(z.string(), loose({ text: z.string(), replies: z.array(reply) })),
  })),
});

export const ShopsJson = loose({ shops: z.record(z.string(), loose({ items: z.array(id) })) });
export const InteractivesJson = loose({
  maps: z.record(z.string(), z.array(loose({ e: id, cell, skill: id }))),
});
export const BankJson = loose({ bankers: z.array(id) });
export const DungeonsJson = loose({ dungeons: z.record(z.string(), z.unknown()) });

const objective = loose({
  id,
  type: z.number().int(),
  map: id.optional(),
  params: z.array(z.number()),
  args: z.array(z.record(z.string(), z.unknown())).optional(),
});
const reward = loose({ items: z.array(z.tuple([id, z.number()])).optional() });
export const QuestsJson = loose({
  quests: z.record(z.string(), loose({
    id,
    name_id: id,
    start: loose({ npc: id, map: id }),
    steps: z.array(loose({
      id,
      name_id: id,
      desc_id: id,
      objectives: z.array(objective),
      rewards: z.array(reward),
    })),
  })),
});

export const TextsJson = z.record(z.string(), z.string());

/** Every file of a world, by path relative to the world folder; `many` = one file per map. */
export const FILES = {
  world: { path: "world.json", schema: WorldJson, optional: false },
  spells: { path: "data/spells.json", schema: SpellsJson, optional: false },
  items: { path: "data/items.json", schema: ItemsJson, optional: false },
  breeds: { path: "data/tables/breeds.json", schema: TableJson, optional: false },
  skills: { path: "data/tables/skills.json", schema: SkillsJson, optional: false },
  jobs: { path: "data/tables/jobs.json", schema: TableJson, optional: true },
  recipes: { path: "data/tables/recipes.json", schema: TableJson, optional: true },
  monsters: { path: "monsters.json", schema: MonstersJson, optional: false },
  quests: { path: "quests.json", schema: QuestsJson, optional: false },
  dialogs: { path: "dialogs.json", schema: DialogsJson, optional: false },
  npcs: { path: "npcs.json", schema: NpcsJson, optional: false },
  shops: { path: "shops.json", schema: ShopsJson, optional: false },
  interactives: { path: "interactives.json", schema: InteractivesJson, optional: false },
  bank: { path: "bank.json", schema: BankJson, optional: true },
  dungeons: { path: "dungeons.json", schema: DungeonsJson, optional: true },
  texts: { path: "Content/I18n/extra_fr.json", schema: TextsJson, optional: false },
} as const;

export type FileKey = keyof typeof FILES;
export type Parsed<K extends FileKey> = z.infer<(typeof FILES)[K]["schema"]>;
export type MapData = z.infer<typeof MapJson>;
export type MapVisual = z.infer<typeof MapVisualJson>;
