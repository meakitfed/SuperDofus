## A player's persistent character: level, XP, kamas, inventory, characteristics,
## current HP (regenerating out of fight) and where it stands. Saved through a
## Persistence (files in standalone, a database on a server).
class_name Character
extends RefCounted

const STATS := StatFormulas.BOOSTABLE
const CAPITAL_PER_LEVEL := 5
const REGEN_MS := 1000 # out of fight: 1 HP per second. APPROX(P5.05): real regen rate (sitting x2…) not sourced

var name := ""
## owner account (Persistence "accounts" key); one account has several characters
var account := ""
var look := ""
## breeds.id (12 = Pandawa) and sex (0 male, 1 female)
var breed := 12
var sex := 0
## creation choices the look was built from (bodies.id, heads.id, colors; 0 / [] = defaults)
var body := 0
var head := 0
var colors: Array = []
## spell book (P1.03): the chosen spell of each spellvariants pair (spells.id; a
## pair without one uses its first spell) and the stored spell bar (SpellBook.bar_layout)
var variants: Array = []
var bar: Array = []
var level := 1
var xp := 0
var kamas := 0
var capital := 0
var stats := {"vitality": 0, "wisdom": 0, "strength": 0, "intelligence": 0, "chance": 0, "agility": 0}
var inventory := Inventory.new()
## characteristics added by scrolls (items effects 606-611), on top of `stats`
var additional := {"vitality": 0, "wisdom": 0, "strength": 0, "intelligence": 0, "chance": 0, "agility": 0}
## save point (Potion de Rappel, lost fight): map id and cell, -1 = the world's
## start; set at a zaap (set_save_point)
var save_map := -1
var save_cell := -1
## zaaps registered (map ids), in visit order
var known_zaaps: Array = []
## quests under way and finished (P2.03), and what they gave besides items: emotes, titles and spells (ids)
var quests := QuestLog.new()
## XP of each job (P2.05)
var jobs := JobLog.new()
var emotes: Array = []
var titles: Array = []
var quest_spells: Array = []
## runtime only (not saved): map id -> {map, coords, name_id, area_name_id, world_map},
## filled by WorldSim from the world data so the client can show them (world map)
var zaap_info := {}
## energy (Energy): lost on defeats, 0 = ghost (life Energy.GHOST) until a phoenix
var energy := Energy.MAX
var life := Energy.ALIVE
## the map it was last saved on doubles the energy regained while logged out (MapData.tavern)
var rest_x2 := false
## runtime only: the world's phoenixes [{map, coords, world_map}] (world map markers)
var phoenixes: Array = []
## HP at sim time hp_t0; out of fight they regenerate (see hp_at)
var hp := -1
var hp_t0 := 0
## last position (map id, cell), -1 = the world's start
var map_id := -1
var cell := -1


func max_hp() -> int:
	return StatFormulas.max_hp(level, stat("vitality"))


func max_ap() -> int:
	return StatFormulas.max_ap(level) + int(bonus().get("ap", 0))


func max_mp() -> int:
	return StatFormulas.max_mp(level) + int(bonus().get("mp", 0))


## Characteristics the worn items and their sets give (Equipment.bonus).
func bonus() -> Dictionary:
	return Equipment.bonus(inventory.worn().values())


## A characteristic for StatFormulas: base + additional (scrolls) + worn items.
func stat(name: String) -> int:
	return int(stats.get(name, 0)) + int(additional.get(name, 0)) + int(bonus().get(name, 0))


func hp_at(now: int) -> int:
	if hp < 0:
		return max_hp()
	return mini(max_hp(), hp + maxi(0, now - hp_t0) / REGEN_MS)


func set_hp(value: int, now: int) -> void:
	hp = clampi(value, 0, max_hp())
	hp_t0 = now


## Adds XP, levels up (capital, full heal). Returns the number of levels gained.
func gain_xp(amount: int, now: int) -> int:
	var before := level
	xp += amount
	level = maxi(level, GameData.level_for_xp(xp))
	if level > before:
		capital += CAPITAL_PER_LEVEL * (level - before)
		set_hp(max_hp(), now)
	return level - before


