## Travel rules (roadmap P1.08): zaap prices. Shared by the sim (what is
## charged) and the client (prices shown before the trip).
class_name Travel
extends RefCounted

## areas.id of Incarnam
const INCARNAM_AREA := 45


## Price of a zaap trip (source: https://dofuswiki.fandom.com/wiki/Zaap):
## 10 kamas per map of straight-line distance, the integer part of
## sqrt(dx² + dy²) between the two maps' coordinates, divided by 4 when
## leaving from Incarnam.
## APPROX(P1.08): community rule (Dofus 2), prices are server data in Dofus 3.
static func zaap_cost(from: Vector2i, to: Vector2i, from_area := 0) -> int:
	var cost := 10 * int(sqrt(float((to - from).length_squared())))
	return cost / 4 if from_area == INCARNAM_AREA else cost
