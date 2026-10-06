# Catalogue des données Dofus 3

Généré par `python tools/extractor/catalog.py` : ne pas éditer les tableaux à la main. Les rôles et les lots se modifient dans `KEY_TABLES` du script.

- Extraction : `python tools/extractor/extract.py --tables all`, incrémentale, qui s'arrête sous 2 Go libres. Les fichiers vont dans `game/content/Content/Data/<table>dataroot.json` (`{objectsById: {id: ligne}}`), qu'on ne commite jamais.
- Lecture côté jeu : `GameData.table("<table>")` et `GameData.row("<table>", id)`. Les copies légères livrées avec le jeu (`game/data/tables/<table>.json`, `gamedata.py table <table>`) passent avant le contenu brut ; voir `shared/game_data.gd`.
- Textes : les `nameId`, `descriptionId`… sont des clés i18n de `Content/I18n/fr.bin` (`python tools/extractor/maps.py i18n`).
- 204 tables, 204 Mo au total.

## Tables clés et lots de la roadmap

| Table | Rôle | Lots | Lignes |
|---|---|---|---|
| `breeds` | Classes : looks, couleurs, coûts du capital par palier (statsPointsFor*), sorts de classe | P1.02, P1.04 | 19 |
| `heads` | Têtes par classe et sexe | P1.02 | 638 |
| `skinslotsrules` | Règles de slots de skin du look | A.01, P1.02 | 951 |
| `namingrules` | Règles de nom (longueur, regexp) pour les personnages, guildes… | P1.01 | 18 |
| `characterxpmappings` | Table d'XP des personnages | A.04 | 2339 |
| `characteristics` | Caractéristiques (keyword, catégorie, formule d'échelle) | P1.04 | 123 |
| `luaformulas` | Formules officielles (XP, prospection, …) en Lua | A.03, P1.04, P1.14 | 38 |
| `constants` | Constantes du jeu | P1.04 | 12 |
| `notifications` | Tutoriel : titre, message, déclencheur (12-14 : mort, énergie, fantôme) | P1.10 | 72 |
| `infomessages` | Messages de jeu → texte i18n (énergie perdue, récupérée…) | P1.10 | 2557 |
| `spells` | Sorts : nom, icône, scripts de FX, niveaux | A.03, P1.03 | 17067 |
| `spelllevels` | Niveaux de sort : coûts, portée, effets, critiques, niveau requis | A.03, P1.03, P1.11–P1.17 | 34697 |
| `spellvariants` | Paires de variantes Dofus 3 | P1.03 | 431 |
| `spellstates` | États (flags : invulnérable, pesanteur, enraciné…) | A.03, P1.14 | 6375 |
| `spellscripts` | Scripts de FX des sorts | A.03 | 14929 |
| `effects` | Définition des effets (caractéristique, opérateur, catégorie) | P1.05, P1.06, P2.07 | 872 |
| `items` | Objets : type, niveau, poids, prix, conditions, possibleEffects, arme | P1.05, P1.06, P2.02 | 21748 |
| `itemtypes` | Types d'objets et catégories (slot d'équipement) | P1.05, P1.06 | 239 |
| `itemsupertypes` | Super-types d'objets | P1.06 | 26 |
| `itemsets` | Panoplies : objets et bonus par nombre d'objets portés | P1.06 | 929 |
| `monsters` | Monstres : grades, sorts, drops, sous-zones, agressivité | A.03, P1.09, P1.16 | 5135 |
| `monsterraces` | Races de monstres, agressivité | P1.09 | 265 |
| `monsterminibosses` | Correspondance archimonstres / miniboss | P4.02 | 306 |
| `mapsinformation` | Maps : coordonnées, sous-zone | P1.07 | 15360 |
| `mapscoordinates` | Coordonnées → maps | P1.07, P1.08 | 6673 |
| `mapscrollactions` | Voisins réels des maps (haut, bas, gauche, droite) | P1.07 | 2223 |
| `subareas` | Sous-zones : maps, niveau, monstres, ressources, zaap associé, voisins | P1.07, P1.09, P2.05 | 562 |
| `areas` | Zones | P1.07 | 69 |
| `superareas` | Continents | P1.08 | 10 |
| `worldmaps` | Cartes du monde | P1.08 | 40 |
| `waypoints` | Zaaps (map, sous-zone) | P1.08 | 62 |
| `pointsofinterest` | Points d'intérêt de la carte | P1.08 | 179 |
| `npcs` | PNJ : look, messages et réponses de dialogue, actions | P2.01 | 6467 |
| `npcmessages` | Textes des messages de PNJ | P2.01 | 55037 |
| `npcactions` | Actions de PNJ (parler, acheter, …) | P2.01, P2.02 | 16 |
| `quests` | Quêtes : catégorie, répétition, niveaux, étapes, condition de départ | P2.03, P2.04 | 1976 |
| `queststeps` | Étapes : objectifs, récompenses, dialogue | P2.03 | 2225 |
| `questobjectives` | Objectifs : type, paramètres, map | P2.03 | 15547 |
| `questobjectivetypes` | Types d'objectifs | P2.03 | 18 |
| `queststeprewards` | Récompenses d'étape | P2.03 | 6707 |
| `questcategories` | Catégories de quêtes | P2.03 | 43 |
| `jobs` | Métiers | P2.05 | 23 |
| `skills` | Compétences : métier, ressource récoltée, objets craftables, animation | P2.05, P2.06 | 368 |
| `interactives` | Types d'éléments interactifs | P2.05 | 446 |
| `recipes` | Recettes : ingrédients, quantités, métier, niveau | P2.06 | 4858 |
| `auctionhouses` | Hôtels de vente : type, quantités autorisées | P2.10 | 7 |
| `achievements` | Succès : points, niveau, objectifs, récompenses | P2.12 | 2780 |
| `achievementobjectives` | Objectifs de succès (critères) | P2.12 | 8946 |
| `achievementrewards` | Récompenses de succès | P2.12 | 6394 |
| `almanaxcalendars` | Almanax : jour, quête, bonus | P2.12 | 376 |
| `mounts` | Montures | P2.14 | 266 |
| `mountfamilies` | Familles de montures | P2.14 | 6 |
| `rides` | Montures (Dofus 3) | P2.14 | 308 |
| `chatchannels` | Canaux de chat | P3.02 | 18 |
| `smileys` | Smileys | P3.02 | 222 |
| `guildrights` | Droits de guilde | P3.06 | 28 |
| `guildranks` | Rangs de guilde | P3.06 | 4 |
| `emblemsymbols` | Emblèmes (guildes, alliances) | P3.06, P3.07 | 488 |
| `alliancerights` | Droits d'alliance | P3.07 | 18 |
| `alignmentsides` | Camps d'alignement | P3.08 | 4 |
| `alignmentranks` | Rangs d'alignement | P3.08 | 39 |
| `alignmentorders` | Ordres d'alignement | P3.08 | 10 |
| `arenaleagues` | Ligues du Kolizéum | P3.09 | 26 |
| `challenges` | Challenges de combat : critères d'activation et de réussite | P1.15 | 842 |
| `dungeons` | Donjons : maps, entrée, sortie, niveau | P4.01 | 187 |
| `titles` | Titres | P4.03 | 539 |
| `ornaments` | Ornements | P4.03 | 167 |
| `emoticons` | Émotes : animation, durée, persistance | P4.03 | 324 |
| `havenbagthemes` | Thèmes de havre-sac | P4.04 | 48 |
| `havenbagfurnitures` | Meubles de havre-sac | P4.04 | 4083 |
| `houses` | Maisons : prix, pièces | P4.05 | 261 |
| `paddocks` | Enclos | P4.05, P2.14 | 6 |
| `calendarevents` | Événements du calendrier | P4.06 | 107 |
| `worldevents` | Événements du monde | P4.06 | 23 |
| `soundbones` | Sons des animations | P5.01 | 7182 |
| `randomdropgroups` | Groupes de drops aléatoires (coffres, sacs) | P1.05 | 314 |
| `bonuses` | Bonus (étoiles, …) | P1.09 | 408 |
| `idles` | Animations d'inactivité | P5.05 | 39 |

