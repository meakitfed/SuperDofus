## Visual sequences of the fight screen played on a FightView (split from it, R.01):
## FX bones, missiles and the carry / throw / drop animations.
class_name FightVisuals
extends RefCounted


## Plays a FX bone ("FX" animation) once at `pos`; returns at its SHOT label or its end.
static func bone_fx(view: FightView, bone: int, pos: Vector2, dir: int, under: bool) -> void:
	var s := DofusSprite.new()
	s.position = pos
	if under:
		view.add_child(s) # below the fighters (team discs layer)
	else:
		s.z_index = 5 # above the fighters, still inside their y-sorted layer
		view._container.add_child(s)
	s.look_string = "{%d}" % bone
	s.animation_finished.connect(func(_a: String) -> void: s.queue_free())
	if not s.play_animation("FX", dir, false):
		s.queue_free()
		return
	var st := {"shot": false}
	s.label_reached.connect(func(label: String, _a: String) -> void:
		if label == "SHOT":
			st["shot"] = true)
	var t0 := Time.get_ticks_msec()
	while is_instance_valid(s) and not st["shot"] and Time.get_ticks_msec() - t0 < 2500:
		await view.get_tree().process_frame


static func missile(view: FightView, bone: int, from: Vector2, to: Vector2, dir: int, curvature: float) -> void:
	var s := DofusSprite.new()
	s.z_index = 5
	view._container.add_child(s)
	s.look_string = "{%d}" % bone
	s.play_animation("FX", dir, true)
	var duration := clampf(from.distance_to(to) / 900.0, 0.12, 0.6)
	var t := 0.0
	while t < duration:
		var k := t / duration
		s.position = from.lerp(to, k) + Vector2(0, -sin(k * PI) * curvature * 10.0)
		await view.get_tree().process_frame
		t += view.get_process_delta_time()
	s.queue_free()


## carry: the carried fighter's sprite goes into its carrier's look (Dofus sub
## entity LIFTED_ENTITY, bone node carried_3_0) and the carrier plays AnimPickup,
## then its *Carrying animations; throw: AnimThrow, the fighter flies to its cell;
## drop: it is back on the carrier's cell. Returns how long to let it play.
static func carry(view: FightView, e: Dictionary) -> float:
	var id := int(e["target"])
	var carrier := int(e["carrier"])
	var t: Dictionary = view.fighters[id]
	var c: Dictionary = view.fighters[carrier]
	var tv: ActorView = view.views[id]
	var cv: ActorView = view.views[carrier]
	match str(e["kind"]):
		"carry":
			t["carried_by"] = carrier
			c["carrying"] = id
			t["cell"] = int(c["cell"])
			var look := DofusLook.parse(view.looks[carrier])
			look.set_sub_entity(DofusSubEntity.Category.LIFTED_ENTITY, DofusLook.parse(view.looks[id]), 0)
			tv.visible = false
			tv.place(int(c["cell"]))
			cv.set_look(str(look), "Carrying")
			cv.play_action(["AnimPickup"])
			return 0.6
		"throw":
			t["carried_by"] = -1
			c["carrying"] = -1
			var to := int(e["to"])
			t["cell"] = to
			cv.face(MapGeometry.facing(int(c["cell"]), to))
			cv.set_look(view.looks[carrier], "")
			cv.play_action(["AnimThrow"])
			tv.position = cv.position + Vector2(0, -60)
			tv.visible = true
			var from := tv.position
			var dest := MapGeometry.to_screen(to)
			var arc := 40.0 + from.distance_to(dest) * 0.25
			var tw := tv.create_tween()
			tw.tween_method(func(k: float) -> void:
				tv.position = from.lerp(dest, k) + Vector2(0, -sin(k * PI) * arc), 0.0, 1.0, 0.45)
			await tw.finished
			tv.place(to)
			return 0.35
		"drop":
			t["carried_by"] = -1
			c["carrying"] = -1
			t["cell"] = int(e["cell"])
			cv.set_look(view.looks[carrier], "")
			if not cv.dead:
				cv.play_action(["AnimDrop"])
			tv.place(int(e["cell"]))
			tv.visible = true
			return 0.4
	return 0.0


static func procedural_fx(view: FightView, fx: Dictionary, spell: Dictionary, caster: ActorView, target: int, to: Vector2, color: Color) -> void:
	match str(fx.get("type", "impact")):
		"projectile":
			await SpellFx.projectile(view, caster.position + FightView.HEAD, to, color)
		"area":
			SpellFx.impact(view, to, color, 0.5)
			await SpellFx.area(view, FightRules.area(spell, target, caster.cell, view.map, view.occupied()), color)
		_:
			await SpellFx.impact(view, to, color)


## Script-driven visuals, like the Dofus client: FX on the caster, a missile,
## then the target FX (and a second one, possibly under the fighters).
static func dofus_fx(view: FightView, fx: Dictionary, caster: ActorView, target: int, dir: int) -> void:
	var cell_pos := MapGeometry.to_screen(target)
	if fx.has("caster"):
		bone_fx(view, int(fx["caster"]), caster.position, dir, false)
	if fx.has("missile"):
		await missile(view, int(fx["missile"]), caster.position + Vector2(0, -float(fx.get("missile_y", 40.0))),
				cell_pos + Vector2(0, -30), dir, float(fx.get("missile_curvature", 0.0)))
	if fx.has("target2"):
		bone_fx(view, int(fx["target2"]), cell_pos, dir, bool(fx.get("target2_under", false)))
	if fx.has("target"):
		await bone_fx(view, int(fx["target"]), cell_pos + Vector2(0, -float(fx.get("target_y", 0.0))), dir, bool(fx.get("target_under", false)))
