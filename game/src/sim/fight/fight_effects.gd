## What a spell does (Dofus formulas, simplified where noted). Pure functions on a
## Fight: they change the fighters and return the effect dicts of the event
## (see Protocol "effect dict").
##   damage = base x (100 + element stat + power) / 100 + damage + element damage, minus the
##            target's fixed element resistance, then x (100 - res%) / 100,
##            absorbed by shields first. Element stats: Fighter.ELEMENT_STAT.
##            Then x (100 + final_damage + combo) / 100 (1171 / 1172 "Dommages finaux", 1027
##            "Dommages Combo" of the bombs, P1.13d). APPROX(P1.13d): applied last, after the
##            resistances; the combo counts like final damage of the fighter holding it.
##   heal   = base x (100 + element stat) / 100 + heals, x (100 + final_heals) / 100 (2971).
##            A spell projected through portals (P1.13f, FightMarks): both x (100 + bonus) / 100,
##            APPROX(P1.13f): after everything else (the text only says "augmentés").
##            steal = damage, caster heals half.
##   push collision = (caster level / 2 + 32 + push damage - push res) x cells left / 4.
##            APPROX(P1.14): Dofus 2 community formula, not found in luaformulas yet.
##   AP / MP removal (dodgeable): each point is lost with p = 0.5 x attack / dodge x left / max,
##            attack = 1 + AP|MP removal, dodge = 1 + AP|MP dodge (StatFormulas).
##            APPROX(P1.14): community formula, to check against luaformulas.
##   trap / glyph_start / glyph_end / unmark (P1.13a): FightMarks; a mark's spell hitting
##            one fighter (glyphs) passes it as `only`.
##   effects with `on` (P1.13b): a trigger buff on their target (FightTriggers), they fire
##            later; damage and heals go through its multipliers and queue its hits.
##   cast (P1.13b): the caster casts the effect's spell on its target's cell, or with
##            by: "target" the target casts it on its own cell (chains of at most
##            FightTriggers.MAX_DEPTH). heal_pct: % of the target's max HP.
##   kill: the target dies. unbuff: the target loses the buffs of spell `origin` (spells.id).
##   runes (P1.13d, 2023): the caster's runes under the target go off (FightMarks.runes).
##   detonate (P1.13d, 1009): the target bomb explodes (Summons.detonate).
##   portal / unportal (P1.13f, 1181 / 1183): on the target cell (FightMarks); teleportal (1182):
##            the target crosses the portals (FightMarks.cross). cond {portal}: targetMask R / r,
##            the spell is / is not projected (Fighter.projecting). A projected spell's areas and
##            pushes start from the portal it comes out of (Fight.cast_from).
##   cond: state conditions, monster filters {monsters: [monsters.id], has} and {player}
##            (a character, not a monster or a summon; APPROX(P1.13d): spells.py) (P1.13d).
##   P1.17b: element "best" (2822 / 2828) = the caster's highest element; `pct` stat (1078) = % of the
##            target's max life; glyph_trigger (1026): FightMarks.trigger_glyphs; the `crit_res` stat
##            (420) lowers a critical hit's damage, flat, after the fixed resistance (APPROX).
##   pass_turn (P1.17b 7, 1031): the target's turn ends after the spell (`Fighter.pass_turn`); heal element "best" (3002).
##   cooldown (P1.17b, 1045 / 1036 / 1035): mode set|sub|add, origin (spells.id), turns; see `cooldown`.
##   reveal (P1.13c, 202): the target stops being invisible (its states with the flag
##            `invisible` end); the end of an invisibility sends everyone a `reveal` effect
##            with its cell (FightVisibility).
##   carry / throw (P1.12): Carry. Effects marked `carried` (targetMask K) touch only the
##            fighter the caster carried when casting; the others never touch it (it was on
##            the caster's cell, out of the area, when the spell was cast).
##   intercept / share / heal_attackers (P1.13e, 765 / 1061 / 786): trigger buffs redirecting the
##            damage of a hit (FightTriggers); `damage` returns every hit it caused.
##   ap / mp `steal` (P1.13m, 84 / 77): the target loses them (dodgeable), the caster wins what was
##            lost, for as long. dispel (P1.13m, 132): the target loses its buffs with `dispellable` 1.
##   teleport / sym_target / sym_caster / swap (P1.13n, Telefrag): a teleport onto an occupied cell
##            swaps the two fighters when can_swap allows it both ways, else nothing moves (client
##            code hai.bnca / dht / hbl / mwk, the teleports of the spell preview). The occupant's
##            move comes first; both moves carry `swapped` (the other one) and `telefrag` (the
##            caster is a Xelor: breedId 5, read at gyn +0x14), logged for targetMask T.
##   rollbacks (P1.13q): sym_impact 1106, rollback_prev 1100 (before the target's latest move),
##            rollback_turn 1099 (its cell when its turn began), to_start 784 (its cell at the start
##            of the fight): the target goes back there, an occupant swaps as in a teleport (Telefrag
##            for a Xelor caster); 1023 is a `swap` that skips can_swap.
##   damage `hp_pct` / `per_ap` (P1.17, 1071 / 1132): see _base.
##   reflect (P1.13o, 107 / 220): fired by a hit, sends a flat damage back to its attacker (APPROX).
##   spell_reflect (P1.13r, 106): a buff; a harmful spell (`REFLECTABLE` effects) of a grade <= `level`
##            cast on its holder by an enemy goes back to the caster, with a chance of `pct` % (one
##            roll per holder and cast); the cast sends a `reflected` effect (APPROX, see spells.py).
## Not simulated: erosion, chain pushes, critical damage bonus.
class_name FightEffects
extends RefCounted

