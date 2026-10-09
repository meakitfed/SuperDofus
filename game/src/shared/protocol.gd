## The API between client and game logic. Every message is a JSON-safe
## Dictionary {"t": <type>, ...}, identical in standalone and server mode.
## Numbers may come back as floats after JSON: always int() when reading.
##
## SCHEMA below is the single source of truth: validate() checks messages
## against it (the sim rejects invalid commands, LocalBackend checks every
## event in tests) and docs/PROTOCOL.md is generated from it
## (tools/protocol_doc.gd; a test fails when the doc is stale).
##
## Envelope: every message may carry `seq` (int). Clients number their
## commands, the sim numbers the events of each session (drain order); an
## error caused by a command carries `ref` = that command's seq.
##
## Adding a message = a constant + a SCHEMA entry + a builder here, a handler
## in WorldSim, a case in the client, then regenerate docs/PROTOCOL.md.
class_name Protocol
extends RefCounted

## Bump when a message changes incompatibly; hello carries it, welcome answers it.
const VERSION := 2

# client -> game
const HELLO := "hello"
const MOVE := "move"
const CHANGE_MAP := "change_map"
const USE_TRIGGER := "use_trigger"
const USE_ZAAP := "use_zaap"
const ZAAP_TRAVEL := "zaap_travel"
const SET_SAVE_POINT := "set_save_point"
const USE_PHOENIX := "use_phoenix"
const INTERACTIVE_USE := "interactive_use"
const CRAFT_OPEN := "craft_open"
const CRAFT_SET := "craft_set"
const CRAFT_DO := "craft_do"
const CRAFT_CLOSE := "craft_close"
const FM_APPLY := "fm_apply"
const NPC_TALK := "npc_talk"
const DIALOG_REPLY := "dialog_reply"
const DIALOG_CLOSE := "dialog_close"
const SHOP_BUY := "shop_buy"
const SHOP_SELL := "shop_sell"
const SHOP_CLOSE := "shop_close"
const BANK_MOVE := "bank_move"
const BANK_KAMAS := "bank_kamas"
const BANK_CLOSE := "bank_close"
const FIGHT_ATTACK := "fight_attack"
const FIGHT_MOVE := "fight_move"
const FIGHT_CAST := "fight_cast"
const FIGHT_END_TURN := "fight_end_turn"
const FIGHT_LEAVE := "fight_leave"
const FIGHT_PLACE := "fight_place"
const FIGHT_READY := "fight_ready"
const FIGHT_OPTION := "fight_option"
const BOOST_STAT := "boost_stat"
const RESET_STATS := "reset_stats"
const USE_ITEM := "use_item"
const DESTROY_ITEM := "destroy_item"
const EQUIP := "equip"
const UNEQUIP := "unequip"
const LIST_CHARACTERS := "list_characters"
const CREATE_CHARACTER := "create_character"
const DELETE_CHARACTER := "delete_character"
const SELECT_CHARACTER := "select_character"
const CHOOSE_VARIANT := "choose_variant"
const MOVE_SPELL := "move_spell"
const ADMIN_CMD := "admin_cmd"
const PING := "ping"
const REGISTER := "register"
const LOGIN := "login"
const CHAT_SEND := "chat_send"

# game -> client
const CHARACTERS := "characters"
const CHARACTER_CREATED := "character_created"
const WELCOME := "welcome"
const MAP_ENTER := "map_enter"
const ZAAP_LIST := "zaap_list"
const ZAAP_KNOWN := "zaap_known"
const DIALOG := "dialog"
const DIALOG_END := "dialog_end"
const SHOP_OPEN := "shop_open"
const SHOP_END := "shop_end"
const BANK_OPEN := "bank_open"
const BANK_UPDATE := "bank_update"
const BANK_END := "bank_end"
const INTERACTIVE_START := "interactive_start"
const INTERACTIVE_END := "interactive_end"
const INTERACTIVE_STATE := "interactive_state"
const JOB_XP := "job_xp"
const CRAFT_STATE := "craft_state"
const CRAFT_DONE := "craft_done"
const FM_RESULT := "fm_result"
const QUEST_START := "quest_start"
const QUEST_UPDATE := "quest_update"
const QUEST_COMPLETE := "quest_complete"
const QUEST_LIST := "quest_list"
const QUEST_ABANDON := "quest_abandon"
const MAP_MARKERS := "map_markers"
const INFO := "info"
const ACTOR_ADD := "actor_add"
const GROUP_ALERT := "group_alert"
const ACTOR_REMOVE := "actor_remove"
const ACTOR_MOVE := "actor_move"
const ACTOR_LOOK := "actor_look"
const ERROR := "error"
const PLAYER_STATS := "player_stats"
const INVENTORY := "inventory"
const ITEM_ADDED := "item_added"
const ITEM_REMOVED := "item_removed"
const FIGHT_START := "fight_start"
const FIGHTER_PLACED := "fighter_placed"
const FIGHTER_READY := "fighter_ready"
const FIGHT_BEGIN := "fight_begin"
const FIGHT_TURN := "fight_turn"
const FIGHTER_MOVE := "fighter_move"
const SPELL_CAST := "spell_cast"
const FIGHT_END := "fight_end"
const FIGHT_OPTIONS := "fight_options"
const CHALLENGE_LIST := "challenge_list"
const CHALLENGE_UPDATE := "challenge_update"
const PONG := "pong"
const LOGIN_OK := "login_ok"
const LOGIN_ERROR := "login_error"
const CHAT_MSG := "chat_msg"

