## Content access + shared caches (bones, skins, clips, resolved looks, baked
## animations). Static so it works everywhere (game, tools, tests) without an autoload;
## every DofusSprite goes through it, so two monsters with the same look share all
## their GPU data. Call `DofusContent.set_provider()` to read from another source.
class_name DofusContent
extends RefCounted

const SETTING_ROOT := "dofus_renderer/content_root"
## Optional extra roots (same `Content/...` layout) read before content_root, e.g. mods.
const SETTING_OVERLAYS := "dofus_renderer/content_overlays"
## Injection point: path of a script (extends DofusContentProvider, no-arg _init) that
## replaces the folder providers below, so a host can read content from anywhere (a cache
## downloaded from a server...) without the add-on knowing it.
const SETTING_PROVIDER := "dofus_renderer/content_provider_script"
const BONES := "Content/Characters/Bones"
const PROPS := "Content/Animations/Props"
const SKINS := "Content/Characters/Skins"
const FALLBACK_BONE := "666"
## generic bundles of a split bone, in lookup priority (breed-specific ones win over all)
const GENERIC_BUNDLE_ORDER := ["static", "movement", "combat", "static-explo", "combat-armes", "metier"]
const BAKED_CACHE_SIZE := 256

## Mipmaps smooth heavy zoom-outs but bleed neighbouring atlas islands into each other
## (coloured fringes); the reference renderer uses plain linear filtering.
static var texture_filter_mipmaps := false

static var _game_data: DofusGameData
static var _families: Dictionary = {}
static var _bones: Dictionary = {} # "b:<name>" / "p:<name>" -> DofusBoneDef (null = missing)
static var _skins: Dictionary = {} # id -> DofusSkinAsset (null = missing)
static var _clips: Dictionary = {} # "<bone>/<anim>" -> DofusAnimClip
static var _resolvers: Dictionary = {}
static var _baked: Dictionary = {} # key -> DofusBakedAnim (insertion order = LRU order)


static var _provider: DofusContentProvider
static var _clip_mutex := Mutex.new()


static func get_provider() -> DofusContentProvider:
	if _provider == null:
		var script_path: String = ProjectSettings.get_setting(SETTING_PROVIDER, "")
		if script_path != "":
			var injected: Variant = (load(script_path) as GDScript).new()
			if injected is DofusContentProvider:
				set_provider(injected)
				return _provider
			push_error("DofusContent: %s is not a DofusContentProvider" % script_path)
		var root: String = ProjectSettings.get_setting(SETTING_ROOT, "res://content")
		var overlays: PackedStringArray = ProjectSettings.get_setting(SETTING_OVERLAYS, PackedStringArray())
		if overlays.is_empty():
			set_provider(DofusFsContentProvider.new(root))
		else: # add-on content first, then the extracted content
			var layers: Array[DofusContentProvider] = []
			for o in overlays:
				layers.append(DofusFsContentProvider.new(o))
			layers.append(DofusFsContentProvider.new(root))
			set_provider(DofusLayeredContentProvider.new(layers))
	return _provider


static func get_game_data() -> DofusGameData:
	if _game_data == null:
		_game_data = DofusGameData.load_from(get_provider())
	return _game_data


static func set_provider(p: DofusContentProvider) -> void:
	_provider = p
	clear_caches()
	var fam: Variant = _provider.read_json(BONES + "/families.json")
	_families = fam if fam is Dictionary else {}


## The preload tasks started so far (wait_preloads).
static var _preload_tasks: Array[int] = []


## Waits for the running preload_clips tasks: a process that quits while they run crashes (headless tests
## call it before quitting).
static func wait_preloads() -> void:
	for id: int in _preload_tasks:
		WorkerThreadPool.wait_for_task_completion(id)
	_preload_tasks.clear()


static func clear_caches() -> void:
	_game_data = null
	_bones.clear()
	_skins.clear()
	_clip_mutex.lock()
	_clips.clear()
	_clip_mutex.unlock()
	_resolvers.clear()
	_baked.clear()


