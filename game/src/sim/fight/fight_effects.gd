## What a spell does (Dofus formulas, simplified where noted). Pure functions on a
## Fight: they change the fighters and return the effect dicts of the event
## (see Protocol "effect dict").
##   What each effect does to a fighter: FightLife (life), FightBuffs (buffs, states, removals),
##   FightDisplace (moves), Carry, Summons, FightMarks; here: the dispatch and the targets.
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
##   carry / throw (P1.12): Carry. Effects marked `carried` (targetMask K) touch only the
##            fighter the caster carried when casting; the others never touch it (it was on
##            the caster's cell, out of the area, when the spell was cast).
##   intercept / share / heal_attackers (P1.13e, 765 / 1061 / 786): trigger buffs redirecting the
##            damage of a hit (FightTriggers); `damage` returns every hit it caused.
##   teleport / sym_target / sym_caster / swap (P1.13n, Telefrag): a teleport onto an occupied cell
##            swaps the two fighters when can_swap allows it both ways, else nothing moves (client
##            code hai.bnca / dht / hbl / mwk, the teleports of the spell preview). The occupant's
##            move comes first; both moves carry `swapped` (the other one) and `telefrag` (the
##            caster is a Xelor: breedId 5, read at gyn +0x14), logged for targetMask T.
##   rollbacks (P1.13q): sym_impact 1106, rollback_prev 1100 (before the target's latest move),
##            rollback_turn 1099 (its cell when its turn began), to_start 784 (its cell at the start
##            of the fight): the target goes back there, an occupant swaps as in a teleport (Telefrag
##            for a Xelor caster); 1023 is a `swap` that skips can_swap.
##   spell_reflect (P1.13r, 106): a buff; a harmful spell (`REFLECTABLE` effects) of a grade <= `level`
##            cast on its holder by an enemy goes back to the caster, with a chance of `pct` % (one
##            roll per holder and cast); the cast sends a `reflected` effect (APPROX, see spells.py).
class_name FightEffects
extends RefCounted