# error codes (error.code); the client turns them into text
const E_BAD_MESSAGE := "bad_message"          # fails SCHEMA
const E_VERSION := "version"                  # hello.v != VERSION
const E_UNKNOWN_WORLD := "unknown_world"
const E_NETWORK := "network"                  # transport: connection refused, lost or closed (made by NetBackend, never by the sim)
const E_UNKNOWN_COMMAND := "unknown_command"
# accounts (S.02a): the code of a login_error, or of an error when a command needs a login first
const E_BAD_CREDENTIALS := "bad_credentials"  # unknown login or wrong password (never says which)
const E_LOGIN_TAKEN := "login_taken"          # register: this login exists
const E_BAD_LOGIN := "bad_login"              # register: login not 3-24 of a-z 0-9 _ -, or password not 6-128 characters
const E_ALREADY_CONNECTED := "already_connected"  # login: this account already has a live connection
const E_NOT_LOGGED_IN := "not_logged_in"      # a game command before login_ok (server mode)
const E_REGISTRATION_CLOSED := "registration_closed"  # register: the server does not create accounts
const E_TOO_MANY_ATTEMPTS := "too_many_attempts"  # login: too many wrong passwords for this connection
const E_CONNECTED_ELSEWHERE := "connected_elsewhere"
const E_NO_START_MAP := "no_start_map"
const E_BAD_CELL := "bad_cell"
const E_UNREACHABLE := "unreachable"
const E_NO_EXIT := "no_exit"
const E_NO_TARGET := "no_target"
const E_IN_FIGHT := "in_fight"
const E_NOT_IN_FIGHT := "not_in_fight"
const E_FIGHT_NOT_STARTED := "fight_not_started"
const E_PLACEMENT_OVER := "placement_over"
const E_UNKNOWN_OPTION := "unknown_option"      # fight_option: not locked / party_only / secret / help
const E_NOT_LEADER := "not_leader"            # only the fight leader changes the options
const E_FIGHT_LOCKED := "fight_locked"        # join_error: the fight is locked
const E_FIGHT_PARTY_ONLY := "fight_party_only"
const E_FIGHT_SECRET := "fight_secret"        # no spectators
const E_NOT_YOUR_TURN := "not_your_turn"
const E_CELL_NOT_FREE := "cell_not_free"
const E_UNKNOWN_SPELL := "unknown_spell"
const E_NOT_ENOUGH_AP := "not_enough_ap"
const E_OUT_OF_RANGE := "out_of_range"
const E_NOT_IN_LINE := "not_in_line"
const E_NEEDS_TARGET := "needs_target"
const E_NO_LOS := "no_los"
const E_SPELL_FORBIDDEN := "spell_forbidden"
const E_SPELL_COOLDOWN := "spell_cooldown"
const E_CAST_LIMIT := "cast_limit"
const E_CAST_LIMIT_TARGET := "cast_limit_target"
const E_SUMMON_LIMIT := "summon_limit"
const E_SPELL_CONDITION := "spell_condition"
const E_UNKNOWN_STAT := "unknown_stat"
const E_NOT_ENOUGH_CAPITAL := "not_enough_capital"
const E_BAD_NAME := "bad_name"                # namingrules (NameRules)
const E_NAME_TAKEN := "name_taken"            # unique per world, whatever the case
const E_TOO_MANY_CHARACTERS := "too_many_characters"
const E_UNKNOWN_CHARACTER := "unknown_character" # not in this world, or another account's
const E_CHARACTER_IN_USE := "character_in_use"  # being played: cannot be deleted
const E_UNKNOWN_BREED := "unknown_breed"
const E_NO_CHARACTER := "no_character"        # a game command before select_character
const E_BAD_LOOK := "bad_look"                # body / head / colors not allowed (LookBuilder.check)
const E_SPELL_LOCKED := "spell_locked"        # level below the spell's minPlayerLevel
const E_SPELL_NOT_SIMULATED := "spell_not_simulated" # none of its effects is simulated yet
const E_BAD_SLOT := "bad_slot"                # spell bar slot out of range
const E_UNKNOWN_ITEM := "unknown_item"        # no such uid in the inventory
const E_ITEM_NOT_USABLE := "item_not_usable"
const E_ITEM_CONDITION := "item_condition"    # items.criterions not met
const E_OVERLOADED := "overloaded"            # more pods than max: cannot move
const E_ITEM_LEVEL := "item_level"            # items.level above the character's
const E_ALREADY_EQUIPPED := "already_equipped" # one of each Dofus / set item
const E_ITEM_WORN := "item_worn"              # unequip it first
const E_NOT_AT_ZAAP := "not_at_zaap"          # not standing next to the map's zaap
const E_UNKNOWN_ZAAP := "unknown_zaap"        # destination never visited (or this zaap)
const E_NOT_ENOUGH_KAMAS := "not_enough_kamas"
const E_GHOST := "ghost"                      # a ghost cannot do that (fight, zaap, items…)
const E_NOT_GHOST := "not_ghost"              # only a ghost is resurrected
const E_NOT_AT_PHOENIX := "not_at_phoenix"    # not standing next to the map's phoenix
const E_ENERGY_FULL := "energy_full"          # energy already at its maximum
const E_NOT_GM := "not_gm"                    # admin_cmd without the GM role
const E_UNKNOWN_MAP := "unknown_map"          # no such map (id or coordinates) in this world
const E_NOT_AT_NPC := "not_at_npc"            # not standing next to that NPC
const E_NO_DIALOG := "no_dialog"              # a silent NPC (no message in the data)
const E_NO_REPLY := "no_reply"                # no dialog open, or a reply that is not offered
const E_NO_SHOP := "no_shop"                  # no shop open, or an item it does not sell
const E_NO_BANK := "no_bank"                  # no chest open (bank_move / bank_kamas), or a stack it does not hold
const E_NOT_SELLABLE := "not_sellable"        # the NPC does not buy this item (items.price = 0)
const E_NO_ELEMENT := "no_element"            # interactive_use: no such harvestable element (or not that skill) on the map
const E_NOT_AT_ELEMENT := "not_at_element"    # not standing next to the element
const E_ELEMENT_BUSY := "element_busy"        # harvested already (grows back later) or someone is on it
const E_JOB_LEVEL := "job_level"              # job level below skills.levelMin
const E_NO_CRAFT := "no_craft"                # craft_set / craft_do without a workshop open, or craft_open on a skill that crafts nothing
const E_NO_RECIPE := "no_recipe"              # craft_do: the ingredients are no recipe of this skill
const E_CRAFT_SLOTS := "craft_slots"          # more ingredients than the job level has slots for
const E_MISSING_INGREDIENTS := "missing_ingredients"  # the bag does not hold the ingredients (count times)
const E_FM_ITEM := "fm_item"                  # fm_apply: not an equipment with characteristics to forge
const E_FM_RUNE := "fm_rune"                  # fm_apply: not a rune we simulate, or none in the bag
const E_CHAT_FLOOD := "chat_flood"            # chat_send: too many messages (msg = seconds to wait, Chat.FLOOD)
const E_CHANNEL_UNAVAILABLE := "channel_unavailable"  # chat_send: unknown channel, or one that needs a group / guild / alliance (P3.03)
const E_PLAYER_OFFLINE := "player_offline"    # chat_send private: nobody of that name is connected (or yourself)
const E_FM_RESERVE := "fm_reserve"            # fm_apply: above the maximum without enough puits (or over the hard limit)

const ERROR_CODES := [E_BAD_CREDENTIALS, E_LOGIN_TAKEN, E_BAD_LOGIN, E_ALREADY_CONNECTED, E_NOT_LOGGED_IN, E_REGISTRATION_CLOSED, E_TOO_MANY_ATTEMPTS, E_BAD_MESSAGE, E_VERSION, E_UNKNOWN_WORLD, E_NETWORK, E_UNKNOWN_COMMAND, E_CONNECTED_ELSEWHERE,
		E_NO_START_MAP, E_BAD_CELL, E_UNREACHABLE, E_NO_EXIT, E_NO_TARGET, E_IN_FIGHT, E_NOT_IN_FIGHT,
		E_FIGHT_NOT_STARTED, E_PLACEMENT_OVER, E_UNKNOWN_OPTION, E_NOT_LEADER, E_FIGHT_LOCKED, E_FIGHT_PARTY_ONLY, E_FIGHT_SECRET, E_NOT_YOUR_TURN, E_CELL_NOT_FREE, E_UNKNOWN_SPELL, E_NOT_ENOUGH_AP,
		E_OUT_OF_RANGE, E_NOT_IN_LINE, E_NEEDS_TARGET, E_NO_LOS, E_SPELL_FORBIDDEN, E_SPELL_COOLDOWN, E_CAST_LIMIT,
		E_CAST_LIMIT_TARGET, E_SUMMON_LIMIT, E_SPELL_CONDITION, E_UNKNOWN_STAT, E_NOT_ENOUGH_CAPITAL, E_BAD_NAME, E_NAME_TAKEN,
		E_TOO_MANY_CHARACTERS, E_UNKNOWN_CHARACTER, E_CHARACTER_IN_USE, E_UNKNOWN_BREED, E_NO_CHARACTER, E_BAD_LOOK,
		E_SPELL_LOCKED, E_SPELL_NOT_SIMULATED, E_BAD_SLOT, E_UNKNOWN_ITEM, E_ITEM_NOT_USABLE, E_ITEM_CONDITION,
		E_OVERLOADED, E_ITEM_LEVEL, E_ALREADY_EQUIPPED, E_ITEM_WORN, E_NOT_AT_ZAAP, E_UNKNOWN_ZAAP,
		E_NOT_ENOUGH_KAMAS, E_GHOST, E_NOT_GHOST, E_NOT_AT_PHOENIX, E_ENERGY_FULL, E_NOT_GM, E_UNKNOWN_MAP,
		E_NOT_AT_NPC, E_NO_DIALOG, E_NO_REPLY, E_NO_SHOP, E_NO_BANK, E_NOT_SELLABLE,
		E_NO_ELEMENT, E_NOT_AT_ELEMENT, E_ELEMENT_BUSY, E_JOB_LEVEL, E_NO_CRAFT, E_NO_RECIPE, E_CRAFT_SLOTS, E_MISSING_INGREDIENTS,
		E_FM_ITEM, E_FM_RUNE, E_FM_RESERVE, E_CHAT_FLOOD, E_CHANNEL_UNAVAILABLE, E_PLAYER_OFFLINE] + ProtocolParty.ERROR_CODES + ProtocolTrade.ERROR_CODES + ProtocolContacts.ERROR_CODES + ProtocolWatch.ERROR_CODES + ProtocolResume.ERROR_CODES + ProtocolAdmin.ERROR_CODES + ProtocolCluster.ERROR_CODES + ProtocolSecurity.ERROR_CODES

