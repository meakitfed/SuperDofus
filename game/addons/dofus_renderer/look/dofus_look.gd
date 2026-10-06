## Dofus entity look: `{bone|skin1,skin2|idx=color,...|scale|cat@idx={sub look}...}`.
## Pure data (no rendering, no IO) so gameplay code may build and serialise looks freely.
class_name DofusLook
extends RefCounted

const PALETTE_SIZE := 16
const _BASES := {"A": 10, "G": 16, "Z": 36}
const _DIGITS := "0123456789abcdefghijklmnopqrstuvwxyz"
const _RIDER_MOUNT_INDICES: Array[int] = [3, 4, 5, 6]

var bone: int = 0
var skins: PackedInt32Array = PackedInt32Array()
## palette index -> Vector3 colour, already normalised by 127 (so 0..~2, as the game does)
var colors: Dictionary = {}
var size: float = 1.0
## category (DofusSubEntity.Category) -> { binding index -> DofusLook }
var sub_entities: Dictionary = {}


static func create(p_bone: int, p_skins: PackedInt32Array = PackedInt32Array(), p_colors: Dictionary = {}, p_size := 1.0) -> DofusLook:
	var look := DofusLook.new()
	look.bone = p_bone
	look.skins = p_skins
	look.colors = p_colors.duplicate()
	look.size = p_size
	return look


# ── parsing ────────────────────────────────────────────────────────────────────

static func parse(look_string: String, number_base := 10) -> DofusLook:
	var s := look_string.strip_edges()
	var base := number_base
	if s.begins_with("["):
		var close := s.find("]")
		var header := s.substr(1, close - 1).split(",")
		base = _BASES.get(header[1] if header.size() > 1 else "", 10)
		s = s.substr(close + 1)
	if s.contains(",{"):
		s = _default_conditional_look(s)

	var inner := s.substr(1) if s.begins_with("{") else s
	if inner.ends_with("}"):
		inner = inner.left(-1)
	var parts := inner.split("|")
	var bone_str: String = parts[0] if parts.size() > 0 else ""
	var skins_str: String = parts[1] if parts.size() > 1 else ""
	var color_str: String = parts[2] if parts.size() > 2 else ""
	var size_str: String = parts[3] if parts.size() > 3 else ""
	var sub_str := "|".join(parts.slice(4)) if parts.size() > 4 else ""

	var look := DofusLook.new()
	look.bone = parse_int(bone_str, base) if bone_str != "" else 0
	if skins_str != "":
		for token in skins_str.split(","):
			look.skins.append(parse_int(token, base))
	if color_str != "":
		look.colors = parse_colors(color_str, base)
	look.size = parse_int(size_str, base) / 100.0 if size_str != "" else 1.0

	if sub_str != "":
		for chunk in _split_sub_entities(sub_str):
			var eq := chunk.find("=")
			if eq < 0:
				continue
			var header := chunk.substr(0, eq)
			var at := header.find("@")
			var category := parse_int(header.substr(0, at), base)
			var binding := parse_int(header.substr(at + 1), base)
			look.set_sub_entity(category, DofusLook.parse(chunk.substr(eq + 1)), binding)
	return look


## Splits `2@0={...},3@0={...}` at top level, honouring nested braces (the reference
## implementation splits naively on `}` which breaks on nested sub-entities).
static func _split_sub_entities(raw: String) -> PackedStringArray:
	var out := PackedStringArray()
	var depth := 0
	var start := 0
	for i in raw.length():
		var c := raw[i]
		if c == "{":
			depth += 1
		elif c == "}":
			depth -= 1
			if depth == 0:
				var chunk := raw.substr(start, i - start + 1)
				if chunk.begins_with(","):
					chunk = chunk.substr(1)
				out.append(chunk)
				start = i + 1
	return out


static func _default_conditional_look(s: String) -> String:
	var candidates: Array[PackedStringArray] = []
	for part in s.split(",{"):
		var clean := part.left(-1) if part.ends_with("}") else part
		candidates.append(clean.split("$"))
	for c in candidates:
		if c.size() > 1 and c[1].ends_with(";"):
			return c[0]
	return candidates[0][0]


static func parse_int(token: String, base := 10) -> int:
	var t := token.strip_edges().to_lower()
	if base == 10:
		return t.to_int()
	var negative := t.begins_with("-")
	if negative:
		t = t.substr(1)
	var value := 0
	for c in t:
		var d := _DIGITS.find(c)
		if d < 0 or d >= base:
			break
		value = value * base + d
	return -value if negative else value


static func parse_colors(value: String, base := 10) -> Dictionary:
	var result := {}
	for item in value.split(","):
		var kv := item.split("=")
		if kv.size() != 2:
			continue
		var idx := parse_int(kv[0], base)
		var raw := kv[1]
		var rgb := raw.substr(1).hex_to_int() if raw.begins_with("#") else parse_int(raw, base)
		result[idx] = int_to_rgb(rgb)
	return result


# ── colours ────────────────────────────────────────────────────────────────────

