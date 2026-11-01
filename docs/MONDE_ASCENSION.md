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
- Pas encore de monstres : `monster_spawn: false` partout.

## Construction
Le monde est fait par l'Atelier, à partir d'une **recette** commitée : `worlds_src/ascension/recipe.json`. Elle contient la liste des maps Dofus de chaque étage, la map d'arrivée et le PNJ dont le gardien prend l'apparence.

```bash
cd atelier
npm run recipe -- ../worlds_src/ascension/recipe.json            # crée game/worlds/ascension (refuse s'il existe)
npm run recipe -- ../worlds_src/ascension/recipe.json --force    # le reconstruit sur le même emplacement d'ids
python ../worlds_src/ascension/pick_maps.py --subarea 444         # aide : les maps d'extérieur d'une sous-zone
python ../worlds_src/ascension/pick_maps.py 154010373 444,445 --max 17   # un groupe relié, à coller dans la recette
```

- `atelier/core/recipe.ts` passe par les éditeurs de l'Atelier :
  - `importDofusMap` copie la grille, le décor et les images ;
  - `createNpc` et `setDialog` créent les gardiens et leurs dialogues.
- Chaque map garde ses `coords`, ses `map_change` (les vraies cases de sortie) et sa map d'origine (`source`).
- Le monde obtenu a 0 erreur au validateur.
- Les ids viennent de l'emplacement réservé dans `atelier/world_ranges.json` : maps 1 900 100 000+, PNJ 1 450 100 000+, textes 1 000 100 000+.

**`game/worlds/ascension/` n'est pas commité** : il contient des données tirées de Dofus (règle du `.gitignore`). Seule la recette l'est.

**Reconstruire avec `--force` efface tout ce qui a été modifié dans l'Atelier.** Une fois le travail commencé dans l'Atelier, n'utiliser la recette que pour repartir de zéro.

## Tests
- `game/tests/test_ascension_world.gd` (`LocalBackend`) vérifie deux choses :
  - les 5 étages sont fermés et ne dépassent pas 20 maps chacun ;
  - le gardien fait monter puis redescendre.
- `game/tests/test_ascension_net.gd` vérifie la montée à travers un serveur sur 127.0.0.1.
- Ces deux tests sont ignorés si le monde n'est pas construit sur la machine.
- `atelier/tests/recipe.test.ts` construit une recette miniature sur un faux Dofus.