# info codes (info.code): game messages that are not errors; the client shows the
# Dofus text (InfoTexts). args = the values of the text.
const I_ENERGY_LOST := "energy_lost"          # [points]
const I_ENERGY_REGAINED := "energy_regained"  # [points] (logged out, consumable)
const I_ENERGY_LOW := "energy_low"            # [energy left]
const I_GHOST := "ghost"                      # [] the character turned into a ghost
const I_RESURRECTED := "resurrected"          # [] a phoenix brought it back to life
const INFO_CODES := [I_ENERGY_LOST, I_ENERGY_REGAINED, I_ENERGY_LOW, I_GHOST, I_RESURRECTED]

const C2S := "client → jeu"
const S2C := "jeu → client"

## type -> [direction, meaning, {field: type}]. Types: int, bool, str, dict,
## array; a trailing "?" = optional. Extra fields are allowed (forward
## compatible), missing or mistyped ones are not.
const SCHEMA := {
	HELLO: [C2S, "Se connecter à un monde. Sans `name` : liste des personnages (characters) ; avec : joue ce personnage, créé au besoin (outils, tests)", {"v": "int", "world": "str", "name": "str?", "look": "str?"}],
	LIST_CHARACTERS: [C2S, "Choix du personnage : redemander la liste", {}],
	CREATE_CHARACTER: [C2S, "Choix du personnage : créer (nom selon namingrules, classe = breeds.id, sexe 0/1, corps = bodies.id, visage = heads.id, couleurs : une par couleur de la classe, -1 = défaut)", {"name": "str", "breed": "int?", "sex": "int?", "body": "int?", "head": "int?", "colors": "array?"}],
	DELETE_CHARACTER: [C2S, "Choix du personnage : supprimer définitivement", {"name": "str"}],
	SELECT_CHARACTER: [C2S, "Choix du personnage : jouer (réponse : welcome)", {"name": "str"}],
	MOVE: [C2S, "Marcher vers une cellule ; la sim calcule et valide le chemin", {"cell": "int", "run": "bool"}],
	CHANGE_MAP: [C2S, "Passer sur la map voisine (joueur sur une cellule de sortie de ce côté : map.map_change)", {"dir": "str"}],
	USE_ZAAP: [C2S, "Utiliser le zaap de la map (joueur à côté) : réponse zaap_list", {}],
	ZAAP_TRAVEL: [C2S, "Voyager vers un zaap connu (joueur à côté d'un zaap ; coûte des kamas)", {"map": "int"}],
	SET_SAVE_POINT: [C2S, "Enregistrer le zaap de la map comme point de sauvegarde (joueur à côté)", {}],
	USE_PHOENIX: [C2S, "Fantôme : ressusciter au phénix de la map (joueur à côté) ; énergie rendue", {}],
	NPC_TALK: [C2S, "Parler à un PNJ de la map (joueur à côté) : réponse dialog", {"npc": "int"}],
	DIALOG_REPLY: [C2S, "Choisir une réponse du dialogue ouvert (dialog.replies[].id) : réponse dialog ou dialog_end", {"reply": "int"}],
	DIALOG_CLOSE: [C2S, "Fermer le dialogue ouvert", {}],
	SHOP_BUY: [C2S, "Acheter `qty` exemplaires d'un objet de la boutique ouverte (items.price chacun, kamas et pods vérifiés) : item_added + player_stats", {"item": "int", "qty": "int"}],
	SHOP_SELL: [C2S, "Vendre `qty` objets d'une pile du sac à la boutique ouverte (prix de rachat NpcShop.sell_price) : item_added / item_removed + player_stats", {"uid": "int", "qty": "int"}],
	SHOP_CLOSE: [C2S, "Fermer la boutique ouverte", {}],
	BANK_MOVE: [C2S, "Coffre ouvert : déposer (`dir` \"in\", `uid` = pile du sac) ou retirer (`dir` \"out\", `uid` = pile du coffre) `qty` objets ; les effets sont conservés. Réponse : item_added / item_removed + player_stats + bank_update", {"uid": "int", "qty": "int", "dir": "str"}],
	BANK_KAMAS: [C2S, "Coffre ouvert : déposer (`dir` \"in\") ou retirer (`dir` \"out\") `amount` kamas. Réponse : player_stats + bank_update", {"amount": "int", "dir": "str"}],
	BANK_CLOSE: [C2S, "Fermer le coffre ouvert", {}],
	USE_TRIGGER: [C2S, "Prendre la porte / l'escalier de la cellule `cell` (map.triggers), depuis cette cellule ou une voisine", {"cell": "int"}],
	INTERACTIVE_USE: [C2S, "Récolter l'élément `element` (map.interactives) avec la compétence `skill` (joueur à côté, niveau de métier suffisant) : interactive_start à la map, puis à la fin item_added, job_xp, interactive_state", {"element": "int", "skill": "int"}],
	CRAFT_OPEN: [C2S, "Ouvrir l'atelier de la compétence `skill` (une compétence de recettes) : craft_state avec le grimoire des recettes", {"skill": "int"}],
	CRAFT_SET: [C2S, "Atelier ouvert : poser les ingrédients [{item, qty}] (un craft de chaque, quantités de la recette) : craft_state {result, max} (result 0 = aucune recette)", {"ingredients": "array"}],
	FM_APPLY: [C2S, "Forgemagie : poser la rune `rune` (id d'objet du sac) sur l'équipement `uid` (sac, pas porté) : fm_result, item_added, item_removed (la rune)", {"uid": "int", "rune": "int"}],
	CRAFT_DO: [C2S, "Atelier ouvert : fabriquer `count` fois la recette posée (ingrédients pris au sac, `count` objets aux jets aléatoires, XP de métier) : craft_done, item_added, job_xp, craft_state", {"count": "int"}],
	CRAFT_CLOSE: [C2S, "Fermer l'atelier ouvert", {}],
	FIGHT_ATTACK: [C2S, "Attaquer un groupe de monstres de la map", {"group": "int"}],
	FIGHT_MOVE: [C2S, "Se déplacer en combat", {"cell": "int"}],
	FIGHT_CAST: [C2S, "Lancer un sort", {"spell": "int", "cell": "int"}],
	FIGHT_END_TURN: [C2S, "Finir son tour", {}],
	FIGHT_LEAVE: [C2S, "Abandonner le combat", {}],
	FIGHT_PLACE: [C2S, "Placement : choisir une cellule de son équipe (échange avec un allié)", {"cell": "int"}],
	FIGHT_READY: [C2S, "Placement : prêt / pas prêt", {"ready": "bool"}],
	FIGHT_OPTION: [C2S, "Options du combat (chef de combat seulement) : `option` = locked (verrouillé), party_only (groupe seul), secret (pas de spectateurs), help (demander de l'aide)", {"option": "str", "value": "bool"}],
	BOOST_STAT: [C2S, "Dépenser jusqu'à `points` de capital sur une caractéristique, au coût du palier de la classe (hors combat ; sans `points` : un point)", {"stat": "str", "points": "int?"}],
	RESET_STATS: [C2S, "Remettre les caractéristiques à 0 et récupérer leur capital (hors combat)", {}],
	USE_ITEM: [C2S, "Utiliser un objet de l'inventaire (consommable, hors combat)", {"uid": "int"}],
	EQUIP: [C2S, "Porter un objet dans un emplacement (Equipment : 0 amulette, 1 arme, 2/4 anneaux, 3 ceinture, 5 bottes, 6 coiffe, 7 cape, 8 familier, 9-14 dofus, 15 bouclier ; hors combat)", {"uid": "int", "slot": "int"}],
	UNEQUIP: [C2S, "Retirer l'objet d'un emplacement (hors combat)", {"slot": "int"}],
	DESTROY_ITEM: [C2S, "Détruire `qty` objets d'une pile (0 ou absent : toute la pile)", {"uid": "int", "qty": "int?"}],
	CHOOSE_VARIANT: [C2S, "Grimoire : utiliser ce sort (spells.id) à la place de l'autre sort de sa paire (hors combat, sort appris)", {"spell": "int"}],
	MOVE_SPELL: [C2S, "Barre de sorts : mettre ce sort (spells.id) dans la case `slot` (le sort qui y était prend son ancienne case)", {"spell": "int", "slot": "int"}],
	ADMIN_CMD: [C2S, "Commande GM (rôle requis ; hors combat ; journalisée) : tp, give, kamas, level, heal, say, who, kick, ban, unban, mute, unmute, reload (ProtocolAdmin.USAGE). `tp` : args [map id, cellule?] ou [x, y, world_map?] (coordonnées : de préférence le monde de la map actuelle, puis l'extérieur). Réponse : admin_result, ou error", {"cmd": "str", "args": "array"}],
	CHARACTERS: [S2C, "Les personnages du compte dans ce monde (écran de choix) ; `breeds` = classes qu'on peut créer", {"list": "array", "max": "int", "world": "dict", "breeds": "array"}],
	CHARACTER_CREATED: [S2C, "Personnage créé ; la liste à jour suit", {"character": "dict"}],
	WELCOME: [S2C, "Connexion acceptée : id du joueur, horloge du jeu, monde", {"v": "int", "you": "int", "time": "int", "world": "dict"}],
	ZAAP_LIST: [S2C, "Destinations du zaap `zaap` (map) : [{map, name_id, area_name_id, coords, cost}] et point de sauvegarde", {"zaap": "int", "destinations": "array", "save_map": "int"}],
	DIALOG: [S2C, "Un PNJ parle : `text_id` (id i18n du client) ou `text` (monde fait main), `replies` [{id, text_id | text}] déjà filtrées par les conditions du personnage ; `action` {type, …} si la réponse précédente en avait une (shop, quête…)", {"npc": "int", "replies": "array"}],
	SHOP_OPEN: [S2C, "Une boutique de PNJ s'ouvre : `items` [{item, price}] (prix d'achat) ; `sell_divisor` : le PNJ rachète au prix / sell_divisor", {"npc": "int", "items": "array", "sell_divisor": "int"}],
	QUEST_START: [S2C, "Une quête commence (réponse `quest_start` d'un PNJ) : `quest` {id, name_id, step, steps, step_name_id, desc_id, level, objectives: [{id, type, params, map, count, need, done, locked}]}", {"quest": "dict"}],
	QUEST_UPDATE: [S2C, "Une quête progresse (objectif, ou étape suivante) : sa vue complète `quest` ; `rewards` {xp, kamas, items: [[id, qty]], emotes, spells, titles} si une étape vient d'être terminée", {"quest": "dict", "rewards": "dict?"}],
	QUEST_COMPLETE: [S2C, "Une quête est terminée : `quest` (id), `name_id`, et les `rewards` de sa dernière étape (déjà donnés : player_stats, item_added suivent)", {"quest": "int", "name_id": "int", "rewards": "dict"}],
	QUEST_ABANDON: [C2S, "Abandonner une quête en cours (P2.04) : sa progression est perdue, `quest_list` revient", {"quest": "int"}],
	MAP_MARKERS: [S2C, "Marqueurs de quête de la map (P2.04), à l'arrivée et à chaque changement de quête : `markers` [{kind: offer (un PNJ propose une quête) | goal (un objectif de l'étape en cours est ici), quest, npc (0 = un lieu), map}]", {"map": "int", "markers": "array"}],
	CRAFT_STATE: [S2C, "Atelier : `skill`, `slots` (cases d'ingrédients du niveau de métier), `view` du métier, `ingredients` posés, `result` (objet fabriqué, 0 = aucune recette), `max` (fois que le sac le permet) ; `book` = les recettes qui tiennent dans les cases [{item, level, ingredients}] (à l'ouverture et après un niveau, [] sinon)", {"skill": "int", "slots": "int", "view": "dict", "ingredients": "array", "result": "int", "max": "int", "book": "array"}],
	FM_RESULT: [S2C, "Résultat d'une rune : `outcome` crit / success / neutral / fail / overmax, `item` = l'équipement après (effets, puits `reserve` en centièmes de poids), `lost` = [[effet, unités perdues]]", {"uid": "int", "rune": "int", "outcome": "str", "item": "dict", "lost": "array"}],
	CRAFT_DONE: [S2C, "`count` exemplaires de `item` fabriqués (les objets arrivent par item_added)", {"item": "int", "count": "int"}],
	QUEST_LIST: [S2C, "Les quêtes du personnage (à la connexion) : `active` [vue de quête] et `finished` [{id, name_id}] dans l'ordre", {"active": "array", "finished": "array"}],
	INTERACTIVE_START: [S2C, "Un joueur (`player` = id d'acteur) commence à récolter `element` avec `skill` jusqu'à `end` (temps de la sim, ms) : animation", {"player": "int", "element": "int", "skill": "int", "end": "int"}],
	INTERACTIVE_END: [S2C, "La récolte de `player` est finie (`done` : réussie) ou interrompue (déplacement, combat, départ)", {"player": "int", "element": "int", "done": "bool"}],
	INTERACTIVE_STATE: [S2C, "L'élément est récolté (`ready` faux, repousse à `until`, temps de la sim) ou a repoussé (`ready` vrai) ; à l'entrée sur la map : les éléments encore récoltés", {"element": "int", "ready": "bool", "until": "int"}],
	JOB_XP: [S2C, "Le métier `job` gagne `gained` XP : `view` {job, level, xp, xp_floor, xp_next}, `levels` = niveaux gagnés", {"gained": "int", "levels": "int", "view": "dict"}],
	BANK_OPEN: [S2C, "Le coffre du compte s'ouvre (réponse « Consulter son coffre personnel » d'un banquier) : `cost` kamas déjà payés (BankRules.access_cost), `kamas` du coffre, `items` = toutes ses piles {uid, id, qty, effects}", {"npc": "int", "cost": "int", "kamas": "int", "items": "array"}],
	BANK_UPDATE: [S2C, "Le coffre a changé : `kamas` (total) et les piles modifiées dans `items` (`qty` 0 = la pile a disparu)", {"kamas": "int", "items": "array"}],
	BANK_END: [S2C, "Le coffre est fermé (fermeture, joueur parti, autre commande)", {}],
	SHOP_END: [S2C, "La boutique est fermée (fermeture, joueur parti, nouveau dialogue)", {}],
	DIALOG_END: [S2C, "Le dialogue est terminé (réponse finale, fermeture, déplacement) ; `action` éventuelle de la dernière réponse", {}],
	ZAAP_KNOWN: [S2C, "Un nouveau zaap est enregistré (première visite de sa map)", {"map": "int"}],
	INFO: [S2C, "Message de jeu (pas une erreur) : `code` (INFO_CODES) et ses valeurs", {"code": "str", "args": "array"}],
	MAP_ENTER: [S2C, "Entrée sur une map : données de la map et acteurs présents", {"map": "dict", "actors": "array"}],
	ACTOR_ADD: [S2C, "Un acteur arrive sur la map (groupe de monstres : `members` [{name_id, level, grade, xp}], `bonus` = étoiles en %; joueur : `breed`, `level`, `life` si fantôme, jamais rien de privé : la sim n'envoie à chacun que la fiche publique de l'autre, P3.01)", {"actor": "dict"}],
	GROUP_ALERT: [S2C, "Un groupe agressif a repéré `target` : il l'attaque s'il reste 3 s dans sa zone", {"group": "int", "target": "int"}],
	ACTOR_REMOVE: [S2C, "Un acteur quitte la map", {"id": "int"}],
	ACTOR_LOOK: [S2C, "Un acteur change d'apparence (objet porté ou retiré) : ses `looks`", {"id": "int", "looks": "array"}],
	ACTOR_MOVE: [S2C, "Un acteur marche : chemin complet et instant de départ", {"id": "int", "path": "array", "t0": "int", "run": "bool"}],
	PING: [C2S, "Horloge : le client mesure son décalage avec le serveur (réseau seulement, répondu par le transport, jamais par la sim)", {"t0": "int"}],
	REGISTER: [C2S, "Compte (serveur seulement) : créer le compte `login` puis s'y connecter (réponse : login_ok ou login_error). Le mot de passe n'est jamais stocké ni journalisé", {"login": "str", "password": "str"}],
	LOGIN: [C2S, "Compte (serveur seulement) : se connecter (réponse : login_ok ou login_error). Une seule connexion par compte. Obligatoire avant hello", {"login": "str", "password": "str"}],
	LOGIN_OK: [S2C, "Connecté : `token` aléatoire de session (exigé par l'API de contenu), `role` (player ou gm), `login` normalisé", {"token": "str", "role": "str", "login": "str"}],
	LOGIN_ERROR: [S2C, "Connexion ou création de compte refusée : `code` (bad_credentials, login_taken, bad_login, already_connected, registration_closed, too_many_attempts)", {"code": "str", "cmd": "str"}],
	CHAT_SEND: [C2S, "Chat (P3.02) : `text` sur le canal `channel` (general, commerce, recruitment, private + `to` = nom du joueur ; group / guild / alliance : P3.03). Un texte qui commence par `/` est une commande (Chat.parse : `/s`, `/b`, `/r`, `/w nom texte`, `/t`, `/g`, `/p`, `/a`, shortcuts de chatchannels). Réponse : chat_msg à chaque destinataire, ou error (chat_flood, channel_unavailable, player_offline)", {"channel": "str", "text": "str", "to": "str?"}],
	CHAT_MSG: [S2C, "Un message de chat : `channel`, `from` (nom) et `from_id` (id d'acteur, bulle au-dessus du personnage), `text` nettoyé, `at` (heure de jeu ms) ; `to` (nom du destinataire) sur un message privé, envoyé aussi à l'expéditeur (écho « À X : ») ; `links` : ids des objets existants cités par `{item:id}` dans le texte (P3.02b) ; canal `group` : les membres du groupe de l'expéditeur", {"channel": "str", "from": "str", "from_id": "int", "text": "str", "at": "int", "to": "str?", "links": "array?"}],
	PONG: [S2C, "Réponse à ping : `t0` renvoyé, `server_ms` = heure de jeu du serveur (celle des `t0` de déplacement) au moment de la réponse", {"t0": "int", "server_ms": "int"}],
	ERROR: [S2C, "Commande refusée ; `ref` = seq de la commande", {"code": "str", "msg": "str", "cmd": "str", "ref": "int?"}],
	PLAYER_STATS: [S2C, "Le personnage (après welcome, combat, boost, grimoire, objet utilisé)", {"stats": "dict"}],
	INVENTORY: [S2C, "Tout l'inventaire (à la connexion)", {"items": "array"}],
	ITEM_ADDED: [S2C, "Une pile d'objets apparaît ou change de quantité", {"item": "dict"}],
	ITEM_REMOVED: [S2C, "Une pile d'objets disparaît", {"uid": "int"}],
	FIGHT_START: [S2C, "Début de combat, phase de placement", {"fight": "int", "you": "int", "fighters": "array", "order": "array", "phase": "str", "placement": "dict", "end": "int"}],
	FIGHTER_PLACED: [S2C, "Placement : un combattant change de cellule", {"id": "int", "cell": "int"}],
	FIGHTER_READY: [S2C, "Placement : un combattant est prêt ou non", {"id": "int", "ready": "bool"}],
	FIGHT_BEGIN: [S2C, "Fin du placement, les tours commencent", {"order": "array"}],
	FIGHT_TURN: [S2C, "`id` joue jusqu'à `end` (ms) ; effets de début de tour", {"id": "int", "ap": "int", "mp": "int", "end": "int", "effects": "array"}],
	FIGHTER_MOVE: [S2C, "Déplacement en combat (`lost` : PA/PM perdus au tacle ; `effects` avant le pas : un porté qui descend de son porteur, `drop` ; `triggered` à l'arrivée : un piège)", {"id": "int", "path": "array", "t0": "int", "mp": "int", "lost": "dict", "effects": "array", "triggered": "array"}],
	SPELL_CAST: [S2C, "Sort lancé et ses effets", {"caster": "int", "spell": "int", "cell": "int", "dir": "int", "ap": "int", "crit": "bool", "effects": "array"}],
	FIGHT_OPTIONS: [S2C, "Les options du combat ont changé : `options` {locked, party_only, secret, help}", {"options": "dict"}],
	CHALLENGE_LIST: [S2C, "Les challenges du combat (au début) : [{id, name_id, desc_id, icon, state, target (id d'un combattant, -1 = aucun), bonus}] ; `state` running / success / failed", {"challenges": "array"}],
	CHALLENGE_UPDATE: [S2C, "Un challenge change d'état : failed dès qu'il est raté, success / failed à la fin du combat", {"id": "int", "state": "str"}],
	FIGHT_END: [S2C, "Fin de combat et gains ; un map_enter suit", {"result": "str", "duration": "int", "rewards": "array"}],
}

