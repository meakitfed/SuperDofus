## Fight rules shared by sim (validation) and client (previews: reachable
## cells, spell range, area, line of sight). Dofus conventions: in fight you
## move in 4 directions (the diamond axes = screen diagonals), distances are
## Manhattan on the diamond lattice, fighters and obstacles block movement and
## line of sight.
class_name FightRules
extends RefCounted

const STEPS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]


static func distance(a: int, b: int) -> int:
	var d := MapGeometry.to_iso(b) - MapGeometry.to_iso(a)
	return absi(d.x) + absi(d.y)


static func neighbors4(cell: int) -> Array[int]:
	var out: Array[int] = []
	var p := MapGeometry.to_iso(cell)
	for s in STEPS:
		var n := MapGeometry.from_iso(p + s)
		if n >= 0:
			out.append(n)
	return out


## cell -> MP cost of every cell reachable from `from` with `mp` movement points.
## `occupied`: cellId -> true for cells holding a fighter.
static func reachable(map: MapData, occupied: Dictionary, from: int, mp: int) -> Dictionary:
	var dist := {from: 0}
	var queue: Array[int] = [from]
	while not queue.is_empty():
		var c: int = queue.pop_front()
		if dist[c] >= mp:
			continue
		for n in neighbors4(c):
			if dist.has(n) or not map.is_fight_walkable(n) or occupied.has(n):
				continue
			dist[n] = dist[c] + 1
			queue.append(n)
	return dist


## Shortest 4-direction path within `mp` (both ends included), empty if impossible.
static func path_to(map: MapData, occupied: Dictionary, from: int, to: int, mp: int) -> Array:
	if from == to:
		return []
	var parent := {from: -1}
	var dist := {from: 0}
	var queue: Array[int] = [from]
	while not queue.is_empty():
		var c: int = queue.pop_front()
		if c == to:
			var path: Array = []
			while c != -1:
				path.push_front(c)
				c = parent[c]
			return path
		if dist[c] >= mp:
			continue
		for n in neighbors4(c):
			if parent.has(n) or not map.is_fight_walkable(n) or occupied.has(n):
				continue
			parent[n] = c
			dist[n] = dist[c] + 1
			queue.append(n)
	return []


## Cells a spell's area covers around `center` (cast from `from`, needed by lines); with the
## map, its cells out of sight are left out (zone_in).
static func area(spell: Dictionary, center: int, from := -1, map: MapData = null, occupied := {}) -> Array[int]:
	if map != null:
		return zone_in(map, occupied, spell.get("area", {}), center, from)
	return zone(spell.get("area", {}), center, from)


## zone() on a map (P1.13l): an area with `sight` (zoneDescr.onlyAffectIfInSightLine) keeps only
## the cells in line of sight from its centre. Source: the client's native code, gtb.blnr ->
## gtb.blnw: when one of the effect's zones (grt field 0x19, set by gru.blhb from the zoneDescr)
## has the flag, the list of cells is filtered by the map provider's cells-in-sight from the
## cast cell (MapPoint of the centre), those it does not return are removed.
## APPROX(P1.13l): the provider's line of sight is taken as the cast's (has_los: fighters block).
static func zone_in(map: MapData, occupied: Dictionary, a: Dictionary, center: int, from := -1) -> Array[int]:
	var cells := zone(a, center, from)
	if not bool(a.get("sight", false)) or center < 0:
		return cells
	var out: Array[int] = []
	for c in cells:
		if c == center or has_los(map, occupied, center, c):
			out.append(c)
	return out


## A carried fighter is touched by an area (P1.13l, zoneDescr.includeCarried): the client's
## gtz.nhs leaves a fighter in state 8 "Porté" (gvr.bmcs -> gui.bluz(8)) out of the zone unless
## the zone has the flag (grt field 0x20). It is 1 on every point (spells.py writes
## `with_carried` on the other shapes only).
static func touches_carried(a: Dictionary) -> bool:
	return str(a.get("shape", "point")) == "point" or bool(a.get("with_carried", false))


