## Where the downloaded worlds are stored (roadmap C.04), without any Node: the folder is chosen by
## the player (any disk, D:/Jeux/SuperDofus), remembered in user://launch.cfg ([content] folder),
## can be forced on the command line (`--content-dir=D:\Jeux\SuperDofus`), is checked (creatable,
## writable, free space) before anything is downloaded, and the old cache (user://worlds, before
## C.04) can be moved to the new folder or simply reused as it is. WorldLoader and ContentSource
## do the reading and the download; this class only decides which folder they use.
##
##   var r := ContentFolder.resolve(AutoRun.options())   # {path, source: "cli"|"config"|"default"}
##   ContentFolder.apply(r["path"])                      # ContentSource.set_cache_base
##   var v := ContentFolder.validate("D:/Jeux/Mondes")   # {ok, error, path, free}
##   var old := ContentFolder.legacy_worlds(path)        # worlds still in user://worlds
##   ContentFolder.migrate(ContentFolder.legacy_dir(), path, ids)   # {ok, moved, skipped, error}
##
## Nothing here knows which game a world runs.
class_name ContentFolder
extends RefCounted

const CONFIG := "user://launch.cfg"
const SECTION := "content"
## the command-line option that forces the folder for this run (and is remembered)
const OPTION := "content-dir"


## The pre-C.04 cache, on disk.
static func legacy_dir() -> String:
	return ProjectSettings.globalize_path(ContentSource.CACHE_BASE)


## "D:\Jeux\x\" -> "D:/Jeux/x"; "" stays "".
static func normalize(path: String) -> String:
	var p := path.strip_edges().replace("\\", "/")
	while p.length() > 1 and p.ends_with("/") and not p.ends_with(":/"):
		p = p.trim_suffix("/")
	return p


## The folder that applies: command line, else the remembered one, else the default
## (the old user://worlds). `configured` = the player already chose (no first-launch screen).
static func resolve(opts: Dictionary, config_path := CONFIG) -> Dictionary:
	var cli := normalize(str(opts.get(OPTION, "")))
	if cli != "":
		return {"path": cli, "source": "cli", "configured": true}
	var mine := remembered(config_path)
	if mine != "":
		return {"path": mine, "source": "config", "configured": true}
	return {"path": legacy_dir(), "source": "default", "configured": false}


static func remembered(config_path := CONFIG) -> String:
	var cfg := ConfigFile.new()
	if cfg.load(config_path) != OK:
		return ""
	return normalize(str(cfg.get_value(SECTION, "folder", "")))


## Keeps the other sections of the file (address, login, last world) as they are.
static func remember(path: String, config_path := CONFIG) -> bool:
	var cfg := ConfigFile.new()
	cfg.load(config_path) # a missing file is fine
	cfg.set_value(SECTION, "folder", normalize(path))
	return cfg.save(config_path) == OK


## Makes `path` the folder of the world caches (ContentSource), without moving anything.
static func apply(path: String) -> void:
	ContentSource.set_cache_base(normalize(path))


## Can `path` hold the worlds? Absolute (or user://), creatable, writable. `free` = free bytes on its
## disk (-1 unknown). `free_space` Callable(path) -> int is injectable (tests).
static func validate(path: String, free_space := DiskSpace.free_bytes) -> Dictionary:
	var p := normalize(path)
	var out := {"ok": false, "error": "", "path": p, "free": -1}
	if p == "":
		out["error"] = "Choisissez un dossier."
		return out
	if not (p.is_absolute_path() or p.begins_with("user://")):
		out["error"] = "Indiquez un chemin complet, par exemple D:/Jeux/SuperDofus."
		return out
	var abs := ProjectSettings.globalize_path(p)
	if DirAccess.make_dir_recursive_absolute(abs) != OK and not DirAccess.dir_exists_absolute(abs):
		out["error"] = "Impossible de créer ce dossier (disque absent ou accès refusé)."
		return out
	var probe := abs.path_join(".write_test")
	var f := FileAccess.open(probe, FileAccess.WRITE)
	if f == null:
		out["error"] = "Ce dossier n'est pas accessible en écriture."
		return out
	f.close()
	DirAccess.remove_absolute(probe)
	out["free"] = int(free_space.call(p)) if free_space.is_valid() else -1
	out["ok"] = true
	return out