## actor dict: {id, kind: "player"|"monster_group", name, cell, dir, looks: [look string],
##              move?: {path, t0, run}, members? (monster_group): [{name, name_id, level}],
##              life? (player): 2 = ghost (Energy)}
## fighter dict: {id, team (0 = players, 1 = monsters), name, looks, cell, dir, level,
##                hp, max_hp, ap, mp, max_ap, max_mp, alive, spells: [id], own_spells: {id: spell}
##                (the weapon hit, Equipment.WEAPON_SPELL), buffs: [buff], shield,
##                summoner (fighter id, -1 = not a summon), monster (monsters.id of a summon),
##                carrying / carried_by (fighter id, -1 = none: carry, P1.12)}
## buff dict: {id, kind: "stat"|"ap"|"mp"|"state"|"shield"|"poison"|"trigger"|"delay"|"spell_reflect", stat?, state?,
##             state_name_id?, flags? (state flags: no_cast, cant_be_moved...), value, turns (-1 = whole
##             fight), caster, spell, on? (trigger: its codes TB, TE, D, DBE, H, X...), effect? (trigger /
##             delay: the kind of the effect it fires / lands; trigger "taken" / "healed": value = the %)} (P1.13b)
## effect dict (spell_cast / fight_turn), always with `target` (fighter id):
##   damage {element, amount, shield, hp, died} · heal {amount, hp} · ap / mp {value, left, dodged}
##   move {path: [cell], how: "push"|"pull"|"teleport"|"swap"|"portal" (P1.13f: path = the portals crossed)...,
##        swap: swapped (the other fighter's id), telefrag (a Xelor's swap: targetMask T, P1.13n)}
##   reflected {to: fighter id} (P1.13r: the harmful effects of this cast on `target` go back to `to`, a spell reflector)
##   · buff {buff} · buff_end {buff: id}
##   summon {summoner, fighter: fighter dict, order: [fighter ids]} (P1.11: a new fighter, the new turn order)
##   carry {carrier, from} (target now on its carrier's cell) · throw {carrier, from, to} ·
##   drop {carrier, cell} (the pair split up: carrier died, carried walked off) (P1.12)
##   mark_add {mark: mark dict} · mark_remove {mark: id} (target = the mark's owner) (P1.13a)
##   cooldown {spell: castable id, turns: cooldown left} (P1.17b: the target's spell cooldown changed)
##   reveal {cell} (the target is no longer invisible: where it is) (P1.13c)
##   explode (the target bomb goes off; its spells' effects follow) (P1.13d)
##   projected {path: [cell], bonus} (the caster's spell goes through these portals and lands on
##   the last one, +bonus% damage and heals) · portal {mark: id, active} (a portal disabled or
##   back on) (P1.13f)
## Each team gets its own view of a fight event (sim FightVisibility, P1.13c): an invisible
## fighter of the other team moves with an empty path, its fighter dict has cell -1, a
## spell it casts has `from` (its cell); the other team's traps are not sent.
## mark dict: {id, kind: "trap"|"glyph_start"|"glyph_end"|"aura" (P1.13b)|"rune"|"glyph_now" (P1.13e)|"wall" (P1.13d: between two
##             bombs, caster = the first bomb)|"portal" (P1.13f: + active, bonus, per_cell), caster, team,
##             spell (castable it casts),
##             origin (spells.id), cell (centre), cells, color ("#rrggbb"), turns (-1 = until triggered),
##             hidden (a trap: only its team draws it)}
## reward dict: {id, name, level, level_up, xp_gained, xp, xp_floor, xp_next, kamas,
##               items: [{id, qty}], hp, max_hp, energy, energy_lost}
## item dict (inventory, item_added): {uid, id, qty, pos (Equipment slot, -1 = bag),
##   effects: [[effects.id, diceNum, diceSide, value]]}
##   (rolled bonuses have diceSide 0; see ItemEffects)
## character summary (characters, character_created): {name, level, breed, sex (0 male, 1 female), look}
## character dict (player_stats): {name, breed, level, xp, xp_floor, xp_next, kamas, capital,
##   stats: {strength, intelligence, chance, agility, vitality, wisdom}, hp, max_hp, hp_t0,
##   regen_ms, ap, mp, additional: {stat: value} (scrolls), bonus: {stat: value} (items, P1.06),
##   weight, max_weight (pods), energy, max_energy, life (0 alive, 2 ghost: Energy),
##   phoenixes: [{map, coords, world_map}] (resurrection phoenixes of the world),
##   derived: {initiative, prospecting, pods, tackle, escape, ap_attack, mp_attack, ap_dodge,
##   mp_dodge, summons, range, crit, power, damage, heals} (StatFormulas), spells: [castable id] (the grade of each used
##   spell, SpellBook), bar: [castable id or 0] (SpellBook.BAR_SLOTS slots)}. Out of fight hp regenerates:
##   hp(now) = min(max_hp, hp + (now - hp_t0) / regen_ms).


