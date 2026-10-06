## Add-on content (mods/<id>/), merged over the generated data without
## touching it. mods/mods.json lists the enabled mods: {"enabled": ["joss"]};
## remove an id to switch that mod off. A mod may hold:
##   spells.json                 {"spells": [castable spell, ...]} (SpellBook format)
##   worlds/<world>/monsters.json {"monsters": {id: {...}}, "groups": {map id: [spawn, ...]}}
##   Content/...                  bones and skins for the renderer (listed in
##                                project.godot, dofus_renderer/content_overlays)
## Mods only add: ids already in the game data are never replaced.
class_name Mods
extends RefCounted

const ROOT := "mods"


static func enabled() -> Array:
	var data: Variant = DataFiles.read_json(ROOT + "/mods.json")
	return (data.get("enabled", []) as Array) if data is Dictionary else []


## Parsed `rel_path` of every enabled mod that has it (Dictionaries only).
static func read_all(rel_path: String) -> Array:
	var out: Array = []
	for id: Variant in enabled():
		var d: Variant = DataFiles.read_json("%s/%s/%s" % [ROOT, str(id), rel_path])
		if d is Dictionary:
			out.append(d)
	return out
