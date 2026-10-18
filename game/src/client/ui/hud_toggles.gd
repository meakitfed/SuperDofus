## What the player hides of the interface (lot U.14): everything at once (`toggle_ui`, Dofus
## `Common/toggleShowUI`), or the chat, the minimap and the quest tracker one by one. The three
## single choices are remembered between sessions (user://hud_toggles.json, like UiWindow's layout);
## "everything hidden" is not: a game must never start with an empty screen. In a fight the hidden
## interface keeps the "end turn" button (FightHud.compact). Pure state: the session applies it.
class_name HudToggles
extends RefCounted

const FILE := "user://hud_toggles.json"
const PARTS := ["chat", "minimap", "tracker"]

static var hidden_all := false
static var folded := {"chat": false, "minimap": false, "tracker": false}
static var persist := true
static var _loaded := false


## True when `part` ("chat", "minimap", "tracker") must not show, by either choice.
static func is_hidden(part: String) -> bool:
	_load()
	return hidden_all or bool(folded.get(part, false))


static func toggle_all() -> void:
	hidden_all = not hidden_all


static func toggle(part: String) -> void:
	_load()
	if not PARTS.has(part):
		return
	folded[part] = not bool(folded[part])
	_save()


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	if not persist or not FileAccess.file_exists(FILE):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(FILE))
	if data is Dictionary:
		for p: String in PARTS:
			folded[p] = bool((data as Dictionary).get(p, false))


static func _save() -> void:
	if not persist:
		return
	var f := FileAccess.open(FILE, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(folded))


## Tests: nothing hidden, nothing read or written on disk.
static func reset_for_tests() -> void:
	_loaded = true
	persist = false
	hidden_all = false
	folded = {"chat": false, "minimap": false, "tracker": false}


## The short hint toasted when the interface goes away.
static func hint() -> String:
	return "Interface masquée : %s pour la réafficher" % Shortcuts.label_key("toggle_ui")