## name "" = go to the character selection (characters event).
static func hello(world: String, name := "", look := "") -> Dictionary:
	var msg := {"t": HELLO, "v": VERSION, "world": world}
	if name != "":
		msg["name"] = name
		msg["look"] = look
	return msg

## Clock sync (network hosts only): t0 = the client's own clock when sending.
static func ping(t0: int) -> Dictionary:
	return {"t": PING, "t0": t0}

static func register(login: String, password: String) -> Dictionary:
	return {"t": REGISTER, "login": login, "password": password}

static func login(login_name: String, password: String) -> Dictionary:
	return {"t": LOGIN, "login": login_name, "password": password}

static func login_ok(token: String, role: String, login_name: String) -> Dictionary:
	return {"t": LOGIN_OK, "token": token, "role": role, "login": login_name}

static func login_error(code: String, cmd: String) -> Dictionary:
	return {"t": LOGIN_ERROR, "code": code, "cmd": cmd}

static func chat_send(channel: String, text: String, to := "") -> Dictionary:
	var msg := {"t": CHAT_SEND, "channel": channel, "text": text}
	if to != "":
		msg["to"] = to
	return msg

static func pong(t0: int, server_ms: int) -> Dictionary:
	return {"t": PONG, "t0": t0, "server_ms": server_ms}

