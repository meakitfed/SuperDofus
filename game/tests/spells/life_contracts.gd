## Contracts of the effects on life (damage, steals, heals, kills). The arena's fighters have no
## characteristic and no resistance, so a hit takes exactly its dice (forced to the min or the
## max), less the area decrease (FightRules.efficiency, P1.13j); a heal gives exactly its dice.
class_name LifeContracts
extends RefCounted

## what a fired trigger hands its effect (Fight.trigger_from / trigger_amount): `far` hit for 100
const TRIGGER_AMOUNT := 100
## the max HP every fighter lost to erosion before an effect hurting by eroded life
const ERODED := 1000


static func register(table: Dictionary) -> void:
	table["damage"] = Damage.new()
	table["steal"] = Steal.new()
	table["heal"] = Heal.new()
	table["heal_pct"] = HealPct.new()
	table["transfer_hp"] = TransferHp.new()
	table["kill"] = Kill.new()
	table["reflect"] = Reflect.new()
	table["heal_attackers"] = HealAttackers.new()
	table["splash_taken"] = SplashTaken.new()
	table["splash_heal"] = SplashHeal.new()
	table["heal_dealt"] = HealDealt.new()


## The area decrease (%) of the effect on `t`: damage, steals and heals of the cast itself.
static func decrease(p: EffectProbe, t: Fighter) -> int:
	if p.kind() not in FightEffects.ZONE_DECREASE or int(p.effect.get("duration", 0)) != 0:
		return 0
	return FightRules.efficiency(p.effect.get("area", p.spell.get("area", {})), p.center, p.me().cell, p.was(t).cell)


static func decreased(v: int, pct: int) -> int:
	return floori(v * (100 - pct) / 100.0)


class Damage extends EffectContract:
	func prepare(p: EffectProbe) -> void:
		if p.effect.has("caster_missing_pct"):
			p.me().hp = p.me().max_hp / 2
		if p.effect.has("per_ap"):
			for f: Fighter in p.arena.fighters():
				f.ap_spent = int(p.effect["per_ap"][0]) * 2
		if p.effect.has("eroded_pct"): # everyone lost ERODED max HP to erosion
			for f: Fighter in p.arena.fighters():
				f.eroded = LifeContracts.ERODED
				f.max_hp -= LifeContracts.ERODED
				f.hp = f.max_hp

	func check(p: EffectProbe, t: Fighter) -> void:
		if int(p.effect.get("duration", 0)) > 0:
			_poison(p, t)
			return
		var base := _base(p, t)
		var pct := LifeContracts.decrease(p, t)
		var lo := LifeContracts.decreased(base[0], pct)
		var hi := LifeContracts.decreased(base[1], pct)
		p.expect(p.in_range(p.hp_lost(t), lo, hi), t, "%s damage: lost %d HP, expected %s" % [
				p.effect.get("element", ""), p.hp_lost(t), str(lo) if lo == hi else "%d..%d" % [lo, hi]])
		_element(p, t)

	## The base of the hit [lo, hi] (FightLife.base): the forced dice, or its % variants.
	func _base(p: EffectProbe, t: Fighter) -> Array:
		var e := p.effect
		var d := p.dice()
		var me := p.was(p.me())
		if e.has("caster_hp_pct"): # 89 "#1 à #2% PV du lanceur"
			return [me.hp * d[0] / 100, me.hp * d[1] / 100]
		if e.has("caster_missing_pct"): # 279 "% PV manquants du lanceur"
			return [(me.max_hp - me.hp) * d[0] / 100, (me.max_hp - me.hp) * d[1] / 100]
		if e.has("mp_left"): # 1012-1016 "(% PM restants)": the target's MP are all there
			return d
		if e.has("eroded_pct"): # 1118 / 1092 "#1 à #2% PV érodés du lanceur / de la cible"
			return [LifeContracts.ERODED * d[0] / 100, LifeContracts.ERODED * d[1] / 100]
		if e.has("hp_pct"): # 1071 "#1% PV de la cible"
			return [p.was(t).hp * int(e["hp_pct"]) / 100, p.was(t).hp * int(e["hp_pct"]) / 100]
		if e.has("per_ap"): # 1132: 2 x per_ap[0] AP used
			return [int(e["per_ap"][1]) * 2, int(e["per_ap"][1]) * 2]
		return [p.forced(), p.forced()]

	func _element(p: EffectProbe, t: Fighter) -> void:
		var want := str(p.effect.get("element", "neutral"))
		if want in ["best", "worst"]: # no characteristic: the first of the tie order
			want = "earth"
		for d: Dictionary in p.outputs(t, "damage"):
			p.expect(str(d["element"]) == want, t, "damage element %s, expected %s" % [d["element"], want])

	## A damage effect lasting turns is a poison: nothing now, its dice at each tick.
	func _poison(p: EffectProbe, t: Fighter) -> void:
		p.expect(p.hp_lost(t) == 0, t, "a poison hurt at once (%d HP)" % p.hp_lost(t))
		var b := one_buff(p, t, "poison")
		if b == null:
			return
		p.expect(b.turns == int(p.effect["duration"]), t, "poison lasts %d turns, expected %d" % [b.turns, p.effect["duration"]])
		var hp := t.hp
		FightLife.poison(p.arena.fight, t, b)
		var d := p.dice()
		p.expect(p.in_range(hp - t.hp, d[0], d[1]), t, "poison tick took %d HP, expected %d..%d" % [hp - t.hp, d[0], d[1]])


