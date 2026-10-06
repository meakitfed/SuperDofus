## One animation of one resolved look, baked frame by frame (lazily) into GPU meshes.
##
## A frame is an ordered list of "layers" ready to be replayed on canvas items:
## consecutive draws sharing texture/blend/mask are merged into one mesh each, so a
## typical character frame is a handful of `canvas_item_add_mesh` calls.
## Shared between every sprite displaying the same (bone, skins, sub entities, anim).
class_name DofusBakedAnim
extends RefCounted

enum LayerKind { DRAW, MASK, SUB }

## Layer dictionary keys:
##   kind: LayerKind, parent: int (-1 = sprite root, else index of a MASK layer)
##   blend: int (Flash blend), cm: int (colour matrix id, -1 none)
##   meshes: Array of [mesh RID, texture RID]
##   key/origin/extra: carried sub-entity reference (SUB)

const _FMT := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) \
		| (Mesh.ARRAY_CUSTOM_R_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)

var anim_name: String
var clip: DofusAnimClip
var resolver: DofusLookResolver
var frame_count := 0

var _frames: Array = [] # Array[Array[Dictionary]] or null when not baked yet
var _bounds: Array = [] # Rect2 per baked frame
var _rids: Array[RID] = []

# batch being assembled
var _b_key: Array = []
var _b_verts := PackedVector2Array()
var _b_uvs := PackedVector2Array()
var _b_colors := PackedColorArray()
var _b_add := PackedFloat32Array()
var _b_idx := PackedFloat32Array()
var _ops: Array = []


func _init(p_anim_name: String, p_clip: DofusAnimClip, p_resolver: DofusLookResolver) -> void:
	anim_name = p_anim_name
	clip = p_clip
	resolver = p_resolver
	frame_count = clip.frame_count
	_frames.resize(frame_count)
	_bounds.resize(frame_count)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for rid in _rids:
			RenderingServer.free_rid(rid)


func is_baked(frame: int) -> bool:
	return _frames[frame] != null


## Layers of `frame` (baked on first access).
func get_layers(frame: int) -> Array:
	if frame_count == 0:
		return []
	frame = posmod(frame, frame_count)
	if _frames[frame] == null:
		_bake(frame)
	return _frames[frame]


func bake_all() -> void:
	for f in frame_count:
		if _frames[f] == null:
			_bake(f)


## Local bounds (Dofus space, unscaled, y up) of the given frame, sub entities excluded.
func get_frame_bounds(frame: int) -> Rect2:
	get_layers(frame)
	return _bounds[posmod(frame, frame_count)]


func get_bounds() -> Rect2:
	var total := Rect2()
	var first := true
	for f in frame_count:
		var r := get_frame_bounds(f)
		if r.size == Vector2.ZERO:
			continue
		total = r if first else total.merge(r)
		first = false
	return total


# ── baking ─────────────────────────────────────────────────────────────────────

func _bake(frame_index: int) -> void:
	_ops = []
	var data := clip.frames[frame_index]
	var order := clip.orders[frame_index]
	var bounds := Rect2()
	var has_bounds := false
	var i := 0
	var n := order.size()
	var serial := 0
	while i < n:
		var b := order[i] * DofusAnimClip.STRIDE
		var res := resolver.node_part(int(data[b + DofusAnimClip.F_SPRITE]), int(data[b + DofusAnimClip.F_CUSTOM]))
		if res[1] != null and res[0]:
			serial += 1
			var node_xf := DofusAnimClip.xform_of(data, b)
			var mul := Color(data[b + DofusAnimClip.F_MUL], data[b + DofusAnimClip.F_MUL + 1],
					data[b + DofusAnimClip.F_MUL + 2], data[b + DofusAnimClip.F_MUL + 3])
			var add := Color(data[b + DofusAnimClip.F_ADD], data[b + DofusAnimClip.F_ADD + 1],
					data[b + DofusAnimClip.F_ADD + 2], data[b + DofusAnimClip.F_ADD + 3])
			var node_mask := int(data[b + DofusAnimClip.F_MASK])
			var blend := int(data[b + DofusAnimClip.F_BLEND])
			var cm := int(data[b + DofusAnimClip.F_MATRIX_ID])
			for item: Array in resolver.process(res[1]):
				if item[0] == DofusLookResolver.LEAF:
					var chunk: DofusSkinPart.Chunk = item[2]
					var skin: DofusSkinAsset = item[3]
					if chunk.texture_index >= skin.textures.size():
						continue
					var tex := skin.textures[chunk.texture_index]
					var mask := chunk.mask if chunk.mask != 0 else node_mask
					# masked draws are never merged across nodes: each is one stencil op
					var key := [tex, blend, mask, cm, serial if mask != 0 else 0]
					if key != _b_key:
						_flush()
						_b_key = key
					var xf: Transform2D = node_xf * (item[1] as Transform2D)
					if mask == DofusAnimClip.MaskFlag.SET or mask == DofusAnimClip.MaskFlag.CLEAR:
						# stencil shapes only use the texture alpha
						_append(xf, chunk, Color.WHITE, Color(0, 0, 0, 0))
					else:
						_append(xf, chunk, mul, add)
					if mask != DofusAnimClip.MaskFlag.SET and mask != DofusAnimClip.MaskFlag.CLEAR:
						var r := xf * chunk.bounds
						bounds = r if not has_bounds else bounds.merge(r)
						has_bounds = true
				else:
					_flush()
					var extra: Transform2D = item[2] if item[3] else Transform2D.IDENTITY
					# the same carried sprite mounted twice in a frame: keep the last one
					for k in range(_ops.size() - 1, -1, -1):
						if _ops[k]["kind"] == LayerKind.SUB and _ops[k]["key"] == item[1]:
							_ops.remove_at(k)
					_ops.append({"kind": LayerKind.SUB, "key": item[1], "origin": node_xf.origin, "extra": extra})
		if res[2] and int(data[b + DofusAnimClip.F_CHILDREN]) > 0:
			i += int(data[b + DofusAnimClip.F_CHILDREN])
		i += 1
	_flush()
	_frames[frame_index] = _plan_layers(_ops)
	_bounds[frame_index] = bounds
	_ops = []


