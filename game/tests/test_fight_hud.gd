## Fight HUD (lot U.05): the parts sit apart and on screen at every window shape, the timeline shrinks
## for many fighters, the floating numbers stay in the free strip, the fighter tooltip and the spell
## reasons say what they should.
extends TestCase

const SIZES := [Vector2(1280, 720), Vector2(1920, 1080), Vector2(2560, 1440), Vector2(1280, 1024), Vector2(1024, 576)]


func _parts(vp: Vector2, n: int) -> Dictionary:
	var s := FightLayout.timeline_scale(vp.x, n, TimelineTile.SIZE.x)
	return {"timeline": Vector2(n * 59.0 + (n - 1) * 6.0, 67.0) * s, "bar": Vector2(780, 130), "options": Vector2(450, 32),
			"banner": Vector2(260, 60), "message": Vector2(300, 34)}


func test_parts_stay_on_screen_and_apart() -> void:
	for vp: Vector2 in SIZES:
		for n in [4, 12, 16]:
			var sizes := _parts(vp, n)
			var at := FightLayout.place(vp, sizes)
			var rects := {}
			for k: String in sizes:
				var r := Rect2(at[k], sizes[k])
				check(Rect2(Vector2.ZERO, vp).grow(0.5).encloses(r), "%s on screen at %s with %d fighters" % [k, vp, n])
				rects[k] = r
			for a: String in ["timeline", "bar", "options", "banner"]:
				for b: String in ["timeline", "bar", "options", "banner"]:
					if a < b:
						check(not (rects[a] as Rect2).intersects(rects[b]), "%s and %s apart at %s" % [a, b, vp])


func test_bands_cover_what_the_parts_take() -> void:
	var sizes := _parts(Vector2(1280, 720), 4)
	var at := FightLayout.place(Vector2(1280, 720), sizes)
	var bands := FightLayout.bands(sizes)
	check((at["options"] as Vector2).y >= 720.0 - bands.y, "the options are inside the bottom band")
	check(bands.x >= (at["timeline"] as Vector2).y + (sizes["timeline"] as Vector2).y, "the timeline is inside the top band")
	check((at["message"] as Vector2).y >= bands.x, "the message is in the free strip")


func test_timeline_shrinks_but_stays_readable() -> void:
	eq(FightLayout.timeline_scale(1280.0, 4, 59.0), 1.0)
	var s := FightLayout.timeline_scale(1280.0, 24, 59.0)
	check(s < 1.0 and s >= FightLayout.MIN_TILE_SCALE, "many fighters: smaller, not unreadable")


func test_floating_text_stays_in_the_strip() -> void:
	var vp := Vector2(1280, 720)
	var bands := Vector2(80, 150)
	var size := Vector2(60, 36)
	for anchor: Vector2 in [Vector2(5, 5), Vector2(640, 20), Vector2(1270, 700), Vector2(640, 715), Vector2(-50, 360)]:
		var at := SpellFx.keep_in_strip(anchor, size, vp, bands)
		check(at.x >= 0.0 and at.x + size.x <= vp.x, "inside horizontally for %s" % anchor)
		check(at.y - SpellFx.RISE >= bands.x and at.y + size.y <= vp.y - bands.y, "clear of both bands for %s" % anchor)


func test_why_a_spell_cannot_be_cast() -> void:
	eq(FightHud._why_text("", true), "")
	check(FightHud._why_text("", false) != "", "not your turn")
	check(FightHud._why_text("PA", true).contains("PA"))
	check(FightHud._why_text("2", true).contains("2 tours"))


func test_fighter_tooltip_and_tile() -> void:
	var tip := {"name": "Tofu", "level": 4, "hp": 10, "max_hp": 24, "ap": 6, "mp": 3, "buffs": ["Sobre"], "ready": true, "team": 1, "alive": true}
	var c := UiTooltips.fighter(tip)
	check(c != null and c.get_child_count() > 3, "a tooltip with its lines")
	c.free()
	var tile := TimelineTile.new()
	tile.setup({"id": 1, "team": 1, "portrait": 0, "looks": [], "hp": 10, "max_hp": 24, "alive": true})
	eq(tile.tooltip_text, "", "no tooltip without data (result window)")
	tile.tip = tip
	check(tile.tooltip_text != "", "tooltip once it knows its fighter")
	tile.free()
