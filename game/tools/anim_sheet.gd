## Every animation of a look as frame strips, for the atelier's animated preview (docs/STUDIO_IA.md):
##   godot --path game -s res://tools/anim_sheet.gd -- --look="{104|||100}" --out=<dir> [--world=<worlds/id dir>[,<dir>...]]
##       [--cell=192] [--max-frames=48] [--anims=AnimStatique,AnimMarche]
## Writes <out>/<anim name>.png per animation clip (one row of cells, transparent background, feet at the
## same spot in every cell) and <out>/sheet.json: cell size, per strip its frame count and rate, and per base
## animation and direction the strip to show and whether to mirror it (3 and 7 of most monsters).
extends SceneTree

var _args := {}
var _cell := 192
var _max_frames := 48
var _vp: SubViewport
var _probe: DofusSprite
var _zoom := 1.0
var _jobs: Array[String] = [] # clip names to draw
var _job := -1
var _sprites: Array[DofusSprite] = []
var _wait := 0
var _info := {}


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if str(_args.get("look", "")) == "" or str(_args.get("out", "")) == "":
		printerr("usage: --look=<look> --out=<dir> [--world=<dir>] [--cell=192] [--max-frames=48] [--anims=A,B]")
		quit(2)
		return
	_cell = int(_args.get("cell", "192"))
	_max_frames = int(_args.get("max-frames", "48"))
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
	_vp.transparent_bg = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_vp)
	_probe = DofusSprite.new()
	_probe.playing = false
	_vp.add_child(_probe)
	_probe.look_string = str(_args["look"])
	# one zoom for every strip: the idle pose fills ~60 % of the cell height
	_probe.play_animation("", 1)
	var r := _probe.get_frame_rect()
	_zoom = clampf(_cell * 0.6 / maxf(r.size.y, 1.0), 0.2, 6.0)
	var wanted := str(_args.get("anims", "")).split(",", false)
	var names := {}
	for n in _probe.get_animation_names():
		names[n] = true
	var anims := {}
	var dirs: Dictionary = _probe.get_animation_directions()
	for base: String in dirs:
		if not wanted.is_empty() and not wanted.has(base):
			continue
		var by_dir := {}
		for dir: int in dirs[base]:
			var res := DofusAnimNames.resolve(names, dir, _probe.look.bone, base)
			if res[0] == "":
				continue
			by_dir[str(dir)] = {"strip": res[0], "flip": res[1]}
			if not _jobs.has(res[0]):
				_jobs.append(res[0])
		anims[base] = by_dir
	_probe.queue_free()
	_info = {"look": str(_args["look"]), "cell": _cell, "foot": [_cell / 2, int(_cell * 0.82)], "zoom": _zoom,
			"anims": anims, "strips": {}}


func _process(_delta: float) -> bool:
	if _job >= 0:
		_wait += 1
		if _wait < 3:
			return false
		var img := _vp.get_texture().get_image()
		img.save_png(str(_args["out"]).path_join("%s.png" % DofusContent.safe_file_name(_jobs[_job])))
	_job += 1
	if _job >= _jobs.size():
		_finish()
		return false
	_strip(_jobs[_job])
	return false


func _strip(anim_name: String) -> void:
	for s in _sprites:
		s.queue_free()
	_sprites.clear()
	var first := DofusSprite.new()
	first.playing = false
	_vp.add_child(first)
	first.look_string = str(_args["look"])
	first.play_exact(anim_name)
	var n := mini(first.get_frame_count(), _max_frames)
	var step := maxf(1.0, first.get_frame_count() / float(_max_frames))
	_vp.size = Vector2i(_cell * maxi(n, 1), _cell)
	for i in n:
		var s := first if i == 0 else DofusSprite.new()
		if i > 0:
			s.playing = false
			_vp.add_child(s)
			s.look_string = str(_args["look"])
			s.play_exact(anim_name)
		s.scale = Vector2(_zoom, _zoom)
		s.position = Vector2(i * _cell + _cell / 2, int(_cell * 0.82))
		s.seek(int(i * step))
		_sprites.append(s)
	_info["strips"][anim_name] = {"file": "%s.png" % DofusContent.safe_file_name(anim_name), "frames": n,
			"fps": first.get_frame_rate() / step}
	_wait = 0


func _finish() -> void:
	var fa := FileAccess.open(str(_args["out"]).path_join("sheet.json"), FileAccess.WRITE)
	fa.store_string(JSON.stringify(_info, " "))
	fa.close()
	print("anim_sheet: ", _jobs.size(), " strips in ", _args["out"])
	DofusContent.clear_caches()
	quit()
