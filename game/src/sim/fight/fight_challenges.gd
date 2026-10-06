## Fight challenges (P1.15): optional objectives drawn when a fight starts; each one that is
## still valid when the players win raises their XP and drops.
## Data: the `challenges` table (Dofus 3 challengesdataroot: name, description, incompatibilities,
## activationCriterion). The `completionCriterion` strings are an unpublished mini-language
## (TM=1,0 / Tm<1,0 / CK~1...) that the client evaluates on its fight events; here the rule of each
## challenge is written by hand from its in-game description (i18n descriptionId), see RULES.
## Only the generic challenges (targetMonsterId = 0) listed in RULES are simulated; the others (a
## given monster, a given class...) are never drawn.
##   luaformulas 100 `challengeCoefficient`: the XP multiplier, applied by FightRewards.
##   APPROX(P1.15): its value is server data (not in the client): BONUS per successful challenge
##   below; the drops get the same multiplier.
##   APPROX(P1.15): number of challenges (1 to 2 per fight, "challenges" roadmap line): 2 when the
##   monster side has 3 fighters or more.
##   APPROX(P1.15): activationCriterion: only GN>n,team / GN<n,team (fighters of a team) and
##   GL>n,team (highest level of a team) are read; the other terms (Gl level ratio, Gd, GB, GC...)
##   are ignored.
## The state lives on the Fight (`challenges`, `chal`) so a Fight stays a plain value; this class
## only holds rules. Hooks, called by Fight: observe() after any action, on_walk(), on_cast(),
## on_turn_end(), finish().
class_name FightChallenges
extends RefCounted

const BONUS := 0.25 # APPROX(P1.15)
const RUNNING := "running"
const SUCCESS := "success"
const FAILED := "failed"

## id -> kind of rule (see _fail_reasons). Descriptions are the challenges' i18n texts.
const RULES := {
	1: "mp_exact", # Zombie: allies use exactly 1 MP per turn (completion TM=1)
	2: "stay", # Statue: allies end their turn on the cell they started it
	3: "first", # Premier: the designated target is finished first (CK~1)
	4: "last", # Dernier: the designated target is finished last (Ck~1)
	5: "once_fight", # Econome: an ally never uses the same spell twice in the fight (SAg0)
	6: "once_turn", # Versatile: never the same spell twice in one turn (SAt0)
	8: "mp_all", # Nomade: allies use all their MP every turn (TM=m)
	9: "weapon", # Barbare: enemies are finished with a weapon (Ma=1)
	10: "level_up", # Cruel: enemies are finished in ascending level order (SL<1)
	17: "no_damage", # Intouchable: allies lose no HP (SD!hc0,e-1)
	25: "level_down", # Ordonne: descending level order (SL>1)
	33: "no_death", # Survivant: no ally dies (Sa=0)
	36: "next_to_enemy", # Hardi (TD<2,hc0,e1)
	37: "next_to_ally", # Collant (TD<2,hc0,hc0)
	39: "away_ally", # Misanthrope (TD>1,hc0,hc0)
	40: "away_enemy", # Prudent (TD>1,hc0,e1)
	44: "everyone_kills", # Partage: every ally finishes at least one enemy (Sk>0,1)
	974: "same_round", # Doume: all enemies die in the same global turn (TK~a,e0,e1,gt)
}


## The challenges of a fight that starts: [{id, name_id, desc_id, icon, state, target, bonus}].
## `rng` is the fight's own challenge generator (it must not move the fight's dice).
static func pick(fight: Fight, rng: RandomNumberGenerator) -> Array:
	var allies := _team(fight, 0)
	var foes := _team(fight, 1)
	if allies.is_empty() or foes.is_empty():
		return []
	var eligible: Array = []
	for key: Variant in RULES:
		var row := GameData.row("challenges", key)
		if key == 44 and allies.size() < 2: # its activation criterion asks 2+ allies (a group of `|`, not read)
			continue
		if not row.is_empty() and int(row.get("targetMonsterId", 0)) == 0 and _active(str(row.get("activationCriterion", "")), allies, foes):
			eligible.append(row)
	var want := 2 if foes.size() >= 3 else 1
	var out: Array = []
	var banned := {}
	while out.size() < want and not eligible.is_empty():
		var row: Dictionary = eligible.pop_at(rng.randi_range(0, eligible.size() - 1))
		if banned.has(int(row["id"])):
			continue
		for other: Variant in row.get("incompatibleChallenges", []):
			banned[int(other)] = true
		var kind := str(RULES[int(row["id"])])
		var target := -1
		if kind == "first" or kind == "last":
			target = (foes[rng.randi_range(0, foes.size() - 1)] as Fighter).id
		out.append({"id": int(row["id"]), "name_id": int(row.get("nameId", 0)), "desc_id": int(row.get("descriptionId", 0)),
				"icon": int(row.get("iconId", 0)), "state": RUNNING, "target": target, "bonus": BONUS})
	return out


