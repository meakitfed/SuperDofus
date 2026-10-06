## The swords of a fight on the map (P3.04b): the `actor_add{kind: "fight"}` the sim sends where a
## group was attacked. Crossed swords with the number of fighters of each team; a click opens the
## menu "Rejoindre" (placement only, team 0) / "Regarder". It shows public information only
## (teams, phase, options); the sim decides whether joining or watching is allowed.
## Drawn with the UI palette (no Dofus texture is needed for two crossed blades).
class_name FightSwords
extends Node2D

## the sprite box under the click (the swords stand on their cell)
const BOX := Rect2(Vector2(-26, -58), Vector2(52, 64))

var fight_id := 0
var teams: Array = [0, 0]
var phase := "placement"
var options := {}


func setup(a: Dictionary) -> void:
	fight_id = int(a["id"])
	teams = (a.get("teams", [0, 0]) as Array).map(func(x: Variant) -> int: return int(x)) # float after JSON
	phase = str(a.get("phase", "placement"))
	options = a.get("options", {})
	position = MapGeometry.to_screen(int(a["cell"]))
	var text := "%d  vs  %d" % [teams[0], teams[1]]
	OtherPlayers.add_tag(self, text, UiStyle.GOLD, -78.0)
	queue_redraw()


func update(_now: int) -> void:
	pass # static: the sim re-sends the actor when it changes


func contains(p: Vector2) -> bool:
	return Rect2(position + BOX.position, BOX.size).has_point(p)


func can_join() -> bool:
	return phase == "placement" and not bool(options.get("locked", false))


func can_watch() -> bool:
	return not bool(options.get("secret", false))


func tooltip() -> String:
	return "Combat : %d contre %d (%s)" % [teams[0], teams[1], "placement" if phase == "placement" else "en cours"]


## The click menu: join the players' team during the placement, or watch.
func menu(session: ClientSession, at: Vector2) -> void:
	var id := fight_id
	ContextMenu.popup(session, at, tooltip(), [
		["Rejoindre", func() -> void: session.backend.send(ProtocolWatch.join(id, 0)), can_join()],
		["Regarder", func() -> void: session.backend.send(ProtocolWatch.spectate(id)), can_watch()]])


func _draw() -> void:
	var blade := UiStyle.TEXT
	for s in [-1.0, 1.0]:
		var tip := Vector2(22.0 * s, -52.0)
		var hilt := Vector2(-16.0 * s, -8.0)
		draw_line(hilt, tip, Color.BLACK, 7.0)
		draw_line(hilt, tip, blade, 4.0)
		var guard := hilt.lerp(tip, 0.25)
		var n := (tip - hilt).orthogonal().normalized() * 8.0
		draw_line(guard - n, guard + n, Color.BLACK, 6.0)
		draw_line(guard - n, guard + n, UiStyle.GOLD, 3.0)
	draw_circle(Vector2(0, -30), 3.0, UiStyle.GOLD)
	var col: Color = FightView.TEAM_COLORS[0]
	draw_circle(Vector2(-18, 2), 4.0, col)
	draw_circle(Vector2(18, 2), 4.0, FightView.TEAM_COLORS[1])