## Absent du client (données serveur Ankama)

| Donnée | Lot | Solution |
|---|---|---|
| Position des PNJ sur les maps | P2.01 | à relever à la main ou à déduire des quêtes (questobjectives.mapId). Voir aussi les éléments des maps. |
| Contenu des boutiques PNJ | P2.02 | à définir par monde (JSON du monde), `APPROX`. |
| Kamas lâchés par les monstres | A.03 | `APPROX` [2·niveau, 4·niveau+6] (maps.py). |
| Composition et fréquence des groupes de monstres | P1.09 | `subareas.monsters` donne la liste (`monsters.json`, `MonsterSpawner`) ; nombre et taille des groupes `APPROX`. Étoiles : par sous-zone (−50 % à +100 %, Dofus 2.51), vitesse `APPROX`. Agression : `monsters.aggressive*` + devblog 2.45 ; `aggressiveAttackDelay` non compris. |
| Prix des zaaps | P1.08 | `APPROX` : wiki Dofus (10 × distance entière en ligne droite, ÷ 4 depuis Incarnam), `shared/travel.gd`. Position des zaaps : `waypoints.mapId` ; cellule relevée sur capture (`links.json`). |
| Destination des portes, escaliers et trappes | P1.07 | `APPROX` : `game/worlds/<id>/links.json`, cellules relevées sur les captures (`client_shot` goto + mark + grid). Les intérieurs sont les maps de `mapsinformation.worldMap = -1` aux mêmes coordonnées. |
| Position des éléments interactifs (ressources, ateliers, zaaps) | P2.05 | dans les données de map (éléments graphiques avec un id d'interactif) : à vérifier dans `maps.py`. |

## Toutes les tables

| Table | Lignes | Taille | Champs |
|---|---|---|---|
| `achievementcategories` | 134 | 29 Ko | `id`, `nameId`, `parentId`, `icon`, `order`, `color`, `achievementIds`, `visibilityCriterion` |
| `achievementobjectives` | 8946 | 792 Ko | `id`, `achievementId`, `order`, `nameId`, `criterion` |
| `achievementrewards` | 6394 | 2 Mo | `id`, `achievementId`, `criterions`, `kamasRatio`, `experienceRatio`, `kamasScaleWithPlayerLevel`, `itemsReward`, `itemsQuantityReward`, `emotesReward`, `spellsReward`, `titlesReward`, `ornamentsReward`, `alterationsReward`, `guildPoints` |
| `achievements` | 2780 | 538 Ko | `id`, `nameId`, `categoryId`, `descriptionId`, `iconId`, `points`, `level`, `order`, `accountLinked`, `objectiveIds`, `rewardIds` |
| `actionfilters` | 14 | 596 o | `id`, `nameId`, `order` |
| `activitysuggestioncategories` | 19 | 841 o | `id`, `nameId`, `parentId` |
| `activitysuggestions` | 1410 | 236 Ko | `id`, `nameId`, `descriptionId`, `categoryId`, `level`, `mapId`, `isLarge`, `startDate`, `endDate`, `icon`, `iconCategoryId` |
| `alignmentgifts` | 290 | 9 Ko | `id`, `nameId` |
| `alignmentorders` | 10 | 397 o | `id`, `nameId`, `sideId` |
| `alignmentranks` | 39 | 3 Ko | `id`, `orderId`, `nameId`, `descriptionId`, `minimumAlignment` |
| `alignmentranksgifts` | 30 | 10 Ko | `id`, `gifts` |
| `alignmentsides` | 4 | 124 o | `id`, `nameId` |
| `alignmenttitles` | 4 | 611 o | `sideId`, `namesId`, `shortsId` |
| `allianceranknamesuggestions` | 18 | 971 o | `uiKey` |
| `allianceranks` | 4 | 289 o | `id`, `nameId`, `order`, `isModifiable`, `gfxId` |
| `alliancerightgroups` | 4 | 1 Ko | `id`, `nameId`, `order`, `rights` |
| `alliancerights` | 18 | 955 o | `id`, `nameId`, `order`, `groupId` |
| `alliancetags` | 16 | 848 o | `id`, `typeId`, `nameId`, `order` |
| `alliancetagtypes` | 3 | 106 o | `id`, `nameId` |
| `almanaxcalendars` | 376 | 112 Ko | `id`, `nameId`, `descId`, `npcId`, `categoryId`, `bonusesIds`, `dates`, `objectiveId`, `meridiaDescriptionId`, `meridiaEffectId`, `rubrikabraxId`, `meridiaIllustrationId`, `celebrationNameId`, `celebrationDescriptionId` |
| `almanaxcategories` | 14 | 2 Ko | `id`, `nameId`, `protectorNameId`, `protectorDescriptionId`, `protectorIllustrationId` |
| `almanaxzodiacs` | 12 | 1 Ko | `id`, `nameId`, `descriptionId`, `dateStart`, `dateEnd`, `picture` |
| `alterationcategories` | 49 | 2 Ko | `id`, `nameId`, `parentId` |
| `alterations` | 520 | 442 Ko | `id`, `nameId`, `descriptionId`, `categoryId`, `iconId`, `isVisible`, `criterions`, `isWebDisplay`, `possibleEffects` |
| `appearances` | 182 | 11 Ko | `id`, `type`, `data`, `usePlayerLook` |
| `areas` | 69 | 16 Ko | `id`, `nameId`, `superAreaId`, `containHouses`, `containPaddocks`, `bounds`, `worldmapId`, `subareaIds`, `hasWorldMap`, `hasSuggestion` |
| `arenaleagues` | 26 | 4 Ko | `id`, `nameId`, `ornamentId`, `icon`, `illus`, `isLastLeague`, `lowRatingBound`, `highRatingBound` |
| `arenaleagueseasons` | 11 | 1 Ko | `uid`, `nameId`, `beginning`, `closure`, `resetDate`, `flagObjectId` |
| `auctionhouses` | 7 | 479 o | `id`, `typeId`, `allowedQuantities` |
| `bodies` | 114 | 17 Ko | `id`, `skins`, `assetId`, `breed`, `gender`, `label`, `order`, `payable`, `availableAtCreation`, `nameId` |
| `bonusescriterions` | 2396 | 92 Ko | `id`, `type`, `value` |
| `bonuses` | 408 | 29 Ko | `id`, `type`, `amount`, `criterionsIds` |
| `breachbosses` | 131 | 23 Ko | `id`, `monsterId`, `category`, `apparitionCriterion`, `accessCriterion`, `incompatibleBosses`, `rewardId` |
| `breachdungeonmodificators` | 410 | 72 Ko | `id`, `modificatorId`, `criterion`, `additionalRewardPercent`, `score`, `isPositiveForPlayers`, `tooltipBaseline` |
| `breachprizes` | 203 | 21 Ko | `id`, `nameId`, `categoryId`, `tooltipKey`, `descriptionKey` |
| `breachworldmapcoordinates` | 202 | 21 Ko | `mapStage`, `mapCoordinateX`, `mapCoordinateY`, `unexploredMapIcon`, `exploredMapIcon` |
| `breachworldmapsectors` | 5 | 548 o | `id`, `sectorNameId`, `legendId`, `sectorIcon`, `minStage`, `maxStage` |
| `breedroles` | 8 | 660 o | `id`, `nameId`, `descriptionId`, `assetId`, `color` |
| `breeds` | 19 | 27 Ko | `id`, `shortNameId`, `descriptionId`, `gameplayDescriptionId`, `maleLook`, `femaleLook`, `creatureBonesId`, `statsPointsForStrength`, `statsPointsForIntelligence`, `statsPointsForChance`, `statsPointsForAgility`, `statsPointsForVitality`, `statsPointsForWisdom`, `breedSpellsId`, `breedRoles`, `maleColors`, `femaleColors`, `complexity`, `sortIndex` |
| `calendarevents` | 107 | 18 Ko | `id`, `categoryId`, `nameId`, `descriptionId`, `criterion`, `recommendedLevel`, `rewards`, `map`, `picture` |
| `cardbackgrounds` | 8 | 481 o | `id`, `nameId`, `isDefault`, `picture` |
| `challenges` | 842 | 178 Ko | `id`, `nameId`, `descriptionId`, `incompatibleChallenges`, `categoryId`, `iconId`, `completionCriterion`, `activationCriterion`, `targetMonsterId` |
| `characteristiccategories` | 5 | 501 o | `id`, `nameId`, `order`, `characteristicIds` |
| `characteristics` | 123 | 18 Ko | `id`, `keyword`, `nameId`, `asset`, `categoryId`, `visible`, `order`, `scaleFormulaId`, `upgradable` |
| `characterxpmappings` | 2339 | 103 Ko | `experiencePoints` |
| `chatchannels` | 18 | 1 Ko | `id`, `nameId`, `descriptionId`, `shortcut`, `isPrivate` |
| `choices` | 36 | 24 Ko | `id`, `choiceNameId`, `parentId`, `duration`, `options` |
| `collectables` | 150 | 13 Ko | `entityId`, `name`, `typeId`, `gfxId`, `order`, `rarity` |
| `collections` | 1 | 12 Ko | `typeId`, `name`, `criterion`, `collectables` |
| `companioncharacteristics` | 1835 | 238 Ko | `id`, `caracId`, `companionId`, `order`, `statPerLevelRange` |
| `companions` | 52 | 16 Ko | `id`, `nameId`, `look`, `webDisplay`, `descriptionId`, `startingSpellLevelId`, `assetId`, `characteristics`, `spells`, `creatureBoneId`, `visibility` |
| `companionspells` | 312 | 26 Ko | `id`, `spellId`, `companionId`, `gradeByLevel` |
| `constants` | 12 | 443 o | `id`, `value` |
| `creaturebonesoverrides` | 3 | 150 o | `boneId`, `creatureBoneId` |
| `creaturebonestypes` | 11 | 403 o | `id`, `creatureBoneId` |
| `custommodebreedspells` | 105 | 8 Ko | `id`, `pairId`, `breedId`, `isInitialSpell`, `isHidden` |
| `documents` | 603 | 446 Ko | `id`, `typeId`, `showTitle`, `showBackgroundImage`, `titleId`, `authorId`, `subTitleId`, `contentId`, `contentCSS`, `clientProperties` |
| `dofusprogressions` | 30 | 17 Ko | `id`, `nameId`, `descriptionId`, `gfxId`, `backgroundColor`, `minLevel`, `maxLevel`, `prerequisites`, `steps`, `order`, `isPrimordial`, `isEvent` |
| `dungeons` | 187 | 65 Ko | `id`, `nameId`, `optimalPlayerLevel`, `mapIds`, `entranceMapId`, `exitMapId`, `minLevel`, `difficulty`, `availableInAutomaticGroupSearch`, `availableInLobby`, `availableOnKeyring`, `requiredObjects`, `achievements`, `bosses` |
| `effects` | 872 | 414 Ko | `id`, `descriptionId`, `iconId`, `characteristic`, `category`, `characteristicOperator`, `showInTooltip`, `useDice`, `forceMinMax`, `boost`, `active`, `oppositeId`, `theoreticalDescriptionId`, `theoreticalPattern`, `showInSet`, `parametersFixed`, `bonusType`, `useInFight`, `effectPriority`, `effectPowerRate`, `elementId`, `isInPercent`, `hideValueInTooltip`, `textIconReferenceId`, `effectTriggerDuration`, `actionFiltersId` |
| `emblembackgrounds` | 34 | 976 o | `id`, `order` |
| `emblemsymbolcategories` | 14 | 433 o | `id`, `nameId` |
| `emblemsymbols` | 488 | 43 Ko | `id`, `skinId`, `iconId`, `order`, `categoryId`, `colorizable` |
| `emoticons` | 324 | 88 Ko | `id`, `nameId`, `shortcutId`, `order`, `animName`, `persistancy`, `persistantAnimName`, `eightDirections`, `aura`, `cooldown`, `duration`, `weight`, `spellLevelId`, `scale`, `allowOnMount`, `criterion` |
| `evolutiveeffects` | 1143 | 161 Ko | `id`, `actionId`, `targetId`, `progressionPerLevelRange` |
| `evolutiveitemtypes` | 2 | 2 Ko | `id`, `maxLevel`, `experienceBoost`, `experienceByLevel` |
| `expeditionseasons` | 2 | 293 o | `uid`, `nameId`, `beginning`, `closure`, `resetDate`, `flagObjectId` |
| `externalnotifications` | 53 | 10 Ko | `id`, `categoryId`, `iconId`, `colorId`, `descriptionId`, `defaultEnable`, `defaultSound`, `defaultMultiAccount`, `defaultNotify`, `name`, `messageId` |
| `featuredescriptions` | 340 | 66 Ko | `id`, `nameId`, `descriptionId`, `priority`, `parentId`, `children`, `criterion`, `images` |
| `fightscenarios` | 22 | 757 o | `id`, `nameId` |
| `forgettablespells` | 300 | 15 Ko | `id`, `pairId`, `itemId` |
| `guildchesttabs` | 8 | 1 Ko | `tabId`, `nameId`, `index`, `gfxId`, `serverType`, `cost`, `seniority`, `openRight`, `dropRight`, `takeRight` |
| `guildhalls` | 7 | 469 o | `id`, `nameId`, `subareaId`, `mapId` |
| `guildhallthemes` | 5 | 217 o | `id`, `nameId`, `order` |
| `guildlevelrewards` | 20 | 2 Ko | `level`, `nameId`, `descriptionId`, `picto` |
| `guildmissionactivities` | 5 | 564 o | `id`, `nameId`, `level`, `recommendedPlayers`, `rerollCost`, `milestonesIds` |
| `guildmissiongrades` | 11 | 818 o | `id`, `name`, `rankId`, `activityPoint`, `token` |
| `guildmissionmilestonerewards` | 0 | 18 o |  |
| `guildmissionmilestones` | 20 | 2 Ko | `id`, `activityId`, `nameId`, `milestoneLevel`, `activityPoint`, `xp`, `acknowledgmentPoint` |
| `guildmissionobjectives` | 496 | 162 Ko | `id`, `superCategoryId`, `missionId`, `order`, `activationCriterion`, `alterationId`, `areaId`, `subareaId`, `mapId`, `descriptionId`, `monsterId`, `inDungeon`, `quantity`, `familyId`, `familyMonsters`, `minLevel`, `intensity`, `stage`, `seedId`, `objectId`, `quests` |
| `guildmissionranks` | 5 | 287 o | `id`, `nameId`, `descriptionId` |
| `guildmissions` | 464 | 75 Ko | `id`, `categoryId`, `superCategoryId`, `nameId`, `recommendedLevel`, `gradeId`, `activityPoint`, `token`, `objectives`, `rankId` |
| `guildmissionsupercategories` | 6 | 197 o | `id`, `nameId` |
| `guildraids` | 2 | 614 o | `id`, `nameId`, `descriptionId`, `duration`, `playerHealth`, `minPlayers`, `maxPlayers`, `groups`, `goals`, `variables`, `maxScore`, `price`, `canFinish`, `canRestart`, `type` |
| `guildraidsgoals` | 32 | 4 Ko | `id`, `raidId`, `nameId`, `value`, `requisiteForDisplay`, `impactProgress`, `score` |
| `guildraidsgroups` | 2 | 209 o | `id`, `raidId`, `nameId`, `descriptionId`, `minPlayers`, `maxPlayers` |
| `guildraidsladdersrewards` | 14 | 2 Ko | `id`, `raidId`, `position`, `percentage`, `ornaments`, `titles`, `guildExperience`, `items`, `order` |
| `guildraidsrewards` | 21 | 4 Ko | `id`, `raidId`, `descriptionId`, `kamas`, `experience`, `score`, `order`, `rewards` |
| `guildranknamesuggestions` | 34 | 2 Ko | `uiKey` |
| `guildranks` | 4 | 221 o | `id`, `nameId`, `order`, `gfxId` |
| `guildrightgroups` | 8 | 2 Ko | `id`, `nameId`, `order`, `rights` |
| `guildrights` | 28 | 1 Ko | `id`, `nameId`, `order`, `groupId` |
| `guildshopboosts` | 5 | 382 o | `id`, `nameId`, `descriptionId`, `alterationId` |
| `guildtags` | 19 | 1002 o | `id`, `typeId`, `nameId`, `order` |
| `guildtagtypes` | 3 | 104 o | `id`, `nameId` |
| `havenbagfurnitures` | 4083 | 1 Mo | `typeId`, `themeId`, `elementId`, `color`, `skillId`, `layerId`, `blocksMovement`, `isStackable`, `cellsWidth`, `cellsHeight`, `order`, `gfxId`, `height`, `horizontalSymmetry`, `origin`, `size` |
| `havenbagthemes` | 48 | 2 Ko | `id`, `nameId`, `mapId` |
| `heads` | 638 | 93 Ko | `id`, `skins`, `assetId`, `breed`, `gender`, `label`, `order`, `payable`, `availableAtCreation`, `nameId` |
| `hintcategories` | 12 | 360 o | `id`, `nameId` |
| `hints` | 834 | 130 Ko | `id`, `categoryId`, `gfx`, `nameId`, `mapId`, `realMapId`, `x`, `y`, `outdoor`, `subareaId`, `worldMapId`, `level` |
| `houses` | 261 | 26 Ko | `typeId`, `defaultPrice`, `nameId`, `descriptionId`, `gfxId`, `roomCount` |
| `idles` | 39 | 6 Ko | `nameId`, `animationKey`, `known`, `iconIdMale`, `iconIdFemale`, `order`, `criterion`, `breed` |
| `infinitedreamintensities` | 10 | 2 Ko | `id`, `intensity`, `droplegend`, `dropBonus`, `xpBonus`, `money`, `additionalLife`, `nameId`, `dreamFragments` |
| `infinitedreamrewardactions` | 161 | 80 Ko | `id`, `effect`, `duration`, `isAlly` |
| `infinitedreamrewards` | 111 | 8 Ko | `id`, `nameId`, `descriptionId`, `actions` |
| `infinitedreamtrials` | 5 | 730 o | `id`, `nameId`, `descriptionId`, `seed`, `achievementId`, `achievementIntensity`, `picture` |
| `infomessages` | 2557 | 129 Ko | `typeId`, `messageId`, `textId` |
| `interactives` | 446 | 14 Ko | `id`, `nameId` |
| `items` | 21748 | 36 Mo | `id`, `nameId`, `typeId`, `descriptionId`, `iconId`, `level`, `realWeight`, `price`, `itemSetId`, `criterions`, `criterionsTarget`, `appearanceId`, `isColorable`, `recipeSlots`, `recipeIds`, `dropMonsterIds`, `dropTemporisMonsterIds`, `possibleEffects`, `evolutiveEffectIds`, `favoriteSubAreas`, `favoriteSubAreasBonus`, `craftXpRatio`, `craftVisibleCriterion`, `craftConditionalCriterion`, `craftFeasibleCriterion`, `visibilityCriterion`, `recyclingNuggets`, `favoriteRecyclingSubareas`, `resourcesBySubarea`, `importantNoticeId`, `criticalHitBonus`, `minRange`, `criticalHitProbability`, `range`, `castInLine`, `apCost`, `castInDiagonal`, `castTestLos`, `maxCastPerTurn` |
| `itemsets` | 929 | 4 Mo | `id`, `items`, `nameId`, `bonusIsSecret`, `isCosmetic`, `effects` |
| `itemsupertypes` | 26 | 1 Ko | `id`, `possiblePositions` |
| `itemtypes` | 239 | 32 Ko | `id`, `nameId`, `superTypeId`, `categoryId`, `isInEncyclopedia`, `rawZone`, `craftXpRatio`, `evolutiveTypeId` |
| `jobs` | 23 | 1 Ko | `id`, `nameId`, `iconId`, `hasLegendaryCraft` |
| `kothroles` | 7 | 318 o | `id`, `nameId`, `isDefault` |
| `legendarypowerscategories` | 33 | 3 Ko | `id`, `categoryName`, `categoryOverridable`, `categorySpells` |
| `legendarytreasurehunts` | 57 | 6 Ko | `id`, `nameId`, `level`, `chestId`, `monsterId`, `mapItemId`, `xpRatio` |
| `livingobjectskinsmoods` | 64 | 16 Ko | `skinId`, `moods` |
| `lobbytags` | 28 | 2 Ko | `id`, `nameId`, `concurrentTags` |
| `lobbytypes` | 7 | 596 o | `id`, `nameId`, `tags`, `minMember`, `maxMember` |
| `luaformulas` | 38 | 21 Ko | `formula` |
| `mapreferences` | 572 | 27 Ko | `id`, `mapId`, `cellId` |
| `mapscoordinates` | 6673 | 474 Ko | `compressedCoords`, `mapIds` |
| `mapscrollactions` | 2223 | 350 Ko | `id`, `rightExists`, `bottomExists`, `leftExists`, `topExists`, `rightMapId`, `bottomMapId`, `leftMapId`, `topMapId` |
| `mapsinformation` | 15360 | 2 Mo | `id`, `posX`, `posY`, `nameId`, `subAreaId`, `worldMap`, `tacticalModeTemplateId` |
| `modsters` | 150 | 35 Ko | `id`, `itemId`, `modsterId`, `order`, `parentsModsterId`, `modsterActiveSpells`, `modsterPassiveSpells`, `modsterHiddenAchievements`, `modsterAchievements` |
| `monsterminibosses` | 306 | 13 Ko | `id`, `monsterReplacingId` |
| `monsterraces` | 265 | 68 Ko | `id`, `superRaceId`, `nameId`, `aggressiveZoneSize`, `aggressiveLevelDiff`, `aggressiveImmunityCriterion`, `aggressiveAttackDelay`, `monsters` |
| `monsters` | 5135 | 30 Mo | `id`, `nameId`, `gfxId`, `race`, `grades`, `look`, `animFunList`, `drops`, `temporisDrops`, `globalDrops`, `subareas`, `spells`, `spellGrades`, `favoriteSubareaId`, `correspondingMiniBossId`, `speedAdjust`, `creatureBoneId`, `summonCost`, `incompatibleIdols`, `incompatibleChallenges`, `aggressiveZoneSize`, `aggressiveLevelDiff`, `aggressiveImmunityCriterion`, `aggressiveAttackDelay`, `scaleGradeRef`, `characRatios`, `isBounty`, `souls` |
| `monstersuperraces` | 35 | 1 Ko | `id`, `nameId` |
| `months` | 12 | 261 o | `nameId` |
| `mountbehaviors` | 10 | 521 o | `id`, `nameId`, `descriptionId` |
| `mountbones` | 144 | 3 Ko | `id` |
| `mountfamilies` | 6 | 304 o | `id`, `nameId`, `headUri` |
| `mounts` | 266 | 400 Ko | `id`, `familyId`, `nameId`, `look`, `certificateId`, `effects` |
| `namingrules` | 18 | 2 Ko | `id`, `minLength`, `maxLength`, `regexp` |
| `notifications` | 72 | 8 Ko | `id`, `titleId`, `messageId`, `iconId`, `typeId`, `trigger`, `cantBeClosed` |
| `npcactions` | 16 | 661 o | `id`, `realId`, `nameId` |
| `npcdialogskins` | 5 | 2 Ko | `id`, `gfxId`, `buttonsColorTypes`, `backgroundColor`, `isBold`, `fontColor`, `borderColor`, `hasHalo`, `headerGfxId`, `headerColor`, `headerFontColor`, `headerDecorationGfxId`, `headerDecorationColor`, `headerOrnamentGfxId`, `headerOrnamentColor` |
| `npcmessages` | 55037 | 7 Mo | `id`, `messageId`, `messageParams`, `messageSkinId`, `messageBubblePosition`, `messageNpcMoodId` |
| `npcs` | 6467 | 5 Mo | `id`, `nameId`, `dialogMessages`, `dialogReplies`, `actions`, `gender`, `look`, `animFunList`, `fastAnimsFun`, `tooltipVisible`, `dialogData`, `defaultSkinId` |
| `optionalfeatures` | 69 | 11 Ko | `id`, `keyword`, `isClient`, `isServer`, `isActivationOnLaunch`, `isActivationOnServerConnection`, `activationCriterions` |
| `ornaments` | 167 | 13 Ko | `id`, `nameId`, `visible`, `assetId`, `iconId`, `order` |
| `paddockgauges` | 6 | 1 Ko | `id`, `name`, `tierMaxValues` |
| `paddocks` | 6 | 197 o | `id`, `nameId` |
| `pointsofinterest` | 179 | 6 Ko | `id`, `nameId` |
| `popupsinformation` | 26 | 8 Ko | `id`, `parentId`, `titleId`, `headerId`, `descriptionId`, `illuName`, `buttons`, `criterion`, `cacheType`, `autoTrigger` |
| `preseticons` | 116 | 2 Ko | `id` |
| `progressingachievementseasons` | 18 | 1 Ko | `id`, `name`, `seasonId` |
| `progressingachievementsteps` | 535 | 49 Ko | `id`, `progressId`, `score`, `isCosmetic`, `achievementId`, `isBuyable` |
| `questcategories` | 43 | 11 Ko | `id`, `nameId`, `order`, `questIds` |
| `questobjectives` | 15547 | 4 Mo | `id`, `stepId`, `typeId`, `dialogId`, `parameters`, `coords`, `mapId` |
| `questobjectivetypes` | 18 | 547 o | `id`, `nameId` |
| `quests` | 1976 | 560 Ko | `id`, `nameId`, `categoryId`, `repeatType`, `type`, `repeatLimit`, `isDungeonQuest`, `levelMin`, `levelMax`, `stepIds`, `isPartyQuest`, `startCriterion`, `followable`, `isEvent`, `startPosition` |
| `queststeprewards` | 6707 | 2 Mo | `id`, `stepId`, `levelMin`, `levelMax`, `kamasRatio`, `experienceRatio`, `kamasScaleWithPlayerLevel`, `itemsReward`, `emotesReward`, `jobsReward`, `spellsReward`, `titlesReward` |
| `queststeps` | 2225 | 446 Ko | `id`, `questId`, `nameId`, `descriptionId`, `dialogId`, `optimalLevel`, `duration`, `objectiveIds`, `rewardsIds` |
| `randomdropgroups` | 314 | 73 Ko | `id`, `randomDropItems`, `displayChances` |
| `recipes` | 4858 | 862 Ko | `resultId`, `resultNameId`, `resultTypeId`, `resultLevel`, `ingredientIds`, `quantities`, `jobId`, `skillId` |
| `ridefoods` | 15 | 634 o | `gid`, `typeId`, `familyId` |
| `ridegauges` | 3 | 194 o | `id`, `maxValue`, `minMood`, `maxMood` |
| `riderbones` | 4 | 87 o | `id` |
| `rides` | 308 | 116 Ko | `id`, `nameId`, `colorId`, `speciesId`, `generation`, `geneticWeight`, `linkedItemGid`, `extractionRewardQuantity`, `senileExtractionRewardQuantity`, `breedingTokenRewardQuantity`, `breedingExperienceRewardQuantity`, `parents`, `children` |
| `ridespecies` | 3 | 191 o | `id`, `nameId`, `extractionRewardGid` |
| `servercommunities` | 14 | 5 Ko | `id`, `nameId`, `defaultCountries`, `shortId`, `supportedLangIds`, `namingRulePlayerNameId`, `namingRuleGuildNameId`, `namingRuleAllianceNameId`, `namingRuleAllianceTagId`, `namingRulePartyNameId`, `namingRuleMountNameId`, `namingRuleNameGeneratorId`, `namingRuleAdminId`, `namingRuleModoId`, `namingRulePresetNameId` |
| `servergametypes` | 6 | 556 o | `id`, `selectableByPlayer`, `nameId`, `rulesId`, `descriptionId` |
| `serverlangs` | 10 | 467 o | `id`, `nameId`, `langCode` |
| `serverpopulations` | 5 | 213 o | `id`, `nameId`, `weight` |
| `servers` | 27 | 4 Ko | `id`, `nameId`, `commentId`, `language`, `populationId`, `gameTypeId`, `communityId`, `monoAccount`, `illus` |
| `serverseasons` | 8 | 1 Ko | `uid`, `nameId`, `beginning`, `closure`, `resetDate`, `flagObjectId` |
| `signs` | 320 | 35 Ko | `signs` |
| `skillnames` | 364 | 12 Ko | `id`, `nameId` |
| `skills` | 368 | 141 Ko | `id`, `nameId`, `parentJobId`, `isForgemagus`, `modifiableItemTypeIds`, `gatheredRessourceItem`, `craftableItemIds`, `range`, `useRangeInClient`, `useAnimation`, `cursor`, `elementActionId`, `availableInHouse`, `clientDisplay`, `levelMin`, `allowMarking` |
| `skinmappings` | 38 | 1 Ko | `id`, `lowDefId` |
| `skinslotsrules` | 951 | 3 Mo | `skinId`, `slotRulesList` |
| `smileypacks` | 8 | 1 Ko | `id`, `nameId`, `order`, `smileys` |
| `smileys` | 222 | 21 Ko | `id`, `order`, `gfxId`, `forPlayers`, `referenceId`, `categoryId` |
| `soundbones` | 7182 | 4 Mo | `animSounds` |
| `speakingitemstexts` | 352 | 37 Ko | `textId`, `textProba`, `textStringId`, `textLevel`, `textSound`, `textRestriction` |
| `speakingitemstriggers` | 22 | 2 Ko | `textIds` |
| `spellbombs` | 10 | 1 Ko | `id`, `chainReactionSpellId`, `explodSpellId`, `wallId`, `instantSpellId`, `comboCoeff` |
| `spellbombwalls` | 8 | 652 o | `id`, `spellId`, `color`, `linear`, `minHop`, `maxHop` |
| `spelllevels` | 34697 | 77 Mo | `id`, `spellId`, `grade`, `spellBreed`, `apCost`, `minRange`, `range`, `criticalHitProbability`, `maxStack`, `maxCastPerTurn`, `maxCastPerTarget`, `maxGlobalCastPerTurn`, `maxGlobalCastPerTarget`, `minCastInterval`, `initialCooldown`, `globalCooldown`, `minPlayerLevel`, `statesCriterion`, `effects`, `criticalEffect`, `previewZones` |
| `spellpairs` | 726 | 51 Ko | `id`, `nameId`, `descriptionId`, `iconId` |
| `spellscripts` | 14929 | 1 Mo | `rawParams`, `type` |
| `spells` | 17067 | 15 Mo | `id`, `nameId`, `descriptionId`, `typeId`, `order`, `scriptParams`, `scriptParamsCritical`, `scriptId`, `scriptIdCritical`, `iconId`, `spellLevels`, `boundScriptUsageData`, `criticalHitBoundScriptUsageData`, `basePreviewZoneDescr`, `adminName` |
| `spellstates` | 6375 | 2 Mo | `id`, `nameId`, `preventsSpellCast`, `preventsFight`, `isSilent`, `cantBeMoved`, `cantBePushed`, `cantDealDamage`, `invulnerable`, `cantSwitchPosition`, `incurable`, `effectsIds`, `icon`, `iconVisibilityMask`, `invulnerableMelee`, `invulnerableRange`, `cantTackle`, `cantBeTackled`, `displayTurnRemaining`, `isMainState` |
| `spelltypes` | 3260 | 203 Ko | `id`, `longNameId`, `shortNameId` |
| `spellvariants` | 431 | 23 Ko | `id`, `breedId`, `spellIds` |
| `stealthbones` | 9 | 172 o | `id` |
| `subareas` | 562 | 592 Ko | `id`, `nameId`, `areaId`, `mapIds`, `bounds`, `shape`, `customWorldMapId`, `packId`, `level`, `isConquestVillage`, `basicAccountAllowed`, `displayOnWorldMap`, `mountAutoTripAllowed`, `psiAllowed`, `monsters`, `entranceMapIds`, `exitMapIds`, `capturable`, `achievements`, `exploreAchievementId`, `harvestables`, `associatedZaapMapId`, `neighbors`, `dungeonId` |
| `superareas` | 10 | 620 o | `id`, `nameId`, `worldmapId`, `hasWorldMap` |
| `taxcollectorfirstnames` | 151 | 5 Ko | `id`, `firstnameId` |
| `taxcollectornames` | 253 | 7 Ko | `id`, `nameId` |
| `texticonreferences` | 103 | 3 Ko | `referenceKey` |
| `titlecategories` | 10 | 313 o | `id`, `nameId` |
| `titles` | 539 | 48 Ko | `id`, `nameMaleId`, `nameFemaleId`, `visible`, `categoryId` |
| `veteranrewards` | 76 | 5 Ko | `id`, `requiredSubDays`, `itemGID`, `itemQuantity` |
| `waypoints` | 62 | 4 Ko | `id`, `mapId`, `subAreaId`, `activated` |
| `worldevents` | 23 | 8 Ko | `id`, `nameId`, `descriptionId`, `categoryId`, `level`, `areas`, `subareas`, `globalDrops`, `fightScenarios`, `deletedObjects`, `monsterHunterGroupsPerMap`, `dungeonHunterGroupsPerMap`, `preMsgId`, `startMsgId`, `endMsgId`, `preMsgDelay`, `worldEventRewardId`, `duration`, `worldEventDataType`, `worldEventEventId` |
| `worldeventsdungeons` | 86 | 10 Ko | `dungeonId`, `dungeonMapIdTeleport`, `scoreGroupShared`, `scorePerDamage`, `scorePerDungeon` |
| `worldeventsfarmingsimulator` | 191 | 5 Ko | `scorePerHarvest` |
| `worldeventsmonstershunter` | 187 | 26 Ko | `monsterList`, `criterion`, `mapList`, `subareaList`, `areaList`, `scoreGroupShared`, `scorePerDamage`, `scorePerMonster` |
| `worldeventsrewards` | 7 | 2 Ko | `worldEventRewardId`, `objects`, `emotes`, `spells`, `titles`, `ornaments`, `rankingConditions`, `criterions`, `experience`, `kamas`, `gameaction`, `guildPoints`, `isForTeam`, `order` |
| `worldeventsworldbosses` | 1 | 201 o | `monsterList`, `criterion`, `mapList`, `subareaList`, `areaList`, `scoreGroupShared`, `scorePerDamage`, `scoreTotal`, `scoreRatio`, `scoreDayCount` |
| `worldmaps` | 40 | 9 Ko | `id`, `nameId`, `origineX`, `origineY`, `mapWidth`, `mapHeight`, `minScale`, `maxScale`, `startScale`, `totalWidth`, `totalHeight`, `zoom`, `visibleOnMap` |