## Dofus colours are divided by 127 (not 255): the shader multiplies the grey
## texture by up to ~2x, which is what gives the characteristic saturated tints.
static func int_to_rgb(value: int, divide := 127.0) -> Vector3:
	return Vector3(((value >> 16) & 0xff) / divide, ((value >> 8) & 0xff) / divide, (value & 0xff) / divide)


static func rgb_to_int(rgb: Vector3) -> int:
	return (clampi(roundi(rgb.x * 127.0), 0, 255) << 16) | (clampi(roundi(rgb.y * 127.0), 0, 255) << 8) 			| clampi(roundi(rgb.z * 127.0), 0, 255)


static func indexed_colors_to_dict(indexed: PackedInt32Array) -> Dictionary:
	var result := {}
	for i in indexed:
		result[(i >> 24) & 0xff] = int_to_rgb(i)
	return result


## Rider colour slots 3..6 drive mount colour slots 1..4.
static func rider_to_mount_colors(rider_colors: Dictionary) -> Dictionary:
	var result := {}
	for position in _RIDER_MOUNT_INDICES.size():
		var rider_index := _RIDER_MOUNT_INDICES[position]
		if rider_colors.has(rider_index):
			result[position + 1] = rider_colors[rider_index]
	return result


func set_color(index: int, rgb: Vector3) -> void:
	colors[index] = rgb


## Colour-by-byte helper for UIs: takes a regular Color (0..1) and stores it the Dofus way.
func set_color_from(index: int, c: Color) -> void:
	colors[index] = Vector3(c.r8, c.g8, c.b8) / 127.0


func get_color(index: int) -> Color:
	var v: Vector3 = colors.get(index, Vector3(127, 127, 127) / 127.0)
	return Color8(clampi(roundi(v.x * 127.0), 0, 255), clampi(roundi(v.y * 127.0), 0, 255), clampi(roundi(v.z * 127.0), 0, 255))


## Shader palette: 16 slots, white when unset.
func palette() -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(PALETTE_SIZE)
	out.fill(Vector3.ONE)
	for idx: int in colors:
		if idx >= 0 and idx < PALETTE_SIZE:
			out[idx] = colors[idx]
	return out


## Fill missing colours (fewer than 6 set) with the breed defaults, recursively.
func inject_default_colors(game_data: DofusGameData) -> void:
	if colors.size() < 6 and game_data != null and skins.size() > 0:
		var defaults := game_data.default_colors_for_body_skin(skins[0])
		for i in defaults.size():
			if not colors.has(i + 1):
				colors[i + 1] = int_to_rgb(defaults[i])
	for category: int in sub_entities:
		for binding: int in sub_entities[category]:
			(sub_entities[category][binding] as DofusLook).inject_default_colors(game_data)


# ── sub entities ───────────────────────────────────────────────────────────────

func set_sub_entity(category: int, sub_look: DofusLook, binding_index := 0) -> void:
	if not sub_entities.has(category):
		sub_entities[category] = {}
	sub_entities[category][binding_index] = sub_look


func remove_sub_entity(category: int, binding_index := 0) -> void:
	if sub_entities.has(category):
		sub_entities[category].erase(binding_index)
		if sub_entities[category].is_empty():
			sub_entities.erase(category)


func get_sub_entity(category: int, binding_index := 0) -> DofusLook:
	return sub_entities.get(category, {}).get(binding_index, null)


## Keys used by the animation data to reference carried sprites: `carried_<cat>_<idx>`.
func sub_entity_keys() -> PackedStringArray:
	var keys := PackedStringArray()
	for category: int in sub_entities:
		for binding: int in sub_entities[category]:
			keys.append(sub_entity_key(category, binding))
	keys.sort()
	return keys


static func sub_entity_key(category: int, binding: int) -> String:
	return "carried_%d_%d" % [category, binding]


# ── misc ───────────────────────────────────────────────────────────────────────

func duplicate_look() -> DofusLook:
	var copy := DofusLook.create(bone, skins.duplicate(), colors, size)
	for category: int in sub_entities:
		for binding: int in sub_entities[category]:
			copy.set_sub_entity(category, (sub_entities[category][binding] as DofusLook).duplicate_look(), binding)
	return copy


func same_skins(other: DofusLook) -> bool:
	var a := skins.duplicate()
	var b := other.skins.duplicate()
	a.sort()
	b.sort()
	return a == b


func _to_string() -> String:
	var color_parts := PackedStringArray()
	var keys := colors.keys()
	keys.sort()
	for idx: int in keys:
		color_parts.append("%d=%d" % [idx, rgb_to_int(colors[idx])])
	var skin_parts := PackedStringArray()
	for s in skins:
		skin_parts.append(str(s))
	var components := PackedStringArray([
		str(bone) if bone != 0 else "",
		",".join(skin_parts),
		",".join(color_parts),
		str(int(floor(size * 100.0 + 0.0001))),
	])
	var subs := PackedStringArray()
	for category: int in sub_entities:
		for binding: int in sub_entities[category]:
			subs.append("%d@%d=%s" % [category, binding, str(sub_entities[category][binding])])
	if not subs.is_empty():
		components.append(",".join(subs))
	return "{%s}" % "|".join(components)
