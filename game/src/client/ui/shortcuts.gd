## Every keyboard shortcut of the client, in one place (Dofus defaults).
## Code asks `Shortcuts.pressed(event, "inventory")` instead of testing keys,
## so the options window (roadmap P5.04) can remap them.
class_name Shortcuts
extends RefCounted

## action -> [keycode, label]
const DEFAULTS := {
	"close": [KEY_ESCAPE, "Fermer la fenêtre"],
	"confirm": [KEY_ENTER, "Valider"],
	"inventory": [KEY_I, "Inventaire"],
	"characteristics": [KEY_C, "Caractéristiques"],
	"end_turn": [KEY_SPACE, "Finir le tour / Prêt"],
	"spells": [KEY_S, "Sorts"],
	"worldmap": [KEY_M, "Carte du monde"],
	"quests": [KEY_Q, "Journal de quêtes"],
	"friends": [KEY_F, "Amis"],
	"workshop": [KEY_J, "Atelier de métier"],
	"smithmagic": [KEY_K, "Forgemagie"],
	"command": [KEY_ENTER, "Ligne de commande (/tp)"],
	"spell_slot_1": [KEY_1, "Sort 1 de la barre"],
	"spell_slot_2": [KEY_2, "Sort 2 de la barre"],
	"spell_slot_3": [KEY_3, "Sort 3 de la barre"],
	"spell_slot_4": [KEY_4, "Sort 4 de la barre"],
	"spell_slot_5": [KEY_5, "Sort 5 de la barre"],
	"spell_slot_6": [KEY_6, "Sort 6 de la barre"],
	"spell_slot_7": [KEY_7, "Sort 7 de la barre"],
	"spell_slot_8": [KEY_8, "Sort 8 de la barre"],
	"spell_slot_9": [KEY_9, "Sort 9 de la barre"],
	"spell_slot_10": [KEY_0, "Sort 10 de la barre"],
}

static var _keys := {}


static func key(action: String) -> Key:
	if _keys.has(action):
		return _keys[action]
	return DEFAULTS.get(action, [KEY_NONE])[0]


static func remap(action: String, keycode: Key) -> void:
	_keys[action] = keycode


## True for the first press (no echo) of the action's key.
static func pressed(event: InputEvent, action: String) -> bool:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return false
	var k := event as InputEventKey
	# spell slots: the digit row wherever it is (AZERTY types & é " … there)
	return k.keycode == key(action) or (action.begins_with("spell_slot_") and k.physical_keycode == key(action))


## "Inventaire (I)": for tooltips and help texts.
static func label(action: String) -> String:
	var d: Array = DEFAULTS.get(action, ["", action])
	return "%s (%s)" % [d[1], OS.get_keycode_string(key(action))]


## Just the key name ("1", "S").
static func label_key(action: String) -> String:
	return OS.get_keycode_string(key(action))
