## One effect of one spell grade, cast alone in a fresh SpellArena: what an EffectContract reads
## (the arena, the effect, where it was aimed, who it should touch, the fighters before) and where
## it writes its failures.
class_name EffectProbe
extends RefCounted

## "min" / "max": the caster's rolls are forced there (stats 781 roll_min / 782 roll_max)
var roll := "max"
var arena: SpellArena
var spell: Dictionary
var effect: Dictionary
var center := -1
var oracle: TargetOracle
var before := {} # fighter id -> FighterSnapshot
var out: Array = []
var errors: PackedStringArray = []
## fighters outside the targets this effect may change all the same (the caster of a steal...)
var may_change := {}
## what a contract's prepare leaves for its checks
var data := {}


func _init(p_spell: Dictionary, p_effect: Dictionary, p_roll: String) -> void:
	spell = p_spell
	effect = p_effect
	roll = p_roll
	arena = SpellArena.new(int(spell.get("breed", 0)))
	arena.me.stats["roll_" + roll] = 1


func fail(message: String) -> void:
	errors.append(message)


## `ok` or the failure `message`, about fighter `f`.
func expect(ok: bool, f: Fighter, message: String) -> void:
	if not ok:
		fail("%s: %s" % [arena.slot_of(f), message])


func me() -> Fighter:
	return arena.me


func kind() -> String:
	return str(effect.get("kind", ""))


## The effect's dice [min, max].
func dice() -> Array:
	var lo := int(effect.get("min", 0))
	return [lo, maxi(lo, int(effect.get("max", lo)))]


## The value of the caster's own roll (damage, steals, heals: forced by `roll`).
func forced() -> int:
	return dice()[0] if roll == "min" else dice()[1]


func was(f: Fighter) -> FighterSnapshot:
	return before.get(f.id)


func hp_lost(f: Fighter) -> int:
	return was(f).hp - f.hp


func is_target(f: Fighter) -> bool:
	return oracle.fighters.has(f)


## Fighters that joined during the cast (summons, doubles).
func newcomers() -> Array:
	return arena.fighters().filter(func(f: Fighter) -> bool: return not before.has(f.id))


## The effect dicts of the cast about `f` of that kind.
func outputs(f: Fighter, out_kind: String) -> Array:
	return out.filter(func(d: Dictionary) -> bool: return int(d.get("target", -1)) == f.id and str(d.get("kind", "")) == out_kind)


## Lowers every fighter's life to half, to see heals.
func wound_everyone() -> void:
	for f: Fighter in arena.fighters():
		f.hp = f.max_hp / 2


## The value lies in [lo, hi].
func in_range(value: int, lo: int, hi: int) -> bool:
	return value >= mini(lo, hi) and value <= maxi(lo, hi)
