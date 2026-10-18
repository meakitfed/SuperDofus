# Sources des règles et scénarios de référence

Objectif : chaque règle du jeu est **la vraie règle de Dofus**, avec sa source citée dans le code. Quand ce n'est pas encore possible, c'est une approximation marquée `APPROX(<lot>): raison`, listée plus bas, que le lot indiqué doit corriger.

## Où trouver une règle, par ordre de confiance

1. **Formules officielles du client** : la table `luaformulas`, en Lua (voir l'index plus bas). Chaque formule est lisible dans `game/content/Content/Data/luaformulas/<id>.lua`, après `python tools/rules_sources.py`. Dans le code, citer `luaformulas <id>`. Exemples : 99 (XP de groupe), 100 (XP du joueur), 106 (prospection), 74/77 (table d'XP).
2. **Tables de données Dofus 3** : `docs/data_catalog.md` indique quelle table sert à quoi. Dans le code, citer `table.champ` (ex. `breeds.statsPointsForStrength`, `spelllevels.criticalHitProbability`). Les champs `*Criterion`/`criteria` (ex. `BT=1`, `HS=498`, `PL>50`) sont des conditions : un seul évaluateur doit les lire : `CriteriaEval` (objets depuis P1.06, puis quêtes et PNJ) ; les états des sorts (`HS=`) passent encore par `FightRules.criterion_ok`.
3. **Code natif du client** (P1.13g) : ce que le client calcule lui-même (formes de zone, aperçus de sorts…) est dans `GameAssembly.dll`, compilé par IL2CPP. `python tools/client_code/client_code.py` retrouve une méthode par son nom ou son adresse (assemblys Cpp2IL de MelonLoader), ses appelants, et la décompile avec Ghidra (projet hors du dépôt, dans `%LOCALAPPDATA%/SuperDofus/client_code` : c'est le code d'Ankama, ne jamais le commiter). C'est la règle telle que le client l'applique : citer `client code <Type>.<méthode>` (ex. `SpellZoneShapeForkBehavior`, `gru.blgy` pour les noms obfusqués) et décrire ce qu'elle fait. Les chaînes littérales du client sont chiffrées : `client_code.py strings` (une fois) les déchiffre, et `decomp` les écrit alors en clair (`STR('a')`) à la place des appels `<PrivateImplementationDetails>.a::xxx()` (P1.13h). Les types que le code lit par un emplacement de métadonnées (`lRam00000001862770e0`) : `client_code.py usage <adresse>` (le nom du type, IL2CPP v39) et `refs <adresse>` (les fonctions qui le lisent) ; `methods.cs … x` donne le type de chaque champ (P1.13k).
4. **Enums du client** : `docs/client_enums.md` (généré par `tools/client_enums/client_enums.cs`) donne le nom officiel de chaque effet (`Metadata.Effect.ActionId`), de chaque lettre de zone (`Metadata.Enums.SpellZoneShape`) et la liste des codes de déclencheurs. Un nom est une source pour le sens, pas pour le détail du calcul. Citer `client enum <Type>`.
5. **Comportement observé dans le client officiel** : ce qu'on voit en jeu, par exemple le timing des animations ou l'ordre des événements. Le noter avec la date et la version du client.
6. **Documentation communautaire** (wikis, guides de formules Dofus 2 et 3) : citer le lien et marquer `APPROX` tant que ce n'est pas confirmé par 1 à 4.
7. **Invention** : seulement pour ce qui n'existe pas côté client (données serveur Ankama, voir « Absent du client » dans `docs/data_catalog.md`). Toujours marquée `APPROX` et configurable dans le JSON du monde.

Les données serveur absentes du client (position des PNJ, boutiques, kamas des monstres, taille des groupes, prix des zaaps) se définissent dans `game/worlds/<monde>/`, jamais en dur dans la sim.

## Scénarios de référence (non-régression et parité serveur)

`game/tests/scenarios/*.jsonl` : une seed, des commandes horodatées et les événements attendus (format en tête de `game/src/api/scenario.gd`). `tests/test_scenarios.gd` les rejoue tous sur `LocalBackend` ; le serveur (lot S.07) rejouera les mêmes fichiers.