## The caster heals half of what each target lost (in its own area too, it hurts itself first).
class Steal extends Damage:
	func prepare(p: EffectProbe) -> void:
		p.me().hp = p.me().max_hp / 2
		p.may_change[p.me().id] = true

	func check(p: EffectProbe, t: Fighter) -> void:
		if t != p.me():
			super.check(p, t)

	func check_cast(p: EffectProbe) -> void:
		if p.is_target(p.me()):
			return
		var want := 0
		for t: Fighter in p.oracle.fighters:
			want += p.hp_lost(t) / 2
		p.expect(-p.hp_lost(p.me()) == want, p.me(), "steal healed the caster %d, expected half the damage: %d" % [-p.hp_lost(p.me()), want])


class Heal extends EffectContract:
	func prepare(p: EffectProbe) -> void:
		p.wound_everyone()

	func check(p: EffectProbe, t: Fighter) -> void:
		var want := LifeContracts.decreased(p.forced(), LifeContracts.decrease(p, t))
		p.expect(-p.hp_lost(t) == want, t, "healed %d, expected %d" % [-p.hp_lost(t), want])


class HealPct extends EffectContract:
	func prepare(p: EffectProbe) -> void:
		p.wound_everyone()

	func check(p: EffectProbe, t: Fighter) -> void:
		var d := p.dice()
		var m := p.was(t).max_hp
		var missing := m - p.was(t).hp
		p.expect(p.in_range(-p.hp_lost(t), mini(m * d[0] / 100, missing), mini(m * d[1] / 100, missing)), t,
				"healed %d, expected %d..%d %% of %d" % [-p.hp_lost(t), d[0], d[1], m])


## 90 "Transfère #1 à #2% des PV": the caster gives part of its life to the target.
class TransferHp extends EffectContract:
	func prepare(p: EffectProbe) -> void:
		p.wound_everyone()
		p.me().hp = p.me().max_hp
		p.may_change[p.me().id] = true

	func check(p: EffectProbe, t: Fighter) -> void:
		if t == p.me():
			return
		var d := p.dice()
		p.expect(p.in_range(-p.hp_lost(t), 1, p.was(p.me()).hp * d[1] / 100), t, "received %d HP" % -p.hp_lost(t))

	func check_cast(p: EffectProbe) -> void:
		var given := 0
		for t: Fighter in p.oracle.fighters:
			if t != p.me():
				given -= p.hp_lost(t)
		# a target healed to the full does not take all it is given
		p.expect(p.hp_lost(p.me()) >= given and (given > 0) == (p.hp_lost(p.me()) > 0), p.me(),
				"gave %d HP, its targets got %d" % [p.hp_lost(p.me()), given])


class Kill extends EffectContract:
	func check(p: EffectProbe, t: Fighter) -> void:
		p.expect(not t.alive, t, "still alive")


## A trigger's effect (FightTriggers.fire sets these): `far` hit the holder for TRIGGER_AMOUNT.
class Fired extends EffectContract:
	func prepare(p: EffectProbe) -> void:
		var far := p.arena.at("far")
		far.hp = far.max_hp / 2
		p.arena.fight.trigger_from = far.id
		p.arena.fight.trigger_amount = LifeContracts.TRIGGER_AMOUNT
		p.may_change[far.id] = true


## 107 / 220: the attacker takes the effect's dice back (APPROX(P1.13o) flat, FightEffects).
class Reflect extends Fired:
	func check_cast(p: EffectProbe) -> void:
		var far := p.arena.at("far")
		if p.oracle.fighters.is_empty() or p.is_target(far):
			return
		var d := p.dice()
		p.expect(p.in_range(p.hp_lost(far), d[0], d[1]), far, "reflected %d, expected %d..%d" % [p.hp_lost(far), d[0], d[1]])


## 786: the attacker heals pct % of its hit, once per holder.
class HealAttackers extends Fired:
	func check_cast(p: EffectProbe) -> void:
		var far := p.arena.at("far")
		if p.oracle.fighters.is_empty():
			return
		var want := LifeContracts.TRIGGER_AMOUNT * int(p.effect.get("pct", 0)) / 100 * p.oracle.fighters.size()
		p.expect(-p.hp_lost(far) == want, far, "attacker healed %d, expected %d" % [-p.hp_lost(far), want])


## 1223 "#1 à #2% des dommages finaux subis".
class SplashTaken extends Fired:
	func check(p: EffectProbe, t: Fighter) -> void:
		var d := p.dice()
		var a := LifeContracts.TRIGGER_AMOUNT
		p.expect(p.in_range(p.hp_lost(t), a * d[0] / 100, a * d[1] / 100), t, "splash took %d HP" % p.hp_lost(t))


## 2020 "Soin : #1 à #2% des dommages subis".
class SplashHeal extends Fired:
	func prepare(p: EffectProbe) -> void:
		super.prepare(p)
		p.wound_everyone()

	func check(p: EffectProbe, t: Fighter) -> void:
		var d := p.dice()
		var a := LifeContracts.TRIGGER_AMOUNT
		p.expect(p.in_range(-p.hp_lost(t), a * d[0] / 100, a * d[1] / 100), t, "splash healed %d" % -p.hp_lost(t))


## 2973 "Soin : #1 à #2% des dommages occasionnés": nothing was dealt by an effect cast alone
## (the whole spell and SpellCases see it heal).
class HealDealt extends EffectContract:
	func check(p: EffectProbe, t: Fighter) -> void:
		p.expect(p.hp_lost(t) == 0, t, "changed life with nothing dealt")