## Cells of an area {shape, size, min?, length?, max?, stop?} around `center`, cast from `from`.
## Source (P1.13g): the client's native code (GameAssembly.dll, Core.dll method addresses from
## Cpp2IL, decompiled with Ghidra): the factory gru.blgy maps each zone letter
## (Metadata.Enums.SpellZoneShape, docs/client_enums.md) to a class
## Core.Features.Fight.Spells.SpellZones.Behaviors.Shapes.SpellZoneShape*Behavior, whose cells
## are drawn here step by step. `size` = zoneDescr.param1, `min` / `length` / `max` = param2.
##   point P; all a / A (WholeMap); circle C (Circle: `min` <= distance <= `size`), ring O
##   (Circle size, size), outside I (Circle 63, size); cross X, cross_ring Q, diagonal_cross +,
##   diagonal_cross_ring #, star * (Cross: arms of `size` steps along the straight / diagonal / 8
##   directions, cells from step `min`, the centre only for X + * with min 0; a diagonal step moves
##   both coordinates); square G / square_ring W (Square: side 2 * max(size, 1) + 1, W without its
##   diagonals, so without its centre); line L and diagonal_line / (Line: steps `min`..`size`
##   along the direction); tline T and diagonal_tline - (PerpendicularLine); boomerang B; cone V;
##   half_circle U; outside_complex Z (every cell whose Euclidean distance is >= size);
##   checkerboard D (Circle keeping the cells whose distance has the parity of `size`); fork F
##   (three prongs of size + 1 cells); rectangle R (2 * size + 1 wide, `length` + 1 long);
##   from_caster l (LineFromCaster: from `size` cells after the caster, `max` cells, up to the
##   target when `stop` = zoneDescr.isStopAtTarget).
## L and /, T and - are the same class: the direction decides (dir8: straight or diagonal).
## N (Regular) has no geometry in the client (gru.blgy logs an error): a point for spells.py.
## custom ; (P1.13l, `cells` = zoneDescr.cellIds, monster spells only): gru.blhb builds the class
## grx, a set of the listed cells (map cells only), whatever the centre and the caster.
## Line of sight (`sight`) is not drawn here: zone_in.
static func zone(a: Dictionary, center: int, from := -1) -> Array[int]:
	var out: Array[int] = []
	if str(a.get("shape", "")) == "custom":
		for cell in a.get("cells", []):
			if int(cell) >= 0 and int(cell) < MapGeometry.CELL_COUNT and not out.has(int(cell)):
				out.append(int(cell))
		return out
	if center < 0:
		return out
	var size := maxi(int(a.get("size", 0)), 0)
	var lo := maxi(int(a.get("min", 0)), 0)
	var shape := str(a.get("shape", "point"))
	# gru.blgm / grt.blgp: the direction is og.ovk(caster, centre), -1 when not aligned
	var d := dir8(from, center) if from >= 0 else 1
	match shape:
		"all":
			for cell in MapGeometry.CELL_COUNT:
				out.append(cell)
		"circle", "ring", "outside", "checkerboard":
			_zone_circle(out, shape, center, size, lo)
		"outside_complex":
			var c := _pt(center)
			for cell in MapGeometry.CELL_COUNT:
				var p := _pt(cell) - c
				if p.x * p.x + p.y * p.y >= size * size:
					_add(out, cell)
		"cross", "cross_ring", "diagonal_cross", "diagonal_cross_ring", "star":
			_zone_cross(out, shape, center, size, lo)
		"square", "square_ring":
			var s := maxi(size, 1)
			var c := _pt(center)
			for dx in range(-s, s + 1):
				for dy in range(-s, s + 1):
					if shape == "square_ring" and absi(dx) == absi(dy):
						continue
					_add(out, _at(c + Vector2i(dx, dy)))
		"line", "diagonal_line":
			_zone_line(out, center, d, size, lo)
		"tline", "diagonal_tline", "boomerang":
			_zone_tline(out, shape, center, d, size, lo)
		"cone":
			_zone_cone(out, center, d, size)
		"half_circle":
			_zone_half_circle(out, center, d, size)
		"fork", "rectangle":
			_zone_box(out, shape, a, center, d, size)
		"from_caster":
			_zone_from_caster(out, a, center, from, d, size)
		_:
			out.append(center)
	return out


## Appends `cell` to a zone when it is on the map and not already in.
static func _add(out: Array[int], cell: int) -> void:
	if cell >= 0 and not out.has(cell):
		out.append(cell)


