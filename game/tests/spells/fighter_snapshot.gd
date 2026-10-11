## A fighter's state frozen at one moment, to compare before / after a spell.
class_name FighterSnapshot
extends RefCounted

var id := 0
var hp := 0
var max_hp := 0
var ap := 0
var mp := 0
var cell := 0
var alive := true
var shield := 0
var states: Array = []
var buffs: Array = [] # Buff ids
var carried_by := -1
var carrying := -1
var pass_turn := false
var cooldowns := {}


static func of(f: Fighter) -> FighterSnapshot:
	var s := FighterSnapshot.new()
	s.id = f.id
	s.hp = f.hp
	s.max_hp = f.max_hp
	s.ap = f.ap
	s.mp = f.mp
	s.cell = f.cell
	s.alive = f.alive
	s.shield = f.shield()
	s.states = f.state_ids()
	s.buffs = f.buffs.map(func(b: Buff) -> int: return b.id)
	s.carried_by = f.carried_by
	s.carrying = f.carrying
	s.pass_turn = f.pass_turn
	s.cooldowns = f.cooldowns.duplicate()
	return s


## The fighter's buffs that `before` did not have.
static func new_buffs(before: FighterSnapshot, f: Fighter) -> Array:
	return f.buffs.filter(func(b: Buff) -> bool: return before == null or not before.buffs.has(b.id))


## What changed, for failure messages ("hp 10000 -> 9980, cell 300 -> 301").
func describe_change(f: Fighter) -> String:
	var parts: PackedStringArray = []
	if f.hp != hp:
		parts.append("hp %d -> %d" % [hp, f.hp])
	if f.cell != cell:
		parts.append("cell %d -> %d" % [cell, f.cell])
	if f.ap != ap:
		parts.append("ap %d -> %d" % [ap, f.ap])
	if f.mp != mp:
		parts.append("mp %d -> %d" % [mp, f.mp])
	if f.alive != alive:
		parts.append("dead" if not f.alive else "revived")
	var added := new_buffs(self, f).map(func(b: Buff) -> String: return b.kind + ("" if b.stat == "" else ":" + b.stat))
	if not added.is_empty():
		parts.append("buffs +%s" % [added])
	return ", ".join(parts) if not parts.is_empty() else "nothing"


## Something visible happened to the fighter (life, cell, AP / MP, buffs, carry).
func changed(f: Fighter) -> bool:
	return f.hp != hp or f.max_hp != max_hp or f.cell != cell or f.ap != ap or f.mp != mp or f.alive != alive \
			or f.carried_by != carried_by or f.carrying != carrying or f.pass_turn != pass_turn \
			or f.buffs.map(func(b: Buff) -> int: return b.id) != buffs or f.cooldowns != cooldowns
