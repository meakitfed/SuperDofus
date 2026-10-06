## Layering rules (docs/ARCHITECTURE.md), checked on the source text:
##   shared/ + sim/  pure logic: no nodes, input, rendering, client or backend
##   client/         never touches sim/ directly, only api/ + shared/
##   size            no script goes over MAX_LINES lines (R.01), unless listed in SIZE_EXCEPTIONS
extends TestCase

const PURE_DIRS := ["res://src/shared", "res://src/sim"]
const PURE_FORBIDDEN := ["Node", "Node2D", "Input", "get_tree", "RenderingServer", "DofusSprite",
		"DofusContent", "GameBackend", "LocalBackend", "ClientSession", "ActorView", "GroupView", "MapView",
		"FightView", "FightHud", "SpellFx", "FightResultWindow", "PlayerHud", "InventoryWindow", "CharacteristicsWindow", "UiWindow", "UiStyle", "ItemSlot", "UiTooltips", "FilePersistence", "Toast", "ErrorTexts",
		"SystemClock", "LocalServer", "FileAccess", "DirAccess", "HTTPRequest", "HTTPClient", "WebSocketPeer",
		"WebSocketMultiplayerPeer", "StreamPeerTCP", "TCPServer", "PacketPeerUDP", "Time", "OS", "Engine",
		"TimelineTile", "ClientTheme", "ServerHost", "NetBackend"]
const CLIENT_FORBIDDEN := ["WorldSim", "MapInstance", "SimActor", "PlayerActor", "MonsterGroup",
		"MonsterGroupAI", "WorldSource", "JsonWorldSource", "Fight", "Fighter", "FightAI", "FightEffects",
		"FightRewards", "Buff", "Character", "Persistence", "Clock", "LocalServer", "ServerHost"]

## A script is split by domain before it passes this size (WorldSim and its WorldHandler
## classes, FightEffects / FightDisplace, FightView / FightTexts / FightVisuals...).
const MAX_LINES := 800
const SIZE_DIRS := ["res://src", "res://addons", "res://tests", "res://tools"]
## path -> why it may stay longer (none today: add a line here, with the reason, rather
## than raising MAX_LINES)
const SIZE_EXCEPTIONS := {}

## C.01: nobody reads res://content, res://data, res://worlds or res://mods directly:
## everything goes through ContentSource (logical paths, so a downloaded world cache can
## replace res://).
const CONTENT_LITERALS := ["res://content", "res://data", "res://worlds", "res://mods"]
## path -> why a literal may stay
const CONTENT_EXCEPTIONS := {
	"res://addons/dofus_renderer/dofus_content.gd": "the add-on's own default root when no provider is injected (it stays standalone)",
	"res://src/shared/content_source.gd": "the layer itself",
}

## The one exception: ContentSource reads the static game data (read-only); DataFiles and the
## renderer provider go through it.
const DATA_READER := "res://src/shared/content_source.gd"


func test_shared_and_sim_are_pure() -> void:
	for dir: String in PURE_DIRS:
		for file in _scripts(dir):
			_forbid(file, PURE_FORBIDDEN if file != DATA_READER else PURE_FORBIDDEN.filter(
					func(w: String) -> bool: return w != "FileAccess" and w != "DirAccess"))


## Determinism: the sim draws only from its seeded RandomNumberGenerator.
func test_sim_has_no_global_random() -> void:
	var re := RegEx.create_from_string("(?<![.\\w])(randf|randi|randf_range|randi_range|randfn|randomize|seed)\\s*\\(")
	for dir: String in PURE_DIRS:
		for file in _scripts(dir):
			var lines := FileAccess.get_file_as_string(file).split("\n")
			for i in lines.size():
				if re.search(lines[i].get_slice("#", 0)) != null:
					check(false, "%s:%d uses the global RNG" % [file, i + 1])


## The network host is a host (S.01): nothing but its own entry point may use it, and
## the engine layers never reach for the server or the transport.
func test_nothing_depends_on_the_server_folder() -> void:
	for dir: String in ["res://src/shared", "res://src/sim", "res://src/client", "res://src/api"]:
		for file in _scripts(dir):
			var lines := FileAccess.get_file_as_string(file).split("
")
			for i in lines.size():
				if lines[i].get_slice("#", 0).contains("res://src/server"):
					check(false, "%s:%d references server/" % [file, i + 1])
	for file in _scripts("res://src/server"):
		_forbid(file, ["ClientSession", "FightView", "PlayerHud", "UiWindow", "MapView", "ActorView", "Input"])


func test_no_hardcoded_content_paths_outside_content_source() -> void:
	for dir: String in ["res://src", "res://addons", "res://scenes", "res://tools"]:
		for file in _scripts(dir):
			if CONTENT_EXCEPTIONS.has(file):
				continue
			var lines := FileAccess.get_file_as_string(file).split("\n")
			for i in lines.size():
				var code := lines[i].get_slice("#", 0)
				for lit: String in CONTENT_LITERALS:
					if code.contains(lit):
						check(false, "%s:%d reads %s directly: use ContentSource" % [file, i + 1, lit])


func test_client_only_uses_the_api() -> void:
	for file in _scripts("res://src/client"):
		_forbid(file, CLIENT_FORBIDDEN)


## File size (R.01): a god object is split before it grows past MAX_LINES.
func test_scripts_stay_small() -> void:
	for dir: String in SIZE_DIRS:
		for file in _scripts(dir):
			if SIZE_EXCEPTIONS.has(file):
				continue
			var lines := FileAccess.get_file_as_string(file).count("
") + 1
			check(lines <= MAX_LINES, "%s has %d lines (max %d): split it by domain" % [file, lines, MAX_LINES])


func _forbid(file: String, words: Array) -> void:
	var lines := FileAccess.get_file_as_string(file).split("\n")
	for i in lines.size():
		var code := lines[i].get_slice("#", 0) # comments may mention anything
		for w: String in words:
			var re := RegEx.create_from_string("\\b%s\\b" % w)
			if re.search(code) != null:
				check(false, "%s:%d uses %s" % [file, i + 1, w])


func _scripts(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir + "/" + f)
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_scripts(dir + "/" + d))
	return out
