## Contracts of the effects that leave something on a fighter: characteristics, AP / MP, shields,
## states, spell reflectors, the passive trigger buffs (multipliers, interceptions, shares), and
## the two wrappers every kind can wear: `on` (a trigger buff) and `delay` (a delay buff).
class_name BuffContracts
extends RefCounted


static func register(table: Dictionary) -> void:
	table["stat"] = Stat.new()
	table["steal_stat"] = StealStat.new()
	table["ap"] = Points.new()
	table["mp"] = Points.new()
	table["shield"] = Shield.new()
	table["state"] = State.new()
	table["unstate"] = Unstate.new()
	table["spell_reflect"] = SpellReflect.new()
	table["taken"] = Multiplier.new()
	table["healed"] = Multiplier.new()
	table["intercept"] = Intercept.new()
	table["share"] = Passive.new()


class Stat extends EffectContract:
	func check(p: EffectProbe, t: Fighter) -> void:
		var stat := str(p.effect.get("stat", ""))
		var b := one_buff(p, t, "stat", stat)
		if b == null:
			return
		var d := p.dice()
		var sign := int(p.effect.get("sign", 1))
		var lo := int(d[0]) * sign
		var hi := int(d[1]) * sign
		if bool(p.effect.get("pct", false)): # 1078 "#1% Vitalité": of the target's max life
			lo = p.was(t).max_hp * lo / 100
			hi = p.was(t).max_hp * hi / 100
		p.expect(p.in_range(b.value, lo, hi), t, "%s %+d, expected %d..%d" % [stat, b.value, lo, hi])
		p.expect(b.turns == buff_turns(p.effect), t, "%s lasts %d turns, expected %d" % [stat, b.turns, buff_turns(p.effect)])
		if stat == "vitality":
			p.expect(t.max_hp - p.was(t).max_hp == b.value, t, "vitality %+d moved max HP by %d" % [b.value, t.max_hp - p.was(t).max_hp])


## 320 / 266-271 "Vole #1 ...": the target loses it, the caster wins as much.
class StealStat extends EffectContract:
	func prepare(p: EffectProbe) -> void:
		p.may_change[p.me().id] = true

	func check(p: EffectProbe, t: Fighter) -> void:
		if t == p.me():
			return
		var stat := str(p.effect.get("stat", ""))
		var lost := one_buff(p, t, "stat", stat)
		if lost == null:
			return
		var d := p.dice()
		p.expect(p.in_range(-lost.value, d[0], d[1]), t, "lost %d %s, expected %d..%d" % [-lost.value, stat, d[0], d[1]])
		var won := new_buffs(p, p.me(), "stat", stat).filter(func(b: Buff) -> bool: return b.value == -lost.value)
		p.expect(won.size() >= 1, p.me(), "did not win the %d %s stolen" % [-lost.value, stat])


## ap / mp: + or - now (on the current points) and for `duration` turns. A dodgeable removal may
## lose 0 to all of its dice (the dodge rolls, FightBuffs.resource).
class Points extends EffectContract:
	func prepare(p: EffectProbe) -> void:
		if bool(p.effect.get("steal", false)):
			p.may_change[p.me().id] = true

	func check(p: EffectProbe, t: Fighter) -> void:
		var res := p.kind()
		var had := p.was(t).ap if res == "ap" else p.was(t).mp
		var now := t.ap if res == "ap" else t.mp
		var d := p.dice()
		if bool(p.effect.get("steal", false)) and t == p.me():
			# H.04c, a steal whose area holds its caster (Macro-Ondes): the caster loses its own share of the
			# dice (a dodgeable removal may lose nothing) and wins what the others lost, in the same cast
			var won := 0
			for f: Fighter in p.oracle.fighters:
				if f != t:
					won += (p.was(f).ap - f.ap) if res == "ap" else (p.was(f).mp - f.mp)
			var own := mini(d[1], had)
			p.expect(p.in_range(now - had, won - own, won), t, "%s %+d, expected %d..%d (wins %d)" % [res, now - had, won - own, won, won])
			return
		var sign := int(p.effect.get("sign", 1))
		var lo := int(d[0])
		var hi := int(d[1])
		if sign < 0:
			lo = -mini(d[0], had) if not bool(p.effect.get("dodge", false)) else 0
			hi = -mini(d[1], had)
		p.expect(p.in_range(now - had, lo, hi), t, "%s %+d, expected %d..%d" % [res, now - had, lo, hi])
		# a lasting change: a buff of what was lost (dodgeable), else of the whole dice (-100 MP: none next turn)
		var buffs := new_buffs(p, t, res)
		if int(p.effect.get("duration", 0)) != 0 and now != had:
			var dodged := sign < 0 and bool(p.effect.get("dodge", false))
			var ok := buffs.size() == 1 and (((buffs[0] as Buff).value == now - had) if dodged
					else p.in_range((buffs[0] as Buff).value, int(d[0]) * sign, int(d[1]) * sign))
			p.expect(ok, t, "no %s buff for the %+d" % [res, now - had])

	func check_cast(p: EffectProbe) -> void:
		if not bool(p.effect.get("steal", false)) or p.is_target(p.me()):
			return
		var res := p.kind()
		var lost := 0
		for t: Fighter in p.oracle.fighters:
			lost += (p.was(t).ap - t.ap) if res == "ap" else (p.was(t).mp - t.mp)
		var won := (p.me().ap - p.was(p.me()).ap) if res == "ap" else (p.me().mp - p.was(p.me()).mp)
		p.expect(won == lost, p.me(), "stole %d %s, its targets lost %d" % [won, res, lost])