## Loses `amount` energy (a defeat): at 0 the character becomes a ghost.
## Returns the energy actually lost.
func lose_energy(amount: int) -> int:
	var lost := mini(energy, maxi(0, amount))
	energy -= lost
	if energy <= 0:
		life = Energy.GHOST
	return lost


## Regains up to `amount` energy (max Energy.MAX); returns what was gained.
func gain_energy(amount: int) -> int:
	var gained := clampi(amount, 0, Energy.MAX - energy)
	energy += gained
	return gained


func is_ghost() -> bool:
	return life == Energy.GHOST


## The look shown in the world: the base look + the skins of worn items (LookBuilder).
func display_look() -> String:
	return LookBuilder.with_equipment(look, LookBuilder.worn_skins(inventory.worn()))


## Pods carried and the most the character can carry (StatFormulas.pods).
func weight() -> int:
	return inventory.weight()


func max_weight() -> int:
	return StatFormulas.pods(stat)


## Overloaded: more pods than it can carry, it cannot move (Dofus).
func overloaded() -> bool:
	return weight() > max_weight()


## What Criteria reads (items.criterions): level, total and additional characteristics.
func criteria_values() -> Dictionary:
	var out := {"level": level, "breed": breed, "sex": sex, "ap": max_ap(), "mp": max_mp(),
			"items": inventory.items.values().map(func(it: Dictionary) -> int: return int(it["id"])),
			"quests_finished": quests.finished.duplicate(), "quests_active": quests.active.keys(),
			"jobs": jobs.levels()}
	for k: String in stats:
		out[k] = stat(k)
		out[k + "_additional"] = int(additional.get(k, 0))
	return out


## Spends up to `points` capital on `stat` (0 = the cost of one point), bought
## point by point at the breed's tier costs (breeds.statsPointsFor*); what cannot
## buy a whole point is kept.
func boost(stat_name: String, points := 0) -> String:
	if not stats.has(stat_name):
		return Protocol.E_UNKNOWN_STAT
	var base := int(stats[stat_name])
	var budget := points if points > 0 else StatFormulas.point_cost(breed, stat_name, base)
	var r := StatFormulas.boost(breed, stat_name, base, mini(budget, capital))
	if int(r[0]) == 0:
		return Protocol.E_NOT_ENOUGH_CAPITAL
	capital -= int(r[1])
	stats[stat_name] = base + int(r[0])
	return ""


## Characteristics back to 0, their capital given back (the tier costs paid).
## APPROX(P1.04): free and out of fight; in Dofus it takes a restat item or NPC
## (not in the client rules).
func reset_stats(now: int) -> void:
	var hp_now := hp_at(now)
	for k: String in stats:
		capital += StatFormulas.capital_for(breed, k, int(stats[k]))
		stats[k] = 0
	set_hp(hp_now, now)


## Initiative, prospecting, pods, tackle… out of fight (StatFormulas.derived).
func derived_stats(now: int) -> Dictionary:
	return StatFormulas.derived(stat, hp_at(now), max_hp())


## Grimoire: use `spell` instead of the other spell of its pair.
func choose_variant(spell: int) -> String:
	var err := SpellBook.variant_error(breed, level, spell)
	if err != "":
		return err
	for other: int in SpellBook.pair_of(breed, spell):
		variants.erase(other)
	variants.append(spell)
	bar = spell_bar() # the new variant takes the old one's slot
	return ""


## Spell bar: put a used spell in `slot`.
func move_spell(spell: int, slot: int) -> String:
	if slot < 0 or slot >= SpellBook.BAR_SLOTS:
		return Protocol.E_BAD_SLOT
	if not SpellBook.chosen_spells(breed, level, variants).has(spell):
		return Protocol.E_UNKNOWN_SPELL
	bar = SpellBook.move_in_bar(spell_bar(), spell, slot)
	return ""


