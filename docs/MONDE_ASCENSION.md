# L'Ascension (monde `ascension`)

Une tour à gravir étage par étage. Elle réutilise les maps, décors, apparences de PNJ (et plus tard les monstres) de Dofus. La progression, les objets, les panoplies et l'apprentissage des sorts (façon roguelike) seront propres à ce monde ; tout cela reste à faire.

## Ce qui existe (premier jet)
- **5 étages**, chacun composé de 10 à 18 vraies maps d'extérieur Dofus, reliées comme dans Dofus. Un étage ne mène qu'à lui-même : toute liaison vers une map hors de l'étage est coupée, donc on ne peut pas en sortir à pied.

  | Étage | Nom | Origine |
  |---|---|---|
  | 1 | Les Prairies | Incarnam : Champs + Pâturages |
  | 2 | Les Îlots | Île des Wabbits : Îlot de la Couronne + Îlot de Waldo |
  | 3 | La Jungle | Île de Moon : Forêt des Masques |
  | 4 | Le Rivage | Otomaï : Île des naufragés |
  | 5 | Le Givre | Frigost : Port de givre |

- Sur la map d'arrivée de chaque étage, un **Gardien de l'escalier** (apparence du Gardien Paspartou). Son dialogue propose « Monter à l'étage N+1 » et « Descendre à l'étage N-1 », sans condition pour l'instant. On peut ensuite y ajouter un critère dans l'Atelier, par exemple une quête finie (`Qf=`) ou un objet possédé (`PO=`).
- On commence sur l'étage 1. Les maps d'arrivée servent de maps de renaissance.
- Classes : celles de Dofus (`breeds: []`), en attendant le système de sorts propre au monde.
- Monstres : voir plus bas.

## Monstres et butin
- **Tous les monstres Dofus** (mêmes ids, stats et sorts ; 1 156 monstres, 101 boss de donjon) sont répartis **par tranche de niveaux**, une par étage : 1-40, 41-80, 81-120, 121-160, 161-200.
- **Dégradé** : chaque étage est découpé en anneaux autour du gardien (distance en maps). Le hub n'a pas de monstres. Le premier anneau tire dans le bas de la tranche (1-16 à l'étage 1), le plus lointain dans le haut (25-40). Chaque anneau est une zone de monstres de l'Atelier, avec :
  - `levels` : seuls les grades dans la fourchette sont tirés ;
  - `bosses` : les boss de donjon de la fourchette (ou les plus proches de la tranche) ;
  - `boss_pct: 5` : chaque membre d'un groupe a 5 % de chances d'être un de ces boss, donc plusieurs boss par groupe sont possibles.
- **Groupes** : 1 à 4 monstres tirés au hasard dans la zone, une nouvelle composition à chaque réapparition (`MonsterSpawner`).
- **Butin : des équipements seulement.**
  - Les monstres ne lâchent plus de ressources (`drops` vides) ; XP et kamas sont gardés.
  - `world.json` `rates` force les **drops bonus** façon Temporis (S.06, `BonusDrops`) à 5 % par monstre tué et par joueur (× prospection / 100), quels que soient les réglages du serveur.
  - Une fois sur deux, l'objet vient des panoplies liées aux monstres tués (des bouftous → pano Bouftou), sinon d'un équipement sans panoplie à ±15 niveaux.
- Les sorts que les données ne connaissent pas encore sont retirés à la copie (le jeu les ignore aussi pour le monde `dofus`), les portraits absents aussi. Les monstres sans squelette dans le contenu sont écartés (17 aujourd'hui).
- `world.json` `"base": "dofus"` dit à l'Atelier que le monde utilise les sorts, monstres et images de Dofus sans les copier : ils ne comptent ni comme erreurs de plage d'ids ni comme fichiers manquants.

## Construction
Le monde est fait par l'Atelier, à partir d'une **recette** commitée : `worlds_src/ascension/recipe.json`. Elle contient la liste des maps Dofus de chaque étage, la map d'arrivée et le PNJ dont le gardien prend l'apparence.

```bash
cd atelier
npm run recipe -- ../worlds_src/ascension/recipe.json            # crée game/worlds/ascension (refuse s'il existe)
npm run recipe -- ../worlds_src/ascension/recipe.json --force    # le reconstruit sur le même emplacement d'ids
npm run recipe -- ../worlds_src/ascension/recipe.json --monsters # refait seulement les monstres (garde les maps, PNJ, dialogues…)
python ../worlds_src/ascension/pick_maps.py --subarea 444         # aide : les maps d'extérieur d'une sous-zone
python ../worlds_src/ascension/pick_maps.py 154010373 444,445 --max 17   # un groupe relié, à coller dans la recette
```

- `atelier/core/recipe_monsters.ts` pose les monstres (section `monsters` de la recette : tranches, largeur d'un anneau, `boss_pct`, `rates`). `--monsters` réécrit `monsters.json` et les zones des maps, rien d'autre : les monstres retouchés dans l'Atelier sont alors perdus.
- `atelier/core/recipe.ts` passe par les éditeurs de l'Atelier :
  - `importDofusMap` copie la grille, le décor et les images ;
  - `createNpc` et `setDialog` créent les gardiens et leurs dialogues.
- Chaque map garde ses `coords`, ses `map_change` (les vraies cases de sortie) et sa map d'origine (`source`).
- Le monde obtenu a 0 erreur au validateur.
- Les ids viennent de l'emplacement réservé dans `atelier/world_ranges.json` : maps 1 900 100 000+, PNJ 1 450 100 000+, textes 1 000 100 000+.

**Servir le monde** (le serveur sert tous les mondes par défaut) : après chaque changement de maps ou de monstres, refaire la liste des assets Dofus du monde puis le publier, sinon les clients n'ont pas les squelettes des monstres.
```bash
godot --headless --path game -s res://tools/world_assets.gd -- --world=ascension   # worlds/ascension/_content.json (~5 Go référencés)
serveur.bat publier                                                                 # incrémental : seuls les nouveaux fichiers sont écrits
```

**`game/worlds/ascension/` n'est pas commité** : il contient des données tirées de Dofus (règle du `.gitignore`). Seule la recette l'est.

**Reconstruire avec `--force` efface tout ce qui a été modifié dans l'Atelier.** Une fois le travail commencé dans l'Atelier, n'utiliser la recette que pour repartir de zéro.

## Tests
- `game/tests/test_ascension_world.gd` (`LocalBackend`) vérifie deux choses :
  - les 5 étages sont fermés et ne dépassent pas 20 maps chacun ;
  - le gardien fait monter puis redescendre ;
  - pas de monstre sur les hubs, des groupes dans la tranche de l'étage partout ailleurs, un combat gagné ne donne que des équipements bonus.
- `game/tests/test_spawn.gd` (zones `levels` / `bosses` / `boss_pct`) et `game/tests/test_rates.gd` (`rates` d'un monde, en local et via le serveur).
- `game/tests/test_ascension_net.gd` vérifie la montée à travers un serveur sur 127.0.0.1.
- Ces deux tests sont ignorés si le monde n'est pas construit sur la machine.
- `atelier/tests/recipe.test.ts` construit une recette miniature sur un faux Dofus.
