## Target masks (spelllevels effects `targetMask`, roadmap P1.13h): who an effect touches, as
## the client's native code decides it (tools/client_code, class gtz, its letters in class gty):
##   gtz.blqi: an empty mask touches everyone; otherwise the side (blqf) must match and no
##   condition (blqh -> blqe per token) may fail.
##   sides (blqf, any matching letter): the caster only with C / c / a (C even outside the area,
##   blqh skips the area check); lowercase = allies, uppercase = enemies (the caster's team);
##   a / g allies, A enemies, h / H characters (not summoned), l / L characters or companions,
##   m / M monsters (not summoned, not static), j / J summons, i / I summons that are not static,
##   s / S static summons, d / D companions, x an empty cell. Static = gyn.bmqg: a creature
##   whose monsters.canPlay is false (MonsterData at 0x18).
##   conditions (a token whose first letter is * b B e E f F z Z K o O P p T W U v V r R Q q,
##   gtz.blqc; *X = on the caster, X = on the target; regex "^\*?([a-zA-Z]+)(\d*)$"):
##   E<n> / e<n> has / has not state n; F<n> / f<n> is / is not monster n; B<n> / b<n> is / is
##   not a character of breed n; Z<n> / z<n> is / is not companion n; V<n> / v<n> life above /
##   at most n % of its max; R / r the spell is / is not projected (FightState cell 0..559);
##   P / p the caster itself or its summoning family / not; K carried by the caster (states 8 / 3
##   and the carrier's carried id) or thrown by it in this cast (a movement event gzw whose
##   throwerEntityId, 0x40, is the caster); W moved in this cast (gvs.bmdi: a movement event gzw
##   whose newPosition passes the map's pointMov, ezl slot 18 = enq.babz -> enq.babg(x, y, true,
##   -1, -1)); T swapped by a Xelor's teleport in this cast (a Telefrag, P1.13n; the preview's
##   gvs.bmdh is the same code as W, see _holds); U summoned in this cast (gvs.bmdp: a summon event
##   haa, cached per fighter); O / o the
##   fighter whose hit fired the trigger; Q / q its summons fill / do not fill its limit
##   (characteristic 26); PB / pb has / has no shield (characteristic 96). Several B / F / Z of
##   the same letter are alternatives (gtz.blqd), all the others must hold. A condition token
##   of another letter (PR...) reads the projected flag; tokens of no known letter (u, Sce,
##   Atq, Def) are ignored, and so are AP<n> / ap<n> / MP<n> / mp<n>: blqe reads them (at most /
##   at least n AP, characteristic 1, or MP, 23) but their first letter never passes blqc.
class_name TargetMask
extends RefCounted

const CONDITION_FIRST := "*bBeEfFzZKoOPpTWUvVrRQq"
const ALTERNATIVES := "BFZ"

static var _cache := {}
static var _re: RegEx


## The mask's tokens ("a,A,*E12" -> ["a", "A", "*E12"]).
static func parse(mask: String) -> Array:
	if not _cache.has(mask):
		var out: Array = []
		for tok: String in mask.split(","):
			if tok.strip_edges() != "":
				out.append(tok.strip_edges())
		_cache[mask] = out
	return _cache[mask]


## Effect `e` (with a `mask`) touches `t`. `caster_states` / `target_states`: the states to test
## (default: the current ones), like FightEffects.cond_ok.
static func affects(fight: Fight, caster: Fighter, t: Fighter, e: Dictionary, caster_states = null, target_states = null) -> bool:
	var tokens := parse(str(e.get("mask", "")))
	if tokens.is_empty():
		return true
	return side_ok(caster, t, tokens) and conditions_ok(fight, caster, t, tokens, caster_states, target_states)


## gtz.blqf: the side letters.
static func side_ok(caster: Fighter, t: Fighter, tokens: Array) -> bool:
	if t == caster:
		return tokens.has("C") or tokens.has("c") or tokens.has("a")
	var ally := t.team == caster.team
	var character := t.monster == 0 # client kind 0 (a character or its double), not a creature
	var summon := t.summoner != -1
	var still := _static(t)
	for tok: String in tokens:
		var side := false
		match tok:
			"a", "g":
				side = true
			"A":
				side = true
			"h", "H", "l", "L":
				side = character and not summon
			"m", "M":
				side = not character and not summon and not still
			"j", "J":
				side = summon
			"i", "I":
				side = summon and not still
			"s", "S":
				side = summon and still
			_:
				continue
		if side and (ally if tok == tok.to_lower() else not ally):
			return true
	return false


