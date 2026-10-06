## Runtime state of one displayed entity (and, recursively, of its carried sub entities):
## current animation, a pool of RenderingServer canvas items replaying baked layers,
## per-look materials (palette). Owned by DofusSprite; sub entities are owned by their parent.
class_name DofusSpriteInstance
extends RefCounted

## How stencil masks are rendered (see DofusSprite.MaskMode).
enum MaskMode { CLIP, HIDE_MASKED, IGNORE }

var look: DofusLook
var mask_mode: MaskMode = MaskMode.CLIP:
	set(value):
		mask_mode = value
		_shown_baked = null
		for sub: DofusSpriteInstance in subs.values():
			sub.mask_mode = value
var _parent_ref: WeakRef # weak: parents own their sub entities
var is_prop := false
var bone_name_override := ""

## Dofus space of this entity (y up). Layers and sub-entity roots are its children.
var root_item: RID
## anim name -> bone bundle holding it
var animations: Dictionary = {}
var subs: Dictionary = {} # "carried_<cat>_<idx>" -> DofusSpriteInstance
var anim_name := ""
var flip := false
var bone: DofusBoneDef
var baked: DofusBakedAnim
var frame := -1

var _palette := PackedVector3Array()
var _sub_keys := PackedStringArray()
var _materials: Dictionary = {}
var _pool: Array[RID] = []
var _pool_parent: Array[RID] = []
var _pool_group: Array[bool] = []
var _used := 0
var _shown_baked: DofusBakedAnim
var _visible_subs: Array[DofusSpriteInstance] = []
var _sub_xforms: Dictionary = {} # DofusSpriteInstance -> Transform2D in this entity's space


func _init(p_look: DofusLook, p_parent: DofusSpriteInstance = null, p_is_prop := false, p_bone_name := "") -> void:
	_parent_ref = weakref(p_parent) if p_parent != null else null
	is_prop = p_is_prop
	bone_name_override = p_bone_name
	root_item = RenderingServer.canvas_item_create()
	set_look(p_look)


func get_parent_instance() -> DofusSpriteInstance:
	return _parent_ref.get_ref() if _parent_ref != null else null


func destroy() -> void:
	for sub: DofusSpriteInstance in subs.values():
		sub.destroy()
	subs.clear()
	for rid in _pool:
		RenderingServer.free_rid(rid)
	_pool.clear()
	if root_item.is_valid():
		RenderingServer.free_rid(root_item)
		root_item = RID()
	baked = null
	_shown_baked = null
	_sub_xforms.clear()
	_visible_subs.clear()


# ── look ───────────────────────────────────────────────────────────────────────

func set_look(new_look: DofusLook) -> void:
	var old := look
	look = new_look
	var structural := old == null or old.bone != look.bone or not old.same_skins(look) \
			or old.sub_entity_keys() != look.sub_entity_keys()
	_palette = look.palette()
	for mat: ShaderMaterial in _materials.values():
		mat.set_shader_parameter("palette", _palette)
	_sync_sub_entities()
	if structural:
		_sub_keys = look.sub_entity_keys()
		animations = DofusContent.animations_for(look.bone, look.skins, is_prop, bone_name_override)
		_shown_baked = null
		if anim_name != "":
			if not play(anim_name):
				baked = null
	else:
		# colours / size only: same baked data, just refresh transforms and palettes
		_shown_baked = null
		_refresh_sub_anims()


func _sync_sub_entities() -> void:
	var wanted := {}
	for category: int in look.sub_entities:
		for binding: int in look.sub_entities[category]:
			var key := DofusLook.sub_entity_key(category, binding)
			var sub_look: DofusLook = look.sub_entities[category][binding]
			wanted[key] = true
			var existing: DofusSpriteInstance = subs.get(key)
			if existing != null:
				existing.set_look(sub_look)
			else:
				var sub := DofusSpriteInstance.new(sub_look, self, is_prop)
				sub.mask_mode = mask_mode
				RenderingServer.canvas_item_set_parent(sub.root_item, root_item)
				RenderingServer.canvas_item_set_visible(sub.root_item, false)
				subs[key] = sub
	for key: String in subs.keys():
		if not wanted.has(key):
			(subs[key] as DofusSpriteInstance).destroy()
			subs.erase(key)


# ── animation ──────────────────────────────────────────────────────────────────

## Plays an exact animation name (e.g. "AnimMarche_1"). Returns false if unknown.
func play(p_anim_name: String) -> bool:
	if not animations.has(p_anim_name):
		return false
	var bundle: String = animations[p_anim_name]
	var b := DofusContent.get_bone(bundle, is_prop)
	if b == null:
		return false
	var new_baked := DofusContent.get_baked(b, look.skins, _sub_keys, p_anim_name)
	if new_baked == null:
		return false
	if bone != b:
		_materials.clear()
	bone = b
	anim_name = p_anim_name
	baked = new_baked
	frame = -1
	_refresh_sub_anims()
	return true


func _refresh_sub_anims() -> void:
	for sub: DofusSpriteInstance in subs.values():
		var r := DofusAnimNames.related_child_anim(sub.animations, anim_name)
		if r[0] != "" and sub.play(r[0]):
			sub.flip = r[1] and not flip
		else:
			sub.baked = null


func frame_count() -> int:
	return baked.frame_count if baked != null else 0


func frame_rate() -> float:
	return bone.frame_rate if bone != null else 30.0


## Longest frame count of this animation and the sub entities it carries.
func max_frame_count() -> int:
	var n := frame_count()
	for sub: DofusSpriteInstance in subs.values():
		n = maxi(n, sub.max_frame_count())
	return n