## circle C, ring O, outside I, checkerboard D: the cells at a distance in [m, r] (D: of the parity of `size`).
static func _zone_circle(out: Array[int], shape: String, center: int, size: int, lo: int) -> void:
	var r := size
	var m := lo
	if shape == "ring":
		m = size
	elif shape == "outside":
		r = 63
		m = size
	var c := _pt(center)
	for cell in _cells_within(center, r):
		var p := _pt(cell) - c
		var dist := absi(p.x) + absi(p.y)
		if dist < m or dist > r:
			continue
		if shape == "checkerboard" and (p.x + p.y - r) % 2 != 0:
			continue
		_add(out, cell)


## cross X, cross_ring Q, diagonal_cross +, diagonal_cross_ring #, star *: arms of `size` steps.
static func _zone_cross(out: Array[int], shape: String, center: int, size: int, lo: int) -> void:
	var with_center := shape in ["cross", "diagonal_cross", "star"]
	var m := maxi(lo, 0 if with_center else 1)
	if m == 0:
		_add(out, center)
		m = 1
	var dirs: Array = [1, 3, 5, 7] if shape.begins_with("cross") else [0, 2, 4, 6]
	if shape == "star":
		dirs = [0, 1, 2, 3, 4, 5, 6, 7]
	for dir in dirs:
		var cur := center
		for i in range(1, size + 1):
			cur = _step8(cur, dir)
			if i >= m:
				_add(out, cur)


## line L and diagonal_line /: steps `lo`..`size` along the direction.
static func _zone_line(out: Array[int], center: int, d: int, size: int, lo: int) -> void:
	var cur := center
	for i in lo:
		cur = _step8(cur, d)
	for i in range(lo, size + 1):
		_add(out, cur)
		cur = _step8(cur, d)


## tline T, diagonal_tline -, boomerang B: two arms perpendicular to the direction.
static func _zone_tline(out: Array[int], shape: String, center: int, d: int, size: int, lo: int) -> void:
	var s := maxi(size, 1)
	var i0 := lo
	if lo == 0:
		_add(out, center)
		i0 = 1
	var p := center
	var q := center
	# PerpendicularLine goes up to its size, the Boomerang's arms stop one short
	for i in range(i0, s + 1 if shape != "boomerang" else s):
		p = _step8(p, _rot(d, 2))
		q = _step8(q, _rot(d, -2))
		_add(out, p)
		_add(out, q)
	if shape == "boomerang":  # the tips curl back towards the caster
		_add(out, _step8(p, _rot(d, 3)))
		_add(out, _step8(q, _rot(d, -3)))


## cone V
static func _zone_cone(out: Array[int], center: int, d: int, size: int) -> void:
	var cur := center
	for i in size + 1:
		_add(out, cur)
		var p := cur
		var q := cur
		for j in i:
			p = _step8(p, _rot(d, 2))
			q = _step8(q, _rot(d, -2))
			_add(out, p)
			_add(out, q)
		cur = _step8(cur, d)


## half_circle U
static func _zone_half_circle(out: Array[int], center: int, d: int, size: int) -> void:
	var p := center
	var q := center
	_add(out, center)
	for i in maxi(size, 1):
		p = _step8(p, _rot(d, 3))
		q = _step8(q, _rot(d, -3))
		_add(out, p)
		_add(out, q)


## fork F (three prongs of size + 1 cells) and rectangle R (2 * size + 1 wide, `length` + 1 long).
static func _zone_box(out: Array[int], shape: String, a: Dictionary, center: int, d: int, size: int) -> void:
	var c := _pt(center)
	var sign := -1 if d == 3 or d == 5 else 1
	if shape == "fork":
		_add(out, center)
		var along_x := d == 1 or d == 5
		for i in range(1, size + 2):
			for k in [-i, 0, i]:
				_add(out, _at(c + (Vector2i(sign * i, k) if along_x else Vector2i(k, sign * i))))
		return
	var w := maxi(size * 2 + 1, 1)
	var n := maxi(int(a.get("length", 0)) + 1, 1)
	for s in n:
		for k in w:
			if d == 3 or d == 7:
				_add(out, _at(c + Vector2i(k - w / 2, s * sign)))
			else:
				_add(out, _at(c + Vector2i(s * sign, k - w / 2)))