## Teams without summons (a summon is neither an ally to protect nor an enemy to finish).
static func _team(fight: Fight, team: int) -> Array:
	return fight.fighters.values().filter(func(f: Fighter) -> bool: return f.team == team and f.summoner == -1)


## activationCriterion: terms joined by `&`; GN / GL as in the header, anything else (and any
## group of alternatives with `|`) ignored.
static func _active(crit: String, allies: Array, foes: Array) -> bool:
	for raw: String in _terms(crit):
		var term := raw.replace("(", "").replace(")", "")
		if raw.contains("|") or not (term.begins_with("GN") or term.begins_with("GL")):
			continue
		var op := term.substr(2, 1)
		var args := term.substr(3).split(",")
		if args.size() < 2:
			continue
		var n := int(args[0])
		var members: Array = allies if int(args[1]) == 0 else foes
		var value := members.size()
		if term.begins_with("GL"):
			value = 0
			for f: Fighter in members:
				value = maxi(value, f.level)
		if (op == ">" and not value > n) or (op == "<" and not value < n) or (op == "=" and value != n):
			return false
	return true


## The top-level `&` terms (parentheses keep their content together).
static func _terms(crit: String) -> Array:
	var out: Array = []
	var depth := 0
	var cur := ""
	for ch in crit:
		if ch == "(":
			depth += 1
		elif ch == ")":
			depth -= 1
		if ch == "&" and depth == 0:
			out.append(cur)
			cur = ""
		else:
			cur += ch
	if cur != "":
		out.append(cur)
	return out


# ── state ───────────────────────────────────────────────────────────────────

static func has_rule(fight: Fight, kind: String) -> bool:
	return not _of(fight, kind).is_empty()


static func _of(fight: Fight, kind: String) -> Array:
	return fight.challenges.filter(func(c: Dictionary) -> bool: return c["state"] == RUNNING and str(RULES.get(int(c["id"]), "")) == kind)


## The fight's challenge coefficient (luaformulas 100): 1 + BONUS per successful challenge.
static func coefficient(fight: Fight) -> float:
	var out := 1.0
	for c: Dictionary in fight.challenges:
		if c["state"] == SUCCESS:
			out += float(c["bonus"])
	return out


static func _fail(fight: Fight, kind: String) -> Array:
	var out: Array = []
	for c: Dictionary in _of(fight, kind):
		c["state"] = FAILED
		fight.emit_event(Protocol.challenge_update(int(c["id"]), FAILED))
		out.append(c)
	return out


static func _is_ally(fight: Fight, f: Fighter) -> bool:
	return f != null and f.team == 0 and f.summoner == -1


## Starts watching (the fight begins): the HP and the life of everyone.
static func begin(fight: Fight) -> void:
	fight.chal = {"hp": {}, "alive": {}, "kills": {}, "order": [], "round": -1, "mp_used": {}, "spells": {}, "turn_spells": {}}
	for f: Fighter in fight.fighters.values():
		fight.chal["hp"][f.id] = f.hp
		fight.chal["alive"][f.id] = f.alive


# ── hooks ────────────────────────────────────────────────────────────────────

## `steps` cells walked by `f`.
static func on_walk(fight: Fight, f: Fighter, steps: int) -> void:
	if fight.chal.is_empty():
		return
	fight.chal["mp_used"][f.id] = int(fight.chal["mp_used"].get(f.id, 0)) + steps


## `f` cast `spell_id` (its turn).
static func on_cast(fight: Fight, f: Fighter, spell_id: int) -> void:
	if fight.chal.is_empty() or not _is_ally(fight, f):
		return
	var used: Dictionary = fight.chal["spells"]
	if used.has(spell_id):
		_fail(fight, "once_fight")
	used[spell_id] = true
	var turn_used: Dictionary = fight.chal["turn_spells"]
	if turn_used.has(spell_id):
		_fail(fight, "once_turn")
	turn_used[spell_id] = true


