## Builds and checks a character's look string from the creation choices,
## exactly like Dofus: "{bone|body skin,face skin|1=color,2=color…|scale}".
## Shared: the sim validates a creation with it, the creation screen previews
## every choice with the very same function.
##   bone and scale:  breeds.maleLook / femaleLook ("{1|120||57}")
##   body skin:       bodies.skins (breed, gender, availableAtCreation; order 1 = base, the breed's own skin)
##   face skin:       heads.skins  (breed, gender, availableAtCreation)
##   colors 1..n:     breeds.maleColors / femaleColors, each one replaceable
class_name LookBuilder
extends RefCounted

const MAX_COLOR := 0xFFFFFF


## breeds rows sorted like the Dofus class list (breeds.sortIndex).
static func breeds() -> Array:
	var out: Array = GameData.table("breeds").values()
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("sortIndex", 0)) < int(b.get("sortIndex", 0)))
	return out


## Choosable bodies / faces of a breed and sex (availableAtCreation, not payable), by order.
static func bodies(breed: int, sex: int) -> Array:
	return _choices("bodies", breed, sex)


static func faces(breed: int, sex: int) -> Array:
	return _choices("heads", breed, sex)


static func default_colors(breed: int, sex: int) -> Array:
	var row := GameData.row("breeds", breed)
	return (row.get("femaleColors" if sex == 1 else "maleColors", []) as Array).map(func(c: Variant) -> int: return int(c))


## "" if the choices are allowed, else an E_* code. body / face: bodies.id /
## heads.id (0 = the first one); colors: [] or one int per breed color (-1 = default).
static func check(breed: int, sex: int, body := 0, face := 0, colors := []) -> String:
	if GameData.row("breeds", breed).is_empty():
		return Protocol.E_UNKNOWN_BREED
	if sex != 0 and sex != 1:
		return Protocol.E_BAD_LOOK
	if body != 0 and not bodies(breed, sex).any(func(b: Dictionary) -> bool: return int(b["id"]) == body):
		return Protocol.E_BAD_LOOK
	if face != 0 and not faces(breed, sex).any(func(h: Dictionary) -> bool: return int(h["id"]) == face):
		return Protocol.E_BAD_LOOK
	if colors.size() > default_colors(breed, sex).size():
		return Protocol.E_BAD_LOOK
	for c: Variant in colors:
		if not (c is int or c is float) or int(c) < -1 or int(c) > MAX_COLOR:
			return Protocol.E_BAD_LOOK
	return ""


## The look string (assumes check() passed; unknown choices fall back to defaults).
static func build(breed: int, sex: int, body := 0, face := 0, colors := []) -> String:
	var row := GameData.row("breeds", breed)
	var base := str(row.get("femaleLook" if sex == 1 else "maleLook", ""))
	var parts := base.trim_prefix("{").trim_suffix("}").split("|") if base != "" else PackedStringArray(["1", str(breed * 10 + sex), "", "100"])
	while parts.size() < 4:
		parts.append("")
	var skins := PackedStringArray()
	var b := _pick(bodies(breed, sex), body)
	skins.append(str(b["skins"]) if not b.is_empty() else parts[1].get_slice(",", 0))
	var h := _pick(faces(breed, sex), face)
	if not h.is_empty():
		skins.append(str(h["skins"]))
	parts[1] = ",".join(skins)
	var defaults := default_colors(breed, sex)
	var cs := PackedStringArray()
	for i in defaults.size():
		var c := int(colors[i]) if i < colors.size() and int(colors[i]) >= 0 else int(defaults[i])
		cs.append("%d=%d" % [i + 1, c])
	parts[2] = ",".join(cs)
	return "{" + "|".join(parts) + "}"


## The look with the skins of worn items added after the body and face skins
## (roadmap P1.06b). A hat, a cape, a shield put their skin in the look's skin
## list, like the look the Dofus server sends; the renderer hides the body parts
## they cover (skinslotsrules, DofusGameData.hidden_slots). The item -> skin link is
## server data: items.json "skin" (tools/extractor/gamedata.py, from the JondoEmu
## dumps: measured on captures, or matched by image). Other parts (colors, scale,
## sub-entities) are kept.
static func with_equipment(look: String, skins: Array) -> String:
	if skins.is_empty() or not (look.begins_with("{") and look.ends_with("}")):
		return look
	var parts := look.trim_prefix("{").trim_suffix("}").split("|")
	if parts.size() < 2:
		return look
	var have := parts[1].split(",", false)
	for s: Variant in skins:
		if not have.has(str(int(s))):
			have.append(str(int(s)))
	parts[1] = ",".join(have)
	return "{" + "|".join(parts) + "}"


## Skins of worn items ({Equipment slot: item instance}), in slot order.
static func worn_skins(worn: Dictionary) -> Array:
	var out: Array = []
	var slots := worn.keys()
	slots.sort()
	for slot: int in slots:
		var skin := int(GameData.item(int(worn[slot]["id"])).get("skin", 0))
		if skin > 0:
			out.append(skin)
	return out


## {bone, skins: [int], colors: {index: int}, scale} of a look string ({} if malformed).
static func parse(look: String) -> Dictionary:
	if not (look.begins_with("{") and look.ends_with("}")):
		return {}
	var parts := look.trim_prefix("{").trim_suffix("}").split("|")
	if parts.size() < 4 or not parts[0].is_valid_int():
		return {}
	var skins: Array = []
	for s in parts[1].split(",", false):
		if not s.is_valid_int():
			return {}
		skins.append(int(s))
	var colors := {}
	for c in parts[2].split(",", false):
		var kv := c.split("=")
		if kv.size() != 2 or not kv[0].is_valid_int() or not kv[1].is_valid_int():
			return {}
		colors[int(kv[0])] = int(kv[1])
	return {"bone": int(parts[0]), "skins": skins, "colors": colors, "scale": int(parts[3]) if parts[3].is_valid_int() else 0}


static func _choices(table: String, breed: int, sex: int) -> Array:
	var out: Array = GameData.table(table).values().filter(func(r: Dictionary) -> bool:
		return int(r.get("breed", 0)) == breed and int(r.get("gender", 0)) == sex \
				and int(r.get("availableAtCreation", 0)) == 1 and int(r.get("payable", 0)) == 0)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["order"]) < int(b["order"]))
	return out


static func _pick(rows: Array, id: int) -> Dictionary:
	for r: Dictionary in rows:
		if int(r["id"]) == id:
			return r
	return rows[0] if not rows.is_empty() else {}
