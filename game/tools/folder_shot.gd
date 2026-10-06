## Capture of the world folder screen (C.04): godot --path game -s res://tools/folder_shot.gd -- --out=f.png [--old=<dir with worlds>]
extends SceneTree


func _init() -> void:
	var out := "folder.png"
	var path := "D:/Jeux/SuperDofus"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		if a.begins_with("--path="):
			path = a.substr(7)
	var s := ContentFolderScreen.new()
	s.current = path
	root.add_child(s)
	await create_timer(0.8).timeout
	root.get_texture().get_image().save_png(out)
	quit()