const SUMMON_KINDS := ["summon", "double", "replace"]
## Effects losing damage away from their area's centre (P1.13j, FightRules.efficiency): the
## client's preview applies it to what the caster's side computes (gzm.bmyv: ra.fay on hal's
## damage, before the target's side ham.bndg), except 80 (push damage), 90, 1047, 1048
## (gzj.bmws), shields 1020 / 1039 / 1040 and the splashes (gzj.bmvt, HitContext.bmuv).
## APPROX(P1.13j): poisons and trigger buffs keep their full damage (the preview only
## computes the cast itself).
const ZONE_DECREASE := ["damage", "steal", "heal"]
## Effects a spell reflector sends back (P1.13r). APPROX(P1.13r): the harmful ones, no source.
const REFLECTABLE := ["damage", "steal", "push", "pull", "recoil"]


## Applies a cast of `spell` on `center`. Returns the effect dicts. The outermost one starts
## `Fight.cast_log` afresh (what the targets underwent in this cast: TargetMask T / W / U / K).
static func apply_spell(fight: Fight, caster: Fighter, spell: Dictionary, center: int, crit: bool, only: Fighter = null) -> Array:
	if fight.cast_depth == 0:
		fight.cast_log = {}
		fight.cast_dealt = 0
	fight.cast_depth += 1
	var ctx := [fight.cast_crit, fight.cast_weapon]
	fight.cast_crit = crit
	fight.cast_weapon = int(spell.get("id", 0)) == Equipment.WEAPON_SPELL
	var out := _apply_spell(fight, caster, spell, center, crit, only)
	fight.cast_crit = ctx[0]
	fight.cast_weapon = ctx[1]
	fight.cast_depth -= 1
	return out


static func _apply_spell(fight: Fight, caster: Fighter, spell: Dictionary, center: int, crit: bool, only: Fighter) -> Array:
	var out: Array = []
	var list: Array = spell.get("effects", [])
	if crit and not (spell.get("crit_effects", []) as Array).is_empty():
		list = spell["crit_effects"]
	# conditions (caster and targets) are read as they were when the spell was cast: a state the spell
	# sets must not switch on its other variant in the same cast
	var states := caster.state_ids()
	var snap := {} # the same for the targets' states (P1.13d: Combo climbs one level per cast)
	for g: Fighter in fight.fighters.values():
		snap[g.id] = g.state_ids()
	var carried: Fighter = fight.fighters.get(caster.carrying)
	var sid := int(spell.get("id", 0))
	var reflected := {} # holder id -> true / false: its reflector's roll for this cast (P1.13r)
	for e: Dictionary in list:
		if not caster.alive and not caster.exploded: # an exploding bomb goes on (Summons.detonate)
			break
		if not cond_ok(e, caster, null, states):
			continue
		var kind := str(e.get("kind", ""))
		if kind in SUMMON_KINDS: # once, on the target cell (Summons)
			out.append_array(Summons.apply(fight, caster, e, center))
			continue
		if kind == "carry":
			out.append_array(Carry.apply(fight, caster, e, center, sid))
			continue
		if kind == "throw":
			out.append_array(Carry.throw(fight, caster, center))
			continue
		if kind in FightMarks.KINDS:
			out.append_array(FightMarks.add(fight, caster, e, center))
			continue
		if kind == "portal":
			out.append_array(FightMarks.portal(fight, caster, e, center))
			continue
		if kind == "unportal":
			out.append_array(FightMarks.unportal(fight, caster, e, center))
			continue
		if kind == "unmark":
			out.append_array(FightMarks.unmark(fight, caster, e))
			continue
		var list_t: Array = [carried] if bool(e.get("carried", false)) else targets(fight, caster, spell, e, center)
		if only != null and str(e.get("target", "")) != "caster":
			list_t = [only]
		for t: Fighter in list_t:
			if t == null or not t.alive or (t == carried) != bool(e.get("carried", false)):
				continue
			if e.has("mask"):
				if not TargetMask.affects(fight, caster, t, e, states, snap.get(t.id)):
					continue
			elif not team_ok(e, caster, t) or not cond_ok(e, caster, t, states, snap.get(t.id)):
				continue
			if str(e.get("kind", "")) in REFLECTABLE and fight.cast_depth == 1:
				var back := _reflector(fight, caster, t, spell, reflected)
				if back != null:
					if not reflected.has(-t.id - 1): # one `reflected` effect per holder
						reflected[-t.id - 1] = true
						out.append({"kind": "reflected", "target": t.id, "to": caster.id})
					t = back
			if int(e.get("delay", 0)) > 0:
				out.append(delayed(fight, caster, t, e, sid, int(spell.get("max_stack", 0))))
				continue
			var fx := e
			if str(e.get("kind", "")) in ZONE_DECREASE and int(e.get("duration", 0)) == 0 and not e.has("on"):
				var pct := FightRules.efficiency(e.get("area", spell.get("area", {})), center, origin(fight, caster), t.cell)
				if pct != 0:
					fx = e.duplicate()
					fx["zone_pct"] = pct
			out.append_array(land(fight, caster, t, fx, center, sid, int(spell.get("max_stack", 0))))
	return out


