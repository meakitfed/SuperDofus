## Finds animations using masks / blend modes / colour matrices / labels (to pick visual test cases):
##   godot --headless --path . -s res://tools/scan_features.gd -- [max_bones]
extends SceneTree


func _init() -> void:
	var max_bones := int(OS.get_cmdline_user_args()[0]) if not OS.get_cmdline_user_args().is_empty() else 300
	var found := {"mask": [], "blend": {}, "matrix": [], "labels": {}}
	var bones := DofusContent.get_provider().list_dirs(DofusContent.BONES)
	var scanned := 0
	for bone_name in bones:
		if scanned >= max_bones:
			break
		var bone_json: Variant = DofusContent.get_provider().read_json("%s/%s/bone.json" % [DofusContent.BONES, bone_name])
		if not bone_json is Dictionary:
			continue
		scanned += 1
		for anim: Dictionary in bone_json["animations"]:
			var bytes := DofusContent.get_provider().read_bytes("%s/%s/%s.dat" % [DofusContent.BONES, bone_name, DofusContent.safe_file_name(anim["name"])])
			if bytes.size() < 8:
				continue
			var clip := DofusAnimClip.from_bytes(bytes)
			var id := "%s/%s" % [bone_name, anim["name"]]
			for f in clip.frame_count:
				var data := clip.frames[f]
				for s in clip.node_count:
					var b := s * DofusAnimClip.STRIDE
					if data[b + DofusAnimClip.F_MASK] != 0 and found["mask"].size() < 15 and not found["mask"].has(id):
						found["mask"].append(id)
					var blend := int(data[b + DofusAnimClip.F_BLEND])
					if blend != 0 and not found["blend"].has(blend):
						found["blend"][blend] = id
			if not clip.color_matrices.is_empty() and found["matrix"].size() < 10:
				found["matrix"].append(id)
			for f: int in clip.labels:
				for l in clip.labels[f]:
					found["labels"][l] = found["labels"].get(l, 0) + 1
	print("scanned %d bones" % scanned)
	print("masks: ", found["mask"])
	print("blends: ", found["blend"])
	print("colour matrices: ", found["matrix"])
	var labels: Dictionary = found["labels"]
	var keys := labels.keys()
	keys.sort_custom(func(a, b): return labels[a] > labels[b])
	print("labels (top): ", keys.slice(0, 30).map(func(k): return "%s=%d" % [k, labels[k]]))
	quit()
