## Renders looks to PNG for visual checks:
##   godot --path . -s res://tools/render_shot.gd -- --out=<png> --anim=AnimMarche --dir=1 --frames=0,8 --zoom=2 "<look>" ["<look>"...]
## (frames are assigned to looks in turn, so repeating a look shows an animation strip)
extends SceneTree

var _args := {}
var _looks: PackedStringArray = []
var _frames := 0
var _sprites: Array[DofusSprite] = []


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			var kv := a.substr(2).split("=", true, 1)
			_args[kv[0]] = kv[1]
		else:
			_looks.append(a)
	if _looks.is_empty():
		_looks.append("{1|10||100}")
	var zoom := float(_args.get("zoom", "2"))
	var cell := float(_args.get("cell", "180")) * zoom
	var cols := mini(_looks.size(), int(_args.get("cols", "4")))
	var rows := ceili(_looks.size() / float(cols))
	root.size = Vector2i(int(cell * cols), int(cell * float(_args.get("aspect", "1.4")) * rows))
	if _args.has("transparent"):
		root.transparent_bg = true
		RenderingServer.set_default_clear_color(Color(0, 0, 0, 0))
	else:
		RenderingServer.set_default_clear_color(Color8(46, 51, 61))
	if _args.has("checker"):
		var bg := Node2D.new()
		bg.draw.connect(func() -> void:
			var n := 24
			for y in range(0, root.size.y, n):
				for x in range(0, root.size.x, n):
					bg.draw_rect(Rect2(x, y, n, n), Color8(90, 120, 80) if (x / n + y / n) % 2 == 0 else Color8(160, 90, 90)))
		root.add_child(bg)
	for i in _looks.size():
		var s := DofusSprite.new()
		s.playing = false
		var aspect := float(_args.get("aspect", "1.4"))
		s.position = Vector2((i % cols + 0.5) * cell, (i / cols + 1) * cell * aspect - float(_args.get("foot", "30")) * zoom)
		s.scale = Vector2(zoom, zoom)
		root.add_child(s)
		if _args.has("mask_mode"):
			s.mask_mode = int(_args["mask_mode"]) as DofusSpriteInstance.MaskMode
		s.look_string = _looks[i]
		s.play_animation(_args.get("anim", ""), int(_args.get("dir", "1")))
		var frames: PackedStringArray = str(_args.get("frames", _args.get("frame", "0"))).split(",")
		s.seek(int(frames[i % frames.size()]))
		_sprites.append(s)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 4:
		var img := root.get_texture().get_image()
		var out: String = _args.get("out", "user://shot.png")
		img.save_png(out)
		print("saved ", ProjectSettings.globalize_path(out))
		for s in _sprites:
			print(s.get_look_string(), " -> ", s.current_animation, " flip=", s.flipped, " frames=", s.get_frame_count())
		DofusContent.clear_caches()
		quit()
	return false