## The fighter a harmful effect of `spell` on `t` goes back to (P1.13r, 106): the caster when `t` holds
## a reflector buff of at least the spell's grade and the roll (`pct` %, once per holder, kept in
## `rolled`) succeeds; null otherwise. Only an enemy's spell, and only a spell with a grade.
static func _reflector(fight: Fight, caster: Fighter, t: Fighter, spell: Dictionary, rolled: Dictionary) -> Fighter:
	if t == caster or t.team == caster.team or not caster.alive or int(spell.get("grade", 0)) <= 0:
		return null
	if not rolled.has(t.id):
		rolled[t.id] = false
		for b: Buff in t.buffs:
			if b.kind == "spell_reflect" and int(spell["grade"]) <= b.value \
					and fight.rng.randi_range(1, 100) <= int(b.effect.get("pct", 100)):
				rolled[t.id] = true
				break
	return caster if bool(rolled[t.id]) else null


## One effect reaching `t` now: a trigger buff if it has `on` (and applied too if `now`),
## otherwise applied, then the triggers of its hits.
static func land(fight: Fight, caster: Fighter, t: Fighter, e: Dictionary, center: int, sid: int, max_stack: int) -> Array:
	var out: Array = []
	if e.has("on"):
		out.append_array(FightTriggers.add(fight, caster, t, e, sid, max_stack, center))
		if not bool(e.get("now", false)):
			return out
	if str(e.get("kind", "")) == "stat" and max_stack > 0:
		out.append_array(_unstack(t, e, sid, max_stack))
	out.append_array(apply(fight, caster, t, e, center, sid))
	out.append_array(FightTriggers.flush(fight))
	return out


## spelllevels.maxStack on characteristic buffs (P1.13d): `t` keeps at most `max_stack` - 1
## buffs of the same characteristic from the same spell (any of its levels, `origin`) before a
## new one: the oldest go (Combo: each level replaces the previous one). APPROX(P1.13d): counted
## per spell and characteristic.
static func _unstack(t: Fighter, e: Dictionary, sid: int, max_stack: int) -> Array:
	var out: Array = []
	var origin := int(SpellBook.get_spell(sid).get("origin", sid))
	var same := t.buffs.filter(func(b: Buff) -> bool:
		return b.kind == "stat" and b.stat == str(e.get("stat", "")) \
				and int(SpellBook.get_spell(b.spell).get("origin", b.spell)) == origin)
	while same.size() >= max_stack:
		out.append_array(remove_buff(t, same.pop_front()))
	return out


## An effect with a `delay` (spelllevels effects `delay`): a "delay" buff on `t` for that
## many of the caster's turns; when it runs out the effect lands (`expire`). APPROX(P1.13b):
## it lands at the start of the caster's turn, like the other buffs end.
static func delayed(fight: Fight, caster: Fighter, t: Fighter, e: Dictionary, sid: int, max_stack: int) -> Dictionary:
	var b := _buff(fight, caster, sid, "delay", int(e["delay"]))
	b.dispellable = int(e.get("dispellable", 1))
	b.effect = e.duplicate()
	b.effect.erase("delay")
	b.value = max_stack
	return _add_buff(t, b)


## Buff `b` of `t` ran out: removed, and a delayed effect lands.
static func expire(fight: Fight, t: Fighter, b: Buff) -> Array:
	var out := remove_buff(t, b, fight)
	var caster: Fighter = fight.fighters.get(b.caster)
	if b.kind == "delay" and t.alive and caster != null and caster.alive:
		out.append_array(land(fight, caster, t, b.effect, t.cell, b.spell, b.value))
	return out


## The effect's `target` side (enemies / allies / all) accepts `t`.
static func team_ok(e: Dictionary, caster: Fighter, t: Fighter) -> bool:
	var who := str(e.get("target", "all"))
	return not ((who == "enemies" and t.team == caster.team) or (who == "allies" and t.team != caster.team))


## Fighters an effect touches: its area (or the spell's) around `center`, filtered
## by team (by its target mask: TargetMask sides; C = the caster even outside the area, gtz.blqh).
## Pushes handle the farthest first so they do not bump into each other.
static func targets(fight: Fight, caster: Fighter, spell: Dictionary, e: Dictionary, center: int) -> Array:
	var who := str(e.get("target", "all"))
	if who == "caster":
		return [caster]
	var tokens := TargetMask.parse(str(e.get("mask", "")))
	var out: Array = []
	var a: Dictionary = e.get("area", spell.get("area", {}))
	var with_carried := FightRules.touches_carried(a)
	var at := {} # cell -> fighters on it, a carried one on its carrier's cell
	for f: Fighter in fight.fighters.values():
		if f.alive:
			if not at.has(f.cell):
				at[f.cell] = []
			at[f.cell].append(f)
	for c in FightRules.zone_in(fight.map, fight.occupied(), a, center, origin(fight, caster)):
		for t: Fighter in at.get(c, []):
			# P1.13l (gtz.nhs): a carried fighter only with includeCarried
			if (t.carried_by != -1 or t.state_ids().has(FightRules.CARRIED_STATE)) and not with_carried:
				continue
			if TargetMask.side_ok(caster, t, tokens) if not tokens.is_empty() else team_ok(e, caster, t):
				out.append(t)
	if tokens.has("C") and not out.has(caster):
		out.append(caster)
	var far_first := str(e.get("kind", "")) in ["push", "pull"]
	out.sort_custom(func(a: Fighter, b: Fighter) -> bool:
		var da := FightRules.distance(a.cell, center)
		var db := FightRules.distance(b.cell, center)
		return da > db if far_first else da < db)
	return out


