## Contracts of the effects that take something away or act on turns: dispels, unbuffs,
## reveals, turn passes, cooldowns.
class_name RemovalContracts
extends RefCounted

## state of 150 "Invisibilité" (FightTriggers.INVISIBLE_STATE)
const INVISIBLE := 250
const COOLDOWN := 2 # the cooldown every fighter's spell has before a cooldown effect


static func register(table: Dictionary) -> void:
	table["dispel"] = Dispel.new()
	table["unbuff"] = Unbuff.new()
	table["reveal"] = Reveal.new()
	table["pass_turn"] = PassTurn.new()
	table["cooldown"] = Cooldown.new()
	table["shorten"] = Shorten.new()


## 132: every buff with `dispellable` 1 goes; each fighter carries one beforehand.
class Dispel extends EffectContract:
	func prepare(p: EffectProbe) -> void:
		for f: Fighter in p.arena.fighters():
			p.arena.give_buff(f, 0)

	func check(p: EffectProbe, t: Fighter) -> void:
		var left := t.buffs.filter(func(b: Buff) -> bool: return b.dispellable == 1)
		p.expect(left.is_empty(), t, "kept %d dispellable buffs" % left.size())


## 406 / 1406: the buffs of spell `origin` (of grade `grade` for 1406) go; each fighter carries one.
class Unbuff extends EffectContract:
	func prepare(p: EffectProbe) -> void:
		var grade := SpellIndex.grade_of(int(p.effect.get("origin", 0)), int(p.effect.get("grade", 0)))
		if grade == 0:
			return # no one can cast that spell: no buff of it to take away
		for f: Fighter in p.arena.fighters():
			p.arena.give_buff(f, grade)

	func check(p: EffectProbe, t: Fighter) -> void:
		var origin := int(p.effect.get("origin", 0))
		var left := t.buffs.filter(func(b: Buff) -> bool:
			return b.stat == "probe" and int(SpellBook.get_spell(b.spell).get("origin", -1)) == origin)
		p.expect(left.is_empty(), t, "kept the buff of spell %d" % origin)


## 202: the target stops being invisible.
class Reveal extends EffectContract:
	func prepare(p: EffectProbe) -> void:
		for f: Fighter in p.arena.fighters():
			p.arena.give_state(f, RemovalContracts.INVISIBLE, ["invisible"])

	func check(p: EffectProbe, t: Fighter) -> void:
		p.expect(not t.has_flag("invisible"), t, "still invisible")


## 1031: the target's turn ends after the spell (or is skipped).
class PassTurn extends EffectContract:
	func check(p: EffectProbe, t: Fighter) -> void:
		p.expect(t.pass_turn, t, "does not pass its turn")


## 1045 set / 1036 sub / 1035 add: the cooldown of the target's spell `origin`.
class Cooldown extends EffectContract:
	func prepare(p: EffectProbe) -> void:
		var grade := SpellIndex.grade_of(int(p.effect.get("origin", 0)))
		p.data["grade"] = grade
		if grade == 0:
			return # no one can cast that spell
		for f: Fighter in p.arena.fighters():
			f.spells.append(grade)
			f.cooldowns[grade] = RemovalContracts.COOLDOWN

	func check(p: EffectProbe, t: Fighter) -> void:
		var grade := int(p.data["grade"])
		if grade == 0:
			return
		var n := int(p.effect.get("turns", 0))
		var want: int = {"set": n, "sub": maxi(RemovalContracts.COOLDOWN - n, 0), "add": RemovalContracts.COOLDOWN + n}[str(p.effect.get("mode", "set"))]
		var got := int(t.cooldowns.get(grade, 0))
		p.expect(got == want, t, "cooldown %d, expected %d (%s %d)" % [got, want, p.effect.get("mode"), n])


## 1075 "Durée des effets : -#1": the target's dispellable buffs lose that many turns (each fighter
## carries one of BUFF_TURNS beforehand; one brought to 0 ends).
class Shorten extends EffectContract:
	func prepare(p: EffectProbe) -> void:
		for f: Fighter in p.arena.fighters():
			p.arena.give_buff(f, 0)

	func check(p: EffectProbe, t: Fighter) -> void:
		var d := p.dice()
		var left := t.buffs.filter(func(b: Buff) -> bool: return b.stat == "probe")
		var turns: int = (left[0] as Buff).turns if not left.is_empty() else 0
		p.expect(p.in_range(turns, SpellArena.BUFF_TURNS - int(d[1]), SpellArena.BUFF_TURNS - int(d[0])) or (left.is_empty() and int(d[1]) >= SpellArena.BUFF_TURNS), t,
				"buff of %d turns left at %d, expected %d - %d..%d" % [SpellArena.BUFF_TURNS, turns, SpellArena.BUFF_TURNS, d[0], d[1]])