# ── rendering ──────────────────────────────────────────────────────────────────

## Shows frame `tick` (wrapped on this animation's length). Sub entities loop on their own length.
func render(tick: int) -> void:
	if baked == null or baked.frame_count == 0:
		_hide_from(0)
		return
	var f := posmod(tick, baked.frame_count)
	if f != frame or baked != _shown_baked:
		frame = f
		_shown_baked = baked
		_apply_layers(baked.get_layers(f))
	for sub in _visible_subs:
		sub.render(tick)


func _apply_layers(layers: Array) -> void:
	var scale := Transform2D.IDENTITY.scaled(Vector2(look.size, look.size))
	var layer_items: Array[RID] = []
	layer_items.resize(layers.size())
	var shown_subs: Array[DofusSpriteInstance] = []
	_used = 0
	for i in layers.size():
		var layer: Dictionary = layers[i]
		var kind: int = layer["kind"]
		if kind == DofusBakedAnim.LayerKind.SUB:
			var sub: DofusSpriteInstance = subs.get(layer["key"])
			if sub == null or sub.baked == null:
				continue
			var t := Transform2D(0.0, (layer["origin"] as Vector2) * look.size) * (layer["extra"] as Transform2D)
			if sub.flip:
				t = t * Transform2D.FLIP_X
			RenderingServer.canvas_item_set_transform(sub.root_item, t)
			_sub_xforms[sub] = t
			RenderingServer.canvas_item_set_draw_index(sub.root_item, i)
			RenderingServer.canvas_item_set_visible(sub.root_item, true)
			shown_subs.append(sub)
			continue
		var p: int = layer["parent"]
		if mask_mode != MaskMode.CLIP:
			if kind == DofusBakedAnim.LayerKind.MASK:
				continue
			if p >= 0 and mask_mode == MaskMode.HIDE_MASKED:
				continue
		var item := _take_item()
		layer_items[i] = item
		var parent_rid := root_item if p < 0 or not layer_items[p].is_valid() else layer_items[p]
		var slot := _used - 1
		if _pool_parent[slot] != parent_rid:
			RenderingServer.canvas_item_set_parent(item, parent_rid)
			_pool_parent[slot] = parent_rid
		RenderingServer.canvas_item_set_transform(item, scale if parent_rid == root_item else Transform2D.IDENTITY)
		var is_group := kind == DofusBakedAnim.LayerKind.MASK
		if _pool_group[slot] != is_group:
			RenderingServer.canvas_item_set_canvas_group_mode(item,
					RenderingServer.CANVAS_GROUP_MODE_CLIP_ONLY if is_group else RenderingServer.CANVAS_GROUP_MODE_DISABLED)
			_pool_group[slot] = is_group
		# Godot clip groups only clip with the default material (a custom shader inverts them)
		RenderingServer.canvas_item_set_material(item, RID() if is_group else _material(layer["blend"], layer["cm"]).get_rid())
		RenderingServer.canvas_item_set_draw_index(item, i)
		RenderingServer.canvas_item_set_visible(item, true)
		RenderingServer.canvas_item_clear(item)
		for m: Array in layer["meshes"]:
			RenderingServer.canvas_item_add_mesh(item, m[0], Transform2D.IDENTITY, Color.WHITE, m[1])
	for sub in _visible_subs:
		if not shown_subs.has(sub):
			RenderingServer.canvas_item_set_visible(sub.root_item, false)
	_visible_subs = shown_subs
	_hide_from(_used)


func _take_item() -> RID:
	if _used >= _pool.size():
		var item := RenderingServer.canvas_item_create()
		RenderingServer.canvas_item_set_default_texture_filter(item, RenderingServer.CANVAS_ITEM_TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
				if DofusContent.texture_filter_mipmaps else RenderingServer.CANVAS_ITEM_TEXTURE_FILTER_LINEAR)
		RenderingServer.canvas_item_set_parent(item, root_item)
		_pool.append(item)
		_pool_parent.append(root_item)
		_pool_group.append(false)
	_used += 1
	return _pool[_used - 1]


func _hide_from(start: int) -> void:
	for k in range(start, _pool.size()):
		RenderingServer.canvas_item_clear(_pool[k])
		RenderingServer.canvas_item_set_visible(_pool[k], false)
	if start == 0:
		for sub in _visible_subs:
			RenderingServer.canvas_item_set_visible(sub.root_item, false)
		_visible_subs.clear()


func _material(blend: int, cm: int) -> ShaderMaterial:
	var key := Vector3i(blend, cm, baked.clip.get_instance_id() if cm >= 0 else 0)
	var mat: ShaderMaterial = _materials.get(key)
	if mat == null:
		var matrix := baked.clip.color_matrices[cm] if cm >= 0 and cm < baked.clip.color_matrices.size() else PackedFloat32Array()
		mat = DofusMaterials.create_material(blend, _palette, matrix)
		_materials[key] = mat
	return mat


## Local bounds (Dofus space, y up, size applied) of the current frame, sub entities included.
func current_bounds() -> Rect2:
	if baked == null:
		return Rect2()
	var r := baked.get_frame_bounds(maxi(frame, 0))
	r = Rect2(r.position * look.size, r.size * look.size)
	for sub in _visible_subs:
		var sb := sub.current_bounds()
		if sb.size != Vector2.ZERO:
			var t: Transform2D = _sub_xforms.get(sub, Transform2D.IDENTITY)
			r = r.merge(t * sb) if r.size != Vector2.ZERO else t * sb
	return r
