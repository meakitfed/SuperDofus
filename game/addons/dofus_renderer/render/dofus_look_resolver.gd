## Resolves what each animation node draws for one (bone bundle, skins, sub entities)
## combination: base bone graphics, skin customisations, slot rules and carried sprites.
## Port of d3-ts-renderer's AssetManager; results are cached and shared by every sprite
## using the same combination.
class_name DofusLookResolver
extends RefCounted

## Items of a compiled element, in draw order.
const LEAF := 0 # [LEAF, Transform2D, DofusSkinPart.Chunk, DofusSkinAsset]
const SUB := 1 # [SUB, key, Transform2D, has_transform]

var bone: DofusBoneDef
var sub_keys: Dictionary = {}

var _custom_symbol_ref: Dictionary = {} # symbol -> DofusSkinAsset
var _intended_empty: Dictionary = {}
var _rules_empty: Dictionary = {}
var _custom_cache: Dictionary = {} # symbol -> [part_or_key, customised]
var _node_cache: Dictionary = {} # Vector2i(custom, sprite) -> [found, part_or_key, customised]
var _processed: Dictionary = {} # DofusSkinPart or key -> Array of items


## `skins` must be ordered as in the look: later skins override earlier ones.
func _init(p_bone: DofusBoneDef, skins: Array[DofusSkinAsset], hidden_slots: Dictionary, p_sub_keys: PackedStringArray) -> void:
	bone = p_bone
	for key in p_sub_keys:
		sub_keys[key] = true
	for skin in skins:
		for symbol in skin.keys:
			_custom_symbol_ref[symbol] = skin
		for empty in skin.empty_customisations:
			_custom_symbol_ref.erase(empty)
	for skin in skins:
		for empty in skin.empty_customisations:
			_intended_empty[empty] = true
	_rules_empty = hidden_slots


## Returns [found, part (DofusSkinPart) or sub-entity key (String) or null, customised].
func node_part(sprite_index: int, custom_index: int) -> Array:
	if sprite_index == -1 and custom_index == -1:
		return [false, null, false]
	var key := Vector2i(maxi(-2, custom_index), maxi(-1, sprite_index))
	var cached: Variant = _node_cache.get(key)
	if cached != null:
		return cached

	var customised := false
	var graphic: Variant = bone.get_graphic(sprite_index)
	if custom_index != -1:
		var r: Array
		if graphic == null:
			var symbol := bone.exposed_name(custom_index)
			if symbol != "":
				r = _custom_part(symbol)
				graphic = r[0]
				customised = r[1]
		else:
			r = _custom_part((graphic as DofusSkinPart).name)
			graphic = r[0]
			customised = r[1]

	var result: Array
	if graphic == null:
		result = [false, null, customised]
	elif graphic is DofusSkinPart:
		result = [(graphic as DofusSkinPart).valid, graphic, customised]
	else:
		result = [true, graphic, customised]
	_node_cache[key] = result
	return result


## [part_or_key_or_null, customised]
func _custom_part(symbol: String) -> Array:
	var cached: Variant = _custom_cache.get(symbol)
	if cached != null:
		return cached
	var r: Array
	if _rules_empty.has(symbol):
		r = [null, true]
	elif symbol.begins_with("carried_") and sub_keys.has(symbol):
		r = [symbol, true]
	elif not symbol.begins_with("carried_") and _custom_symbol_ref.has(symbol):
		r = [(_custom_symbol_ref[symbol] as DofusSkinAsset).get_part(symbol), true]
	else:
		r = [null, _intended_empty.has(symbol)]
	_custom_cache[symbol] = r
	return r


## Flattened draw items of a part (its display list walked recursively).
func process(part: Variant) -> Array:
	var cached: Variant = _processed.get(part)
	if cached != null:
		return cached
	var items: Array
	if part is DofusSkinPart:
		items = _walk(part, Transform2D.IDENTITY)
	else:
		items = [[SUB, part, Transform2D.IDENTITY, false]]
	_processed[part] = items
	return items


func _walk(part: DofusSkinPart, xform: Transform2D) -> Array:
	var result: Array = []
	var index := 0
	var draw_index := 0
	var count := part.entry_counts.size()
	while index < count:
		if part.entry_counts[index] == -1:
			if draw_index < part.chunks.size():
				var chunk := part.chunks[draw_index]
				if not chunk.is_empty():
					result.append([LEAF, xform, chunk, part.source])
				draw_index += 1
			index += 1
			continue
		if part.symbol_ids[index] < 0:
			index += 1
			continue
		var symbol := part.symbol_name(index)
		if symbol == "" or symbol == part.name:
			index += 1
			continue
		var r := _custom_part(symbol)
		var new_part: Variant = r[0]
		if new_part == null and not r[1]:
			index += 1
			continue
		if new_part is DofusSkinPart:
			if (new_part as DofusSkinPart).source == part.source:
				index += 1
				continue
			result.append_array(_walk(new_part, xform * part.entry_xforms[index]))
		elif new_part != null:
			result.append([SUB, new_part, xform * part.entry_xforms[index], true])
		var next := part.index_update(index, draw_index)
		index = next.x
		draw_index = next.y
	return result