## Where `caster`'s spell comes from: its cell, or the portal a projected spell comes out of.
static func origin(fight: Fight, caster: Fighter) -> int:
	return fight.cast_from if fight.cast_from >= 0 else caster.cell


## State conditions of an effect ({who, state, has}); `t` null = caster ones only.
## `caster_states`: the caster's states to test (default: its current ones).
static func cond_ok(e: Dictionary, caster: Fighter, t: Fighter, caster_states = null, target_states = null) -> bool:
	for c: Dictionary in e.get("cond", []):
		var has := false
		if c.has("portal"): # targetMask R / r (P1.13f)
			if (caster.projecting >= 0) != bool(c["portal"]):
				return false
			continue
		if c.has("monsters") or c.has("player"): # targetMask F / f, p / P
			var who: Fighter = caster if str(c.get("who", "")) == "caster" else t
			if who == null:
				continue
			if c.has("player"):
				if who.is_character() != bool(c["player"]):
					return false
				continue
			has = (c["monsters"] as Array).any(func(m: Variant) -> bool: return int(m) == who.monster)
		elif str(c.get("who", "")) == "caster":
			has = (caster_states as Array).has(int(c["state"])) if caster_states != null else caster.has_state(int(c["state"]))
		elif t != null:
			has = (target_states as Array).has(int(c["state"])) if target_states != null else t.has_state(int(c["state"]))
		else:
			continue
		if has != bool(c["has"]):
			return false
	return true


static func apply(fight: Fight, caster: Fighter, t: Fighter, e: Dictionary, center: int, spell_id: int) -> Array:
	var prev := fight.dispellable
	fight.dispellable = int(e.get("dispellable", 1))
	var out := _apply(fight, caster, t, e, center, spell_id)
	fight.dispellable = prev
	return out


static func _apply(fight: Fight, caster: Fighter, t: Fighter, e: Dictionary, center: int, spell_id: int) -> Array:
	var kind := str(e.get("kind", ""))
	match kind:
		"damage", "steal", "heal", "heal_pct", "heal_attackers", "reflect", "transfer_hp", "heal_dealt", "splash_taken", "splash_heal":
			return _apply_life(fight, caster, t, e, kind, spell_id)
		"spell_reflect", "stat", "steal_stat", "shield", "state", "unstate":
			return _apply_buff(fight, caster, t, e, kind, spell_id)
		"reveal", "dispel", "unbuff", "pass_turn", "cooldown":
			return _apply_removal(fight, caster, t, e, kind)
		"cast":
			var sub := SpellBook.get_spell(int(e.get("spell", 0)))
			if sub.is_empty() or fight.chain_depth >= FightTriggers.MAX_DEPTH:
				return []
			fight.chain_depth += 1
			var cast := apply_spell(fight, t if str(e.get("by", "")) == "target" else caster, sub, t.cell, false)
			fight.chain_depth -= 1
			return cast
		"kill":
			return [kill(t)]
		"runes":
			return FightMarks.runes(fight, caster, t)
		"glyph_trigger": # P1.17b, 1026 ForceGlyphTrigger "Déclenche les glyphes"
			return FightMarks.trigger_glyphs(fight, caster, t)
		"detonate":
			return Summons.detonate(fight, t)
		"teleportal":
			return FightMarks.cross(fight, t)
		"push", "pull", "recoil", "advance":
			return FightDisplace.push(fight, caster, t, e, center)
		"teleport", "swap", "sym_target", "sym_caster", "sym_impact", "rollback_prev", "rollback_turn", "to_start":
			return FightDisplace.teleport(fight, caster, t, kind, center, int(e.get("effect", FightDisplace.MOVE_EFFECT.get(kind, 0))))
		"ap", "mp":
			return resource(fight, caster, t, e, spell_id)
	return []