const SUMMON_KINDS := ["summon", "double", "replace", "illusion"]
## Effects acting once on the target cell rather than on each fighter of the area: summons, carry /
## throw, marks, portals. With `on` or `delay` they wait on their targets like any effect, then act
## on the holder's cell. A teleport (4) moves its caster to the cell, whoever the mask names (Bond, Pas
## Chassé: "a,A" on a free cell, P1.18).
const CELL_KINDS := SUMMON_KINDS + FightMarks.KINDS + ["carry", "throw", "portal", "unportal", "unmark", "teleport"]
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
		fight.cast_serial += 1
	fight.cast_depth += 1
	fight.cast_chain.append(int(spell.get("id", 0)))
	var ctx := [fight.cast_crit, fight.cast_weapon]
	fight.cast_crit = crit
	fight.cast_weapon = int(spell.get("id", 0)) == Equipment.WEAPON_SPELL
	var out := _apply_spell(fight, caster, spell, center, crit, only)
	fight.cast_crit = ctx[0]
	fight.cast_weapon = ctx[1]
	fight.cast_depth -= 1
	fight.cast_chain.pop_back()
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
	# P1.18: each effect touches the fighters its area held when the spell was cast (Souterrain swaps then
	# hits its target, "échange de position avec la cible et occasionne des dommages"), and the ones the
	# cast summoned there (targetMask U: Double's hooks); a fighter that died or got carried meanwhile is
	# left out below
	var planned := {}
	for i in list.size():
		if not bool(list[i].get("carried", false)):
			planned[i] = targets(fight, caster, spell, list[i], center)
	for i in list.size():
		var e: Dictionary = list[i]
		if not caster.alive and not caster.exploded: # an exploding bomb goes on (Summons.detonate)
			break
		if not cond_ok(e, caster, null, states):
			continue
		var kind := str(e.get("kind", ""))
		if kind in CELL_KINDS and not e.has("on") and int(e.get("delay", 0)) == 0: # once, on the target cell
			out.append_array(on_cell(fight, caster, e, center, sid))
			continue
		var list_t: Array = [carried] if bool(e.get("carried", false)) else planned[i] + targets(fight, caster, spell, e, center) 				.filter(func(f: Fighter) -> bool:
					return not planned[i].has(f) and bool(fight.cast_log.get(f.id, {}).get("summoned", false)))
		if str(e.get("mask", "")).split(",").has("U") and not bool(e.get("carried", false)):
			# P1.18d: targetMask U names the creatures this cast summoned, wherever they stand: the delayed kill of
			# Pavois (1172120: « Les boucliers sont détruits au tour suivant ») reaches every shield of its zone,
			# not only the one on the centre cell
			for f: Fighter in fight.fighters.values():
				if f.alive and not list_t.has(f) and bool(fight.cast_log.get(f.id, {}).get("summoned", false)):
					list_t.append(f)
		if only != null and str(e.get("target", "")) != "caster":
			list_t = [only]
		var mirrored := {} # fighters a symmetry of this effect already moved: a pair swaps once
		for t: Fighter in list_t:
			if t == null or not t.alive or (t == carried) != bool(e.get("carried", false)) or mirrored.has(t.id) 					or (t != carried and t.carried_by != -1):
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
				out.append(FightBuffs.delayed(fight, caster, t, e, sid, int(spell.get("max_stack", 0))))
				continue
			var fx := e
			if str(e.get("kind", "")) in ZONE_DECREASE and int(e.get("duration", 0)) == 0 and not e.has("on"):
				var pct := FightRules.efficiency(e.get("area", spell.get("area", {})), center, origin(fight, caster), t.cell)
				if pct != 0:
					fx = e.duplicate()
					fx["zone_pct"] = pct
			var landed := land(fight, caster, t, fx, center, sid, int(spell.get("max_stack", 0)))
			if kind in FightDisplace.SYMMETRIES:
				for d: Dictionary in landed:
					if str(d.get("kind", "")) == "move":
						mirrored[int(d["target"])] = true
			out.append_array(landed)
		# APPROX(P1.18b): a one-turn state the spell sets on its caster is a flag of this very cast (Runification:
		# state 296 "Rune", then its steals and stat gains read `*E296`, after the unstate that cleans it up)
		if kind == "state" and str(e.get("target", "")) == "caster" and int(e.get("duration", 0)) == 1 \
				and not states.has(int(e.get("state", 0))) and _unstated_later(list, i, int(e.get("state", 0))):
			states.append(int(e["state"]))
	return out


## A later effect of `list` (after `i`) takes `state` off the caster again: a working flag of the cast.
static func _unstated_later(list: Array, i: int, state: int) -> bool:
	for j in range(i + 1, list.size()):
		var u: Dictionary = list[j]
		if str(u.get("kind", "")) == "unstate" and str(u.get("target", "")) == "caster" and int(u.get("state", 0)) == state:
			return true
	return false


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
		out.append_array(FightBuffs.unstack(t, e, sid, max_stack))
	out.append_array(apply(fight, caster, t, e, center, sid))
	out.append_array(FightTriggers.flush(fight))
	return out


## The effect's `target` side (enemies / allies / all) accepts `t`.
static func team_ok(e: Dictionary, caster: Fighter, t: Fighter) -> bool:
	var who := str(e.get("target", "all"))
	return not ((who == "enemies" and t.team == caster.team) or (who == "allies" and t.team != caster.team))


## Fighters an effect touches: its area (or the spell's) around `center`, filtered
## by team (by its target mask: TargetMask sides; C = the caster even outside the area, gtz.blqh).
## Pushes handle the farthest first, pulls the nearest first, so they do not bump into each other.
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
	var far_first := str(e.get("kind", "")) == "push" # pulls: the nearest first, for the same reason
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


## The spell (grade id) destroys, with a kill of mask U, the creatures it summoned (Pavois, Balise Tactique).
static func dies_with_cast(spell_id: int) -> bool:
	for e: Dictionary in SpellBook.get_spell(spell_id).get("effects", []):
		if str(e.get("kind", "")) == "kill" and str(e.get("mask", "")).split(",").has("U"):
			return true
	return false