## from_caster l: from `size` cells after the caster, `max` cells, up to the target when `stop`.
static func _zone_from_caster(out: Array[int], a: Dictionary, center: int, from: int, d: int, size: int) -> void:
	var cur := from if from >= 0 else center
	var last := size + int(a.get("max", 63)) - 1
	if a.get("stop", false) and from >= 0:
		last = mini(last, distance(from, center))
	for i in size:
		cur = _step8(cur, d)
	for i in range(size, last + 1):
		_add(out, cur)
		cur = _step8(cur, d)


## Damage decrease in areas (P1.13j): the % an effect loses on `cell` when its area `a`
## {shape, size, min?, max?, step?, steps?} is centred on `center` and cast from `from`.
## Source: the client's native code. The fight preview (HitContext.bmuv -> gzm.bmyw) multiplies
## each target's damage by (100 - grt.blgw) / 100; grt.blgw asks the area's "malus behaviour"
## built by gru.blgz (step = zoneDescr.damageDecreaseStepPercent, steps =
## maxDamageDecreaseApplyCount): when param1 < 51 (grz.blil),
##   min(100, min(distance - offset, steps) * step)
## with the distance (blim of the class) from the centre:
##   grz (Manhattan, oh.owi): star *, B, D, I, L, T, Z, and C, Q, X, l (offset param2), O (offset
##       param1); gsc (Manhattan / 2: diagonal steps): + (offset param2), #, -, /, U;
##   gse (the larger coordinate difference): G, R, W; gsd (0): a, A;
##   gsa / gsb (cone V, fork F): along the direction og.ovk(caster, centre): |dx| (1 / 5), |dy|
##       (3 / 7), and on a diagonal | |xc - yc| +/- |x - y| | (0 / 4: +, 2 / 6: -) as the client
##       computes it (sic), 0 when not aligned.
## The effect (hs.nfg) needs param1 >= 1 and a shape other than P.
static func efficiency(a: Dictionary, center: int, from: int, cell: int) -> int:
	var step := int(a.get("step", 0))
	var size := int(a.get("size", 0))
	var shape := str(a.get("shape", "point"))
	if step <= 0 or size < 1 or size >= 51 or shape == "point" or center < 0 or cell < 0:
		return 0
	var c := _pt(center)
	var p := _pt(cell)
	var manhattan := absi(p.x - c.x) + absi(p.y - c.y)
	var dist := 0
	var offset := 0
	match shape:
		"star", "boomerang", "checkerboard", "outside", "line", "tline", "outside_complex":
			dist = manhattan
		"circle", "cross_ring", "cross":
			dist = manhattan
			offset = int(a.get("min", 0))
		"from_caster": # gru.blgz passes param2 (its number of cells) as the offset
			dist = manhattan
			offset = int(a.get("max", 0))
		"ring":
			dist = manhattan
			offset = size
		"diagonal_cross":
			dist = manhattan >> 1
			offset = int(a.get("min", 0))
		"diagonal_cross_ring", "diagonal_line", "diagonal_tline", "half_circle":
			dist = manhattan >> 1
		"square", "rectangle", "square_ring":
			dist = maxi(absi(p.x - c.x), absi(p.y - c.y))
		"cone", "fork":
			match dir8(from, center) if from >= 0 else 1:
				1, 5:
					dist = absi(c.x - p.x)
				3, 7:
					dist = absi(c.y - p.y)
				0, 4:
					dist = absi(absi(c.x - c.y) + absi(p.x - p.y))
				2, 6:
					dist = absi(absi(c.x - c.y) - absi(p.x - p.y))
		_: # all (gsd), shapes without a malus behaviour
			return 0
	var n := mini(maxi(dist, 0) - offset, int(a.get("steps", 0)))
	return mini(n * step, 100)


## Cells at most `r` steps from `center` (all of them when `r` is large).
static func _cells_within(center: int, r: int) -> Array[int]:
	var out: Array[int] = []
	if r >= 12:
		for cell in MapGeometry.CELL_COUNT:
			out.append(cell)
		return out
	var c := _pt(center)
	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			var cell := _at(c + Vector2i(dx, dy))
			if cell >= 0:
				out.append(cell)
	return out


## The client's map coordinates (Core.PathFinding.WorldData.MapPoint, oh.owg / oh.owh:
## x = col + floor((row + 1) / 2), y = col - floor(row / 2)): our iso coords with y flipped.
static func _pt(cell: int) -> Vector2i:
	var p := MapGeometry.to_iso(cell)
	return Vector2i(p.x, -p.y)