## "12,4 Go libres" / "espace libre inconnu".
static func free_text(free: int) -> String:
	return "espace libre inconnu" if free < 0 else WorldLoader.format_bytes(free) + " libres"


## The worlds (complete or partial caches: a folder with its install state) found in `dir`, as
## [{id, bytes}] sorted by id. Empty when `dir` is the folder being used.
static func legacy_worlds(dir: String, exclude := "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var base := normalize(dir)
	if base == "" or (exclude != "" and _same(base, exclude)) or not DirAccess.dir_exists_absolute(base):
		return out
	var ids := DirAccess.get_directories_at(base)
	ids.sort()
	for id in ids:
		var dir_id := base.path_join(id)
		if FileAccess.file_exists(dir_id.path_join(ContentSource.MANIFEST)) or FileAccess.file_exists(dir_id.path_join(ContentSource.LEGACY_MANIFEST)):
			out.append({"id": id, "bytes": dir_size(base.path_join(id))})
	return out


## Total bytes of the files under `dir`.
static func dir_size(dir: String) -> int:
	var total := 0
	for f in DirAccess.get_files_at(dir):
		total += maxi(0, FileHash.size_of(dir.path_join(f)))
	for d in DirAccess.get_directories_at(dir):
		total += dir_size(dir.path_join(d))
	return total


## Moves the caches `ids` from `from` to `to` (rename when both are on one disk, else copy then delete
## the source). A world already present in `to` is left alone (`skipped`: the old copy stays).
## {ok, moved: [ids], skipped: [ids], error}. The space needed is checked before a copy.
static func migrate(from: String, to: String, ids: Array, free_space := DiskSpace.free_bytes) -> Dictionary:
	var out := {"ok": true, "moved": [], "skipped": [], "error": ""}
	var src := normalize(from)
	var dst := normalize(to)
	if _same(src, dst):
		return out
	DirAccess.make_dir_recursive_absolute(dst)
	for id: String in ids:
		var a := src.path_join(id)
		var b := dst.path_join(id)
		if DirAccess.dir_exists_absolute(b) and (FileAccess.file_exists(b.path_join(ContentSource.MANIFEST))
				or FileAccess.file_exists(b.path_join(ContentSource.LEGACY_MANIFEST))):
			out["skipped"].append(id)
			continue
		if DirAccess.rename_absolute(a, b) == OK:
			out["moved"].append(id)
			continue
		var need := dir_size(a)
		var free := int(free_space.call(dst)) if free_space.is_valid() else -1
		if free >= 0 and need > free:
			out["ok"] = false
			out["error"] = "Espace insuffisant pour déplacer %s : %s nécessaires, %s libres." % [
					id, WorldLoader.format_bytes(need), WorldLoader.format_bytes(free)]
			return out
		var err := _copy_dir(a, b)
		if err != OK:
			remove_dir(b) # no half world left behind: the next launch downloads it again
			out["ok"] = false
			out["error"] = "Copie de %s interrompue (erreur %d) : l'ancien dossier est intact." % [id, err]
			return out
		remove_dir(a)
		out["moved"].append(id)
	# the old base is removed only when it ends up empty (never someone's other files)
	if DirAccess.dir_exists_absolute(src) and DirAccess.get_directories_at(src).is_empty() \
			and DirAccess.get_files_at(src).is_empty():
		DirAccess.remove_absolute(src)
	return out


static func remove_dir(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		remove_dir(dir.path_join(d))
	DirAccess.remove_absolute(dir)


static func _copy_dir(a: String, b: String) -> int:
	var err := DirAccess.make_dir_recursive_absolute(b)
	if err != OK:
		return err
	for f in DirAccess.get_files_at(a):
		err = DirAccess.copy_absolute(a.path_join(f), b.path_join(f))
		if err != OK:
			return err
	for d in DirAccess.get_directories_at(a):
		err = _copy_dir(a.path_join(d), b.path_join(d))
		if err != OK:
			return err
	return OK


static func _same(a: String, b: String) -> bool:
	return normalize(ProjectSettings.globalize_path(a)).to_lower() == normalize(ProjectSettings.globalize_path(b)).to_lower()
