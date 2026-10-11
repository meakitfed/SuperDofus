## The standard fight every spell test plays in: an open board, neutral fighters (no characteristic,
## no resistance, no buff, HP high enough never to die by accident) in one fixed layout around the
## caster, named by slot. Iso offsets from the caster's cell (MapGeometry.to_iso):
##
##          ally_t (2,-1)
##   ally (-1,0)   me (0,0)   . (1,0)   foe (2,0)   . (3,0)   foe_2 (4,0)
##                 free (0,2)           foe_n (2,1)   foe_d (3,1)
##                                                                    far (8,5)
##
## `foe` is the usual target: in line with the caster (lines, cones, pushes) with free cells behind
## it, `foe_n` / `ally_t` its neighbours (circle 1, enemies-only areas spare `ally_t`), `foe_d` its
## diagonal (squares, not circles 1), `foe_2` two cells behind (a push of 2 bumps into it), `far`
## out of every small area, `free` an empty cell (summons, teleports, marks). Characters: me,
## ally, ally_t, foe, foe_d; monsters (not summoned): foe_n, foe_2, far.
class_name SpellArena
extends RefCounted

const CENTER := 300
const HP := 10000
const LEVEL := 100
const SEED := 7
const BUFF_TURNS := 3 # what give_buff lasts
const LAYOUT := {
	"me": {"at": Vector2i(0, 0), "team": 0},
	"ally": {"at": Vector2i(-1, 0), "team": 0},
	"ally_t": {"at": Vector2i(2, -1), "team": 0},
	"foe": {"at": Vector2i(2, 0), "team": 1},
	"foe_n": {"at": Vector2i(2, 1), "team": 1, "monster": 31},
	"foe_d": {"at": Vector2i(3, 1), "team": 1},
	"foe_2": {"at": Vector2i(4, 0), "team": 1, "monster": 31},
	"far": {"at": Vector2i(8, 5), "team": 1, "monster": 31},
}
const FREE := Vector2i(0, 2)

var fight: Fight
var events: Array = []
var slots := {} # slot name -> Fighter
var me: Fighter:
	get:
		return slots["me"]
var foe: Fighter:
	get:
		return slots["foe"]


## `breed`: the caster's class (its spells' masks B / b and Telefrags read it).
func _init(breed := 0) -> void:
	fight = Fight.new(1, MapData.new(), SEED, func(ev: Dictionary) -> void: events.append(ev))
	var id := 1
	for slot: String in LAYOUT:
		var f := Fighter.new()
		f.id = id
		f.name = slot
		f.team = int(LAYOUT[slot]["team"])
		f.cell = cell_at(LAYOUT[slot]["at"])
		f.level = LEVEL
		f.hp = HP
		f.max_hp = HP
		f.monster = int(LAYOUT[slot].get("monster", 0))
		f.ai = f.team == 1
		f.plays = true
		slots[slot] = f
		fight.add_fighter(f)
		id += 1
	me.breed = breed
	fight.start_placement(0)
	fight.begin(0)
	while fight.current() != me: # the caster plays first: its buffs count down on its own turns
		fight.end_turn(0)


static func cell_at(offset: Vector2i) -> int:
	return MapGeometry.from_iso(MapGeometry.to_iso(CENTER) + offset)


func free_cell() -> int:
	return cell_at(FREE)


func at(slot: String) -> Fighter:
	return slots[slot]


## Slot name of `f` ("summon:<id>" for the fighters the spell brought).
func slot_of(f: Fighter) -> String:
	for slot: String in slots:
		if slots[slot] == f:
			return slot
	return "summon:%d" % f.id


func fighters() -> Array:
	return fight.fighters.values()


## Every fighter's state now, by fighter id.
func snapshot() -> Dictionary:
	var out := {}
	for f: Fighter in fighters():
		out[f.id] = FighterSnapshot.of(f)
	return out


## Puts `f` in state `state` for the whole fight, as a spell would (no trigger fires).
func give_state(f: Fighter, state: int, flags: Array = []) -> void:
	var b := Buff.new()
	b.id = fight.next_buff_id()
	b.kind = "state"
	b.state = state
	b.flags = flags
	b.turns = -1
	b.caster = f.id
	f.buffs.append(b)


## Gives `f` a dispellable characteristic buff of spell grade `spell_id`, cast by `caster`.
func give_buff(f: Fighter, spell_id: int, caster: Fighter = null, stat := "probe") -> Buff:
	var b := Buff.new()
	b.id = fight.next_buff_id()
	b.kind = "stat"
	b.stat = stat
	b.value = 1
	b.turns = BUFF_TURNS
	b.caster = (caster if caster != null else me).id
	b.spell = spell_id
	f.buffs.append(b)
	return b


## Casts `spell` on `center` the way Fight.cast does once every check passed (no AP, range or line
## of sight): the effects, then the triggers, deaths and auras they cause. `crit` picks the
## critical effects; `by` the caster (the arena's `me` by default). Returns the effect dicts.
func cast(spell: Dictionary, center: int, crit := false, by: Fighter = null) -> Array:
	var out := FightEffects.apply_spell(fight, by if by != null else me, spell, center, crit)
	out.append_array(FightTriggers.flush(fight))
	out.append_array(fight.handle_deaths())
	out.append_array(FightMarks.auras(fight))
	return out


## Ends turns until `f` starts one (its poisons tick, its glyphs hit...). Returns the turn effects.
func play_until(f: Fighter) -> Array:
	var out: Array = []
	for guard in fight.order.size() * 2:
		events.clear()
		fight.end_turn(0)
		for ev: Dictionary in events:
			out.append_array(ev.get("effects", []))
		if fight.current() == f or fight.result != "":
			break
	return out
