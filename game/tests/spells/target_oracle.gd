## Who an effect should touch, worked out from the spell data and the arena alone (independently of
## FightEffects.targets / TargetMask): the fighters standing in its area (FightRules.zone_in, the
## geometry test_zones checks) on the side its `target` / mask letters name, meeting its state
## conditions. `exact` is false when the effect has a condition the oracle does not judge
## (breed, life, carried, moved in the cast...): then the fighters it gives are only the ones the
## effect *may* touch.
##   mask sides: lowercase = the caster's team, uppercase = the other one; a / g / A anyone,
##   h / l characters, m monsters, j / i / s summons (all / playing / static); the caster itself
##   only with a / c / C, and C even outside the area.
class_name TargetOracle
extends RefCounted

const SIDES := "aAgGhHlLmMjJiIsS"
## first letters of the condition tokens (the client's gtz.blqc); a token starting otherwise is ignored
const CONDITION_FIRST := "bBeEfFzZKoOPpTWUvVrRQq"

var fighters: Array = []
var exact := true


static func expected(arena: SpellArena, spell: Dictionary, e: Dictionary, center: int) -> TargetOracle:
	var o := TargetOracle.new()
	var me := arena.me
	var tokens := Array(str(e.get("mask", "")).split(",", false))
	if str(e.get("target", "")) == "caster":
		if o._conditions_ok(e, tokens, me, me):
			o.fighters = [me]
		return o
	var area: Dictionary = e.get("area", spell.get("area", {}))
	var cells := FightRules.zone_in(arena.fight.map, arena.fight.occupied(), area, center, me.cell)
	for f: Fighter in arena.fighters():
		if not f.alive or f.carried_by != -1 or not cells.has(f.cell):
			continue
		if (_side_ok(me, f, tokens) if not tokens.is_empty() else _team_ok(e, me, f)) and o._conditions_ok(e, tokens, me, f):
			o.fighters.append(f)
	if tokens.has("C") and not o.fighters.has(me) and o._conditions_ok(e, tokens, me, me):
		o.fighters.append(me)
	return o


static func _team_ok(e: Dictionary, me: Fighter, f: Fighter) -> bool:
	match str(e.get("target", "all")):
		"enemies":
			return f.team != me.team
		"allies":
			return f.team == me.team
	return true


static func _side_ok(me: Fighter, f: Fighter, tokens: Array) -> bool:
	if f == me:
		return tokens.has("a") or tokens.has("c") or tokens.has("C")
	for tok: String in tokens:
		if tok.length() != 1 or not SIDES.contains(tok):
			continue
		var kind_ok := true
		match tok.to_lower():
			"h", "l":
				kind_ok = f.monster == 0 and f.summoner == -1
			"m":
				kind_ok = f.monster != 0 and f.summoner == -1 and f.plays
			"j":
				kind_ok = f.summoner != -1
			"i":
				kind_ok = f.summoner != -1 and f.plays
			"s":
				kind_ok = f.summoner != -1 and not f.plays
		if kind_ok and (f.team == me.team) == (tok == tok.to_lower()):
			return true
	return false


## The effect's conditions hold for `f`: its `cond` (states, monsters, player, portal), its mask's
## states E / e, family P / p,
## monsters F / f (several F: any of them). Any other condition makes the result inexact (and is
## taken as holding).
func _conditions_ok(e: Dictionary, tokens: Array, me: Fighter, f: Fighter) -> bool:
	for c: Dictionary in e.get("cond", []):
		var who := me if str(c.get("who", "")) == "caster" else f
		if c.has("portal"):
			if bool(c["portal"]): # the arena's spells are never projected
				return false
		elif c.has("player"):
			if who.is_character() != bool(c["player"]):
				return false
		elif c.has("monsters"):
			if (c["monsters"] as Array).any(func(m: Variant) -> bool: return int(m) == who.monster) != bool(c["has"]):
				return false
		elif who.has_state(int(c["state"])) != bool(c["has"]):
			return false
	var any_monster := {} # "F" / "*F" -> one of them held
	for tok: String in tokens:
		var body := tok.trim_prefix("*")
		if body == "" or (tok.length() == 1 and SIDES.contains(tok)) or tok in ["c", "C"] or not CONDITION_FIRST.contains(body[0]):
			continue # a side letter, or a token the client ignores (u, Sce, AP<n>...)
		var who := me if tok.begins_with("*") else f
		var letter := body[0]
		var n := int(body.substr(1)) if body.substr(1).is_valid_int() else -1
		match letter if body.length() == 1 or n >= 0 else "":
			"E", "e":
				if who.has_state(n) != (letter == "E"):
					return false
			"P", "p":
				if (who == me or who.summoner == me.id) != (letter == "P"):
					return false
			"F":
				var key := tok.substr(0, tok.length() - body.length() + 1)
				any_monster[key] = bool(any_monster.get(key, false)) or who.monster == n
			"f":
				if who.monster == n:
					return false
			"z":
				pass
			_:
				exact = false
	return not any_monster.values().has(false)