func _append(xf: Transform2D, chunk: DofusSkinPart.Chunk, mul: Color, add: Color) -> void:
	var count := chunk.positions.size()
	_b_verts.append_array(xf * chunk.positions)
	_b_uvs.append_array(chunk.uvs)
	_b_idx.append_array(chunk.color_idx)
	var colors := PackedColorArray()
	colors.resize(count)
	colors.fill(mul)
	_b_colors.append_array(colors)
	var start := _b_add.size()
	_b_add.resize(start + count * 4) # new elements are zeroed
	if add != Color(0, 0, 0, 0):
		for v in count:
			var o := start + v * 4
			_b_add[o] = add.r
			_b_add[o + 1] = add.g
			_b_add[o + 2] = add.b
			_b_add[o + 3] = add.a


func _flush() -> void:
	if _b_verts.is_empty():
		_b_key = []
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _b_verts
	arrays[Mesh.ARRAY_TEX_UV] = _b_uvs
	arrays[Mesh.ARRAY_COLOR] = _b_colors
	arrays[Mesh.ARRAY_CUSTOM0] = _b_add
	arrays[Mesh.ARRAY_CUSTOM1] = _b_idx
	var mesh := RenderingServer.mesh_create()
	RenderingServer.mesh_add_surface_from_arrays(mesh, RenderingServer.PRIMITIVE_TRIANGLES, arrays, [], {}, _FMT)
	_rids.append(mesh)
	var tex: Texture2D = _b_key[0]
	_ops.append({"kind": LayerKind.DRAW, "mesh": mesh, "texture": tex.get_rid(),
			"blend": _b_key[1], "mask": _b_key[2], "cm": _b_key[3], "serial": _b_key[4]})
	_b_key = []
	_b_verts = PackedVector2Array()
	_b_uvs = PackedVector2Array()
	_b_colors = PackedColorArray()
	_b_add = PackedFloat32Array()
	_b_idx = PackedFloat32Array()


## Turns the op stream into canvas-item layers. Stencil masks become Godot clip groups:
## a CLIP_ONLY layer drawing the mask shape, with the OBEY draws as its children.
## Godot cannot nest clip groups, so masks are flattened: content obeys the innermost
## open mask only (the stencil intersection of nested masks is approximated), and a mask
## that no draw obeys is dropped entirely (it has no visible effect).
static func _plan_layers(ops: Array) -> Array:
	var layers: Array = []
	var stack: Array = [] # open masks: {"serial", "meshes", "layer"}
	var open_layer := -1 # mask layer currently receiving OBEY draws
	for op: Dictionary in ops:
		if op["kind"] == LayerKind.SUB:
			layers.append({"kind": LayerKind.SUB, "parent": -1, "key": op["key"], "origin": op["origin"], "extra": op["extra"]})
			open_layer = -1
			continue
		var mask: int = op["mask"]
		var mesh_ref := [op["mesh"], op["texture"]]
		if mask == DofusAnimClip.MaskFlag.CLEAR:
			if not stack.is_empty():
				stack.pop_back()
			open_layer = -1
			continue
		if mask == DofusAnimClip.MaskFlag.SET:
			if not stack.is_empty() and stack.back()["serial"] == op["serial"]:
				(stack.back()["meshes"] as Array).append(mesh_ref) # same mask node, other texture
			else:
				stack.push_back({"serial": op["serial"], "meshes": [mesh_ref], "layer": -1})
			open_layer = -1
			continue
		var parent := -1
		if mask == DofusAnimClip.MaskFlag.OBEY and not stack.is_empty():
			var top: Dictionary = stack.back()
			if open_layer < 0 or open_layer != top["layer"]:
				layers.append({"kind": LayerKind.MASK, "parent": -1, "blend": 0, "cm": -1, "meshes": top["meshes"]})
				top["layer"] = layers.size() - 1
				open_layer = top["layer"]
			parent = open_layer
		else:
			open_layer = -1
		var last: Dictionary = layers.back() if not layers.is_empty() else {}
		if not last.is_empty() and last["kind"] == LayerKind.DRAW and last["parent"] == parent 				and last["blend"] == op["blend"] and last["cm"] == op["cm"]:
			(last["meshes"] as Array).append(mesh_ref)
		else:
			layers.append({"kind": LayerKind.DRAW, "parent": parent, "blend": op["blend"], "cm": op["cm"], "meshes": [mesh_ref]})
	return layers
