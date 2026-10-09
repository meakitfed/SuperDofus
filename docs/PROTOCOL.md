# Protocole SuperDofus (version 2)

Généré depuis `game/src/shared/protocol.gd` (`SCHEMA`) par `tools/protocol_doc.gd` : ne pas éditer à la main.

Chaque message est un objet JSON `{t, seq?, …}`. Les commandes sont numérotées par le client ; les événements sont numérotés par la sim, par session. Une erreur porte `ref`, le `seq` de la commande refusée. Les champs en plus sont tolérés, et un champ manquant ou mal typé fait rejeter la commande (`error{code: bad_message}`). Les nombres peuvent revenir en flottants après JSON : faire `int()` à la lecture.

## Client → Jeu

| Type | Champs | Sens |
|---|---|---|
| `hello` | `v`: int, `world`: str, `name`: str?, `look`: str? | Se connecter à un monde. Sans `name` : liste des personnages (characters) ; avec : joue ce personnage, créé au besoin (outils, tests) |
| `list_characters` | — | Choix du personnage : redemander la liste |
| `create_character` | `name`: str, `breed`: int?, `sex`: int?, `body`: int?, `head`: int?, `colors`: array? | Choix du personnage : créer (nom selon namingrules, classe = breeds.id, sexe 0/1, corps = bodies.id, visage = heads.id, couleurs : une par couleur de la classe, -1 = défaut) |
| `delete_character` | `name`: str | Choix du personnage : supprimer définitivement |
| `select_character` | `name`: str | Choix du personnage : jouer (réponse : welcome) |
| `move` | `cell`: int, `run`: bool | Marcher vers une cellule ; la sim calcule et valide le chemin |
| `change_map` | `dir`: str | Passer sur la map voisine (joueur sur une cellule de sortie de ce côté : map.map_change) |
| `use_zaap` | — | Utiliser le zaap de la map (joueur à côté) : réponse zaap_list |
| `zaap_travel` | `map`: int | Voyager vers un zaap connu (joueur à côté d'un zaap ; coûte des kamas) |
| `set_save_point` | — | Enregistrer le zaap de la map comme point de sauvegarde (joueur à côté) |
| `use_phoenix` | — | Fantôme : ressusciter au phénix de la map (joueur à côté) ; énergie rendue |
| `npc_talk` | `npc`: int | Parler à un PNJ de la map (joueur à côté) : réponse dialog |
| `dialog_reply` | `reply`: int | Choisir une réponse du dialogue ouvert (dialog.replies[].id) : réponse dialog ou dialog_end |
| `dialog_close` | — | Fermer le dialogue ouvert |
| `shop_buy` | `item`: int, `qty`: int | Acheter `qty` exemplaires d'un objet de la boutique ouverte (items.price chacun, kamas et pods vérifiés) : item_added + player_stats |
| `shop_sell` | `uid`: int, `qty`: int | Vendre `qty` objets d'une pile du sac à la boutique ouverte (prix de rachat NpcShop.sell_price) : item_added / item_removed + player_stats |
| `shop_close` | — | Fermer la boutique ouverte |
| `bank_move` | `uid`: int, `qty`: int, `dir`: str | Coffre ouvert : déposer (`dir` "in", `uid` = pile du sac) ou retirer (`dir` "out", `uid` = pile du coffre) `qty` objets ; les effets sont conservés. Réponse : item_added / item_removed + player_stats + bank_update |
| `bank_kamas` | `amount`: int, `dir`: str | Coffre ouvert : déposer (`dir` "in") ou retirer (`dir` "out") `amount` kamas. Réponse : player_stats + bank_update |
| `bank_close` | — | Fermer le coffre ouvert |
| `use_trigger` | `cell`: int | Prendre la porte / l'escalier de la cellule `cell` (map.triggers), depuis cette cellule ou une voisine |
| `interactive_use` | `element`: int, `skill`: int | Récolter l'élément `element` (map.interactives) avec la compétence `skill` (joueur à côté, niveau de métier suffisant) : interactive_start à la map, puis à la fin item_added, job_xp, interactive_state |
| `craft_open` | `skill`: int | Ouvrir l'atelier de la compétence `skill` (une compétence de recettes) : craft_state avec le grimoire des recettes |
| `craft_set` | `ingredients`: array | Atelier ouvert : poser les ingrédients [{item, qty}] (un craft de chaque, quantités de la recette) : craft_state {result, max} (result 0 = aucune recette) |
| `fm_apply` | `uid`: int, `rune`: int | Forgemagie : poser la rune `rune` (id d'objet du sac) sur l'équipement `uid` (sac, pas porté) : fm_result, item_added, item_removed (la rune) |
| `craft_do` | `count`: int | Atelier ouvert : fabriquer `count` fois la recette posée (ingrédients pris au sac, `count` objets aux jets aléatoires, XP de métier) : craft_done, item_added, job_xp, craft_state |
| `craft_close` | — | Fermer l'atelier ouvert |
| `fight_attack` | `group`: int | Attaquer un groupe de monstres de la map |
| `fight_move` | `cell`: int | Se déplacer en combat |
| `fight_cast` | `spell`: int, `cell`: int | Lancer un sort |
| `fight_end_turn` | — | Finir son tour |
| `fight_leave` | — | Abandonner le combat |
| `fight_place` | `cell`: int | Placement : choisir une cellule de son équipe (échange avec un allié) |
| `fight_ready` | `ready`: bool | Placement : prêt / pas prêt |
| `fight_option` | `option`: str, `value`: bool | Options du combat (chef de combat seulement) : `option` = locked (verrouillé), party_only (groupe seul), secret (pas de spectateurs), help (demander de l'aide) |
| `boost_stat` | `stat`: str, `points`: int? | Dépenser jusqu'à `points` de capital sur une caractéristique, au coût du palier de la classe (hors combat ; sans `points` : un point) |
| `reset_stats` | — | Remettre les caractéristiques à 0 et récupérer leur capital (hors combat) |
| `use_item` | `uid`: int | Utiliser un objet de l'inventaire (consommable, hors combat) |
| `equip` | `uid`: int, `slot`: int | Porter un objet dans un emplacement (Equipment : 0 amulette, 1 arme, 2/4 anneaux, 3 ceinture, 5 bottes, 6 coiffe, 7 cape, 8 familier, 9-14 dofus, 15 bouclier ; hors combat) |
| `unequip` | `slot`: int | Retirer l'objet d'un emplacement (hors combat) |
| `destroy_item` | `uid`: int, `qty`: int? | Détruire `qty` objets d'une pile (0 ou absent : toute la pile) |
| `choose_variant` | `spell`: int | Grimoire : utiliser ce sort (spells.id) à la place de l'autre sort de sa paire (hors combat, sort appris) |
| `move_spell` | `spell`: int, `slot`: int | Barre de sorts : mettre ce sort (spells.id) dans la case `slot` (le sort qui y était prend son ancienne case) |
| `admin_cmd` | `cmd`: str, `args`: array | Commande GM (rôle requis ; hors combat ; journalisée) : tp, give, kamas, level, heal, say, who, kick, ban, unban, mute, unmute, reload (ProtocolAdmin.USAGE). `tp` : args [map id, cellule?] ou [x, y, world_map?] (coordonnées : de préférence le monde de la map actuelle, puis l'extérieur). Réponse : admin_result, ou error |
| `quest_abandon` | `quest`: int | Abandonner une quête en cours (P2.04) : sa progression est perdue, `quest_list` revient |
| `ping` | `t0`: int | Horloge : le client mesure son décalage avec le serveur (réseau seulement, répondu par le transport, jamais par la sim) |
| `register` | `login`: str, `password`: str | Compte (serveur seulement) : créer le compte `login` puis s'y connecter (réponse : login_ok ou login_error). Le mot de passe n'est jamais stocké ni journalisé |
| `login` | `login`: str, `password`: str | Compte (serveur seulement) : se connecter (réponse : login_ok ou login_error). Une seule connexion par compte. Obligatoire avant hello |
| `chat_send` | `channel`: str, `text`: str, `to`: str? | Chat (P3.02) : `text` sur le canal `channel` (general, commerce, recruitment, private + `to` = nom du joueur ; group / guild / alliance : P3.03). Un texte qui commence par `/` est une commande (Chat.parse : `/s`, `/b`, `/r`, `/w nom texte`, `/t`, `/g`, `/p`, `/a`, shortcuts de chatchannels). Réponse : chat_msg à chaque destinataire, ou error (chat_flood, channel_unavailable, player_offline) |
| `party_invite` | `name`: str | Groupe (P3.03) : inviter le joueur connecté `name` (le chef seul, ou n'importe qui hors d'un groupe : cela en crée un). Réponse : party_invited chez lui, ou error (player_offline, already_in_party, party_full, not_party_leader) |
| `party_accept` | `from`: str | Groupe : accepter l'invitation de `from` (une minute) : party_update à tous les membres, ou error (no_invitation, already_in_party, party_full) |
| `party_decline` | `from`: str | Groupe : refuser l'invitation de `from` : party_declined chez l'invitant |
| `party_leave` | — | Groupe : le quitter (le suivant devient chef ; à un seul membre il se dissout) : party_left puis party_update aux autres |
| `party_kick` | `name`: str | Groupe : exclure le membre `name` (le chef seul) : party_left{kicked} chez lui |
| `party_leader` | `name`: str | Groupe : passer le commandement au membre `name` (le chef seul) : party_update |
| `party_follow` | `name`: str | Groupe : suivre le membre `name` ("" = ne plus suivre) : quand il change de carte hors combat, vous l'y rejoignez |
| `fight_join` | `fight`: int, `team`: int | Rejoindre le combat `fight` de sa map, dans l'équipe `team` (0 = les joueurs ; pendant le placement seulement, 8 par équipe) : fight_start chez vous (vous êtes un combattant), fighter_joined chez les autres. Erreurs : no_fight, fight_started, fight_full, bad_team, fight_locked, fight_party_only, in_fight |
| `fight_spectate` | `fight`: int | Regarder le combat `fight` de sa map : fight_watch (l'état du combat) puis tous ses événements, sans pouvoir agir (fight_leave pour sortir). Erreurs : no_fight, fight_secret, in_fight |
| `resume` | `token`: str | Compte (serveur seulement) : reprendre la session du `token` après une coupure (réponse : resume_ok puis les événements de l'état courant, ou login_error{bad_token | already_connected}) |
| `server_list` | — | Serveur : demande la liste des mondes ouverts (réponse : servers) |
| `trade_invite` | `name`: str | Échange (P3.11) : inviter le joueur `name` de votre map (hors combat, aucun des deux en échange). Réponse : trade_invited chez lui, ou error (player_offline, no_target, trade_busy, ghost) |
| `trade_accept` | `from`: str | Échange : accepter l'invitation de `from` (une minute) : trade_open aux deux, ou error (no_trade_invitation, trade_busy) |
| `trade_decline` | `from`: str | Échange : refuser l'invitation de `from` : trade_end{declined} chez l'invitant |
| `trade_set` | `items`: array, `kamas`: int | Échange ouvert : poser votre offre, `items` [{uid, qty}] (piles du sac, 20 au plus) et `kamas` ; elle remplace la précédente et annule les deux validations. Réponse : trade_update aux deux, ou error (unknown_item, item_worn, not_enough_kamas, overloaded : le sac de l'autre ne peut pas tout porter) |
| `trade_ready` | — | Échange ouvert : valider l'offre telle qu'elle est ; à la double validation l'échange est fait (trade_end{done} + item_added / item_removed + player_stats), ou error (overloaded) sans rien changer |
| `trade_cancel` | — | Échange ouvert : l'annuler : trade_end{cancelled} aux deux |
| `contacts_get` | — | Amis (P3.05) : demander ses listes. Réponse : contacts |
| `contact_add` | `kind`: str, `name`: str | Amis : ajouter le personnage `name` à la liste `kind` (friend, enemy, ignored ; il quitte les autres listes). Réponse : contacts, ou error (contact_unknown, contact_self, contact_exists, contact_full, bad_contact_kind) |
| `contact_remove` | `kind`: str, `name`: str | Amis : retirer `name` de la liste `kind`. Réponse : contacts, ou error (contact_unknown, bad_contact_kind) |

## Jeu → Client

| Type | Champs | Sens |
|---|---|---|
| `characters` | `list`: array, `max`: int, `world`: dict, `breeds`: array | Les personnages du compte dans ce monde (écran de choix) ; `breeds` = classes qu'on peut créer |
| `character_created` | `character`: dict | Personnage créé ; la liste à jour suit |
| `welcome` | `v`: int, `you`: int, `time`: int, `world`: dict | Connexion acceptée : id du joueur, horloge du jeu, monde |
| `zaap_list` | `zaap`: int, `destinations`: array, `save_map`: int | Destinations du zaap `zaap` (map) : [{map, name_id, area_name_id, coords, cost}] et point de sauvegarde |
| `dialog` | `npc`: int, `replies`: array | Un PNJ parle : `text_id` (id i18n du client) ou `text` (monde fait main), `replies` [{id, text_id | text}] déjà filtrées par les conditions du personnage ; `action` {type, …} si la réponse précédente en avait une (shop, quête…) |
| `shop_open` | `npc`: int, `items`: array, `sell_divisor`: int | Une boutique de PNJ s'ouvre : `items` [{item, price}] (prix d'achat) ; `sell_divisor` : le PNJ rachète au prix / sell_divisor |
| `quest_start` | `quest`: dict | Une quête commence (réponse `quest_start` d'un PNJ) : `quest` {id, name_id, step, steps, step_name_id, desc_id, level, objectives: [{id, type, params, map, count, need, done, locked}]} |
| `quest_update` | `quest`: dict, `rewards`: dict? | Une quête progresse (objectif, ou étape suivante) : sa vue complète `quest` ; `rewards` {xp, kamas, items: [[id, qty]], emotes, spells, titles} si une étape vient d'être terminée |
| `quest_complete` | `quest`: int, `name_id`: int, `rewards`: dict | Une quête est terminée : `quest` (id), `name_id`, et les `rewards` de sa dernière étape (déjà donnés : player_stats, item_added suivent) |
| `map_markers` | `map`: int, `markers`: array | Marqueurs de quête de la map (P2.04), à l'arrivée et à chaque changement de quête : `markers` [{kind: offer (un PNJ propose une quête) | goal (un objectif de l'étape en cours est ici), quest, npc (0 = un lieu), map}] |
| `craft_state` | `skill`: int, `slots`: int, `view`: dict, `ingredients`: array, `result`: int, `max`: int, `book`: array | Atelier : `skill`, `slots` (cases d'ingrédients du niveau de métier), `view` du métier, `ingredients` posés, `result` (objet fabriqué, 0 = aucune recette), `max` (fois que le sac le permet) ; `book` = les recettes qui tiennent dans les cases [{item, level, ingredients}] (à l'ouverture et après un niveau, [] sinon) |
| `fm_result` | `uid`: int, `rune`: int, `outcome`: str, `item`: dict, `lost`: array | Résultat d'une rune : `outcome` crit / success / neutral / fail / overmax, `item` = l'équipement après (effets, puits `reserve` en centièmes de poids), `lost` = [[effet, unités perdues]] |
| `craft_done` | `item`: int, `count`: int | `count` exemplaires de `item` fabriqués (les objets arrivent par item_added) |
| `quest_list` | `active`: array, `finished`: array | Les quêtes du personnage (à la connexion) : `active` [vue de quête] et `finished` [{id, name_id}] dans l'ordre |
| `interactive_start` | `player`: int, `element`: int, `skill`: int, `end`: int | Un joueur (`player` = id d'acteur) commence à récolter `element` avec `skill` jusqu'à `end` (temps de la sim, ms) : animation |
| `interactive_end` | `player`: int, `element`: int, `done`: bool | La récolte de `player` est finie (`done` : réussie) ou interrompue (déplacement, combat, départ) |
| `interactive_state` | `element`: int, `ready`: bool, `until`: int | L'élément est récolté (`ready` faux, repousse à `until`, temps de la sim) ou a repoussé (`ready` vrai) ; à l'entrée sur la map : les éléments encore récoltés |
| `job_xp` | `gained`: int, `levels`: int, `view`: dict | Le métier `job` gagne `gained` XP : `view` {job, level, xp, xp_floor, xp_next}, `levels` = niveaux gagnés |
| `bank_open` | `npc`: int, `cost`: int, `kamas`: int, `items`: array | Le coffre du compte s'ouvre (réponse « Consulter son coffre personnel » d'un banquier) : `cost` kamas déjà payés (BankRules.access_cost), `kamas` du coffre, `items` = toutes ses piles {uid, id, qty, effects} |
| `bank_update` | `kamas`: int, `items`: array | Le coffre a changé : `kamas` (total) et les piles modifiées dans `items` (`qty` 0 = la pile a disparu) |
| `bank_end` | — | Le coffre est fermé (fermeture, joueur parti, autre commande) |
| `shop_end` | — | La boutique est fermée (fermeture, joueur parti, nouveau dialogue) |
| `dialog_end` | — | Le dialogue est terminé (réponse finale, fermeture, déplacement) ; `action` éventuelle de la dernière réponse |
| `zaap_known` | `map`: int | Un nouveau zaap est enregistré (première visite de sa map) |
| `info` | `code`: str, `args`: array | Message de jeu (pas une erreur) : `code` (INFO_CODES) et ses valeurs |
| `map_enter` | `map`: dict, `actors`: array | Entrée sur une map : données de la map et acteurs présents |
| `actor_add` | `actor`: dict | Un acteur arrive sur la map (groupe de monstres : `members` [{name_id, level, grade, xp}], `bonus` = étoiles en %; joueur : `breed`, `level`, `life` si fantôme, jamais rien de privé : la sim n'envoie à chacun que la fiche publique de l'autre, P3.01) |
| `group_alert` | `group`: int, `target`: int | Un groupe agressif a repéré `target` : il l'attaque s'il reste 3 s dans sa zone |
| `actor_remove` | `id`: int | Un acteur quitte la map |
| `actor_look` | `id`: int, `looks`: array | Un acteur change d'apparence (objet porté ou retiré) : ses `looks` |
| `actor_move` | `id`: int, `path`: array, `t0`: int, `run`: bool | Un acteur marche : chemin complet et instant de départ |
| `login_ok` | `token`: str, `role`: str, `login`: str | Connecté : `token` aléatoire de session (exigé par l'API de contenu), `role` (player ou gm), `login` normalisé |
| `login_error` | `code`: str, `cmd`: str | Connexion ou création de compte refusée : `code` (bad_credentials, login_taken, bad_login, already_connected, registration_closed, too_many_attempts) |
| `chat_msg` | `channel`: str, `from`: str, `from_id`: int, `text`: str, `at`: int, `to`: str?, `links`: array? | Un message de chat : `channel`, `from` (nom) et `from_id` (id d'acteur, bulle au-dessus du personnage), `text` nettoyé, `at` (heure de jeu ms) ; `to` (nom du destinataire) sur un message privé, envoyé aussi à l'expéditeur (écho « À X : ») ; `links` : ids des objets existants cités par `{item:id}` dans le texte (P3.02b) ; canal `group` : les membres du groupe de l'expéditeur |
| `pong` | `t0`: int, `server_ms`: int | Réponse à ping : `t0` renvoyé, `server_ms` = heure de jeu du serveur (celle des `t0` de déplacement) au moment de la réponse |
| `error` | `code`: str, `msg`: str, `cmd`: str, `ref`: int? | Commande refusée ; `ref` = seq de la commande |
| `player_stats` | `stats`: dict | Le personnage (après welcome, combat, boost, grimoire, objet utilisé) |
| `inventory` | `items`: array | Tout l'inventaire (à la connexion) |
| `item_added` | `item`: dict | Une pile d'objets apparaît ou change de quantité |
| `item_removed` | `uid`: int | Une pile d'objets disparaît |
| `fight_start` | `fight`: int, `you`: int, `fighters`: array, `order`: array, `phase`: str, `placement`: dict, `end`: int | Début de combat, phase de placement |
| `fighter_placed` | `id`: int, `cell`: int | Placement : un combattant change de cellule |
| `fighter_ready` | `id`: int, `ready`: bool | Placement : un combattant est prêt ou non |
| `fight_begin` | `order`: array | Fin du placement, les tours commencent |
| `fight_turn` | `id`: int, `ap`: int, `mp`: int, `end`: int, `effects`: array | `id` joue jusqu'à `end` (ms) ; effets de début de tour |
| `fighter_move` | `id`: int, `path`: array, `t0`: int, `mp`: int, `lost`: dict, `effects`: array, `triggered`: array | Déplacement en combat (`lost` : PA/PM perdus au tacle ; `effects` avant le pas : un porté qui descend de son porteur, `drop` ; `triggered` à l'arrivée : un piège) |
| `spell_cast` | `caster`: int, `spell`: int, `cell`: int, `dir`: int, `ap`: int, `crit`: bool, `effects`: array | Sort lancé et ses effets |
| `fight_options` | `options`: dict | Les options du combat ont changé : `options` {locked, party_only, secret, help} |
| `challenge_list` | `challenges`: array | Les challenges du combat (au début) : [{id, name_id, desc_id, icon, state, target (id d'un combattant, -1 = aucun), bonus}] ; `state` running / success / failed |
| `challenge_update` | `id`: int, `state`: str | Un challenge change d'état : failed dès qu'il est raté, success / failed à la fin du combat |
| `fight_end` | `result`: str, `duration`: int, `rewards`: array | Fin de combat et gains ; un map_enter suit |
| `party_invited` | `from`: str | Groupe : `from` vous invite (party_accept / party_decline) |
| `party_update` | `party`: dict | Groupe : sa composition et la position de ses membres (voir en tête de protocol_party.gd) |
| `party_left` | `reason`: str | Groupe : vous n'en faites plus partie, `reason` = left | kicked | dissolved |
| `party_declined` | `name`: str | Groupe : `name` a refusé votre invitation |
| `fight_watch` | `fight`: int, `fighters`: array, `order`: array, `phase`: str, `placement`: dict, `end`: int, `turn`: int, `options`: dict, `challenges`: array | Vous regardez un combat : `fight`, `fighters`, `order`, `phase` (placement | fight), `placement`, `end` (fin du chrono en cours), `turn` (id du combattant qui joue, -1 au placement), `options`, `challenges` |
| `fighter_joined` | `fighter`: dict, `order`: array | Un joueur rejoint le combat pendant le placement : sa fiche de combattant (`fighter`) et le nouvel ordre |
| `fighter_left` | `id`: int, `order`: array | Un joueur quitte le combat (fuite) sans le terminer : `id` ne combat plus ; `order` = le nouvel ordre |
| `net_reconnecting` | `attempt`: int, `delay_ms`: int, `reason`: str | Transport (fait par le backend réseau, jamais par le serveur) : la connexion est coupée, nouvel essai n°`attempt` dans `delay_ms` (1, 2, 4, 8 s puis toutes les 8 s) ; `resume_ok` y met fin, une erreur login_error{bad_token} l'abandonne |
| `resume_ok` | `token`: str, `role`: str, `login`: str, `state`: dict | Session reprise : `token`, `role`, `login` comme login_ok, et `state` {world, name, playing, in_fight} ; suivent les événements qui reconstruisent le client (combat en cours, sinon la map) |
| `admin_result` | `cmd`: str, `args`: array | Une commande GM (admin_cmd) a été exécutée : `cmd` et `args` (valeurs utiles : joueur visé, quantité, liste des joueurs pour `who`…) |
| `announce` | `from`: str, `text`: str | Message d'un GM à tous les joueurs du monde (/say) : `from` (nom du GM) et `text` |
| `servers` | `worlds`: array | Mondes ouverts du serveur : `worlds` = [{id, content, name, module, players, version}] (content = le monde dont l'instance lit les données, S.04b : l'id lui-même pour un monde ordinaire ; version = celle du paquet de contenu, "" s'il n'y en a pas) |
| `trade_invited` | `from`: str | Échange : `from` vous invite (trade_accept / trade_decline) |
| `trade_open` | `with`: str, `with_id`: int | Échange : la fenêtre s'ouvre avec le joueur `with` (id d'acteur `with_id`) |
| `trade_update` | `mine`: dict, `theirs`: dict | Échange : les deux offres, `mine` et `theirs` (voir en tête de protocol_trade.gd), envoyées à chaque changement |
| `trade_end` | `reason`: str, `code`: str? | Échange : fin (la fenêtre se ferme), `reason` = done | cancelled | declined | expired | moved | fight | disconnected | action | failed ; `code` = le refus quand reason = failed |
| `contacts` | `friends`: array, `enemies`: array, `ignored`: array | Amis : les trois listes du compte (voir en tête de protocol_contacts.gd) |
| `contact_status` | `kind`: str, `name`: str, `online`: bool, `playing`: str, `level`: int | Amis : un ami (`kind` friend) vient de se connecter ou de se déconnecter : `name`, `online`, `playing` (son personnage), `level` |

## Codes d'erreur

`bad_credentials`, `login_taken`, `bad_login`, `already_connected`, `not_logged_in`, `registration_closed`, `too_many_attempts`, `bad_message`, `version`, `unknown_world`, `network`, `unknown_command`, `connected_elsewhere`, `no_start_map`, `bad_cell`, `unreachable`, `no_exit`, `no_target`, `in_fight`, `not_in_fight`, `fight_not_started`, `placement_over`, `unknown_option`, `not_leader`, `fight_locked`, `fight_party_only`, `fight_secret`, `not_your_turn`, `cell_not_free`, `unknown_spell`, `not_enough_ap`, `out_of_range`, `not_in_line`, `needs_target`, `no_los`, `spell_forbidden`, `spell_cooldown`, `cast_limit`, `cast_limit_target`, `summon_limit`, `spell_condition`, `unknown_stat`, `not_enough_capital`, `bad_name`, `name_taken`, `too_many_characters`, `unknown_character`, `character_in_use`, `unknown_breed`, `no_character`, `bad_look`, `spell_locked`, `spell_not_simulated`, `bad_slot`, `unknown_item`, `item_not_usable`, `item_condition`, `overloaded`, `item_level`, `already_equipped`, `item_worn`, `not_at_zaap`, `unknown_zaap`, `not_enough_kamas`, `ghost`, `not_ghost`, `not_at_phoenix`, `energy_full`, `not_gm`, `unknown_map`, `not_at_npc`, `no_dialog`, `no_reply`, `no_shop`, `no_bank`, `not_sellable`, `no_element`, `not_at_element`, `element_busy`, `job_level`, `no_craft`, `no_recipe`, `craft_slots`, `missing_ingredients`, `fm_item`, `fm_rune`, `fm_reserve`, `chat_flood`, `channel_unavailable`, `player_offline`, `party_full`, `already_in_party`, `not_in_party`, `not_party_leader`, `no_invitation`, `trade_busy`, `not_in_trade`, `no_trade_invitation`, `bad_contact_kind`, `contact_self`, `contact_exists`, `contact_full`, `contact_unknown`, `no_fight`, `fight_full`, `fight_started`, `bad_team`, `spectating`, `bad_token`, `banned`, `muted`, `kicked`, `world_closed`, `rate_limited`

Le détail des dictionnaires imbriqués (acteur, combattant, buff, effet, récompense, personnage) est en tête de `protocol.gd`.