# ── raw assets ─────────────────────────────────────────────────────────────────

static func get_bone(bone_name: String, is_prop := false) -> DofusBoneDef:
	var key := ("p:" if is_prop else "b:") + bone_name
	if _bones.has(key):
		return _bones[key]
	var folder := "%s/%s" % [PROPS if is_prop else BONES, bone_name]
	var data: Variant = get_provider().read_json(folder + "/bone.json")
	var bone: DofusBoneDef = null
	if data is Dictionary:
		var skin_data: Variant = get_provider().read_json(folder + "/skin.json")
		if skin_data is Dictionary:
			var skin := DofusSkinAsset.from_json(skin_data, _load_textures(folder, (skin_data["textures"] as Array).size()))
			bone = DofusBoneDef.from_json(data, skin, is_prop)
			if bone.name == "":
				bone.name = bone_name
	else:
		push_warning("DofusContent: bone '%s' not found in %s" % [bone_name, folder])
	_bones[key] = bone
	return bone


static func get_skin(skin_id: int) -> DofusSkinAsset:
	if _skins.has(skin_id):
		return _skins[skin_id]
	var folder := "%s/%d" % [SKINS, skin_id]
	var data: Variant = get_provider().read_json(folder + "/skin.json")
	var skin: DofusSkinAsset = null
	if data is Dictionary:
		skin = DofusSkinAsset.from_json(data, _load_textures(folder, (data["textures"] as Array).size()))
	_skins[skin_id] = skin # missing skins are skipped, like the game does
	return skin


static func get_clip(bone: DofusBoneDef, anim_name: String) -> DofusAnimClip:
	var key := _clip_key(bone.name, bone.is_prop, anim_name)
	_clip_mutex.lock()
	var clip: DofusAnimClip = _clips.get(key)
	_clip_mutex.unlock()
	if clip == null:
		clip = _decode_clip(bone.name, bone.is_prop, anim_name)
		if clip != null:
			_clip_mutex.lock()
			_clips[key] = clip
			_clip_mutex.unlock()
	return clip


## Decodes animation clips on the WorkerThreadPool so the first play of a new
## animation/direction doesn't hitch. `anims` maps anim name -> bone bundle (see animations_for).
static func preload_clips(anims: Dictionary, is_prop := false) -> void:
	var todo: Array = []
	_clip_mutex.lock()
	for anim_name: String in anims:
		if not _clips.has(_clip_key(anims[anim_name], is_prop, anim_name)):
			todo.append([anims[anim_name], anim_name])
	_clip_mutex.unlock()
	if todo.is_empty():
		return
	get_provider()
	_preload_tasks.append(WorkerThreadPool.add_task(func() -> void:
		for job: Array in todo:
			var key := _clip_key(job[0], is_prop, job[1])
			_clip_mutex.lock()
			var done := _clips.has(key)
			_clip_mutex.unlock()
			if done:
				continue
			var clip := _decode_clip(job[0], is_prop, job[1])
			if clip != null:
				_clip_mutex.lock()
				_clips[key] = clip
				_clip_mutex.unlock(), true, "DofusContent.preload_clips"))


static func _clip_key(bone_name: String, is_prop: bool, anim_name: String) -> String:
	return "%s/%s/%s" % ["p" if is_prop else "b", bone_name, anim_name]


static func _decode_clip(bone_name: String, is_prop: bool, anim_name: String) -> DofusAnimClip:
	var folder := PROPS if is_prop else BONES
	var bytes := _provider.read_bytes("%s/%s/%s.dat" % [folder, bone_name, safe_file_name(anim_name)])
	return DofusAnimClip.from_bytes(bytes) if bytes.size() >= 8 else null


## Same percent-encoding as tools/extractor (Windows-forbidden characters and '%').
static func safe_file_name(anim_name: String) -> String:
	var out := ""
	for c in anim_name:
		out += "%%%02X" % c.unicode_at(0) if '<>:"/\\|?*%'.contains(c) else c
	return out