static func _at(v: Vector2i) -> int:
	return MapGeometry.from_iso(Vector2i(v.x, -v.y))


## The client's 8 directions (og.ovl), in map coordinates: odd = one coordinate changes
## (neighbouring cells), even = both change (a diagonal step, 2 cells away).
const DIRS8: Array[Vector2i] = [Vector2i(1, 1), Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
		Vector2i(-1, -1), Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1)]


## og.ovk: the direction from `from` to `to` when they are aligned (straight: og.ovd, the same
## cell gives 1; diagonal: og.ova), -1 otherwise.
static func dir8(from: int, to: int) -> int:
	var v := _pt(to) - _pt(from)
	if v.y == 0:
		return 1 if v.x >= 0 else 5
	if v.x == 0:
		return 7 if v.y >= 0 else 3
	if v.x == -v.y:
		return 2 if v.x >= 0 else 6
	if v.x == v.y:
		return 0 if v.x >= 0 else 4
	return -1


## og.ovt: `d` turned by `n` eighths (-1 turns too: (d + n) mod 8).
static func _rot(d: int, n: int) -> int:
	return posmod(d + n, 8)


## oh.owq: the next cell along direction `d`, -1 outside the map or without a direction.
static func _step8(cell: int, d: int) -> int:
	if cell < 0 or d < 0:
		return -1
	return _at(_pt(cell) + DIRS8[d])


## Unit step along the main diamond axis from `from` towards `to` (ZERO if same cell).
static func direction(from: int, to: int) -> Vector2i:
	var d := MapGeometry.to_iso(to) - MapGeometry.to_iso(from)
	if d == Vector2i.ZERO:
		return d
	if absi(d.x) >= absi(d.y):
		return Vector2i(signi(d.x), 0)
	return Vector2i(0, signi(d.y))


## Next cell from `cell` one step along `dir`, -1 outside the map.
static func step(cell: int, dir: Vector2i) -> int:
	return MapGeometry.from_iso(MapGeometry.to_iso(cell) + dir)


## Carry (P1.12, sim Carry): spellstates 3 "Porteur" and 8 "Porté".
const CARRIER_STATE := 3
const CARRIED_STATE := 8


## The spell as a caster in `states` casts it: a carrier's throw lands on a free
## cell, and Karcham / Chamrak reach `carry_range` farther ("La portée maximale du
## sort est augmentée lorsque le lanceur porte une cible", spell description).
static func for_caster(spell: Dictionary, states: Array) -> Dictionary:
	if not states.has(CARRIER_STATE):
		return spell
	var throws := (spell.get("effects", []) as Array).any(func(e: Dictionary) -> bool: return str(e.get("kind", "")) == "throw")
	if not throws and int(spell.get("carry_range", 0)) == 0:
		return spell
	var s := spell.duplicate()
	if throws:
		s["need_free_cell"] = true
		s["need_taken_cell"] = false
	var r: Array = spell.get("range", [1, 1])
	s["range"] = [int(r[0]), int(r[1]) + int(spell.get("carry_range", 0))]
	return s


## A state that prevents casting (spellstates.preventsSpellCast: Porteur) still lets
## through the spells that need it (statesCriterion "HS=<state>": the throws).
static func needs_state(spell: Dictionary, state: int) -> bool:
	for tok in str(spell.get("criterion", "")).replace("(", "&").replace(")", "&").replace("|", "&").split("&"):
		if tok.strip_edges() == "HS=%d" % state:
			return true
	return false


## Dofus spell criterion on the caster's states: "HS=498", "HS!8", combined with
## & and | and parentheses. Unknown terms (level, items...) count as true.
static func criterion_ok(criterion: String, states: Array) -> bool:
	if criterion.strip_edges() == "":
		return true
	var tokens: Array[String] = []
	var cur := ""
	for ch in criterion:
		if ch in "&|()":
			if cur.strip_edges() != "":
				tokens.append(cur.strip_edges())
			tokens.append(ch)
			cur = ""
		else:
			cur += ch
	if cur.strip_edges() != "":
		tokens.append(cur.strip_edges())
	var pos := [0]
	return _crit_or(tokens, pos, states)


