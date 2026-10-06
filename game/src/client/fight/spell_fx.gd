## Procedural spell visuals (the real Dofus spell FX are not extracted yet):
## impact ring, projectile, area flash, floating damage numbers.
## Each effect is a short-lived node; `await SpellFx.xxx(...)` waits for its end.
class_name SpellFx
extends Node2D

var kind := ""
var color := Color.WHITE
var progress := 0.0:
	set(v):
		progress = v
		queue_redraw()
var from := Vector2.ZERO
var to := Vector2.ZERO
var cells: Array = []


static func impact(parent: Node, pos: Vector2, p_color: Color, duration := 0.35) -> void:
	var fx := _make(parent, "impact", p_color)
	fx.position = pos
	await fx._run(duration)


static func projectile(parent: Node, p_from: Vector2, p_to: Vector2, p_color: Color) -> void:
	var fx := _make(parent, "projectile", p_color)
	fx.from = p_from
	fx.to = p_to
	await fx._run(clampf(p_from.distance_to(p_to) / 900.0, 0.15, 0.45))
	await impact(parent, p_to, p_color)


static func area(parent: Node, p_cells: Array, p_color: Color) -> void:
	var fx := _make(parent, "area", p_color)
	fx.cells = p_cells
	await fx._run(0.45)


static func floating_text(parent: Node, pos: Vector2, text: String, p_color: Color, size := 26) -> void:
	var label := Label.new()
	label.theme = ClientTheme.get_theme()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", p_color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	label.position = pos - Vector2(label.get_minimum_size().x * 0.5, 20)
	label.z_index = 100
	parent.add_child(label)
	var tw := label.create_tween().set_parallel()
	tw.tween_property(label, "position:y", label.position.y - 55, 1.1).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(label, "modulate:a", 0.0, 0.5).set_delay(0.6)
	tw.chain().tween_callback(label.queue_free)


static func _make(parent: Node, p_kind: String, p_color: Color) -> SpellFx:
	var fx := SpellFx.new()
	fx.kind = p_kind
	fx.color = p_color
	fx.z_index = 90
	parent.add_child(fx)
	return fx


func _run(duration: float) -> void:
	var tw := create_tween()
	tw.tween_property(self, "progress", 1.0, duration)
	await tw.finished
	queue_free()


func _draw() -> void:
	match kind:
		"impact":
			var r := lerpf(8.0, 46.0, progress)
			var a := 1.0 - progress
			draw_circle(Vector2.ZERO, r * 0.6, Color(color, 0.5 * a))
			draw_arc(Vector2.ZERO, r, 0, TAU, 32, Color(color, a), 4.0)
			draw_arc(Vector2.ZERO, r * 0.55, 0, TAU, 24, Color(Color.WHITE, a), 2.0)
		"projectile":
			var p := from.lerp(to, progress) + Vector2(0, -sin(progress * PI) * 60.0)
			for i in 4: # little trail
				var q := from.lerp(to, maxf(0.0, progress - i * 0.05)) + Vector2(0, -sin(maxf(0.0, progress - i * 0.05) * PI) * 60.0)
				draw_circle(q, 9.0 - i * 2.0, Color(color, 0.8 - i * 0.18))
			draw_circle(p, 5.0, Color.WHITE)
		"area":
			var a := sin(progress * PI)
			for c: int in cells:
				var s := MapGeometry.to_screen(c)
				var w := IsoGrid.CELL_W * 0.5
				var h := IsoGrid.CELL_H * 0.5
				draw_colored_polygon(PackedVector2Array([s + Vector2(0, -h), s + Vector2(w, 0), s + Vector2(0, h), s + Vector2(-w, 0)]), Color(color, 0.6 * a))