## Effects that hurt, heal or give back life.
static func _apply_life(fight: Fight, caster: Fighter, t: Fighter, e: Dictionary, kind: String, spell_id: int) -> Array:
	match kind:
		"damage":
			var duration := int(e.get("duration", 0))
			if duration > 0:
				var b := _buff(fight, caster, spell_id, "poison", duration)
				b.effect = e
				return [_add_buff(t, b)]
			return _dealt(fight, damage(fight, caster, t, str(e.get("element", "neutral")), _base(fight, e, t, caster), int(e.get("zone_pct", 0))))
		"steal":
			var before := fight.cast_dealt
			var out := damage(fight, caster, t, str(e.get("element", "neutral")), roll(fight, e, caster), int(e.get("zone_pct", 0)))
			_dealt(fight, out)
			var dealt := fight.cast_dealt - before
			if caster.alive:
				var healed := heal_raw(caster, dealt / 2)
				if int(healed["amount"]) > 0: # V / VA, never H (P1.13m, gzp.bmzy; gzj.bmvy)
					FightTriggers.event(fight, caster, FightTriggers.LIFE, caster.id, int(healed["amount"]))
				out.append(healed)
			return out
		"heal_attackers": # 786 (P1.13e): fired by a hit, the attacker heals pct % of it
			var attacker: Fighter = fight.fighters.get(fight.trigger_from)
			if attacker == null or not attacker.alive:
				return []
			return [receive_heal(fight, attacker, fight.trigger_amount * int(e.get("pct", 0)) / 100, caster, false)]
		"reflect": # 107 / 220 (P1.13o): fired by a hit, the attacker takes a flat amount back
			var from: Fighter = fight.fighters.get(fight.trigger_from)
			if from == null or not from.alive or from == t or fight.trigger_amount <= 0:
				return []
			# APPROX(P1.13o): no formula found (luaformulas, client enums, JondoEmu): the amount is
			# the effect's roll (diceNum), plus the holder's `reflect` stat for 107 (boosted), never
			# reduced by the attacker's resistances; it triggers nothing
			var back := roll(fight, e) + (t.stat("reflect") if bool(e.get("boosted", false)) else 0)
			return [hurt(from, back, "neutral")]
		"heal":
			return [heal(fight, caster, t, str(e.get("element", "fire")), roll(fight, e, caster), int(e.get("zone_pct", 0)))]
		"heal_pct":
			return [receive_heal(fight, t, t.max_hp * roll(fight, e) / 100, caster)]
		"transfer_hp": # P1.17b (11), 90 "Transfere #1 a #2% des PV": the caster gives that % of its life
			# APPROX(P1.17b): i18n text only; the caster's current life, the receiver is healed as by any heal
			if t == caster or not caster.alive:
				return []
			var give := mini(caster.hp - 1, caster.hp * roll(fight, e) / 100)
			if give <= 0:
				return []
			caster.hp -= give
			return [{"kind": "damage", "target": caster.id, "element": "neutral", "amount": give, "shield": 0,
					"hp": caster.hp, "died": false}, receive_heal(fight, t, give, caster, false)]
		"heal_dealt": # 2973 "Soin : #1 a #2% des dommages occasionnes": a % of what the caster dealt in this cast
			return [receive_heal(fight, t, fight.cast_dealt * roll(fight, e) / 100, caster, false)]
		"splash_taken": # 1223 "Dommages : #1 a #2% des dommages finaux subis": a % of the hit that fired the trigger
			if fight.trigger_amount <= 0 or t == null or not t.alive:
				return []
			return [hurt(t, fight.trigger_amount * roll(fight, e) / 100, "neutral")]
		"splash_heal": # 2020 (P1.17b 13) "Soin : #1 a #2% des dommages subis". APPROX(P1.17b): i18n text only
			if fight.trigger_amount <= 0 or t == null or not t.alive:
				return []
			return [receive_heal(fight, t, fight.trigger_amount * roll(fight, e) / 100, caster, false)]
	return []


## Adds the damage in `out` to what the caster dealt in this cast (Fight.cast_dealt); returns `out`.
static func _dealt(fight: Fight, out: Array) -> Array:
	for h: Dictionary in out:
		if str(h.get("kind", "")) == "damage":
			fight.cast_dealt += int(h["amount"])
	return out


## Effects that put a buff, a shield or a state on a fighter.
static func _apply_buff(fight: Fight, caster: Fighter, t: Fighter, e: Dictionary, kind: String, spell_id: int) -> Array:
	var duration := int(e.get("duration", 0))
	match kind:
		"spell_reflect": # 106 (P1.13r): a buff the holder's incoming spells read (_reflector)
			var rb := _buff(fight, caster, spell_id, "spell_reflect", int(e.get("turns", 1)))
			rb.value = int(e.get("level", 0))
			rb.effect = e
			return [_add_buff(t, rb)]
		"steal_stat": # the target loses it, the caster gains as much (320 "Vole #1 Portée")
			var v := roll(fight, e)
			var turns := maxi(duration, 1) if duration >= 0 else -1
			var lost := _buff(fight, caster, spell_id, "stat", turns)
			lost.stat = str(e.get("stat", ""))
			lost.value = -v
			var won := _buff(fight, caster, spell_id, "stat", turns)
			won.stat = lost.stat
			won.value = v
			stat_changed(fight, t, lost.stat, -v)
			stat_changed(fight, caster, won.stat, v)
			return [_add_buff(t, lost), _add_buff(caster, won)]
		"stat":
			var b := _buff(fight, caster, spell_id, "stat", maxi(duration, 1) if duration >= 0 else -1)
			b.stat = str(e.get("stat", ""))
			b.value = roll(fight, e) * int(e.get("sign", 1))
			if bool(e.get("pct", false)): # P1.17b, 1078 "#1% Vitalité": % of the target's max life
				b.value = t.max_hp * b.value / 100
			if b.stat == "vitality":
				t.max_hp += b.value
				t.hp = clampi(t.hp + maxi(0, b.value), 1, t.max_hp)
			stat_changed(fight, t, b.stat, b.value)
			return [_add_buff(t, b)]
		"shield":
			var b := _buff(fight, caster, spell_id, "shield", maxi(duration, 1) if duration >= 0 else -1)
			var of := str(e.get("of", "level"))
			var base := caster.level if of == "level" else t.max_hp
			b.value = maxi(1, roll(fight, e) if of == "flat" else base * roll(fight, e) / 100)
			FightTriggers.event(fight, caster, ["CS"], t.id, b.value) # P1.13i, gzp.bnaa
			FightTriggers.event(fight, t, FightTriggers.LIFE, caster.id, b.value) # P1.13m: a shield is a life output
			return [_add_buff(t, b)]
		"state":
			var out := remove_state(t, int(e["state"]), fight)
			out.append(add_state(fight, caster, t, e, maxi(duration, 1) if duration >= 0 else -1, spell_id))
			return out
		"unstate":
			return remove_state(t, int(e["state"]), fight)
	return []