static func _load_textures(folder: String, count: int) -> Array[Texture2D]:
	var out: Array[Texture2D] = []
	for i in count:
		var img := get_provider().load_image("%s/%d" % [folder, i])
		if img == null:
			img = Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
		elif texture_filter_mipmaps:
			img.generate_mipmaps()
		out.append(ImageTexture.create_from_image(img))
	return out


# ── bones split in several bundles (player bone 1) ─────────────────────────────

static func is_family(bone_id: int) -> bool:
	get_provider() # loads the family index
	return _families.has(str(bone_id))


## anim name -> bundle (bone folder) for a look. Split bones pick the look's
## breed-specific bundles first, then the generic ones.
static func animations_for(bone_id: int, skins: PackedInt32Array, is_prop := false, bone_name := "") -> Dictionary:
	var out := {}
	if bone_name == "" and not is_prop and is_family(bone_id):
		var bundles: Dictionary = _families[str(bone_id)]
		var breed := get_game_data().breed_of(skins)
		var ordered: Array[String] = []
		for suffix: String in GENERIC_BUNDLE_ORDER:
			if bundles.has("%d-%s" % [bone_id, suffix]):
				ordered.append("%d-%s" % [bone_id, suffix])
		for bundle: String in bundles:
			var parts := bundle.split("-")
			if not ordered.has(bundle) and not (parts.size() >= 3 and parts[1].is_valid_int()):
				ordered.append(bundle)
		if breed > 0:
			for suffix in ["static", "combat"]:
				var own := "%d-%d-%s" % [bone_id, breed, suffix]
				if bundles.has(own):
					ordered.append(own)
		for bundle in ordered: # later bundles override earlier ones
			for anim: String in bundles[bundle]:
				out[anim] = bundle
		return out
	var name := bone_name if bone_name != "" else str(bone_id)
	var bone := get_bone(name, is_prop)
	if bone == null and not is_prop:
		name = FALLBACK_BONE
		bone = get_bone(name)
	if bone != null:
		for anim: String in bone.animations:
			out[anim] = name
	return out


# ── resolved looks & baked animations ──────────────────────────────────────────

static func get_resolver(bone: DofusBoneDef, skins: PackedInt32Array, sub_keys: PackedStringArray) -> DofusLookResolver:
	var key := "%s|%s|%s|%s" % [bone.is_prop, bone.name, skins, sub_keys]
	var resolver: DofusLookResolver = _resolvers.get(key)
	if resolver == null:
		var skin_assets: Array[DofusSkinAsset] = []
		for id in skins:
			var s := get_skin(id)
			if s != null:
				skin_assets.append(s)
		resolver = DofusLookResolver.new(bone, skin_assets, get_game_data().hidden_slots(skins), sub_keys)
		_resolvers[key] = resolver
	return resolver


static func get_baked(bone: DofusBoneDef, skins: PackedInt32Array, sub_keys: PackedStringArray, anim_name: String) -> DofusBakedAnim:
	var key := "%s|%s|%s|%s|%s" % [bone.is_prop, bone.name, skins, sub_keys, anim_name]
	var baked: DofusBakedAnim = _baked.get(key)
	if baked != null:
		_baked.erase(key) # refresh LRU position
		_baked[key] = baked
		return baked
	var clip := get_clip(bone, anim_name)
	if clip == null:
		return null
	baked = DofusBakedAnim.new(anim_name, clip, get_resolver(bone, skins, sub_keys))
	_baked[key] = baked
	while _baked.size() > BAKED_CACHE_SIZE:
		_baked.erase(_baked.keys()[0]) # sprites still hold the ones they display
	return baked


static func stats() -> Dictionary:
	return {"bones": _bones.size(), "skins": _skins.size(), "clips": _clips.size(),
			"resolvers": _resolvers.size(), "baked": _baked.size()}
