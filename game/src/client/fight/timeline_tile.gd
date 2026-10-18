## One fighter in the fight timeline: the Dofus 3 team tile (blue / red, normal,
## "over" for the playing fighter, "dark" once dead), the portrait (monster picto,
## or the live look of a player) and a thin HP bar.
class_name TimelineTile
extends Control

const SIZE := Vector2(59, 60)
const HUD := "UI/darkStone/texture/hud/background_timeline_%s_%s"

var fighter_id := 0
## your own tile gets a discreet gold frame (the playing one a full one)
var is_you := false
## what the tooltip shows (UiTooltips.fighter); {} = no tooltip
var tip := {}:
	set(v):
		tip = v
		tooltip_text = " " if not v.is_empty() else "" # non-empty: Godot then asks _make_custom_tooltip
var _bg: TextureRect
var _hp: ColorRect
var _frame: Panel
var _ready_mark: Label
var _team := "blue"


func setup(f: Dictionary) -> void:
	fighter_id = int(f["id"])
	_team = "blue" if int(f["team"]) == 0 else "red"
	custom_minimum_size = SIZE + Vector2(0, 7)
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
	var hp_bg := ColorRect.new()
	hp_bg.color = UiStyle.BG_INSET
	hp_bg.position = Vector2(2, SIZE.y + 1)
	hp_bg.size = Vector2(SIZE.x - 4, 5)
	hp_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hp_bg)
	_hp = ColorRect.new()
	_hp.position = hp_bg.position
	_hp.size = hp_bg.size
	_hp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hp)
	_frame = Panel.new()
	_frame.size = SIZE
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frame)
	_ready_mark = UiStyle.label("✔", UiStyle.GOOD, UiStyle.FS_SMALL)
	_ready_mark.add_theme_color_override("font_outline_color", Color.BLACK)
	_ready_mark.add_theme_constant_override("outline_size", 4)
	_ready_mark.position = Vector2(SIZE.x - 16, 2)
	_ready_mark.visible = false
	_ready_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ready_mark)


## state: "normal", "over" (playing) or "dark" (dead)
func update(f: Dictionary, playing: bool) -> void:
	var alive := bool(f["alive"])
	var state := "dark" if not alive else ("over" if playing else "normal")
	_bg.texture = ClientTheme.texture(HUD % [_team, state])
	if _bg.texture == null:
		_bg.texture = null
	var ratio := clampf(float(f["hp"]) / maxf(1.0, float(f["max_hp"])), 0.0, 1.0)
	_hp.size.x = (SIZE.x - 4) * ratio
	_hp.color = UiStyle.BAD.lerp(UiStyle.GOOD, ratio)
	modulate = Color(1, 1, 1, 1.0 if alive else 0.5)
	_ready_mark.visible = bool(tip.get("ready", false))
	if playing and alive:
		_frame.add_theme_stylebox_override("panel", UiStyle.ring(UiStyle.GOLD, 2, 3))
	elif is_you and alive:
		_frame.add_theme_stylebox_override("panel", UiStyle.ring(UiStyle.ACCENT_DIM, 1, 3))
	else:
		_frame.add_theme_stylebox_override("panel", UiStyle.ring(Color(0, 0, 0, 0), 0, 3))


func _make_custom_tooltip(_for_text: String) -> Object:
	return UiTooltips.fighter(tip) if not tip.is_empty() else null


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