## Effects that take buffs away (or reveal, or act on the turn / the cooldowns).
static func _apply_removal(fight: Fight, caster: Fighter, t: Fighter, e: Dictionary, kind: String) -> Array:
	match kind:
		"reveal":
			var shown: Array = []
			for b: Buff in t.buffs.duplicate():
				if b.kind == "state" and b.flags.has("invisible"):
					shown.append_array(remove_buff(t, b, fight))
			if not shown.is_empty(): # CIOFF (P1.13m, gzp.bnaa): its caster made someone visible
				FightTriggers.event(fight, caster, ["CIOFF"], t.id)
			return shown
		"dispel": # 132 (P1.13m): DIS on the target (gzp.bmzy: a dispel output gzv)
			var listeners := FightTriggers.dis_listeners(t)
			var lost: Array = []
			for b: Buff in t.buffs.duplicate():
				if b.dispellable == 1:
					lost.append_array(remove_buff(t, b, fight))
			FightTriggers.queue_dispelled(fight, t, listeners, caster.id)
			return lost
		"pass_turn": # P1.17b (7), 1031 CharacterPassCurrentTurn
			t.pass_turn = true
			return [{"kind": "pass_turn", "target": t.id}]
		"cooldown": # P1.17b, 1045 set / 1036 sub / 1035 add: the target's spell `origin` (spells.id)
			return cooldown(t, e)
		"unbuff":
			var gone: Array = []
			for b: Buff in t.buffs.duplicate():
				var bs := SpellBook.get_spell(b.spell)
				# 1406 (P1.17b, 8): only the buffs of that grade (`grade`, the rank of the spell)
				if int(bs.get("origin", -1)) == int(e.get("origin", -2)) and (not e.has("grade") or int(bs.get("grade", 0)) == int(e["grade"])):
					gone.append_array(remove_buff(t, b, fight))
			return gone
	return []


## A characteristic of `t` changed by `value` (P1.13i, gzp.bmzy): R its range goes down, LPU its
## vitality goes up.
static func stat_changed(fight: Fight, t: Fighter, stat: String, value: int) -> void:
	if stat == "range" and value < 0:
		FightTriggers.event(fight, t, ["R"])
	elif stat == "vitality" and value > 0:
		FightTriggers.event(fight, t, ["LPU"])


## Puts `t` in state `s` {state, state_name_id, flags} for `turns` (-1 = until removed).
static func add_state(fight: Fight, caster: Fighter, t: Fighter, s: Dictionary, turns: int, spell_id: int) -> Dictionary:
	var b := _buff(fight, caster, spell_id, "state", turns)
	b.state = int(s["state"])
	b.state_name_id = int(s.get("state_name_id", 0))
	b.flags = s.get("flags", [])
	FightTriggers.state_changed(fight, t, b.state, true, caster)
	return _add_buff(t, b)


## The base of a damage effect: its dice, or (P1.17) `hp_pct` % of the target's current life (1071,
## APPROX(P1.17): only the i18n text "#1% PV de la cible", current life, then the usual formula) or
## `per_ap` [ap, damage] (1132 "#2 dommages Eau pour #1 PA utilisé": the target's AP spent this turn).
## `caster_hp_pct` (P1.17b, 8; 89 "#1 à #2% PV du lanceur", APPROX: the caster's current life, dice = the %).
static func _base(fight: Fight, e: Dictionary, t: Fighter, caster: Fighter = null) -> int:
	if e.has("caster_hp_pct") and caster != null:
		return caster.hp * roll(fight, e) / 100
	if e.has("caster_missing_pct") and caster != null: # P1.17b (9), 279 "#1 a #2% PV manquants du lanceur"
		return maxi(0, caster.max_hp - caster.hp) * roll(fight, e) / 100
	if e.has("mp_left"): # P1.17b (10), 1012-1016 "(% PM restants)": APPROX, the dice x the target's MP left / max
		return roll(fight, e) * t.mp / maxi(1, t.max_mp)
	if e.has("hp_pct"):
		return t.hp * int(e["hp_pct"]) / 100
	if e.has("per_ap"):
		var p: Array = e["per_ap"]
		return int(p[1]) * (t.ap_spent / maxi(1, int(p[0])))
	return roll(fight, e, caster)


## Tirage d'un effet. 782 (`roll_max`) force le maximum, 781 (`roll_min`) le minimum, pour les dommages et soins
## du porteur (P1.17b, APPROX : d'apres les noms de l'enum ActionId seulement ; le maximum l'emporte).
static func roll(fight: Fight, e: Dictionary, bearer: Fighter = null) -> int:
	var lo := int(e.get("min", 0))
	var hi := maxi(lo, int(e.get("max", lo)))
	if bearer != null and bearer.stat("roll_max") > 0:
		return hi
	if bearer != null and bearer.stat("roll_min") > 0:
		return lo
	return fight.rng.randi_range(lo, hi)


## "Meilleur élément" (P1.17b, 2822 / 2828): the element of the caster's highest characteristic
## (strength = earth, intelligence = fire, chance = water, agility = air). APPROX(P1.17b): only the
## i18n text; ties go to earth, fire, water, air; neutral is never chosen.
static func best_element(caster: Fighter) -> String:
	var best := "earth"
	var top := -999999
	for el: String in ["earth", "fire", "water", "air"]:
		var v := caster.stat(Fighter.ELEMENT_STAT[el])
		if v > top:
			top = v
			best = el
	return best


