## Views of a look on one sheet, for the atelier's AI re-skin (docs/STUDIO_IA.md):
##   godot --path game -s res://tools/skin_probe.gd -- --look="{104|||100}" --out=<dir> [--world=<worlds/id dir>[,<dir>...]]
##       [--views=AnimStatique:1:0,AnimMarche:5:0.33,...] [--cols=3] [--cell=336x512]
## Writes <out>/color.png (the look, transparent background), <out>/uv.png (the same pixels with the
## coordinate atlases of DofusContent.probe_atlases: which texel of which atlas each pixel shows) and
## <out>/views.json (sheet size, zoom, the views as played, the atlas of each probe slot).
## A view is anim:dir:frame, frame being an index or a fraction (< 1) of the animation length.
extends SceneTree

const DEFAULT_VIEWS := "AnimStatique:1:0,AnimStatique:5:0,AnimMarche:1:0.33,AnimMarche:5:0.33,AnimAttaque0:1:0.5,AnimAttaque0:5:0.5"
const MARGIN := 12.0

var _args := {}
var _views: Array = [] # [anim, dir, frame spec]
var _cols := 3
var _cell := Vector2i(336, 512)
var _vp: SubViewport
var _sprites: Array[DofusSprite] = []
var _zoom := 1.0
var _played: Array = []
var _pass := 0 # 0 = colour, 1 = probe
var _wait := 0


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if str(_args.get("look", "")) == "" or str(_args.get("out", "")) == "":
		printerr("usage: --look=<look> --out=<dir> [--world=<dir>] [--views=...] [--cols=3] [--cell=336x512]")
		quit(2)
		return
	for v in str(_args.get("views", DEFAULT_VIEWS)).split(",", false):
		var p := v.split(":")
		_views.append([p[0], int(p[1]) if p.size() > 1 else 1, p[2] if p.size() > 2 else "0"])
	_cols = int(_args.get("cols", "3"))
	var cell := str(_args.get("cell", "336x512")).split("x")
	_cell = Vector2i(int(cell[0]), int(cell[1]))
	if _args.has("world"): # folders holding Content/, first wins, comma separated
		var layers: Array[DofusContentProvider] = []
		for w in str(_args["world"]).split(",", false):
			layers.append(DofusFsContentProvider.new(w))
		for o: String in ProjectSettings.get_setting(DofusContent.SETTING_OVERLAYS, PackedStringArray()):
			layers.append(DofusFsContentProvider.new(o))
		layers.append(DofusFsContentProvider.new(ProjectSettings.get_setting(DofusContent.SETTING_ROOT)))
		DofusContent.set_provider(DofusLayeredContentProvider.new(layers))
	DirAccess.make_dir_recursive_absolute(str(_args["out"]))
	_vp = SubViewport.new()
	_vp.size = Vector2i(_cell.x * _cols, _cell.y * ceili(_views.size() / float(_cols)))
	_vp.transparent_bg = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_vp)
	_build()


## Places one sprite per view; the zoom is measured on the colour pass and kept for the probe pass.
func _build() -> void:
	for s in _sprites:
		s.queue_free()
	_sprites.clear()
	_played.clear()
	var rects: Array[Rect2] = []
	for v: Array in _views:
		var s := DofusSprite.new()
		s.playing = false
		_vp.add_child(s)
		s.look_string = str(_args["look"])
		s.play_animation(v[0], v[1])
		var n := s.get_frame_count()
		var spec: String = v[2]
		var f := int(float(spec) * n) if spec.contains(".") else int(spec)
		f = clampi(f, 0, maxi(n - 1, 0))
		s.seek(f)
		_sprites.append(s)
		rects.append(s.get_frame_rect())
		_played.append({"anim": v[0], "dir": v[1], "frame": f, "played": s.current_animation, "flipped": s.flipped, "frames": n})
	if _pass == 0:
		_zoom = INF
		for r in rects:
			if r.size.x > 0 and r.size.y > 0:
				_zoom = minf(_zoom, minf((_cell.x - 2 * MARGIN) / r.size.x, (_cell.y - 2 * MARGIN) / r.size.y))
		if _zoom == INF:
			_zoom = 1.0
	for i in _sprites.size():
		var cell_origin := Vector2((i % _cols) * _cell.x, (i / _cols) * _cell.y)
		var r := rects[i]
		_sprites[i].scale = Vector2(_zoom, _zoom)
		_sprites[i].position = (cell_origin + Vector2(_cell) / 2.0 - r.get_center() * _zoom).round()
		_played[i]["rect"] = [cell_origin.x, cell_origin.y, _cell.x, _cell.y]
	_wait = 0


func _process(_delta: float) -> bool:
	_wait += 1
	if _wait < 4:
		return false
	var out := str(_args["out"])
	var img := _vp.get_texture().get_image()
	if _pass == 0:
		img.save_png(out.path_join("color.png"))
		_pass = 1
		DofusContent.probe_atlases = true
		DofusContent.probe_slots.clear()
		DofusContent.clear_caches()
		_build()
		return false
	img.save_png(out.path_join("uv.png"))
	var info := {"look": str(_args["look"]), "width": _vp.size.x, "height": _vp.size.y, "cols": _cols,
			"cell": [_cell.x, _cell.y], "zoom": _zoom, "views": _played, "slots": DofusContent.probe_slots}
	var fa := FileAccess.open(out.path_join("views.json"), FileAccess.WRITE)
	fa.store_string(JSON.stringify(info, " "))
	fa.close()
	print("skin_probe: ", out, " slots=", DofusContent.probe_slots)
	DofusContent.clear_caches()
	quit()
	return false