## The spell bar (spells.id or 0 per slot).
func spell_bar() -> Array:
	return SpellBook.bar_layout(breed, level, variants, bar)


## Castable ids the character knows (its fighter's spells).
func known_spells() -> Array:
	return SpellBook.known_ids(breed, level, variants)


## Fight characteristics (Fighter.stats keys): the six with their bonuses, and
## every other characteristic items give (power, damage, resistances…).
func fight_stats() -> Dictionary:
	var out := bonus()
	out.erase("ap")
	out.erase("mp")
	for k: String in stats:
		out[k] = stat(k)
	return out


## equip: wears the instance `uid` in `slot` (Equipment.equip_error); the item
## already there goes back to the bag; one item of a stack is split off.
## `new_uid` makes the uid of a split item. Returns {err, changed: [instances],
## removed: [uids]} for the item events.
func equip(uid: int, slot: int, new_uid: Callable) -> Dictionary:
	var out := {"err": "", "changed": [], "removed": []}
	var it := inventory.get_item(uid)
	if it.is_empty():
		out["err"] = Protocol.E_UNKNOWN_ITEM
		return out
	if int(it.get("pos", Inventory.BAG)) == slot:
		return out
	var worn := {}
	for s: int in inventory.worn():
		worn[s] = int(inventory.worn()[s]["id"])
	worn.erase(int(it.get("pos", Inventory.BAG)))
	var err := Equipment.equip_error(int(it["id"]), slot, level, criteria_values(), worn)
	if err != "":
		out["err"] = err
		return out
	var hp_now := hp
	var there: Dictionary = inventory.worn().get(slot, {})
	if not there.is_empty():
		var back := unequip(slot)
		out["changed"].append_array(back["changed"])
		out["removed"].append_array(back["removed"])
	if int(it.get("pos", Inventory.BAG)) == Inventory.BAG and int(it["qty"]) > 1:
		var left := inventory.remove(uid, 1)
		out["changed"].append(left)
		var one_uid := int(new_uid.call())
		var reserve := int(it.get("reserve", 0))
		it = {"uid": one_uid, "id": int(it["id"]), "qty": 1, "effects": (it["effects"] as Array).duplicate(true), "pos": slot}
		if reserve != 0: # P2.07: the forgemagie puits follows the item
			it["reserve"] = reserve
		inventory.items[one_uid] = it
	else:
		it["pos"] = slot
	out["changed"].append(it)
	hp = mini(hp_now, max_hp()) if hp_now >= 0 else hp_now
	return out


## unequip: back to the bag, joining an identical stack there.
func unequip(slot: int) -> Dictionary:
	var out := {"err": "", "changed": [], "removed": []}
	var it: Dictionary = inventory.worn().get(slot, {})
	if it.is_empty():
		out["err"] = Protocol.E_BAD_SLOT
		return out
	var into := inventory.find_stack(int(it["id"]), it["effects"], int(it.get("reserve", 0)))
	if into != 0:
		inventory.items.erase(int(it["uid"]))
		inventory.items[into]["qty"] = int(inventory.items[into]["qty"]) + int(it["qty"])
		out["removed"].append(int(it["uid"]))
		out["changed"].append(inventory.items[into])
	else:
		it["pos"] = Inventory.BAG
		out["changed"].append(it)
	if hp > max_hp():
		hp = max_hp()
	return out


