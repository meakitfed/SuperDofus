## What one effect kind must do, checked on an EffectProbe (one effect cast alone in the
## SpellArena). Subclasses (LifeContracts, BuffContracts, ...) override what they need:
##   aim:     where the spell goes: TARGET (the fighter cells, the first one the effect touches),
##            FREE (an empty cell: summons, teleports), CELL (the caster's own cell for a spell
##            cast on itself, else an empty one: marks), ADJACENT (a fighter next to the caster:
##            carry);
##   prepare: sets the arena up before the cast (wounds for heals, a state to remove...);
##   check:   each fighter the effect should touch (TargetOracle);
##   check_cast: once, after the per-target checks (the caster's side, new fighters, marks);
##   strict:  false when the effect may change fighters outside its targets (sub-spells).
## Every fighter neither targeted nor allowed (EffectProbe.may_change) must stay untouched.
class_name EffectContract
extends RefCounted

enum Aim { TARGET, FREE, CELL, ADJACENT }


func aim() -> Aim:
	return Aim.TARGET


func prepare(_p: EffectProbe) -> void:
	pass


func check(_p: EffectProbe, _t: Fighter) -> void:
	pass


func check_cast(_p: EffectProbe) -> void:
	pass


func strict(_p: EffectProbe) -> bool:
	return true


## The new buffs of `t` of kind `buff_kind` (and with that `stat` when not "").
static func new_buffs(p: EffectProbe, t: Fighter, buff_kind: String, stat := "") -> Array:
	return FighterSnapshot.new_buffs(p.was(t), t).filter(func(b: Buff) -> bool:
		return b.kind == buff_kind and (stat == "" or b.stat == stat))


## The turns a buff of the effect lasts: its duration, at least 1, or -1 (the whole fight).
static func buff_turns(e: Dictionary) -> int:
	var d := int(e.get("duration", 0))
	return maxi(d, 1) if d >= 0 else -1


## Exactly one new buff of that kind on `t`, else a failure; returns it (or null).
static func one_buff(p: EffectProbe, t: Fighter, buff_kind: String, stat := "") -> Buff:
	var list := new_buffs(p, t, buff_kind, stat)
	p.expect(list.size() == 1, t, "expected one new %s buff%s, got %d" % [buff_kind, " " + stat if stat != "" else "", list.size()])
	return list[0] if list.size() == 1 else null
