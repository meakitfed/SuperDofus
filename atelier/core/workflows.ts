// Guided workflows: ordered steps toward a goal ("a playable class", "a quest"...). Each step's state is read from
// the world data itself, never stored, so a workflow can neither get out of sync with the world nor leave a broken
// reference behind: the last step of each one is a check of the playable report that must pass.
import type { World } from "./io";
import { playableReport } from "./playable";
import { reachableMaps } from "./rules_maps";

export interface WorkflowStep { label: string; hint: string; done: boolean; /** tab of the world page where the step happens */ tab: string }
export interface Workflow { id: string; title: string; goal: string; steps: WorkflowStep[]; done: boolean }

type Raw = Record<string, any>;
export interface WorkflowFacts { ownBones: number; images: Record<string, number> }

export const WORKFLOW_IDS = ["class", "monster", "quest", "dungeon", "link", "merchant", "resource"] as const;

export function workflows(w: World, facts: WorkflowFacts): Workflow[] {
  const wf = w.files;
  const checks = new Map(playableReport(w).map((c) => [c.code, c]));
  const ok = (code: string) => checks.get(code)?.status === "ok";
  const maps = [...w.maps.values()] as Raw[];
  const reach = reachableMaps(w);
  const spells = wf.spells.spells as Raw[];
  const owned = new Set(Object.values(wf.spells.classes as Raw).flatMap((c: Raw) => (c.pairs ?? []).map((p: number[]) => p[0])));
  const mobs = Object.values(wf.monsters.monsters) as Raw[];
  const npcCount = Object.values(wf.npcs.maps).reduce((n, l) => n + l.length, 0);
  const startMap = (wf.world as Raw).start_map;
  const gathers = Object.values(wf.skills.objectsById as Raw).filter((k: Raw) => Number(k.gatheredRessourceItem) > 0);
  const placed = (skill: number) => Object.entries(wf.interactives.maps).some(([mid, l]) => reach.has(Number(mid)) && l.some((e) => e.skill === skill));

  const make = (id: string, title: string, goal: string, steps: WorkflowStep[]): Workflow => ({ id, title, goal, steps, done: steps.every((s) => s.done) });
  const step = (label: string, hint: string, done: boolean, tab: string): WorkflowStep => ({ label, hint, done, tab });

  return [
    make("class", "Nouvelle classe jouable", "Une classe qu'un joueur peut choisir et avec laquelle il peut se battre dès le niveau 1.", [
      step("Créer un sort de niveau 1", "Le premier sort de la classe : il doit être utilisable dès le niveau 1.", spells.some((s) => s.level <= 1), "/sorts"),
      step("Avoir un squelette", "Le personnage a besoin d'un squelette animé : copie-en un depuis un autre monde.", facts.ownBones > 0, "/classes"),
      step("Créer la classe", "Nom, rôle, description, squelette et grimoire (les sorts qu'elle apprend).", wf.world.breeds.length > 0, "/classes"),
      step("Un sort de niveau 1 dans le grimoire", "Sans lui la classe naît désarmée.", wf.world.breeds.length > 0 && ok("P_CLASS_STARTER"), "/classes"),
    ]),
    make("monster", "Nouveau monstre, butin et zone", "Un monstre qu'on rencontre vraiment sur une map et qui laisse des objets.", [
      step("Une image de portrait", "Importe un portrait pour le monstre (catégorie Monstres).", (facts.images.monster ?? 0) > 0, "/assets"),
      step("Un sort de monstre", "Les grades du monstre lancent des sorts : crée-en un.", spells.length > 0, "/sorts"),
      step("Un objet à laisser en butin", "Un objet que le monstre pourra faire tomber.", wf.items.items.length > 0, "/objets"),
      step("Créer le monstre et sa zone", "Grades, butin, et zone de rencontre.", mobs.length > 0, "/monstres"),
      step("Attribuer la zone à une map avec apparitions", "Donne la zone à une map où des monstres apparaissent.", mobs.length > 0 && ok("P_MONSTER_REACHABLE") && ok("P_ZONE_USED"), "/maps"),
      step("Le butin est obtenable", "Chaque objet du monde doit avoir une source.", ok("P_ITEM_OBTAINABLE"), "/monstres"),
    ]),
    make("quest", "Nouvelle quête", "Un PNJ donne une quête que le joueur peut commencer puis terminer.", [
      step("Une map pour le PNJ", "Le PNJ vit sur une map atteignable.", maps.length > 0, "/maps"),
      step("Placer le PNJ donneur", "Pose un PNJ sur une cellule de la map.", npcCount > 0, "/pnj"),
      step("Créer la quête", "Étapes, objectifs et récompenses.", Object.keys(wf.quests.quests).length > 0, "/quetes"),
      step("Le donneur est atteignable", "Le joueur doit pouvoir arriver jusqu'au PNJ.", Object.keys(wf.quests.quests).length > 0 && ok("P_QUEST_GIVER"), "/quetes"),
      step("Les objectifs sont atteignables", "PNJ, maps, monstres et objets demandés doivent exister et se trouver.", Object.keys(wf.quests.quests).length > 0 && ok("P_QUEST_TARGETS") && ok("P_QUEST_LEVELS"), "/quetes"),
    ]),
    make("dungeon", "Nouveau donjon", "Une suite de maps reliées, avec des monstres, accessible depuis le reste du monde.", [
      step("Au moins deux maps en plus de la map de départ", "Crée les salles du donjon.", maps.length >= 3, "/maps"),
      step("Créer le donjon", "Ses salles dans l'ordre, sa map d'entrée, ses clés et son boss.", Object.keys(((wf as Raw).dungeons?.dungeons ?? {}) as Raw).length > 0, "/donjons"),
      step("Les relier entre elles et au monde", "Portes ou voisines : tout doit être atteignable.", maps.length >= 3 && maps.every((m) => reach.has(m.id)), "/maps"),
      step("Une zone de monstres", "Crée la zone et ses monstres.", Object.keys(wf.monsters.subareas).length > 0, "/monstres"),
      step("Faire apparaître les monstres dans le donjon", "Attribue la zone à une map non départ avec apparitions.", maps.some((m) => m.id !== startMap && m.monster_spawn && m.subarea !== undefined && reach.has(m.id)), "/maps"),
      step("Chaque monstre est rencontrable", "Rien d'inutile dans le monde.", ok("P_MONSTER_REACHABLE") && ok("P_ZONE_USED"), "/monstres"),
    ]),
    make("link", "Relier deux maps", "Que le joueur puisse passer d'une map à l'autre, dans les deux sens.", [
      step("Avoir deux maps", "Crée la seconde map.", maps.length >= 2, "/maps"),
      step("Poser une porte ou une voisine", "Dans l'éditeur de map, relie-les.", maps.length >= 2 && maps.every((m) => reach.has(m.id)), "/maps"),
    ]),
    make("merchant", "Ajouter un PNJ marchand", "Un PNJ dont la boutique s'ouvre vraiment depuis le dialogue.", [
      step("Créer des objets à vendre", "Il faut au moins un objet.", wf.items.items.length > 0, "/objets"),
      step("Placer le PNJ avec sa boutique", "Coche la boutique et choisis les objets.", Object.keys(wf.shops.shops).length > 0, "/pnj"),
      step("La réponse « boutique » existe dans le dialogue", "Sinon le joueur ne peut pas l'ouvrir.", Object.keys(wf.shops.shops).length > 0 && ok("P_SHOP_OPENABLE"), "/pnj"),
    ]),
    make("resource", "Ressource à récolter", "Un métier, une ressource qui donne un objet, et des endroits où la récolter.", [
      step("Un objet à récolter", "La ressource donne un objet : crée-le (par exemple du bois).", wf.items.items.length > 0, "/objets"),
      step("Une image de tuile", "L'image de la ressource sur la map : importe-la (catégorie Tuiles).", (facts.images.tile ?? 0) > 0, "/assets"),
      step("Créer un métier", "Le métier qui permet de la récolter (Bûcheron…).", Object.keys(((wf as Raw).jobs?.objectsById ?? {}) as Raw).length > 0, "/ressources"),
      step("Créer la ressource", "Son nom, son métier, l'objet qu'elle donne et le niveau requis.", gathers.length > 0, "/ressources"),
      step("La poser sur une map atteignable", "Un joueur doit pouvoir arriver jusqu'à elle.", gathers.length > 0 && gathers.every((k: Raw) => placed(k.id)), "/ressources"),
    ]),
  ];
}