## Everything the owner's client may know (protocol "character dict").
func public_dict(now: int) -> Dictionary:
	return {"name": name, "look": display_look(), "breed": breed, "level": level, "xp": xp, "xp_floor": GameData.xp_floor(level),
			"xp_next": GameData.xp_next(level), "kamas": kamas, "capital": capital,
			"stats": stats.duplicate(), "hp": hp_at(now), "max_hp": max_hp(), "hp_t0": now,
			"regen_ms": REGEN_MS, "ap": max_ap(), "mp": max_mp(),
			"additional": additional.duplicate(), "bonus": bonus(), "derived": derived_stats(now),
			"weight": weight(), "max_weight": max_weight(),
			"energy": energy, "max_energy": Energy.MAX, "life": life, "phoenixes": phoenixes.duplicate(true), "zaaps": known_zaaps.map(func(id: int) -> Dictionary: return zaap_info.get(id, {"map": id})), "save_map": save_map,
			"spells": known_spells(), "jobs": jobs.to_views(),
			"bar": spell_bar().map(func(s: int) -> int: return SpellBook.grade_for(s, level) if s != 0 else 0)}


## Save format (JSON-safe). hp is stored as regenerated at `now`.
func to_dict(now: int) -> Dictionary:
	return {"name": name, "account": account, "breed": breed, "sex": sex, "body": body, "head": head, "colors": colors.duplicate(), "variants": variants.duplicate(), "bar": bar.duplicate(), "look": look, "level": level, "xp": xp, "kamas": kamas, "capital": capital,
			"stats": stats.duplicate(), "additional": additional.duplicate(), "items": inventory.to_array(),
			"hp": hp_at(now), "map": map_id, "cell": cell, "save_map": save_map, "save_cell": save_cell, "zaaps": known_zaaps.duplicate(),
			"energy": energy, "life": life, "rest_x2": rest_x2, "worn_look": display_look(),
			"quests": quests.to_dict(), "jobs": jobs.to_dict(), "emotes": emotes.duplicate(), "titles": titles.duplicate(), "quest_spells": quest_spells.duplicate()}


static func from_dict(d: Dictionary, now: int) -> Character:
	var c := Character.new()
	c.name = str(d.get("name", ""))
	c.look = str(d.get("look", ""))
	c.account = str(d.get("account", ""))
	c.breed = int(d.get("breed", 12))
	c.sex = int(d.get("sex", 0))
	c.body = int(d.get("body", 0))
	c.head = int(d.get("head", 0))
	c.colors = (d.get("colors", []) as Array).map(func(v: Variant) -> int: return int(v))
	c.variants = (d.get("variants", []) as Array).map(func(v: Variant) -> int: return int(v))
	c.bar = (d.get("bar", []) as Array).map(func(v: Variant) -> int: return int(v))
	c.level = int(d.get("level", 1))
	c.xp = int(d.get("xp", 0))
	c.kamas = int(d.get("kamas", 0))
	c.capital = int(d.get("capital", 0))
	var st: Dictionary = d.get("stats", {})
	for k: String in c.stats:
		c.stats[k] = int(st.get(k, 0))
	var add: Dictionary = d.get("additional", {})
	for k: String in c.additional:
		c.additional[k] = int(add.get(k, 0))
	c.inventory = Inventory.from_array(d.get("items", []))
	var legacy: Dictionary = d.get("inventory", {}) # before P1.05: {item id: qty}, no uid
	for k: String in legacy:
		c.inventory.items[-int(k)] = {"uid": -int(k), "id": int(k), "qty": int(legacy[k]), "effects": []}
	c.save_map = int(d.get("save_map", -1))
	c.save_cell = int(d.get("save_cell", -1))
	c.known_zaaps = (d.get("zaaps", []) as Array).map(func(v: Variant) -> int: return int(v))
	c.map_id = int(d.get("map", -1))
	c.cell = int(d.get("cell", -1))
	c.energy = clampi(int(d.get("energy", Energy.MAX)), 0, Energy.MAX)
	c.life = int(d.get("life", Energy.ALIVE))
	c.rest_x2 = bool(d.get("rest_x2", false))
	c.quests = QuestLog.from_dict(d.get("quests", {}))
	c.jobs = JobLog.from_dict(d.get("jobs", {}))
	for key: String in ["emotes", "titles", "quest_spells"]:
		c.set(key, (d.get(key, []) as Array).map(func(v: Variant) -> int: return int(v)))
	c.set_hp(int(d.get("hp", c.max_hp())), now)
	return c