## gtz.blqh / blqe: every condition token holds (B / F / Z: one of the same letter).
static func conditions_ok(fight: Fight, caster: Fighter, t: Fighter, tokens: Array, caster_states = null, target_states = null) -> bool:
	if _re == null:
		_re = RegEx.create_from_string("^\\*?([a-zA-Z]+)(\\d*)$")
	var skip := {}
	for i in tokens.size():
		var tok: String = tokens[i]
		if skip.has(i) or not CONDITION_FIRST.contains(tok[0]):
			continue
		var m := _re.search(tok)
		if m == null:
			continue
		var on_caster := tok.begins_with("*")
		var who := caster if on_caster else t
		var states = caster_states if on_caster else target_states
		var letter := m.get_string(1)
		var n := int(m.get_string(2)) if m.get_string(2) != "" else -1
		var ok := _holds(fight, caster, who, letter, n, states)
		var pos := 1 if on_caster else 0
		if ALTERNATIVES.contains(letter[0]):
			var later := false
			for j in range(i + 1, tokens.size()):
				var other: String = tokens[j]
				if other.length() > pos and other[pos] == tok[pos]:
					later = true
					if ok:
						skip[j] = true
			if ok or later:
				continue
		if not ok:
			return false
	return true


static func _holds(fight: Fight, caster: Fighter, who: Fighter, letter: String, n: int, states) -> bool:
	match letter:
		"E", "e":
			var has: bool = (states as Array).has(n) if states != null else who.has_state(n)
			return has == (letter == "E")
		"F", "f":
			return (who.monster != 0 and who.monster == n) == (letter == "F")
		"B", "b":
			return (who.monster == 0 and who.breed == n) == (letter == "B")
		"Z":
			return false # no companions
		"z":
			return true
		"V", "v":
			return (float(n) < who.hp * 100.0 / maxi(1, who.max_hp)) == (letter == "V")
		"r":
			return caster.projecting < 0
		"P", "p":
			return _family(caster, who) == (letter == "P")
		"K": # gtz.blqe K
			return who.carried_by == caster.id or int(_logged(fight, who).get("thrower", -1)) == caster.id
		"O", "o":
			return fight.trigger_from >= 0 and who.id == fight.trigger_from
		"Q", "q":
			return (Summons.max_summons(who) <= Summons.count(fight, who)) == (letter == "Q")
		"PB", "pb":
			return (who.shield() > 0) == (letter == "PB")
		"T":
			# P1.13n: swapped by a Xelor's teleport in this cast (FightDisplace._swap). The client's
			# preview (gvs.bmdh) lets any move through, but T is only on Xelor spells, next to their
			# Telefrag sub-spell, and the game's help (i18n, "Les Téléfrags") says: "générés lorsque
			# deux entités échangent de positions suite aux effets de téléportation d'un sort Xélor"
			return bool(_logged(fight, who).get("telefrag", false))
		"W": # gvs.bmdi: moved in this cast (no spell uses it)
			return bool(_logged(fight, who).get("moved", false))
		"U":
			return bool(_logged(fight, who).get("summoned", false))
	return caster.projecting >= 0 # R, and any other condition letter (gtz.blqe: the flag as is)


## gtz.blqe P: `who` is the caster, its summoner, one of its summons, or a summon of the same summoner.
static func _family(caster: Fighter, who: Fighter) -> bool:
	if who.id == caster.id:
		return true
	if who.summoner == -1:
		return caster.summoner != -1 and caster.summoner == who.id
	if who.summoner == caster.id:
		return true
	if caster.summoner == -1:
		return false
	return caster.summoner == who.summoner or caster.summoner == who.id


## What `who` underwent in the cast being resolved (Fight.cast_log).
static func _logged(fight: Fight, who: Fighter) -> Dictionary:
	return fight.cast_log.get(who.id, {})


## gyn.bmqg ("static" creature): a monster whose monsters.canPlay is false (Fighter.plays: Summons
## reads it; characters and other monsters play).
static func _static(t: Fighter) -> bool:
	return not t.plays
