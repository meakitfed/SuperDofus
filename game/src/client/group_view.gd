## A monster group: the leader follows the game's movement, followers are purely
## visual (as in Dofus): each stands on a free cell around the leader and walks
## there with a small delay whenever the leader moves.
class_name GroupView
extends Node2D

const FOLLOW_DELAY_MS := 180

var members: Array[ActorView] = []
var _finder: MapPathfinder


func setup(looks: Array, cell: int, dir: int, finder: MapPathfinder) -> void:
	y_sort_enabled = true # members are sorted together with the other actors
	_finder = finder
	var spots := _spots_around(cell, looks.size() - 1)
	for i in looks.size():
		var v := ActorView.new()
		add_child(v)
		v.setup(str(looks[i]), cell if i == 0 else spots[i - 1], dir)
		members.append(v)


func leader() -> ActorView:
	return members[0]


## group_alert: a "!" over the leader (Dofus shows a sign before an aggression).
func show_alert() -> void:
	var l := UiStyle.label("!", UiStyle.BAD, 34)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 8)
	l.position = Vector2(-8, -150)
	leader().add_child(l)
	get_tree().create_timer(3.0).timeout.connect(l.queue_free)


func set_move(path: Array, t0: int, run: bool, now: int) -> void:
	leader().set_move(path, t0, run)
	var spots := _spots_around(path[-1], members.size() - 1)
	for i in range(1, members.size()):
		members[i].walk_to(spots[i - 1], now, _finder, FOLLOW_DELAY_MS * i)


func update(now: int) -> void:
	for m in members:
		m.update(now)


## Up to `count` walkable cells around `center` (closest first); repeats the
## center when the area is too crowded.
func _spots_around(center: int, count: int) -> Array[int]:
	var out: Array[int] = []
	var ring := MapGeometry.neighbors(center)
	ring.sort_custom(func(a: int, b: int) -> bool:
		return MapGeometry.to_screen(a).distance_to(MapGeometry.to_screen(center)) < MapGeometry.to_screen(b).distance_to(MapGeometry.to_screen(center)))
	for c in ring:
		if out.size() >= count:
			break
		if _finder.map.is_walkable(c):
			out.append(c)
	while out.size() < count:
		out.append(center)
	return out
