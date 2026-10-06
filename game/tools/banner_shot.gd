## Capture of the reconnection banner (S.02c): godot --path game -s res://tools/banner_shot.gd -- --out=b.png
extends SceneTree


func _init() -> void:
	var out := "banner.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	var layer := CanvasLayer.new()
	root.add_child(layer)
	layer.add_child(CharacterSelectScreen.backdrop())
	var banner := ReconnectBanner.new()
	layer.add_child(banner)
	banner.wait(2, 4000)
	await create_timer(0.8).timeout
	root.get_texture().get_image().save_png(out)
	quit()
