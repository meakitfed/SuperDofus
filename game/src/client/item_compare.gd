## Compares two items' effects (the comparison block of an item tooltip, the equipment's total bonus)
## without any Node: only numbers and effects.id, the wording stays in UiTooltips.
class_name ItemCompare
extends RefCounted


## The number an effect [effects.id, min, max, value] stands for (a range: its middle).
static func value(e: Array) -> float:
	var lo := int(e[1])
	var hi := int(e[2])
	if hi > lo and lo != 0:
		return (lo + hi) / 2.0
	return float(lo if lo != 0 else hi)


## Per effect id, the sum of the values (an item's effects, or all the worn items'): {id: value}.
static func totals(effect_lists: Array) -> Dictionary:
	var out := {}
	for lines: Array in effect_lists:
		for e: Array in lines:
			out[int(e[0])] = float(out.get(int(e[0]), 0.0)) + value(e)
	return out


## What `candidate` changes against `worn`: [[effect id, delta]] for every effect either has, in the
## order the candidate lists them (then the ones only the worn item has), zero deltas left out.
static func deltas(candidate: Array, worn: Array) -> Array:
	var a := totals([candidate])
	var b := totals([worn])
	var out := []
	var seen := {}
	for e: Array in candidate + worn:
		var id := int(e[0])
		if seen.has(id):
			continue
		seen[id] = true
		var d := float(a.get(id, 0.0)) - float(b.get(id, 0.0))
		if absf(d) > 0.001:
			out.append([id, d])
	return out