static func _crit_or(t: Array[String], pos: Array, states: Array) -> bool:
	var v := _crit_and(t, pos, states)
	while pos[0] < t.size() and t[pos[0]] == "|":
		pos[0] += 1
		v = _crit_and(t, pos, states) or v
	return v


static func _crit_and(t: Array[String], pos: Array, states: Array) -> bool:
	var v := _crit_term(t, pos, states)
	while pos[0] < t.size() and t[pos[0]] == "&":
		pos[0] += 1
		v = _crit_term(t, pos, states) and v
	return v


static func _crit_term(t: Array[String], pos: Array, states: Array) -> bool:
	if pos[0] >= t.size():
		return true
	var tok := t[pos[0]]
	pos[0] += 1
	if tok == "(":
		var v := _crit_or(t, pos, states)
		if pos[0] < t.size() and t[pos[0]] == ")":
			pos[0] += 1
		return v
	if tok.begins_with("HS") and tok.length() > 3 and tok.substr(3).is_valid_int():
		var has := states.has(int(tok.substr(3)))
		return has if tok[2] == "=" else not has
	return true


## Line of sight between two cell centres: no cell strictly between them may
## block sight (walls, trees: MapData.los_blocked; holes do not) or hold a fighter.
static func has_los(map: MapData, occupied: Dictionary, from: int, to: int) -> bool:
	var a := Vector2(MapGeometry.to_iso(from))
	var b := Vector2(MapGeometry.to_iso(to))
	var n := int(ceil(a.distance_to(b) * 3.0))
	for i in range(1, n):
		var p := a.lerp(b, float(i) / n)
		# a point exactly between cells touches both: only block on clear hits
		var c := MapGeometry.from_iso(Vector2i(roundi(p.x), roundi(p.y)))
		if c < 0 or c == from or c == to:
			continue
		if absf(p.x - roundf(p.x)) > 0.45 and absf(p.y - roundf(p.y)) > 0.45:
			continue
		if map.blocks_los(c) or occupied.has(c):
			return false
	return true


## Cells a spell can target from `from` (range + line of sight).
static func targetable(map: MapData, occupied: Dictionary, spell: Dictionary, from: int, range_bonus := 0) -> Array[int]:
	var out: Array[int] = []
	var p := MapGeometry.to_iso(from)
	var max_r := max_range(spell, range_bonus)
	for dx in range(-max_r, max_r + 1):
		for dy in range(-max_r, max_r + 1):
			var c := MapGeometry.from_iso(p + Vector2i(dx, dy))
			if c >= 0 and cast_error(map, occupied, spell, from, c, 99, range_bonus) == "":
				out.append(c)
	return out


## "" if `spell` can be cast from `from` on `target` with `ap` action points,
## otherwise the reason.
## Max range with the caster's range bonus (only for "range_boost" spells), never below min range.
static func max_range(spell: Dictionary, range_bonus := 0) -> int:
	var r: Array = spell.get("range", [1, 1])
	var bonus := range_bonus if bool(spell.get("range_boost", false)) else 0
	return maxi(int(r[0]), int(r[1]) + bonus)


static func cast_error(map: MapData, occupied: Dictionary, spell: Dictionary, from: int, target: int, ap: int, range_bonus := 0) -> String:
	if spell.is_empty():
		return Protocol.E_UNKNOWN_SPELL
	if int(spell.get("ap", 0)) > ap:
		return Protocol.E_NOT_ENOUGH_AP
	if not map.is_fight_walkable(target):
		return Protocol.E_BAD_CELL
	var r: Array = spell.get("range", [1, 1])
	var d := distance(from, target)
	if d < int(r[0]) or d > max_range(spell, range_bonus):
		return Protocol.E_OUT_OF_RANGE
	if bool(spell.get("in_line", false)):
		var d2 := MapGeometry.to_iso(target) - MapGeometry.to_iso(from)
		if d2.x != 0 and d2.y != 0:
			return Protocol.E_NOT_IN_LINE
	if bool(spell.get("need_free_cell", false)) and (occupied.has(target) or target == from):
		return Protocol.E_CELL_NOT_FREE
	if bool(spell.get("need_taken_cell", false)) and not occupied.has(target) and target != from:
		return Protocol.E_NEEDS_TARGET
	if bool(spell.get("los", true)) and not has_los(map, occupied, from, target):
		return Protocol.E_NO_LOS
	return ""
