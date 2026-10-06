## Game-data tables the renderer needs: bodies (skin -> breed/gender), breed default
## colours, and skin slot rules (which equipment hides which body part).
class_name DofusGameData
extends RefCounted

enum SlotRuleType { DEFAULT = 0, BREED = 1, BREED_AND_SEX = 2, FACE = 3 }

const SLOT_PREFIXES := {
	0: "Bandeau_", 1: "BandeauB_", 2: "Barbe_", 3: "Chapeau_", 4: "ChapeauB_",
	5: "cheveux_", 20: "Frange_", 6: "Custo_", 7: "Oreille_d_", 8: "Oreille_g_",
	9: "Oreille_", 10: "Oreille_b_", 11: "Masque_", 12: "MasqueB_", 13: "NatteHaute_",
	16: "Natte_", 17: "NatteB_", 19: "Natte_Basse_", 14: "Patte_d_", 15: "Patte_g_",
	18: "Patte_0", 21: "Tete_OL_",
}

## body skin id -> body dictionary (id, skins, breed, gender…)
var bodies_by_skin: Dictionary = {}
## breed id -> breed dictionary (maleColors, femaleColors, maleLook…)
var breeds: Dictionary = {}
## skin id -> { rule type -> { rule info -> Array[{id, mask}] } }
var slot_rules: Dictionary = {}


static func load_from(provider: DofusContentProvider) -> DofusGameData:
	var gd := DofusGameData.new()
	var bodies: Variant = provider.read_json("Content/Data/bodiesdataroot.json")
	if bodies is Dictionary:
		for v: Dictionary in (bodies["objectsById"] as Dictionary).values():
			gd.bodies_by_skin[str(v.get("skins", "")).to_int()] = v
	var breeds: Variant = provider.read_json("Content/Data/breedsdataroot.json")
	if breeds is Dictionary:
		for v: Dictionary in (breeds["objectsById"] as Dictionary).values():
			gd.breeds[int(v["id"])] = v
	var slots: Variant = provider.read_json("Content/Data/skinslotsrulesdataroot.json")
	if slots is Dictionary:
		var by_id: Dictionary = slots["objectsById"]
		for skin_id: String in by_id:
			var per_type := {}
			for rule: Dictionary in by_id[skin_id].get("slotRulesList", []):
				var t := int(rule["slotRuleType"])
				if not per_type.has(t):
					per_type[t] = {}
				per_type[t][int(rule["slotRuleInfo"])] = rule["slotsRules"]
			gd.slot_rules[skin_id.to_int()] = per_type
	return gd


func body_for_skin(skin_id: int) -> Dictionary:
	return bodies_by_skin.get(skin_id, {})


## 2 * breed + gender, or -1 when the first skin is not a playable body.
func breed_and_sex(skins: PackedInt32Array) -> int:
	if skins.is_empty():
		return -1
	var body := body_for_skin(skins[0])
	return -1 if body.is_empty() else 2 * int(body["breed"]) + int(body["gender"])


func breed_of(skins: PackedInt32Array) -> int:
	if skins.is_empty():
		return -1
	var body := body_for_skin(skins[0])
	return -1 if body.is_empty() else int(body["breed"])


func default_colors_for_body_skin(skin_id: int) -> PackedInt32Array:
	var body := body_for_skin(skin_id)
	if body.is_empty():
		return PackedInt32Array()
	var breed: Dictionary = breeds.get(int(body["breed"]), {})
	var key := "femaleColors" if int(body["gender"]) == 1 else "maleColors"
	return PackedInt32Array(breed.get(key, []))


## Symbol names hidden by equipment slot rules for this look (e.g. a hat hides the hair).
func hidden_slots(skins: PackedInt32Array) -> Dictionary:
	var hidden := {}
	if skins.size() <= 2:
		return hidden
	var body := body_for_skin(skins[0])
	if body.is_empty():
		return hidden
	var breed := int(body["breed"])
	var sex := int(body["gender"])
	var rules := [
		[SlotRuleType.FACE, skins[1]],
		[SlotRuleType.BREED_AND_SEX, 2 * breed + sex],
		[SlotRuleType.BREED, breed],
		[SlotRuleType.DEFAULT, 0],
	]
	for i in range(2, skins.size()):
		var skin_rules: Dictionary = slot_rules.get(skins[i], {})
		if skin_rules.is_empty():
			continue
		for rule: Array in rules:
			var slots: Variant = skin_rules.get(rule[0], {}).get(rule[1])
			if slots != null:
				_add_slots(slots, hidden)
				break
	return hidden


static func _add_slots(slots: Array, out: Dictionary) -> void:
	for slot: Dictionary in slots:
		var mask := int(slot["mask"])
		var prefix: String = SLOT_PREFIXES.get(int(slot["id"]), "")
		if prefix == "":
			continue
		var skip_test := (mask & 1) == 0
		for i in 5:
			if skip_test or (mask & (1 << ((i + 1) & 0x1f))) == 0:
				out["%s%d" % [prefix, i + 2 if i > 2 else i]] = true
