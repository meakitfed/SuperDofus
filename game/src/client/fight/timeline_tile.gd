## One fighter in the fight timeline: the Dofus 3 team tile (blue / red, normal,
## "over" for the playing fighter, "dark" once dead), the portrait (monster picto,
## or the live look of a player) and a thin HP bar.
class_name TimelineTile
extends Control

const SIZE := Vector2(59, 60)
const HUD := "UI/darkStone/texture/hud/background_timeline_%s_%s"

var fighter_id := 0
var _bg: TextureRect
var _hp: ColorRect
var _team := "blue"


func setup(f: Dictionary) -> void:
	fighter_id = int(f["id"])
	_team = "blue" if int(f["team"]) == 0 else "red"
	custom_minimum_size = SIZE + Vector2(0, 6)
	mouse_filter = Control.MOUSE_FILTER_PASS
	_bg = TextureRect.new()
	_bg.size = SIZE
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)
	var portrait := ClientTheme.texture("Picto/Monsters/%d" % int(f.get("portrait", 0))) if int(f.get("portrait", 0)) > 0 else null
	if portrait != null:
		var tr := TextureRect.new()
		tr.texture = portrait
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.position = Vector2(4, 4)
		tr.size = SIZE - Vector2(8, 8)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(tr)
	elif not (f.get("looks", []) as Array).is_empty():
		add_child(_live_portrait(str(f["looks"][0])))
	_hp = ColorRect.new()
	_hp.position = Vector2(2, SIZE.y + 1)
	_hp.size = Vector2(SIZE.x - 4, 4)
	add_child(_hp)


## state: "normal", "over" (playing) or "dark" (dead)
func update(f: Dictionary, playing: bool) -> void:
	var alive := bool(f["alive"])
	var state := "dark" if not alive else ("over" if playing else "normal")
	_bg.texture = ClientTheme.texture(HUD % [_team, state])
	if _bg.texture == null:
		_bg.texture = null
	var ratio := clampf(float(f["hp"]) / maxf(1.0, float(f["max_hp"])), 0.0, 1.0)
	_hp.size.x = (SIZE.x - 4) * ratio
	_hp.color = Color(0.9, 0.2, 0.15).lerp(Color(0.35, 0.85, 0.3), ratio)
	modulate = Color(1, 1, 1, 1.0 if alive else 0.5)


## Players have no picto: render their look in a small viewport (upper body).
func _live_portrait(look: String) -> Control:
	var box := SubViewportContainer.new()
	box.position = Vector2(4, 4)
	box.size = SIZE - Vector2(8, 8)
	box.stretch = true
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vp := SubViewport.new()
	vp.transparent_bg = true
	vp.size = Vector2i(SIZE - Vector2(8, 8))
	box.add_child(vp)
	var s := DofusSprite.new()
	s.mask_mode = DofusSpriteInstance.MaskMode.HIDE_MASKED # clip groups draw black on transparent targets
	s.position = Vector2(vp.size.x * 0.5, vp.size.y + 48.0) # head and shoulders
	s.scale = Vector2(0.9, 0.9)
	s.playing = false
	vp.add_child(s)
	s.look_string = look
	return box