## A turn begins: per-turn counters restart.
static func on_turn_begin(fight: Fight, f: Fighter) -> void:
	if fight.chal.is_empty():
		return
	fight.chal["mp_used"][f.id] = 0
	fight.chal["turn_spells"] = {}


## `f`'s turn ends (it is alive): position and movement challenges.
static func on_turn_end(fight: Fight, f: Fighter) -> void:
	if fight.chal.is_empty() or not _is_ally(fight, f) or not f.alive:
		return
	if int(fight.chal["mp_used"].get(f.id, 0)) != 1:
		_fail(fight, "mp_exact")
	if f.mp > 0:
		_fail(fight, "mp_all")
	if f.cell != f.turn_begin_cell:
		_fail(fight, "stay")
	var near_foe := false
	var near_ally := false
	for g: Fighter in fight.fighters.values():
		if g.id == f.id or not g.alive or g.carried_by != -1:
			continue
		if FightRules.distance(f.cell, g.cell) <= 1:
			if g.team == f.team:
				near_ally = true
			else:
				near_foe = true
	if not near_foe:
		_fail(fight, "next_to_enemy")
	if not near_ally:
		_fail(fight, "next_to_ally")
	if near_ally:
		_fail(fight, "away_ally")
	if near_foe:
		_fail(fight, "away_enemy")


## After any action: HP lost, deaths and kills since the last look.
static func observe(fight: Fight) -> void:
	if fight.chal.is_empty() or fight.challenges.is_empty():
		return
	var hp: Dictionary = fight.chal["hp"]
	var alive: Dictionary = fight.chal["alive"]
	var fresh: Array = []
	for f: Fighter in fight.fighters.values():
		if f.team == 0 and f.hp < int(hp.get(f.id, f.hp)):
			_fail(fight, "no_damage")
		hp[f.id] = f.hp
		if bool(alive.get(f.id, true)) and not f.alive:
			if f.team == 0 and f.summoner == -1:
				_fail(fight, "no_death")
			elif f.team == 1 and f.summoner == -1:
				fresh.append(f)
		alive[f.id] = f.alive
	fresh.sort_custom(func(a: Fighter, b: Fighter) -> bool: return a.id < b.id)
	for f: Fighter in fresh:
		_killed(fight, f)


static func _killed(fight: Fight, f: Fighter) -> void:
	var chal: Dictionary = fight.chal
	var order: Array = chal["order"]
	# enemies still standing when `f` fell (simultaneous deaths are judged one after the other)
	var standing := _team(fight, 1).filter(func(g: Fighter) -> bool: return g.id != f.id and g.alive)
	var first := order.is_empty()
	order.append(f.id)
	var killer: Fighter = fight.fighters.get(f.last_hit_by)
	while killer != null and killer.summoner != -1:
		killer = fight.fighters.get(killer.summoner)
	if killer != null and killer.team == 0:
		chal["kills"][killer.id] = int(chal["kills"].get(killer.id, 0)) + 1
	for c: Dictionary in _of(fight, "first"):
		if first and f.id != int(c["target"]):
			c["state"] = FAILED
			fight.emit_event(Protocol.challenge_update(int(c["id"]), FAILED))
	for c: Dictionary in _of(fight, "last"):
		if f.id == int(c["target"]) and not standing.is_empty():
			c["state"] = FAILED
			fight.emit_event(Protocol.challenge_update(int(c["id"]), FAILED))
	if not f.last_hit_weapon:
		_fail(fight, "weapon")
	for g: Fighter in standing:
		if g.level < f.level:
			_fail(fight, "level_up")
		if g.level > f.level:
			_fail(fight, "level_down")
	if int(chal["round"]) == -1:
		chal["round"] = fight.fight_round
	elif int(chal["round"]) != fight.fight_round:
		_fail(fight, "same_round")


## The fight is over: running challenges are won if the players won, else lost.
static func finish(fight: Fight) -> void:
	if fight.chal.is_empty() and fight.challenges.is_empty():
		return
	observe(fight)
	var won := fight.result == "win"
	if won and has_rule(fight, "everyone_kills"):
		for f: Fighter in _team(fight, 0):
			if int(fight.chal["kills"].get(f.id, 0)) < 1:
				_fail(fight, "everyone_kills")
				break
	for c: Dictionary in fight.challenges:
		if c["state"] == RUNNING:
			c["state"] = SUCCESS if won else FAILED
			fight.emit_event(Protocol.challenge_update(int(c["id"]), str(c["state"])))
