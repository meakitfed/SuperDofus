## One graphic symbol: a small display list whose `-1` entries draw the next mesh chunk
## and whose other entries place referenced symbols with an affine transform.
class_name DofusSkinPart
extends RefCounted


## Triangle soup (de-indexed, so frames can be assembled with native array appends).
class Chunk:
	extends RefCounted
	var texture_index := 0
	var mask := 0
	var positions := PackedVector2Array()
	var uvs := PackedVector2Array()
	var color_idx := PackedFloat32Array()
	var bounds := Rect2()

	func is_empty() -> bool:
		return positions.is_empty()


var name: String
var source: DofusSkinAsset
var symbol_ids := PackedInt32Array()
var entry_counts := PackedInt32Array()
var entry_xforms: Array[Transform2D] = []
var chunks: Array[Chunk] = []
var valid := false


func _init(stub: Dictionary, p_source: DofusSkinAsset) -> void:
	name = str(stub.get("name", ""))
	source = p_source
	for e: Dictionary in stub.get("DisplayListEntry", []):
		symbol_ids.append(int(e["symbolId"]))
		entry_counts.append(int(e["entries"]))
		var t: Dictionary = e["transform"]
		# row-major [[rX, -rY, tX], [-uX, uY, -tY]]
		entry_xforms.append(Transform2D(
			Vector2(t["rX"], -t["uX"]),
			Vector2(-t["rY"], t["uY"]),
			Vector2(t["tX"], -t["tY"])))
	for c: Dictionary in stub.get("skinChunks", []):
		chunks.append(_build_chunk(c))
		if int(c["vertexCount"]) > 0:
			valid = true


func _build_chunk(c: Dictionary) -> Chunk:
	var chunk := Chunk.new()
	chunk.texture_index = int(c["textureIndex"])
	chunk.mask = int(c["maskState"])
	var start_v := int(c["startVertexIndex"])
	var start_i := int(c["startIndexIndex"])
	var count := int(c["indexCount"])
	if int(c["vertexCount"]) <= 0 or count <= 0:
		return chunk
	chunk.positions.resize(count)
	chunk.uvs.resize(count)
	chunk.color_idx.resize(count)
	var tris := source.triangles
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for k in count:
		var v := tris[start_i + k] + start_v
		var p := source.positions[v]
		chunk.positions[k] = p
		chunk.uvs[k] = source.uvs[v]
		chunk.color_idx[k] = source.color_idx[v]
		lo = lo.min(p)
		hi = hi.max(p)
	chunk.bounds = Rect2(lo, hi - lo)
	return chunk


func symbol_name(entry_index: int) -> String:
	var id := symbol_ids[entry_index]
	if id < 0 or id >= source.referenced_symbols.size():
		return ""
	return source.referenced_symbols[id]


## Skip a referenced symbol's inline children; returns Vector2i(next_index, next_draw_index).
func index_update(index: int, draw_index: int) -> Vector2i:
	var next := index + 1
	var end := next + maxi(entry_counts[index], 0)
	var d := draw_index
	for i in range(next, mini(end, entry_counts.size())):
		if entry_counts[i] == -1:
			d += 1
	return Vector2i(end, d)