## of "level": % of the caster's level; "max_hp": % of the target's max life; "flat": the dice.
class Shield extends EffectContract:
	func check(p: EffectProbe, t: Fighter) -> void:
		var b := one_buff(p, t, "shield")
		if b == null:
			return
		var d := p.dice()
		var of := str(p.effect.get("of", "level"))
		var base := p.me().level if of == "level" else p.was(t).max_hp
		var lo: int = d[0] if of == "flat" else maxi(1, base * d[0] / 100)
		var hi: int = d[1] if of == "flat" else maxi(1, base * d[1] / 100)
		p.expect(p.in_range(b.value, lo, hi), t, "shield %d, expected %d..%d (%s)" % [b.value, lo, hi, of])


class State extends EffectContract:
	func check(p: EffectProbe, t: Fighter) -> void:
		var state := int(p.effect["state"])
		p.expect(t.has_state(state), t, "not in state %d" % state)
		var b := one_buff(p, t, "state")
		if b != null:
			p.expect(b.turns == buff_turns(p.effect), t, "state %d lasts %d turns, expected %d" % [state, b.turns, buff_turns(p.effect)])


class Unstate extends EffectContract:
	func prepare(p: EffectProbe) -> void:
		for f: Fighter in p.arena.fighters():
			if not f.has_state(int(p.effect["state"])):
				p.arena.give_state(f, int(p.effect["state"]))

	func check(p: EffectProbe, t: Fighter) -> void:
		p.expect(not t.has_state(int(p.effect["state"])), t, "still in state %d" % int(p.effect["state"]))


## 106: a reflector of the spells up to grade `level`.
class SpellReflect extends EffectContract:
	func check(p: EffectProbe, t: Fighter) -> void:
		var b := one_buff(p, t, "spell_reflect")
		if b != null:
			p.expect(b.value == int(p.effect.get("level", 0)), t, "reflects up to grade %d, expected %d" % [b.value, p.effect.get("level", 0)])


## The passive kinds only live as trigger buffs (FightTriggers.PASSIVE).
class Passive extends EffectContract:
	func check(p: EffectProbe, t: Fighter) -> void:
		var list := new_buffs(p, t, "trigger").filter(func(b: Buff) -> bool: return str(b.effect.get("kind", "")) == p.kind())
		p.expect(list.size() == 1, t, "expected one %s trigger buff, got %d" % [p.kind(), list.size()])


## 1163 "Dommages subis x#1%" / 1159 "Soins reçus x#1%": a probe hit / heal of 100 is multiplied.
class Multiplier extends Passive:
	func check(p: EffectProbe, t: Fighter) -> void:
		super.check(p, t)
		if not t.alive:
			return
		var want := roundi(100 * int(p.effect.get("pct", 100)) / 100.0)
		if p.kind() == "taken":
			var hits := FightLife.damage(p.arena.fight, p.arena.at("far"), t, "neutral", 100)
			var got := 0
			for h: Dictionary in hits:
				got += int(h["amount"]) + int(h.get("shield", 0))
			p.expect(got == want, t, "a hit of 100 took %d, expected %d" % [got, want])
		else:
			t.hp = maxi(1, t.max_hp - 1000)
			var got := int(FightLife.receive_heal(p.arena.fight, t, 100)["amount"])
			p.expect(got == mini(want, 1000), t, "a heal of 100 gave %d, expected %d" % [got, want])


## 765: the fighter on the spell's target cell (else the caster) takes the holder's hits.
class Intercept extends Passive:
	func check(p: EffectProbe, t: Fighter) -> void:
		super.check(p, t)
		var on := p.arena.fight.fighter_at(p.center)
		var want := on.id if on != null else p.me().id
		for b: Buff in new_buffs(p, t, "trigger"):
			p.expect(b.value == want, t, "intercepted by %d, expected %d" % [b.value, want])


## Any kind with `on`: a trigger buff with its codes, for `turns` (the effect itself is checked
## apart, cast without `on`).
class Trigger extends EffectContract:
	func check(p: EffectProbe, t: Fighter) -> void:
		var list := new_buffs(p, t, "trigger").filter(func(b: Buff) -> bool: return b.effect == p.effect)
		p.expect(list.size() == 1, t, "expected one trigger buff on %s, got %d" % [p.effect.get("on"), list.size()])
		if list.size() == 1:
			var b: Buff = list[0]
			p.expect(b.on == p.effect["on"], t, "trigger codes %s, expected %s" % [b.on, p.effect["on"]])
			p.expect(b.turns == int(p.effect.get("turns", 1)), t, "trigger lasts %d turns, expected %d" % [b.turns, p.effect.get("turns", 1)])

	func strict(p: EffectProbe) -> bool:
		return not bool(p.effect.get("now", false)) # `now`: the effect lands at once too


## Any kind with `delay`: a delay buff for that many of the caster's turns, holding the effect.
class Delay extends EffectContract:
	func check(p: EffectProbe, t: Fighter) -> void:
		var b := one_buff(p, t, "delay")
		if b != null:
			p.expect(b.turns == int(p.effect["delay"]), t, "delay of %d turns, expected %d" % [b.turns, p.effect["delay"]])
			p.expect(str(b.effect.get("kind", "")) == p.kind(), t, "delays %s, expected %s" % [b.effect.get("kind"), p.kind()])
