## Computes the assets of content/ a world uses and writes them to worlds/<id>/_content.json, which
## WorldPackage adds to the package (roadmap C.02b, WorldAssets):
##   godot --headless --path game -s res://tools/world_assets.gd -- --world=incarnam
##   options: --root=<dir> (folder holding worlds/, data/, content/; default the project)
##            --check-trace=<file> (a client_shot --trace file: lists the files read but not in the package, exit 1 if any)
##            --dry (print only), --missing (list the referenced files absent from content/)
##            --zones (C.02c: base + zones when world.json has `zone_key`: what a client downloads at once, then
##            per zone; the report gives the sizes, --dry writes nothing)
extends SceneTree


func _init() -> void:
	var opts := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		opts[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var world := str(opts.get("world", ""))
	if world == "":
		printerr("usage: --world=<id> [--root=<dir>] [--dry] [--missing]")
		quit(2)
		return
	var root := str(opts.get("root", ProjectSettings.globalize_path("res://"))).replace("\\", "/")
	var wa := WorldAssets.new(root, world)
	var globs := PackedStringArray() if opts.has("zones") else wa.compute()
	if globs.is_empty() and not opts.has("zones"):
		printerr("world %s: nothing found under %s (%s)" % [world, root, ", ".join(wa.missing)])
		quit(1)
		return
	if opts.has("check-trace"):
		var paths := FileAccess.get_file_as_string(str(opts["check-trace"])).split("\n", false)
		var bad := wa.uncovered(globs, paths)
		print("trace: %d paths read, %d not covered by the package of %s" % [paths.size(), bad.size(), world])
		for b in bad:
			print("  NOT COVERED ", b)
		quit(1 if bad.size() > 0 else 0)
		return
	var zoned := {}
	if opts.has("zones"):
		zoned = wa.compute_zoned()
		if zoned.is_empty():
			printerr("world %s: no zone_key in world.json, nothing to split" % world)
			quit(1)
			return
		globs = zoned["base"]
		_report_zones(wa, zoned)
	var size := wa.size_of(globs)
	print("world %s: %d globs, %.1f MB of content; %s" % [world, globs.size(), size / 1048576.0, JSON.stringify(wa.stats)])
	if opts.has("missing"):
		for m in wa.missing:
			print("  missing ", m)
	else:
		print("  %d referenced files absent from content/ (--missing to list them)" % wa.missing.size())
	if not opts.has("dry"):
		var err := wa.save(globs, zoned)
		if err != "":
			printerr(err)
			quit(1)
			return
		print("  written worlds/%s/%s" % [world, WorldAssets.FILE])
	quit(0)


## Sizes of the split: base, zones (sum, largest, median), and the real total (a shared glob counts once).
func _report_zones(wa: WorldAssets, zoned: Dictionary) -> void:
	var zones: Dictionary = zoned["zones"]
	var sizes: Array = []
	var all := {}
	var count_files := 0
	for z: Dictionary in zones.values():
		sizes.append(int(z["bytes"]))
		for dir: String in z["files"]:
			count_files += (z["files"][dir] as Array).size()
			for n: String in z["files"][dir]:
				all[dir + "/" + n] = true
		for g: String in z["dirs"]:
			all[g] = true
	sizes.sort()
	var union := wa.size_of(PackedStringArray(all.keys()))
	var base := wa.size_of(zoned["base"])
	var heavy: Array = []
	for g: String in zoned["base"]:
		heavy.append([wa.size_of(PackedStringArray([g])), g])
	heavy.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	print("heaviest base globs:")
	for i in mini(12, heavy.size()):
		print("  %8.1f MB  %s" % [heavy[i][0] / 1048576.0, heavy[i][1]])
	var big: Array = []
	for id: String in zones:
		big.append([int(zones[id]["bytes"]), id, (zones[id]["maps"] as Array).size()])
	big.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	print("heaviest zones:")
	for i in mini(6, big.size()):
		print("  %8.1f MB  zone %s (%d maps)" % [big[i][0] / 1048576.0, big[i][1], big[i][2]])
	print("zones: %d, start zone %s" % [zones.size(), zoned["start_zone"]])
	print("  base          %9.1f MB (%d globs)" % [base / 1048576.0, (zoned["base"] as Array).size()])
	print("  all the zones %9.1f MB once each (%d distinct files or folders)" % [union / 1048576.0, all.size()])
	print("  whole world   %9.1f MB" % [(base + union) / 1048576.0])
	if not sizes.is_empty():
		print("  per zone: median %.2f MB, largest %.1f MB, sum with the shared files counted again %.1f MB" % [
				sizes[sizes.size() / 2] / 1048576.0, sizes[-1] / 1048576.0, sizes.reduce(func(a: int, b: int) -> int: return a + b, 0) / 1048576.0])