static func list_characters() -> Dictionary:
	return {"t": LIST_CHARACTERS}


## body / head: bodies.id / heads.id (0 = default); colors: [] or one int per breed color (-1 = default).
static func create_character(name: String, breed := 12, sex := 0, body := 0, head := 0, colors := []) -> Dictionary:
	return {"t": CREATE_CHARACTER, "name": name, "breed": breed, "sex": sex, "body": body, "head": head, "colors": colors}

static func delete_character(name: String) -> Dictionary:
	return {"t": DELETE_CHARACTER, "name": name}

static func select_character(name: String) -> Dictionary:
	return {"t": SELECT_CHARACTER, "name": name}

static func characters(list: Array, max_count: int, world: Dictionary, breeds := []) -> Dictionary:
	return {"t": CHARACTERS, "list": list, "max": max_count, "world": world, "breeds": breeds}

static func character_created(summary: Dictionary) -> Dictionary:
	return {"t": CHARACTER_CREATED, "character": summary}

static func move(cell: int, run := false) -> Dictionary:
	return {"t": MOVE, "cell": cell, "run": run}

static func use_phoenix() -> Dictionary:
	return {"t": USE_PHOENIX}

static func info(code: String, args := []) -> Dictionary:
	return {"t": INFO, "code": code, "args": args}