## A CELL_KINDS effect of `caster` on `cell`.
static func on_cell(fight: Fight, caster: Fighter, e: Dictionary, cell: int, spell_id: int) -> Array:
	match str(e.get("kind", "")):
		"summon", "double", "replace", "illusion":
			# P1.18d: a summon with an area of size > 0 (and no `replaces`: Bambouseraie, left to P1.18e) brings one creature
			# on each free cell of it, for the ones that use no summon slot and are destroyed later by the same spell (APPROX(P1.18d): the monsters
			# whose zone summons grew the matrix, Rejet or Forêt de Cactus, stay on one cell; Pavois 1172120:
			# « Invoque plusieurs boucliers statiques en zone »); the others (size 0, point) stay on the one cell
			var a: Dictionary = e.get("area", {})
			var zone_summon := str(e.get("kind", "")) == "summon" and float(a.get("size", 0.0)) > 0.0 and not e.has("replaces")
			zone_summon = zone_summon and not bool(SpellBook.summon(int(e.get("monster", 0))).get("slot", false)) and dies_with_cast(spell_id)
			if zone_summon:
				var made: Array = []
				for c: int in FightRules.zone_in(fight.map, fight.occupied(), a, cell, origin(fight, caster)):
					made.append_array(Summons.apply(fight, caster, e, c))
				return made
			return Summons.apply(fight, caster, e, cell)
		"carry":
			return Carry.apply(fight, caster, e, cell, spell_id)
		"throw":
			return Carry.throw(fight, caster, cell)
		"portal":
			return FightMarks.portal(fight, caster, e, cell)
		"unportal":
			return FightMarks.unportal(fight, caster, e, cell)
		"unmark":
			return FightMarks.unmark(fight, caster, e)
		"teleport":
			return FightDisplace.teleport_to(fight, caster, e, cell)
	return FightMarks.add(fight, caster, e, cell)


static func apply(fight: Fight, caster: Fighter, t: Fighter, e: Dictionary, center: int, spell_id: int) -> Array:
	var prev := fight.dispellable
	fight.dispellable = int(e.get("dispellable", 1))
	var out := _apply(fight, caster, t, e, center, spell_id)
	fight.dispellable = prev
	return out


static func _apply(fight: Fight, caster: Fighter, t: Fighter, e: Dictionary, center: int, spell_id: int) -> Array:
	var kind := str(e.get("kind", ""))
	if kind in CELL_KINDS: # fired by a trigger or a delay: on the holder's cell
		return on_cell(fight, caster, e, t.cell, spell_id)
	if kind in FightTriggers.PASSIVE: # without trigger codes (Bave Affaiblissante: 1163 on "I")
		# APPROX(P1.18): a buff lasting its duration, at least the current turn, as the other buffs
		var buff := e.duplicate()
		buff["turns"] = FightBuffs.turns_of(e)
		return FightTriggers.add(fight, caster, t, buff, spell_id, 0, center)
	match kind:
		"damage", "steal", "heal", "heal_pct", "heal_attackers", "reflect", "transfer_hp", "heal_dealt", "splash_taken", "splash_heal":
			return FightLife.apply(fight, caster, t, e, kind, spell_id)
		"spell_reflect", "stat", "steal_stat", "shield", "state", "unstate":
			return FightBuffs.apply(fight, caster, t, e, kind, spell_id)
		"reveal", "dispel", "unbuff", "pass_turn", "cooldown", "shorten":
			return FightBuffs.remove(fight, caster, t, e, kind)
		"cast":
			var sub := SpellBook.get_spell(int(e.get("spell", 0)))
			if sub.is_empty() or fight.chain_depth >= FightTriggers.MAX_DEPTH:
				return []
			fight.chain_depth += 1
			var cast := apply_spell(fight, t if str(e.get("by", "")) == "target" else caster, sub, t.cell, false)
			fight.chain_depth -= 1
			return cast
		"kill":
			return [FightLife.kill(t)]
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
		"swap", "sym_target", "sym_caster", "sym_impact", "rollback_prev", "rollback_turn", "to_start":
			return FightDisplace.teleport(fight, caster, t, kind, center, int(e.get("effect", FightDisplace.MOVE_EFFECT.get(kind, 0))))
		"ap", "mp":
			return FightBuffs.resource(fight, caster, t, e, spell_id)
	return []