## "Pire element" (P1.17b 9, 2832 "dommages du pire element"): the lowest of the four, same tie order
## as `best_element`. APPROX(P1.17b 9): only the i18n text.
static func worst_element(caster: Fighter) -> String:
	var worst := "earth"
	var low := 999999
	for el: String in ["earth", "fire", "water", "air"]:
		var v := caster.stat(Fighter.ELEMENT_STAT[el])
		if v < low:
			low = v
			worst = el
	return worst


## The hits of `caster` on `t`: `t`'s, or its interceptor's, and its sharers' (P1.13e).
## `zone_pct`: the area decrease (P1.13j), on the caster's side (ra.fay: floor), before resistances.
static func damage(fight: Fight, caster: Fighter, t: Fighter, element: String, base: int, zone_pct := 0) -> Array:
	if element == "best":
		element = best_element(caster)
	elif element == "worst":
		element = worst_element(caster)
	var power := caster.stat(Fighter.ELEMENT_STAT.get(element, "strength")) + caster.stat("power")
	var dmg := base * maxi(0, 100 + power) / 100 + caster.stat("damage") + caster.stat("damage_" + element)
	if zone_pct != 0:
		dmg = floori(dmg * (100 - zone_pct) / 100.0)
	dmg = maxi(0, dmg - t.stat("res_fixed_" + element))
	if fight.cast_crit: # P1.17b, 420 "Résistance Critiques": flat, on a critical hit (APPROX, see the header)
		dmg = maxi(0, dmg - t.stat("crit_res"))
	var res := clampi(t.stat("res_" + element), -100, 100)
	dmg = maxi(0, dmg * (100 - res) / 100)
	dmg = maxi(0, dmg * (100 + caster.stat("final_damage") + caster.stat("combo")) / 100)
	if caster.projecting >= 0:
		dmg = dmg * (100 + caster.projecting) / 100
	if t.has_flag("invulnerable") or caster.has_flag("no_damage"):
		dmg = 0
	dmg = roundi(dmg * FightTriggers.multiplier(t, "taken"))
	# redirections (P1.13e, FightTriggers): an interceptor takes it, sharers split it
	var codes := FightTriggers.codes(caster, t, element)
	t = FightTriggers.interceptor(fight, t, codes)
	var group := FightTriggers.sharers(fight, t, FightTriggers.codes(caster, t, element))
	var out: Array = []
	var part := dmg / group.size()
	for g: Fighter in group:
		var amount := part + (dmg - part * group.size() if g == t else 0)
		FightTriggers.hit(fight, caster, g, element, amount)
		out.append(hurt(g, amount, element))
	return out


## `t` dies at once (a summon replaced, or dying with its summoner).
## Cooldown effects (P1.17b): 1045 CharacterSetSpellCooldown "relance fixée à #3" (a spell
## already castable gets that cooldown too), 1036 CharacterRemoveSpellCooldown "-#3 tour(s)
## de relance", 1035 CharacterAddSpellCooldown "+#3" (a spell with no cooldown gets it).
## Applies to every grade the target holds of spell e.origin (spells.id). One `cooldown`
## effect per changed grade: {spell, turns (left)}.
static func cooldown(t: Fighter, e: Dictionary) -> Array:
	var out: Array = []
	var mode := str(e.get("mode", "set"))
	var n := int(e.get("turns", 0))
	for sid: int in t.spells:
		if int(SpellBook.get_spell(sid).get("origin", -1)) != int(e.get("origin", -2)):
			continue
		var before := int(t.cooldowns.get(sid, 0))
		var after := n if mode == "set" else (maxi(before - n, 0) if mode == "sub" else before + n)
		if after == before:
			continue
		if after <= 0:
			t.cooldowns.erase(sid)
		else:
			t.cooldowns[sid] = after
		out.append({"kind": "cooldown", "target": t.id, "spell": sid, "turns": maxi(after, 0)})
	return out


static func kill(t: Fighter) -> Dictionary:
	var amount := t.hp
	t.hp = 0
	t.alive = false
	return {"kind": "damage", "target": t.id, "element": "neutral", "amount": amount, "shield": 0, "hp": 0, "died": true}


## Takes `dmg` HP from `t` (shields first).
static func hurt(t: Fighter, dmg: int, element: String) -> Dictionary:
	var absorbed := 0
	for b: Buff in t.buffs:
		if b.kind == "shield" and dmg > 0:
			var a := mini(b.value, dmg)
			b.value -= a
			dmg -= a
			absorbed += a
	t.buffs = t.buffs.filter(func(b: Buff) -> bool: return b.kind != "shield" or b.value > 0)
	dmg = mini(dmg, t.hp)
	t.hp -= dmg
	if t.hp <= 0:
		t.alive = false
	return {"kind": "damage", "target": t.id, "element": element, "amount": dmg, "shield": absorbed,
			"hp": t.hp, "died": not t.alive}


static func heal(fight: Fight, caster: Fighter, t: Fighter, element: String, base: int, zone_pct := 0) -> Dictionary:
	if element == "best": # 3002 (P1.17b 7)
		element = best_element(caster)
	var stat := caster.stat(Fighter.ELEMENT_STAT.get(element, "intelligence"))
	var amount := base * maxi(0, 100 + stat) / 100 + caster.stat("heals")
	if zone_pct != 0: # P1.13j, as for damage
		amount = floori(amount * (100 - zone_pct) / 100.0)
	amount = maxi(0, amount * (100 + caster.stat("final_heals")) / 100)
	if caster.projecting >= 0:
		amount = amount * (100 + caster.projecting) / 100
	return receive_heal(fight, t, amount, caster)