static func change_map(dir: String) -> Dictionary:
	return {"t": CHANGE_MAP, "dir": dir}

static func admin_cmd(cmd: String, args: Array = []) -> Dictionary:
	return {"t": ADMIN_CMD, "cmd": cmd, "args": args}

static func use_trigger(cell: int) -> Dictionary:
	return {"t": USE_TRIGGER, "cell": cell}

static func use_zaap() -> Dictionary:
	return {"t": USE_ZAAP}

static func zaap_travel(map: int) -> Dictionary:
	return {"t": ZAAP_TRAVEL, "map": map}

static func npc_talk(npc: int) -> Dictionary:
	return {"t": NPC_TALK, "npc": npc}

static func dialog_reply(reply: int) -> Dictionary:
	return {"t": DIALOG_REPLY, "reply": reply}

static func dialog_close() -> Dictionary:
	return {"t": DIALOG_CLOSE}

static func dialog(npc: int, view: Dictionary, action := {}) -> Dictionary:
	var d := {"t": DIALOG, "npc": npc, "replies": view.get("replies", [])}
	for k: String in ["text_id", "text"]:
		if view.has(k):
			d[k] = view[k]
	if not action.is_empty():
		d["action"] = action
	return d

static func shop_buy(item: int, qty: int) -> Dictionary:
	return {"t": SHOP_BUY, "item": item, "qty": qty}

static func shop_sell(uid: int, qty: int) -> Dictionary:
	return {"t": SHOP_SELL, "uid": uid, "qty": qty}

static func shop_close() -> Dictionary:
	return {"t": SHOP_CLOSE}

static func shop_open(npc: int, items: Array, sell_divisor: int) -> Dictionary:
	return {"t": SHOP_OPEN, "npc": npc, "items": items, "sell_divisor": sell_divisor}

static func quest_start(quest: Dictionary) -> Dictionary:
	return {"t": QUEST_START, "quest": quest}

static func quest_update(quest: Dictionary, rewards := {}) -> Dictionary:
	var d := {"t": QUEST_UPDATE, "quest": quest}
	if not rewards.is_empty():
		d["rewards"] = rewards
	return d

static func quest_complete(quest: int, name_id: int, rewards: Dictionary) -> Dictionary:
	return {"t": QUEST_COMPLETE, "quest": quest, "name_id": name_id, "rewards": rewards}

static func quest_abandon(quest: int) -> Dictionary:
	return {"t": QUEST_ABANDON, "quest": quest}

static func map_markers(map: int, markers: Array) -> Dictionary:
	return {"t": MAP_MARKERS, "map": map, "markers": markers}

static func quest_list(active: Array, finished: Array) -> Dictionary:
	return {"t": QUEST_LIST, "active": active, "finished": finished}

static func bank_move(uid: int, qty: int, dir: String) -> Dictionary:
	return {"t": BANK_MOVE, "uid": uid, "qty": qty, "dir": dir}

static func bank_kamas(amount: int, dir: String) -> Dictionary:
	return {"t": BANK_KAMAS, "amount": amount, "dir": dir}

static func bank_close() -> Dictionary:
	return {"t": BANK_CLOSE}

static func bank_open(npc: int, cost: int, kamas: int, items: Array) -> Dictionary:
	return {"t": BANK_OPEN, "npc": npc, "cost": cost, "kamas": kamas, "items": items}

static func bank_update(kamas: int, items: Array) -> Dictionary:
	return {"t": BANK_UPDATE, "kamas": kamas, "items": items}

static func bank_end() -> Dictionary:
	return {"t": BANK_END}

static func shop_end() -> Dictionary:
	return {"t": SHOP_END}

static func dialog_end(action := {}) -> Dictionary:
	var d := {"t": DIALOG_END}
	if not action.is_empty():
		d["action"] = action
	return d

static func set_save_point() -> Dictionary:
	return {"t": SET_SAVE_POINT}

static func zaap_list(zaap: int, destinations: Array, save_map: int) -> Dictionary:
	return {"t": ZAAP_LIST, "zaap": zaap, "destinations": destinations, "save_map": save_map}

static func zaap_known(map: int) -> Dictionary:
	return {"t": ZAAP_KNOWN, "map": map}

static func fight_attack(group_id: int) -> Dictionary:
	return {"t": FIGHT_ATTACK, "group": group_id}

static func fight_move(cell: int) -> Dictionary:
	return {"t": FIGHT_MOVE, "cell": cell}

static func fight_cast(spell_id: int, cell: int) -> Dictionary:
	return {"t": FIGHT_CAST, "spell": spell_id, "cell": cell}

static func fight_end_turn() -> Dictionary:
	return {"t": FIGHT_END_TURN}

static func fight_option(option: String, value: bool) -> Dictionary:
	return {"t": FIGHT_OPTION, "option": option, "value": value}

static func fight_options(options: Dictionary) -> Dictionary:
	return {"t": FIGHT_OPTIONS, "options": options.duplicate()}

static func challenge_list(challenges: Array) -> Dictionary:
	return {"t": CHALLENGE_LIST, "challenges": challenges.duplicate(true)}

static func challenge_update(id: int, state: String) -> Dictionary:
	return {"t": CHALLENGE_UPDATE, "id": id, "state": state}

static func fight_leave() -> Dictionary:
	return {"t": FIGHT_LEAVE}

static func fight_place(cell: int) -> Dictionary:
	return {"t": FIGHT_PLACE, "cell": cell}

static func fight_ready(ready := true) -> Dictionary:
	return {"t": FIGHT_READY, "ready": ready}


## points: capital to spend, 0 = one characteristic point.
static func boost_stat(stat: String, points := 0) -> Dictionary:
	var msg := {"t": BOOST_STAT, "stat": stat}
	if points > 0:
		msg["points"] = points
	return msg

static func reset_stats() -> Dictionary:
	return {"t": RESET_STATS}

static func equip(uid: int, slot: int) -> Dictionary:
	return {"t": EQUIP, "uid": uid, "slot": slot}

static func unequip(slot: int) -> Dictionary:
	return {"t": UNEQUIP, "slot": slot}

static func use_item(uid: int) -> Dictionary:
	return {"t": USE_ITEM, "uid": uid}


## qty 0 = the whole stack.
static func destroy_item(uid: int, qty := 0) -> Dictionary:
	var msg := {"t": DESTROY_ITEM, "uid": uid}
	if qty > 0:
		msg["qty"] = qty
	return msg

static func inventory(items: Array) -> Dictionary:
	return {"t": INVENTORY, "items": items}

static func interactive_start(player: int, element: int, skill: int, end: int) -> Dictionary:
	return {"t": INTERACTIVE_START, "player": player, "element": element, "skill": skill, "end": end}

static func interactive_end(player: int, element: int, done: bool) -> Dictionary:
	return {"t": INTERACTIVE_END, "player": player, "element": element, "done": done}

static func interactive_state(element: int, ready: bool, until := 0) -> Dictionary:
	return {"t": INTERACTIVE_STATE, "element": element, "ready": ready, "until": until}

static func job_xp(gained: int, levels: int, view: Dictionary) -> Dictionary:
	return {"t": JOB_XP, "gained": gained, "levels": levels, "view": view.duplicate()}