- Seuls les événements de règles sont figés (`Scenario.RECORDED`). L'errance des monstres et les détails d'animation ne le sont pas.
- Un scénario qui échoue signale soit une régression, soit un changement de règle voulu. Dans ce cas, on le réenregistre et on le note dans le Journal de la roadmap.
- Chaque lot de règles ajoute ou met à jour au moins un scénario.

```bash
# enregistrer (le bot ScenarioBot joue les combats : --bot=fight, --bot=fight:<spells.id> pour lancer ce sort d'abord, ou --bot=pass pour perdre)
godot --headless --path game -s res://tools/sim_cli.gd -- --world=incarnam --seconds=150 --cmd=500:fight_attack \
      --bot=fight '--character={"level":10,"xp":19200,"stats":{"strength":40,"vitality":60},"hp":160}' \
      --record=res://tests/scenarios/fight_won.jsonl "--doc=Ce que le scénario fige"
# rejouer et vérifier un seul scénario
godot --headless --path game -s res://tools/sim_cli.gd -- --scenario=res://tests/scenarios/fight_won.jsonl
# réenregistrer (même en-tête, mêmes commandes, nouvelles attentes) après un changement de règle voulu
godot --headless --path game -s res://tools/sim_cli.gd -- --rerecord=res://tests/scenarios/fight_won.jsonl
```

| Scénario | Ce qu'il fige |
|---|---|
| `explore.jsonl` | déplacement, changement de map, refus typés (`unknown_stat`, `bad_cell`, `no_exit`) |
| `fight_won.jsonl` | combat gagné par le bot niveau 10 : placement, initiative, déplacements, sorts et effets, Karcham porte un Tofu puis le lance (P1.12), tours des monstres, XP, kamas, objets |
| `fight_lost.jsonl` | défaite d'un niveau 1 qui passe : IA des Tofus, mort, retour au point de sauvegarde avec 1 PV, 10 points d'énergie perdus (P1.10) |
| `look.jsonl` | apparence : chapeau puis bouclier de l'intrépide ajoutés au look (`actor_look`), chapeau retiré (P1.06b, skins JondoEmu mesurés) |
| `doors.jsonl` | portes (P1.07b) : trop loin refusé (`no_exit`), porte des Champs utilisée depuis une case voisine, arrivée à côté de la porte de la maison, sortie |
| `summons.jsonl` | invocation (P1.11) : un Osamodas niveau 10 (bot) invoque un Tofu (monstre 8070, 50 PV), qui joue juste après lui ; victoire |
| `traps.jsonl` | pièges (P1.13a) : un Sram niveau 15 (bot) pose un Piège Sournois, un monstre s'arrête dessus en marchant : piège retiré, dommages Feu, attiré vers le centre (`fighter_move.triggered`) ; victoire |
| `triggers.jsonl` | effets déclenchés (P1.13b) : un Sram niveau 5 (bot) empoisonne un monstre avec Arsenic (TB, 2 tours) : dommages Air au début des tours de la cible (`fight_turn.effects`) ; victoire |
| `invisible.jsonl` | invisibilité (P1.13c) : un Sram niveau 5 (bot) se rend invisible 1 tour : les monstres ne le visent ni ne le suivent, puis `reveal` avec sa case ; victoire |
| `smithmagic.jsonl` | forgemagie (P2.07a, tout APPROX) : une Cape du Justicier, un puits vide refuse la Rune Fo, 14 Runes Pui (issues, puits rempli par les échecs), puis la Rune Fo passe en overmax ; objet inconnu et rune épuisée refusés |
| `bombs.jsonl` | runes et bombes (P1.13d) : un Roublard niveau 10 (bot) pose une Explobombe près d'un monstre et la fait exploser au Détonateur (`explode`, réaction en chaîne puis explosion : dommages en cercle 2, la bombe meurt), à chaque tour ; P1.11b : sans équipement, ses bombes n'héritent de rien (environ 10 dommages par explosion) et il perd |
| `portals.jsonl` | portails (P1.13f) : un Eliotrope niveau 180 (bot, variante Exil) pose un Portail à côté de lui, Exil pose un portail sous un monstre et le fait traverser (`move` how `portal`), puis Affront est projeté par le portail (`projected` : il tombe sur la sortie avec le bonus par case, sans la poussée `r`) |
| `intercept.jsonl` | interception (P1.13e) : un Enutrof niveau 5 (bot) invoque un Sac Animé à côté de lui (765 sur les alliés en cercle 2) : les coups des monstres sur l'Enutrof vont au Sac jusqu'à sa mort, puis de nouveau à lui |
| `quests.jsonl` | quêtes (P2.03) : la quête 1639 « Transport peu commun » d'Incarnam de bout en bout : proposée en réponse du PNJ (1001639), acceptée (`quest_start`), parler à 2882 puis la map atteinte (`quest_update`), retour au PNJ (`quest_complete` : XP, kamas, 5 x 16513), la suite 1640 est alors offerte |
| `double.jsonl` | masque `U` (P1.13k) : un Sram niveau 10 lance Double à côté de lui ; le sous-sort 1041005 et l'état 1486 (masque `a,U`) ne touchent que le double invoqué pendant ce lancer (`gvs.bmdp`) |
| `bank.jsonl` | coffre de compte (P2.08) : coffre fermé refusé (`no_bank`), dépôt d'objets (effets conservés) et de kamas, retrait trop grand (`not_enough_kamas`), retrait d'une pile, fermeture, réouverture payante (1 kama par pile, APPROX) |

