## Animation naming rules: `<Base>_<direction>`, mirrored directions, and the
## fallback chain used to pick a carried sub-entity's animation.
class_name DofusAnimNames
extends RefCounted

enum Direction { RIGHT = 0, DOWN_RIGHT = 1, DOWN = 2, DOWN_LEFT = 3, LEFT = 4, UP_LEFT = 5, UP = 6, UP_RIGHT = 7 }

const _OPPOSITE := {0: 4, 1: 3, 3: 1, 4: 0, 5: 7, 7: 5}
const _EXPLO_COMBAT := "(Explo|Combat)\\d+"


static var _explo_regex: RegEx


## Opposite (mirrored) direction, or -1 for DOWN/UP which have none.
static func opposite(direction: int) -> int:
	return _OPPOSITE.get(direction, -1)


static func split(anim_name: String) -> Array:
	var i := anim_name.rfind("_")
	if i < 0:
		return [anim_name, -1]
	var tail := anim_name.substr(i + 1)
	return [anim_name.substr(0, i), tail.to_int() if tail.is_valid_int() else -1]


static func default_base(bone: int) -> String:
	return "AnimStatiqueExplo0" if bone == 1 else "AnimStatique"


## Resolve `base` + `direction` against the available animation names.
## Exact direction first, then its mirror, then the nearest direction (many monsters only
## have diagonals 1/5, mirrored to 3/7). Returns [anim_name, flip_x] or ["", false].
static func resolve(animations: Dictionary, direction: int, bone: int, base := "") -> Array:
	var wanted := base if base != "" else default_base(bone)
	for d in _nearest_directions(direction):
		var direct := "%s_%d" % [wanted, d]
		if animations.has(direct):
			return [direct, false]
		var m := opposite(d)
		if m >= 0 and animations.has("%s_%d" % [wanted, m]):
			return ["%s_%d" % [wanted, m], true]
	# a base-less anim (FX, props) may exist without a direction suffix
	if animations.has(wanted):
		return [wanted, false]
	if base == "":
		# anything but the artwork/illustration clips, preferring the requested direction
		var fallback := ""
		for k: String in animations:
			if k.begins_with("AnimArtwork"):
				continue
			if k.ends_with("_%d" % direction):
				return [k, false]
			if fallback == "":
				fallback = k
		if fallback != "":
			return [fallback, false]
	return ["", false]


## Directions by increasing angular distance; ties favour the ones facing the camera
## (south), so east falls back to south-east and west to south-west.
static func _nearest_directions(direction: int) -> Array[int]:
	var out: Array[int] = [direction]
	for k in range(1, 5):
		var a := posmod(direction + k, 8)
		var b := posmod(direction - k, 8)
		if a == b:
			out.append(a)
		elif _facing_camera(b) > _facing_camera(a):
			out.append_array([b, a])
		else:
			out.append_array([a, b])
	return out


static func _facing_camera(d: int) -> int:
	return 1 if d in [1, 2, 3] else (0 if d in [0, 4] else -1)


## base name -> sorted directions available (mirrors included).
static func directions_by_anim(animations: Array) -> Dictionary:
	var out := {}
	for key: String in animations:
		var parts := split(key)
		var dir: int = parts[1]
		if dir < 0:
			continue
		var base: String = parts[0]
		if not out.has(base):
			out[base] = []
		var set: Array = out[base]
		if not set.has(dir):
			set.append(dir)
		var opp := opposite(dir)
		if opp >= 0 and not set.has(opp):
			set.append(opp)
	for base: String in out:
		out[base].sort()
	return out


## Animation a carried sprite (pet, mount…) plays while its parent plays `parent_anim`.
## Returns [anim_name, flip_x] or ["", false].
static func related_child_anim(animations: Dictionary, parent_anim: String) -> Array:
	if _explo_regex == null:
		_explo_regex = RegEx.create_from_string(_EXPLO_COMBAT)
	var clean := _explo_regex.sub(parent_anim, "")
	if animations.has(clean):
		return [clean, false]
	var i := parent_anim.rfind("_")
	if i < 0:
		return ["", false]
	var base := parent_anim.substr(0, i)
	var orientation := parent_anim.substr(i + 1)
	var found := _child_candidate(animations, base, orientation)
	if found != "":
		return [found, false]
	if orientation.is_valid_int():
		var opp := opposite(orientation.to_int())
		if opp >= 0:
			found = _child_candidate(animations, base, str(opp))
			if found != "":
				return [found, true]
	if not animations.is_empty():
		return [animations.keys()[0], false]
	return ["", false]


static func _child_candidate(animations: Dictionary, base: String, orientation: String) -> String:
	for c in ["%sExplo0_%s" % [base, orientation], "%s_%s" % [base, orientation],
			"AnimStatiqueExplo0_%s" % orientation, "AnimStatique_%s" % orientation, "FX_%s" % orientation]:
		if animations.has(c):
			return c
	return ""