## `t` receives a heal of `amount` from `healer`: incurable, heal multipliers, H triggers (CH on
## the healer unless `ch` is false).
static func receive_heal(fight: Fight, t: Fighter, amount: int, healer: Fighter = null, ch := true) -> Dictionary:
	if t.has_flag("incurable"):
		amount = 0
	var out := heal_raw(t, roundi(amount * FightTriggers.multiplier(t, "healed")))
	FightTriggers.healed(fight, t, int(out["amount"]), healer, ch)
	return out


static func heal_raw(t: Fighter, amount: int) -> Dictionary:
	amount = clampi(amount, 0, t.max_hp - t.hp)
	t.hp += amount
	return {"kind": "heal", "target": t.id, "amount": amount, "hp": t.hp}


## +/- AP or MP, now (on the current points) and for `duration` turns (buff).
static func resource(fight: Fight, caster: Fighter, t: Fighter, e: Dictionary, spell_id: int) -> Array:
	var kind := str(e["kind"])
	var sign := int(e.get("sign", 1))
	var amount := roll(fight, e)
	var dodged := 0
	if sign < 0 and bool(e.get("dodge", false)):
		var attack := 1.0 + (StatFormulas.ap_attack(caster.stat) if kind == "ap" else StatFormulas.mp_attack(caster.stat))
		var dodge := 1.0 + (StatFormulas.ap_dodge(t.stat) if kind == "ap" else StatFormulas.mp_dodge(t.stat))
		var cur := t.ap if kind == "ap" else t.mp
		var total := maxf(1.0, t.cur_max_ap() if kind == "ap" else t.cur_max_mp())
		var lost := 0
		for i in amount:
			var p := clampf(0.5 * attack / dodge * float(cur - lost) / total, 0.1, 0.9)
			if fight.rng.randf() < p:
				lost += 1
		dodged = amount - lost
		amount = lost
	var value := amount * sign
	if kind == "ap":
		t.ap = maxi(0, t.ap + value)
	else:
		t.mp = maxi(0, t.mp + value)
	var out := {"kind": kind, "target": t.id, "value": value, "left": t.ap if kind == "ap" else t.mp, "dodged": dodged}
	if value != 0: # APA / MPA (P1.13i, gzp.bmzy: characteristics 1 / 23)
		FightTriggers.event(fight, t, ["APA" if kind == "ap" else "MPA"], caster.id)
	var duration := int(e.get("duration", 0))
	if duration != 0 and value != 0:
		var b := _buff(fight, caster, spell_id, kind, duration)
		b.value = value
		t.buffs.append(b)
		out["buff"] = b.to_dict()
	var res: Array = [out]
	if bool(e.get("steal", false)) and value != 0 and caster.alive and caster != t:
		# 84 / 77 (P1.13m): the caster wins what was lost; CAPA / CMPA (gzp.bnaa: a stat output with isSteal)
		var won := resource(fight, caster, caster, {"kind": kind, "min": -value, "max": -value, "duration": duration}, spell_id)
		res.append_array(won)
		FightTriggers.event(fight, caster, ["CAPA" if kind == "ap" else "CMPA"], t.id, -value)
	return res


static func remove_state(t: Fighter, state: int, fight: Fight = null) -> Array:
	var out: Array = []
	for b: Buff in t.buffs.duplicate():
		if b.kind == "state" and b.state == state:
			out.append_array(remove_buff(t, b, fight))
	return out


## Ends a buff (expired, dispelled, caster dead). With `fight`, a state's end is an EOFF event.
static func remove_buff(t: Fighter, b: Buff, fight: Fight = null) -> Array:
	t.buffs.erase(b)
	if fight != null and b.kind == "state":
		FightTriggers.state_changed(fight, t, b.state, false)
	if b.kind == "stat" and b.stat == "vitality":
		t.max_hp -= b.value
		t.hp = clampi(t.hp, 1 if t.alive else 0, maxi(1, t.max_hp))
	var out: Array = [{"kind": "buff_end", "target": t.id, "buff": b.id}]
	if b.flags.has("invisible") and not t.has_flag("invisible"):
		out.append({"kind": "reveal", "target": t.id, "cell": t.cell})
	return out


## A poison ticking at the start of its target's turn.
static func poison(fight: Fight, t: Fighter, b: Buff) -> Array:
	var caster: Fighter = fight.fighters.get(b.caster, t)
	fight.hit_source = "poison"
	var out := damage(fight, caster, t, str(b.effect.get("element", "neutral")), roll(fight, b.effect))
	fight.hit_source = ""
	return out


static func _buff(fight: Fight, caster: Fighter, spell_id: int, kind: String, turns: int) -> Buff:
	var b := Buff.new()
	b.id = fight.next_buff_id()
	b.dispellable = fight.dispellable
	b.kind = kind
	b.turns = turns
	b.caster = caster.id
	b.spell = spell_id
	if fight.aura_tag != 0: # given by an aura: lasts while its holder stays inside
		b.aura = fight.aura_tag
		b.turns = -1
	return b


static func _add_buff(t: Fighter, b: Buff) -> Dictionary:
	t.buffs.append(b)
	return {"kind": "buff", "target": t.id, "buff": b.to_dict()}