## Registre des approximations

Généré par `python tools/rules_sources.py` à partir des commentaires `APPROX` du code.

<!-- APPROX:START -->
| Où | Lot qui corrigera | Approximation |
|---|---|---|
| `game/src/client/map_cursor.gd:39` | P2.05c | the Dofus cursors (tools, one per |
| `game/src/client/market_model.gd:8` | P2.10b | itemtypes.categoryId has no name in the client tables, the |
| `game/src/server/admin/admin_actions.gd:14` | A1.02a | give / kamas / level / heal / tp / kick need the player connected and out of a |
| `game/src/server/admin/admin_actions.gd:50` | A1.01 | tables only) |
| `game/src/server/auth/auth_service.gd:18` | S.02b | 10 minutes, a fight that lasts longer releases the character anyway |
| `game/src/server/auth/password_hash.gd:4` | S.02a | Godot has neither argon2 nor bcrypt without a GDExtension, so the |
| `game/src/server/cluster/world_cluster.gd:11` | S.04b | removing an instance keeps its saved characters (a later `create` of the same |
| `game/src/server/persistence/server_persistence.gd:18` | S.03 | 10, as the roadmap says |
| `game/src/server/persistence/server_persistence.gd:20` | S.03 | 5 min, so that a character |
| `game/src/server/security/address_penalties.gd:5` | S.05c | 3 cuts in 10 min = 10 min of ban, values without a source. Nothing here |
| `game/src/server/server_host.gd:18` | S.05 | no source (nothing Dofus): a token bucket per connection |
| `game/src/server/server_host.gd:70` | S.02b | 20 s = two pings of NetBackend (every 10 s) |
| `game/src/server/server_host.gd:95` | S.03 | 5 min |
| `game/src/server/server_host.gd:109` | S.05c | burst 10 then 2 per |
| `game/src/server/server_host.gd:288` | S.02a | two friends behind the |
| `game/src/server/world_assets.gd:20` | C.02b | an item the world never hands out (admin `give`, an item of another world) has no |
| `game/src/server/world_assets.gd:269` | C.02e | the sizes count what each block downloads alone; two blocks that share a texture |
| `game/src/shared/chat.gd:34` | P3.02 | no flood constant in the Dofus data (constants / chatchannels). Values |
| `game/src/shared/chat.gd:43` | P3.02 | length limit of a message (Dofus 2: 256 characters) |
| `game/src/shared/contacts.gd:8` | P3.05 | the data has no list limit or exclusivity rule (tables of the social |
| `game/src/shared/contacts.gd:11` | P3.05 | adding a friend is one-way and immediate (no request / acceptance). |
| `game/src/shared/crafting.gd:11` | P2.06 | ingredient slots of a job level = 2, +1 every 20 levels, at most 8 |
| `game/src/shared/crafting.gd:16` | P2.06 | XP of one craft = BASE + the level of the item (items.craftXpRatio is -1 for 96 % of the recipes |
| `game/src/shared/dungeon.gd:8` | P4.01 | the real group compositions of dungeon rooms are server data (absent). |
| `game/src/shared/dungeon.gd:43` | P4.01 | checked on the |
| `game/src/shared/dungeon.gd:54` | P4.01 | all are consumed on entry. |
| `game/src/shared/dungeon.gd:62` | P4.01 | the door opens then). |
| `game/src/shared/dungeon.gd:78` | P4.01 | 2-3 groups, bigger with the room index; the last room is one group of the |
| `game/src/shared/emotes.gd:26` | P3.02c | the emote is free when no quest / achievement reward gives it; the others need |
| `game/src/shared/equipment.gd:107` | P1.06 | the same item of a set only |
| `game/src/shared/fight_rules.gd:83` | P1.13l | the provider's line of sight is taken as the cast's (has_los: fighters block). |
| `game/src/shared/guild.gd:11` | P3.06a | the default rights of each rank (DEFAULT_RIGHTS) are ours, the data has none |
| `game/src/shared/guild.gd:13` | P3.06a | 200 members at most (Dofus 2); no guildalogemme item is consumed at creation. |
| `game/src/shared/item_effects.gd:13` | P2.05b | read from the scrolls (items 695 "Parchemin de Bucheron" = [614, 0, 2, 100]), |
| `game/src/shared/jobs.gd:14` | P2.05 | every job is known from the start at level 1 (Dofus 3 has no job to learn |
| `game/src/shared/jobs.gd:17` | P2.05 | time a harvest takes (the animation `skills.useAnimation` lasts about that long) |
| `game/src/shared/jobs.gd:19` | P2.05 | time a harvested resource takes to grow back |
| `game/src/shared/jobs.gd:62` | P2.05c | the job XP table is not in the client: it is not in |
| `game/src/shared/jobs.gd:99` | P2.05 | 1-2 at the level the resource needs, |
| `game/src/shared/map_data.gd:41` | P1.08 | the cell (the interactive's position) is picked on a capture (links.json) |
| `game/src/shared/map_data.gd:53` | P1.10 | phoenix positions are server data, absent from the client and |
| `game/src/shared/market_rules.gd:31` | P2.10b | a literal text, the client's own |
| `game/src/shared/party.gd:5` | P3.03 | the limit of 8 players and the 60 s lifetime of an invitation are the |
| `game/src/shared/protocol_duel.gd:11` | P3.10 | a challenge waits one minute (same as the trade invitation, no source in the client tables) |
| `game/src/shared/smithmagic.gd:35` | P2.07 | weight of one unit, in hundredths (effects.id -> weight x 100) |
| `game/src/shared/spell_book.gd:43` | P1.03 | Dofus 3 shows pages of spell shortcuts |
| `game/src/shared/stat_formulas.gd:15` | P1.04 | base pods, strength bonus and base summons/crit are the |
| `game/src/shared/stat_formulas.gd:77` | P1.04 | community formula, not in the client data. |
| `game/src/shared/stat_formulas.gd:85` | P1.04 | community formula |
| `game/src/shared/stat_formulas.gd:94` | P1.04 | community formula |
| `game/src/shared/stat_formulas.gd:111` | P1.04 | community formula |
| `game/src/shared/trade_rules.gd:4` | P3.11 | the numbers below (60 s invitation, 20 stacks per offer, quantity cap) are |
| `game/src/shared/travel.gd:14` | P1.08 | community rule (Dofus 2), prices are server data in Dofus 3. |
| `game/src/sim/achievements.gd:11` | P2.12a | only the achievements whose every objective uses a key above are kept (725 of 2780); the others |
| `game/src/sim/achievements.gd:13` | P2.12a | "EM>id,0,d" (beat the monster in its dungeon) counts any win against the monster. |
| `game/src/sim/character.gd:9` | P5.05 | real regen rate (sitting x2…) not sourced |
| `game/src/sim/character.gd:180` | P1.04 | free and out of fight; in Dofus it takes a restat item or NPC |
| `game/src/sim/character_roster.gd:7` | P1.01 | the real per-server slot count (subscription, bonus slots) is server-side, not in the client data. |
| `game/src/sim/character_roster.gd:39` | P1.01 | Dofus also refuses reserved or |
| `game/src/sim/dialog.gd:12` | P2.01 | the real server's tree (which message follows which reply, and the |
| `game/src/sim/energy.gd:25` | P1.10 | the threshold is server-side, not in the sources |
| `game/src/sim/energy.gd:30` | P1.10 | capped at level 200 (omega levels are not in the sources) |
| `game/src/sim/fight/bonus_drops.gd:7` | S.06 | the official Temporis tables (monsters.temporisDrops) are |
| `game/src/sim/fight/carry.gd:14` | P1.12 | a carried fighter that walks away frees |
| `game/src/sim/fight/fight.gd:14` | P1.15 | no extra time kept) |
| `game/src/sim/fight/fight.gd:19` | S.02b | 60 s, not in the sources |
| `game/src/sim/fight/fight.gd:505` | P1.14 | community tackle formula (kept share = (escape + 2) / (2 x (tackle + 2))) |
| `game/src/sim/fight/fight.gd:569` | P1.13f | a spell needing a fighter may target a portal it would be projected through |
| `game/src/sim/fight/fight_ai.gd:10` | P1.13c | it does not guess where they are). |
| `game/src/sim/fight/fight_ai.gd:26` | P1.16 | then it fights back (Dofus monsters do not flee at all): a runner nobody can catch stalls the fight |
| `game/src/sim/fight/fight_ai.gd:219` | P1.11 | a summon is worth a good hit, on a free cell |
| `game/src/sim/fight/fight_buffs.gd:6` | P1.14 | community formula, no counterpart in luaformulas (checked), pinned by tests/test_formulas.gd. |
| `game/src/sim/fight/fight_buffs.gd:98` | P1.18 | i18n text only; the buffs that a dispel would remove (dispellable 1), a buff |
| `game/src/sim/fight/fight_buffs.gd:176` | H.04c | a target cannot lose more points than it holds (a removal of 100 AP, Noyade, took up to |
| `game/src/sim/fight/fight_buffs.gd:255` | P1.13d | counted |
| `game/src/sim/fight/fight_buffs.gd:269` | P1.13b | (voir le code) |
| `game/src/sim/fight/fight_challenges.gd:10` | P1.15 | its value is server data (not in the client): BONUS per successful challenge |
| `game/src/sim/fight/fight_challenges.gd:12` | P1.15 | number of challenges (1 to 2 per fight, "challenges" roadmap line): 2 when the |
| `game/src/sim/fight/fight_challenges.gd:14` | P1.15 | activationCriterion: only GN>n,team / GN<n,team (fighters of a team) and |
| `game/src/sim/fight/fight_displace.gd:55` | P1.14 | community collision formula, pinned by tests/test_formulas.gd PUSH_CASES |
| `game/src/sim/fight/fight_displace.gd:106` | P1.13q | the client's symmetry point is not read, the cast cell is taken |
| `game/src/sim/fight/fight_displace.gd:128` | P1.18 | going back is not a move of the history (Mot Farceur rolls back |
| `game/src/sim/fight/fight_effects.gd:21` | P1.13d | spells.py) (P1.13d). |
| `game/src/sim/fight/fight_effects.gd:55` | P1.13j | poisons and trigger buffs keep their full damage (the preview only |
| `game/src/sim/fight/fight_effects.gd:58` | P1.13r | the harmful ones, no source. |
| `game/src/sim/fight/fight_effects.gd:156` | P1.18b | a one-turn state the spell sets on its caster is a flag of this very cast (Runification: |
| `game/src/sim/fight/fight_effects.gd:291` | P1.18d | the monsters |
| `game/src/sim/fight/fight_effects.gd:331` | P1.18 | a buff lasting its duration, at least the current turn, as the other buffs |
| `game/src/sim/fight/fight_life.gd:6` | P1.13d | applied last, after the |
| `game/src/sim/fight/fight_life.gd:10` | P1.18 | the client enum names and i18n texts only, applied multiplicatively after |
| `game/src/sim/fight/fight_life.gd:15` | P1.13f | after everything else (the text only says "augmentés"). |
| `game/src/sim/fight/fight_life.gd:54` | P1.13o | no formula found (luaformulas, client enums, JondoEmu): the amount is |
| `game/src/sim/fight/fight_life.gd:64` | P1.17b | i18n text only; the caster's current life, the receiver is healed as by any heal |
| `game/src/sim/fight/fight_life.gd:79` | P1.17b | i18n text only |
| `game/src/sim/fight/fight_life.gd:95` | P1.17 | only the i18n text "#1% PV de la cible", current life, then the usual formula) or |
| `game/src/sim/fight/fight_life.gd:97` | — | the caster's current life, dice = the %). |
| `game/src/sim/fight/fight_life.gd:129` | P1.17b | only the |
| `game/src/sim/fight/fight_life.gd:143` | P1.17b 9 | only the i18n text. |
| `game/src/sim/fight/fight_life.gd:227` | P1.14 | base 10 % + stat `erosion` (776), capped at 50 %: community values; no formula in |
| `game/src/sim/fight/fight_marks.gd:15` | P1.13d | one rune of a caster per cell, the new one replaces the old |
| `game/src/sim/fight/fight_marks.gd:19` | P1.13e | nothing more |
| `game/src/sim/fight/fight_marks.gd:25` | P1.13d | same-monster pairs, the hop = the |
| `game/src/sim/fight/fight_marks.gd:37` | P1.13f | Exil still sends them through). |
| `game/src/sim/fight/fight_marks.gd:190` | P1.17b | (voir le code) |
| `game/src/sim/fight/fight_rewards.gd:4` | P1.09 | the monsters' kamas ranges and their sharing are not Dofus 3 data |
| `game/src/sim/fight/fight_triggers.gd:15` | P1.13b | (voir le code) |
| `game/src/sim/fight/fight_triggers.gd:17` | P1.13i | nor by a poison), DT / DG by a trap's / a glyph's spell (flags of |
| `game/src/sim/fight/fight_triggers.gd:21` | P1.13i | not for its push damage); CH it heals someone (not with 786 / 1164), CS |
| `game/src/sim/fight/fight_triggers.gd:22` | P1.13i | once per |
| `game/src/sim/fight/fight_triggers.gd:38` | P1.13m | the effect |
| `game/src/sim/fight/fight_triggers.gd:44` | P1.13m | the client also lights the author's ION / IOFF there; not here). |
| `game/src/sim/fight/fight_triggers.gd:47` | P1.13e | only walking, not MP lost otherwise. The client does not know this code |
| `game/src/sim/fight/fight_triggers.gd:58` | P1.13e | the amount is not re-reduced by its resistances. |
| `game/src/sim/fight/fight_triggers.gd:60` | P1.13e | even split, the remainder on the one hit. |
| `game/src/sim/fight/fight_triggers.gd:65` | P1.13b | (voir le code) |
| `game/src/sim/fight/fight_triggers.gd:69` | P1.13b | else "when hit, take 7 more" never ends), and chains stop at depth |
| `game/src/sim/fight/fight_triggers.gd:80` | P1.13p | the meaning is deduced from the descriptions, not measured on a capture. |
| `game/src/sim/fight/fight_triggers.gd:194` | P1.13m | Barricade / Bastion have dispellable 1 on their DIS trigger and say "s'il est |
| `game/src/sim/fight/fight_visibility.gd:8` | P1.13c | a spell it casts shows the other team the cell it casts from |
| `game/src/sim/fight/fighter.gd:143` | P1.17b | 280 adds to the minimum |
| `game/src/sim/fight/summons.gd:10` | P1.11b | not measured; read from the data, where these bonuses are shares: |
| `game/src/sim/fight/summons.gd:24` | P1.11 | the caster's copy (look, level, HP, characteristics), no spells. |
| `game/src/sim/fight/summons.gd:31` | P1.13d | the data does not say what casts chainReactionSpellId and |
| `game/src/sim/fight/summons.gd:94` | P1.17b | i18n text only (Roublardise, Goberration); an |
| `game/src/sim/fight/target_mask.gd:114` | H.04c | `*h` / `*m` / `*j`... (a side letter after the `*` of "on the caster", Ossuaire, |
| `game/src/sim/map_instance.gd:32` | P1.09 | monsters.aggressiveAttackDelay (10000 ms) is not used, its |
| `game/src/sim/monster_spawner.gd:12` | P1.09 | how many groups a map holds and how big they are is server |
| `game/src/sim/quest_engine.gd:17` | P2.03 | the order is not stated in the data (questobjectives has none): runs of one type are the reading |
| `game/src/sim/quest_engine.gd:23` | P2.03 | the dialogs of a quest step (queststeps.dialogId) are server data, absent from the client: the |
| `game/src/sim/quest_engine.gd:27` | P2.03 | a quest is offered whatever its levelMin (a recommended level, the real condition is the criteria). |
| `game/src/sim/quest_engine.gd:33` | P2.03 | the quest reward formulas are server code (queststeprewards only holds ratios): XP = ratio x this share |
| `game/src/sim/quest_engine.gd:42` | P2.04 | the meaning of repeatType is not in the client data (quests.repeatLimit is always 1, no delay field): |
| `game/src/sim/quest_engine.gd:264` | P2.03 | see XP_SHARE |
| `game/src/sim/subarea_bonus.gd:16` | P1.09 | the 2.51 system balances zones of the same level from the |
| `game/src/sim/world_admin.gd:15` | A1.01 | a mute without a duration lasts 10 minutes; ceiling one week |
| `game/src/sim/world_admin.gd:114` | A1.01 | reloads the data tables (GameData: items, XP, tables) read by the rules; the |
| `game/src/sim/world_chat.gd:92` | P3.02 | spectators hear nobody yet, P3.04) |
| `game/src/sim/world_contacts.gd:13` | S.05c | 2 s, so that the |
| `game/src/sim/world_crafting.gd:3` | P2.06 | no workshop element is needed (the workshops of the maps are server data absent from the |
| `game/src/sim/world_death.gd:5` | P1.10 | Dofus 2 behaviour (a ghost only |
| `game/src/sim/world_duel.gd:5` | P3.10 | a duel is allowed on every map and between any levels (Dofus 3 blocks it on some maps |
| `game/src/sim/world_dungeons.gd:90` | P4.01 | every member needs the level, the key is taken once, from the leader |
| `game/src/sim/world_dungeons.gd:144` | P4.01 | empty pool): straight on |
| `game/src/sim/world_dungeons.gd:170` | P4.01 | the real compositions are server data. |
| `game/src/sim/world_dungeons.gd:249` | P4.01 | the cell of the door is the one the player entered from (same map), else the centre |
| `game/src/sim/world_fight_watch.gd:6` | P3.04 | a spectator sees the fight like a team without sight of the invisible (no seat on |
| `game/src/sim/world_guild.gd:12` | P3.06a | two commands of two worlds on the same guild at the same instant are not |
| `game/src/sim/world_npcs.gd:31` | P2.01 | talking needs the player on a cell beside the NPC (like the zaap), the |
| `game/src/sim/world_party.gd:196` | P3.03 | they are placed next to the |
| `game/src/sim/world_sim.gd:330` | P1.10 | a ghost walks (the sources only say it is slow) |
| `game/src/sim/world_sim.gd:365` | P1.03 | out of fight only (Dofus: the spell book is locked in fight), not in the data |
| `game/src/sim/world_travel.gd:115` | P1.08 | a zaap is registered when its map is entered (the roadmap's |
| `tools/extractor/maps.py:327` | P1.09 | monster kamas are server-side data, absent from the client |
| `tools/extractor/spells.py:87` | P1.17b | only the i18n text, no formula found |
| `tools/extractor/spells.py:128` | P1.17b | erosion itself is not simulated, nothing reads "erosion") |
| `tools/extractor/spells.py:131` | P1.17b | from the enum names only |
| `tools/extractor/spells.py:136` | P1.17b | signs and stat names from the enum names only |
| `tools/extractor/spells.py:184` | P1.11 | 1011 and 1008 (bombs) have the same text |
| `tools/extractor/spells.py:188` | P1.17b | i18n text only |
| `tools/extractor/spells.py:196` | — | the state is removed, not suspended) |
| `tools/extractor/spells.py:227` | P1.13f | A = every portal, read from its description |
| `tools/extractor/spells.py:232` | P1.13f | nothing in the data casts 24955 / 24956 |
| `tools/extractor/spells.py:239` | P1.13b | read from the data, not measured: the Sram's |
| `tools/extractor/spells.py:253` | P1.13r | nothing in the client names the fields |
| `tools/extractor/spells.py:260` | P1.17b | only the i18n texts. |
| `tools/extractor/spells.py:262` | — | i18n text only) |
| `tools/extractor/spells.py:264` | P1.13c | (voir le code) |
| `tools/extractor/spells.py:269` | P1.13f | read |
| `tools/extractor/spells.py:291` | P1.13p | not measured |
| `tools/extractor/spells.py:313` | P1.17b | a global cast limit on the target we cannot read; the spells keep their own per_turn / per_target |
| `tools/extractor/spells.py:314` | P1.17b | the target following its caster's moves is not simulated |
| `tools/extractor/spells.py:316` | P1.17b | the player does not take over the entity's turn, FightAI keeps playing it |
| `tools/extractor/spells.py:320` | P1.13d | not shown) |
| `tools/extractor/spells.py:322` | P1.18 | FightAI keeps its own profile |
| `tools/extractor/spells.py:696` | P1.13e | a delayed kill of the caster in a summoning spell kills the summon. |
<!-- APPROX:END -->

## Index des formules officielles (`luaformulas`)

Généré par `python tools/rules_sources.py`.

<!-- FORMULAS:START -->
| Id | Paramètres | Commentaire |
|---|---|---|
| 2 | monster_level, monster_is_boss |  |
| 3 | monster_level, monster_grade_hidden_level, stat_base, monster_grade_level | By pass for monsters with 0 pm remains 0 pm : no scale but remains boostable, -1pm remains |
| 4 | monster_level, stat_ratio |  |
| 5 | monster_level, stat_ratio, stat_base |  |
| 12 | monster_level, monster_grade_hidden_level, stat_base, monster_grade_level |  |
| 46 | sum_of_jobs_earned_levels |  |
| 56 | ib_floor, ib_room_absolute_score, ib_room_relative_score |  |
| 69 | ib_floor, ib_room_absolute_score, ib_room_relative_score | Coefficient d'expérience finale en fonction du score de la salle. |
| 70 | monster_level, monster_grade_hidden_level, monster_grade_level |  |
| 74 | experience |  |
| 76 | tempoken |  |
| 77 | level |  |
| 78 | item_quantity_20763 |  |
| 79 | tempoken |  |
| 80 | item_quantity_20763 |  |
| 83 | item_quantity_20763 |  |
| 84 | tempoken |  |
| 85 |  |  |
| 86 | number_controlled_territories |  |
| 89 | number_controlled_territories |  |
| 91 |  |  |
| 94 | guild_level |  |
| 97 | number_players_my_alliance, number_players_opponent_alliance, roles_variation |  |
| 98 | number_players_my_alliance, number_players_opponent_alliance, roles_variation |  |
| 99 | players, monsters, fightIsWin, rewardRate | players : list of fighter data |
| 100 | xp, monsters, player, maxLevel, challengeCoefficient | xp : initial xp earn from monsters |
| 101 |  |  |
| 102 |  |  |
| 103 | xp, player, bonus, percentage | xp : experience earn from the player |
| 104 | my_alliance_score, opponent_alliance_score, total_score_koth, target_value |  |
| 105 | my_alliance_score, opponent_alliance_score, total_score_koth, target_value |  |
| 106 | prospection_bonus | Fontion exponentielle |
| 107 | item_quantity_20763 |  |
| 108 | tempoken |  |
| 109 | player_level |  |
| 110 | player_level |  |
| 111 | lvl |  |
| 115 | lvl | lvl : Guild level |
<!-- FORMULAS:END -->