static func craft_open(skill: int) -> Dictionary:
	return {"t": CRAFT_OPEN, "skill": skill}

static func craft_set(ingredients: Array) -> Dictionary:
	return {"t": CRAFT_SET, "ingredients": ingredients.duplicate(true)}

static func craft_do(count: int) -> Dictionary:
	return {"t": CRAFT_DO, "count": count}

static func craft_close() -> Dictionary:
	return {"t": CRAFT_CLOSE}

static func craft_state(skill: int, slots: int, view: Dictionary, ingredients: Array, result: int, max_count: int, book: Array) -> Dictionary:
	return {"t": CRAFT_STATE, "skill": skill, "slots": slots, "view": view.duplicate(), "ingredients": ingredients.duplicate(true), "result": result, "max": max_count, "book": book}

static func fm_apply(uid: int, rune: int) -> Dictionary:
	return {"t": FM_APPLY, "uid": uid, "rune": rune}

static func fm_result(uid: int, rune: int, outcome: String, item: Dictionary, lost: Array) -> Dictionary:
	return {"t": FM_RESULT, "uid": uid, "rune": rune, "outcome": outcome, "item": item.duplicate(true), "lost": lost.duplicate(true)}

static func craft_done(item: int, count: int) -> Dictionary:
	return {"t": CRAFT_DONE, "item": item, "count": count}

static func interactive_use(element: int, skill: int) -> Dictionary:
	return {"t": INTERACTIVE_USE, "element": element, "skill": skill}

static func item_added(item: Dictionary) -> Dictionary:
	return {"t": ITEM_ADDED, "item": item.duplicate(true)}

static func item_removed(uid: int) -> Dictionary:
	return {"t": ITEM_REMOVED, "uid": uid}

static func choose_variant(spell: int) -> Dictionary:
	return {"t": CHOOSE_VARIANT, "spell": spell}

static func move_spell(spell: int, slot: int) -> Dictionary:
	return {"t": MOVE_SPELL, "spell": spell, "slot": slot}

static func welcome(you: int, time: int, world: Dictionary) -> Dictionary:
	return {"t": WELCOME, "v": VERSION, "you": you, "time": time, "world": world}

static func map_enter(map: Dictionary, actors: Array) -> Dictionary:
	return {"t": MAP_ENTER, "map": map, "actors": actors}

static func actor_add(actor: Dictionary) -> Dictionary:
	return {"t": ACTOR_ADD, "actor": actor}

static func group_alert(group: int, target: int) -> Dictionary:
	return {"t": GROUP_ALERT, "group": group, "target": target}

static func actor_remove(id: int) -> Dictionary:
	return {"t": ACTOR_REMOVE, "id": id}

static func actor_look(id: int, looks: Array) -> Dictionary:
	return {"t": ACTOR_LOOK, "id": id, "looks": looks}

static func actor_move(id: int, path: Array, t0: int, run: bool) -> Dictionary:
	return {"t": ACTOR_MOVE, "id": id, "path": path, "t0": t0, "run": run}


## code: one of the E_* constants; msg: English detail for logs; cmd: the
## refused command's type.
static func error(code: String, msg := "", cmd := "") -> Dictionary:
	return {"t": ERROR, "code": code, "msg": msg if msg != "" else code, "cmd": cmd}

static func player_stats(character: Dictionary) -> Dictionary:
	return {"t": PLAYER_STATS, "stats": character}

static func fight_start(fight_id: int, you: int, fighters: Array, order: Array, placement := {}, end := 0) -> Dictionary:
	return {"t": FIGHT_START, "fight": fight_id, "you": you, "fighters": fighters, "order": order,
			"phase": "placement", "placement": placement, "end": end}

static func fighter_placed(id: int, cell: int) -> Dictionary:
	return {"t": FIGHTER_PLACED, "id": id, "cell": cell}

static func fighter_ready(id: int, ready: bool) -> Dictionary:
	return {"t": FIGHTER_READY, "id": id, "ready": ready}

static func fight_begin(order: Array) -> Dictionary:
	return {"t": FIGHT_BEGIN, "order": order}

static func fight_turn(id: int, ap: int, mp: int, end: int, effects := []) -> Dictionary:
	return {"t": FIGHT_TURN, "id": id, "ap": ap, "mp": mp, "end": end, "effects": effects}

static func fighter_move(id: int, path: Array, t0: int, mp: int, lost := {}, effects: Array = [], triggered: Array = []) -> Dictionary:
	return {"t": FIGHTER_MOVE, "id": id, "path": path, "t0": t0, "mp": mp, "lost": lost, "effects": effects, "triggered": triggered}

static func spell_cast(caster: int, spell_id: int, cell: int, dir: int, ap: int, effects: Array, crit := false) -> Dictionary:
	return {"t": SPELL_CAST, "caster": caster, "spell": spell_id, "cell": cell, "dir": dir, "ap": ap,
			"crit": crit, "effects": effects}

static func fight_end(result: String, duration := 0, rewards := []) -> Dictionary:
	return {"t": FIGHT_END, "result": result, "duration": duration, "rewards": rewards}


## "" when `msg` matches SCHEMA (in the expected direction, if given), else a
## short English reason. Numbers that came back from JSON as integral floats
## count as ints.
static func validate(msg: Dictionary, direction := "") -> String:
	var type := str(msg.get("t", ""))
	var entry: Array = SCHEMA.get(type, ProtocolParty.SCHEMA.get(type, ProtocolWatch.SCHEMA.get(type, ProtocolResume.SCHEMA.get(type, ProtocolAdmin.SCHEMA.get(type, ProtocolCluster.SCHEMA.get(type, ProtocolTrade.SCHEMA.get(type, ProtocolContacts.SCHEMA.get(type, []))))))))
	if entry.is_empty():
		return "unknown message type '%s'" % type
	if direction != "" and entry[0] != direction:
		return "'%s' is not a %s message" % [type, direction]
	var fields: Dictionary = entry[2]
	if msg.has("seq") and not _is_type(msg["seq"], "int"):
		return "seq must be an int"
	for f: String in fields:
		var kind: String = fields[f]
		var optional := kind.ends_with("?")
		kind = kind.trim_suffix("?")
		if not msg.has(f):
			if optional:
				continue
			return "%s: missing field '%s'" % [type, f]
		if not _is_type(msg[f], kind):
			return "%s: field '%s' must be %s" % [type, f, kind]
	return ""

static func _is_type(v: Variant, kind: String) -> bool:
	match kind:
		"int":
			return typeof(v) == TYPE_INT or (typeof(v) == TYPE_FLOAT and v == floorf(v) and is_finite(v))
		"bool":
			return typeof(v) == TYPE_BOOL
		"str":
			return typeof(v) == TYPE_STRING
		"dict":
			return typeof(v) == TYPE_DICTIONARY
		"array":
			return typeof(v) == TYPE_ARRAY
	return false


## What a network hop does to a message.
static func roundtrip(msg: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(msg))


## True if `v` only contains Dictionary / Array / String / int / float / bool / null.
static func is_json_safe(v: Variant) -> bool:
	match typeof(v):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
			return true
		TYPE_ARRAY:
			for e: Variant in v:
				if not is_json_safe(e):
					return false
			return true
		TYPE_DICTIONARY:
			for k: Variant in v:
				if typeof(k) != TYPE_STRING or not is_json_safe(v[k]):
					return false
			return true
	return false
