## What the effects leave on a fighter or take away (split from FightEffects): characteristics,
## AP / MP, shields, states, spell reflectors; dispels, unbuffs, reveals, turn passes, cooldowns;
## delayed effects (`delay`) and the buffs' life cycle.
##   AP / MP removal (dodgeable): each point is lost with p = 0.5 x attack / dodge x left / max,
##            attack = 1 + AP|MP removal, dodge = 1 + AP|MP dodge (StatFormulas).
##            APPROX(P1.14): community formula, to check against luaformulas.
##   ap / mp `steal` (P1.13m, 84 / 77): the target loses them (dodgeable), the caster wins what was
##            lost, for as long. dispel (P1.13m, 132): the target loses its buffs with `dispellable` 1.
##   cooldown (P1.17b, 1045 / 1036 / 1035): mode set|sub|add, origin (spells.id), turns; see `cooldown`.
##   reveal (P1.13c, 202): the target stops being invisible (its states with the flag
##            `invisible` end); the end of an invisibility sends everyone a `reveal` effect
##            with its cell (FightVisibility).
##   shorten (P1.18, 1075): the target's dispellable buffs lose turns (see `remove`).
##   pass_turn (P1.17b 7, 1031): the target's turn ends after the spell (`Fighter.pass_turn`).
class_name FightBuffs
extends RefCounted


## The turns a buff of effect `e` lasts: its duration, at least the current turn; -1 = the whole fight.
static func turns_of(e: Dictionary) -> int:
	var duration := int(e.get("duration", 0))
	return maxi(duration, 1) if duration >= 0 else -1


## Effects that put a buff, a shield or a state on a fighter.
static func apply(fight: Fight, caster: Fighter, t: Fighter, e: Dictionary, kind: String, spell_id: int) -> Array:
	match kind:
		"spell_reflect": # 106 (P1.13r): a buff the holder's incoming spells read (_reflector)
			var rb := make(fight, caster, spell_id, "spell_reflect", int(e.get("turns", 1)))
			rb.value = int(e.get("level", 0))
			rb.effect = e
			return [attach(t, rb)]
		"steal_stat": # the target loses it, the caster gains as much (320 "Vole #1 Portée")
			var v := FightLife.roll(fight, e)
			var turns := turns_of(e)
			var lost := make(fight, caster, spell_id, "stat", turns)
			lost.stat = str(e.get("stat", ""))
			lost.value = -v
			var won := make(fight, caster, spell_id, "stat", turns)
			won.stat = lost.stat
			won.value = v
			stat_changed(fight, t, lost.stat, -v)
			stat_changed(fight, caster, won.stat, v)
			return [attach(t, lost), attach(caster, won)]
		"stat":
			var b := make(fight, caster, spell_id, "stat", turns_of(e))
			b.stat = str(e.get("stat", ""))
			b.value = FightLife.roll(fight, e) * int(e.get("sign", 1))
			if bool(e.get("pct", false)): # P1.17b, 1078 "#1% Vitalité": % of the target's max life
				b.value = t.max_hp * b.value / 100
			if b.stat == "vitality":
				t.max_hp += b.value
				t.hp = clampi(t.hp + maxi(0, b.value), 1, t.max_hp)
			stat_changed(fight, t, b.stat, b.value)
			return [attach(t, b)]
		"shield":
			var b := make(fight, caster, spell_id, "shield", turns_of(e))
			var of := str(e.get("of", "level"))
			var base := caster.level if of == "level" else t.max_hp
			b.value = maxi(1, FightLife.roll(fight, e) if of == "flat" else base * FightLife.roll(fight, e) / 100)
			FightTriggers.event(fight, caster, ["CS"], t.id, b.value) # P1.13i, gzp.bnaa
			FightTriggers.event(fight, t, FightTriggers.LIFE, caster.id, b.value) # P1.13m: a shield is a life output
			return [attach(t, b)]
		"state":
			var out := remove_state(t, int(e["state"]), fight)
			out.append(add_state(fight, caster, t, e, turns_of(e), spell_id))
			return out
		"unstate":
			return remove_state(t, int(e["state"]), fight)
	return []


## Effects that take buffs away (or reveal, or act on the turn / the cooldowns).
static func remove(fight: Fight, caster: Fighter, t: Fighter, e: Dictionary, kind: String) -> Array:
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
		"shorten": # P1.18, 1075 "Durée des effets : -#1": the target's dispellable buffs end sooner
			# APPROX(P1.18): i18n text only; the buffs that a dispel would remove (dispellable 1), a buff
			# brought to 0 turns ends now
			var n := FightLife.roll(fight, e)
			var ended: Array = []
			for b: Buff in t.buffs.duplicate():
				if b.dispellable == 1 and b.turns > 0 and b.aura == 0:
					b.turns = maxi(0, b.turns - n)
					if b.turns == 0:
						ended.append_array(expire(fight, t, b))
			return ended
		"unbuff":
			var gone: Array = []
			for b: Buff in t.buffs.duplicate():
				var bs := SpellBook.get_spell(b.spell)
				# 1406 (P1.17b, 8): only the buffs of that grade (`rank`: spelllevels.grade, monsters too, P1.18)
				if int(bs.get("origin", -1)) == int(e.get("origin", -2)) and (not e.has("grade") or int(bs.get("rank", 0)) == int(e["grade"])):
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
	var b := make(fight, caster, spell_id, "state", turns)
	b.state = int(s["state"])
	b.state_name_id = int(s.get("state_name_id", 0))
	b.flags = s.get("flags", [])
	FightTriggers.state_changed(fight, t, b.state, true, caster)
	return attach(t, b)


## +/- AP or MP, now (on the current points) and for `duration` turns (buff).
static func resource(fight: Fight, caster: Fighter, t: Fighter, e: Dictionary, spell_id: int) -> Array:
	var kind := str(e["kind"])
	var sign := int(e.get("sign", 1))
	var amount := FightLife.roll(fight, e)
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
		var b := make(fight, caster, spell_id, kind, duration)
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


## spelllevels.maxStack on characteristic buffs (P1.13d): `t` keeps at most `max_stack` - 1
## buffs of the same characteristic from the same spell (any of its levels, `origin`) before a
## new one: the oldest go (Combo: each level replaces the previous one). APPROX(P1.13d): counted
## per spell and characteristic.
static func unstack(t: Fighter, e: Dictionary, sid: int, max_stack: int) -> Array:
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
	var b := make(fight, caster, sid, "delay", int(e["delay"]))
	b.dispellable = int(e.get("dispellable", 1))
	b.effect = e.duplicate()
	b.effect.erase("delay")
	b.value = max_stack
	return attach(t, b)


## Buff `b` of `t` ran out: removed, and a delayed effect lands.
static func expire(fight: Fight, t: Fighter, b: Buff) -> Array:
	var out := remove_buff(t, b, fight)
	var caster: Fighter = fight.fighters.get(b.caster)
	if b.kind == "delay" and t.alive and caster != null and caster.alive:
		out.append_array(FightEffects.land(fight, caster, t, b.effect, t.cell, b.spell, b.value))
	return out


static func make(fight: Fight, caster: Fighter, spell_id: int, kind: String, turns: int) -> Buff:
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


static func attach(t: Fighter, b: Buff) -> Dictionary:
	t.buffs.append(b)
	return {"kind": "buff", "target": t.id, "buff": b.to_dict()}
