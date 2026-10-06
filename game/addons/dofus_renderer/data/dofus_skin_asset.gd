## A skin (or a bone's own base skin): a library of named graphic symbols sharing one
## vertex/triangle pool and a few texture atlases.
class_name DofusSkinAsset
extends RefCounted

var name: String = ""
var keys: PackedStringArray = PackedStringArray()
var part_stubs: Array = []
## symbol name -> index into part_stubs (first occurrence wins, like indexOf)
var key_index: Dictionary = {}
var referenced_symbols: PackedStringArray = PackedStringArray()
var empty_customisations: PackedStringArray = PackedStringArray()

var positions: PackedVector2Array = PackedVector2Array()
var uvs: PackedVector2Array = PackedVector2Array()
## per-vertex palette slot (vertex pos.z), 0 = not recoloured
var color_idx: PackedFloat32Array = PackedFloat32Array()
var triangles: PackedInt32Array = PackedInt32Array()
var textures: Array[Texture2D] = []

var _parts: Dictionary = {}


static func from_json(data: Dictionary, p_textures: Array[Texture2D]) -> DofusSkinAsset:
	var skin := DofusSkinAsset.new()
	skin.name = str(data.get("m_Name", ""))
	skin.keys = PackedStringArray(data.get("m_keys", []))
	skin.part_stubs = data.get("m_values", [])
	for i in skin.keys.size():
		if not skin.key_index.has(skin.keys[i]):
			skin.key_index[skin.keys[i]] = i
	skin.referenced_symbols = PackedStringArray(data.get("referencedSymbols", []))
	skin.empty_customisations = PackedStringArray(data.get("emptyCustomisations", []))
	skin.triangles = PackedInt32Array(data.get("triangles", []))
	var verts: Array = data.get("vertices", [])
	var n := verts.size()
	skin.positions.resize(n)
	skin.uvs.resize(n)
	skin.color_idx.resize(n)
	for i in n:
		var v: Dictionary = verts[i]
		var pos: Dictionary = v["pos"]
		var uv: Dictionary = v["uv"]
		skin.positions[i] = Vector2(pos["x"], pos["y"])
		skin.color_idx[i] = pos["z"]
		skin.uvs[i] = Vector2(uv["x"], uv["y"])
	skin.textures = p_textures
	return skin


func has_symbol(symbol: String) -> bool:
	return key_index.has(symbol)


## Compiled part for one of this skin's symbols (cached).
func get_part(symbol: String) -> DofusSkinPart:
	var cached: DofusSkinPart = _parts.get(symbol)
	if cached != null:
		return cached
	var i: int = key_index.get(symbol, -1)
	if i < 0:
		return null
	var part := DofusSkinPart.new(part_stubs[i], self)
	_parts[symbol] = part
	return part


## Compile an arbitrary stub that references this skin's geometry (bone graphics).
func compile_stub(stub: Dictionary) -> DofusSkinPart:
	return DofusSkinPart.new(stub, self)


func texture_count() -> int:
	return textures.size()
