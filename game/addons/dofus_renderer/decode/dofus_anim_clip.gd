## Decoded `.dat` animation: a Flash-like display list per frame.
##
## The file stores, per frame, every node slot with a *delta* of its render state
## (only changed fields). Deltas accumulate from frame 0, so the whole clip is
## resolved once here into dense per-frame records that can be indexed randomly.
class_name DofusAnimClip
extends RefCounted

enum NodeFlag { SPRITE_INDEX = 1, OPACITY = 2, COLOR_MUL = 4, COLOR_ADD = 8, MATRIX = 16, CUSTOMISATION = 32, MASK = 64, EXTENDED = 128 }
enum MaskFlag { NONE = 0, SET = 1, OBEY = 2, CLEAR = 4 }
enum Blend {
	NORMAL = 0, NORMAL_ALT = 1, LAYER = 2, MULTIPLY = 3, SCREEN = 4, LIGHTEN = 5, DARKEN = 6, DIFFERENCE = 7,
	ADD = 8, SUBTRACT = 9, INVERT = 10, ALPHA = 11, ERASE = 12, OVERLAY = 13, HARDLIGHT = 14, PREMULTIPLIED = 15,
}

## Record layout (floats) of one node slot inside a frame snapshot.
const F_SLOT := 0 # unused, kept for alignment/debug
const F_SPRITE := 1
const F_CUSTOM := 2
const F_CHILDREN := 3
const F_XFORM := 4 # 6 floats: x.x, y.x, origin.x, x.y, y.y, origin.y (row-major a00 a01 a02 a10 a11 a12)
const F_MUL := 10 # rgba
const F_ADD := 14 # rgba
const F_MASK := 18
const F_BLEND := 19
const F_ALPHA := 20
const F_MATRIX_ID := 21 # index into color_matrices, -1 when none
const STRIDE := 22

var frame_count := 0
var node_count := 0
## frame -> PackedStringArray of labels starting on that frame
var labels: Dictionary = {}
## one state snapshot per frame: PackedFloat32Array(node_count * STRIDE), indexed by slot
var frames: Array[PackedFloat32Array] = []
## draw order per frame: node slots in the order they must be drawn
var orders: Array[PackedInt32Array] = []
## 4x5 Flash colour matrices (20 floats each), referenced by F_MATRIX_ID
var color_matrices: Array[PackedFloat32Array] = []


static func from_bytes(data: PackedByteArray) -> DofusAnimClip:
	var clip := DofusAnimClip.new()
	clip._decode(data)
	return clip


static func xform_of(frame: PackedFloat32Array, base: int) -> Transform2D:
	return Transform2D(
		Vector2(frame[base + F_XFORM], frame[base + F_XFORM + 3]),
		Vector2(frame[base + F_XFORM + 1], frame[base + F_XFORM + 4]),
		Vector2(frame[base + F_XFORM + 2], frame[base + F_XFORM + 5]))


func frames_with_label(label: String) -> PackedInt32Array:
	var out := PackedInt32Array()
	for f: int in labels:
		if (labels[f] as PackedStringArray).has(label):
			out.append(f)
	return out


func _decode(data: PackedByteArray) -> void:
	frame_count = data.decode_u16(0)
	node_count = data.decode_u16(2)
	var label_count := data.decode_u16(4)
	var pos := 8
	for i in label_count:
		var frame := data.decode_u16(pos)
		var length := data[pos + 2]
		var label := data.slice(pos + 3, pos + 3 + length).get_string_from_utf8()
		pos = _align(pos + 3 + length, 2)
		var at_frame: PackedStringArray = labels.get(frame, PackedStringArray())
		at_frame.append(label) # packed arrays are values: write back
		labels[frame] = at_frame
	pos = _align(pos, 4)
	var offsets := PackedInt32Array()
	offsets.resize(frame_count)
	for i in frame_count:
		offsets[i] = data.decode_s32(pos + i * 4)

	# persistent per-slot state, advanced frame after frame
	var state := PackedFloat32Array()
	state.resize(node_count * STRIDE)
	for s in node_count:
		_reset_slot(state, s * STRIDE)

	frames.resize(frame_count)
	orders.resize(frame_count)
	for f in frame_count:
		pos = offsets[f]
		var order := PackedInt32Array()
		order.resize(node_count)
		for n in node_count:
			var slot := data.decode_s16(pos)
			pos += 2
			order[n] = slot
			pos = _read_delta(data, pos, state, slot * STRIDE)
		frames[f] = state.duplicate()
		orders[f] = order


static func _align(pos: int, n: int) -> int:
	var rem := pos % n
	return pos + (n - rem) if rem != 0 else pos


static func _reset_slot(state: PackedFloat32Array, b: int) -> void:
	state[b + F_SLOT] = 0
	state[b + F_SPRITE] = -1
	state[b + F_CUSTOM] = -1
	state[b + F_CHILDREN] = -1
	state[b + F_XFORM] = 1; state[b + F_XFORM + 1] = 0; state[b + F_XFORM + 2] = 0
	state[b + F_XFORM + 3] = 0; state[b + F_XFORM + 4] = 1; state[b + F_XFORM + 5] = 0
	for k in 4:
		state[b + F_MUL + k] = 1
		state[b + F_ADD + k] = 0
	state[b + F_MASK] = 0
	state[b + F_BLEND] = 0
	state[b + F_ALPHA] = 1
	state[b + F_MATRIX_ID] = -1


func _read_delta(data: PackedByteArray, pos: int, state: PackedFloat32Array, b: int) -> int:
	var flags := data[pos]
	pos += 1
	if flags & NodeFlag.OPACITY:
		state[b + F_ALPHA] = data[pos] / 127.0
		pos += 1
	pos = _align(pos, 4)
	if flags & (NodeFlag.SPRITE_INDEX | NodeFlag.CUSTOMISATION):
		state[b + F_SPRITE] = data.decode_s16(pos)
		state[b + F_CUSTOM] = data.decode_s16(pos + 2)
		state[b + F_CHILDREN] = data.decode_s16(pos + 4)
		pos = _align(pos + 6, 4)
	if flags & NodeFlag.COLOR_MUL:
		for k in 4:
			state[b + F_MUL + k] = data.decode_s8(pos + k) / 127.0
		pos += 4
	if flags & NodeFlag.COLOR_ADD:
		for k in 4:
			state[b + F_ADD + k] = data.decode_s8(pos + k) / 127.0
		pos += 4
	if flags & NodeFlag.MATRIX:
		for k in 6:
			state[b + F_XFORM + k] = data.decode_float(pos + k * 4)
		pos += 24
	if flags & NodeFlag.MASK:
		state[b + F_MASK] = data[pos]
		pos += 4
	if flags & NodeFlag.EXTENDED:
		pos = _read_extended(data, pos, state, b)
	return pos


## Blend mode + colour matrix + Flash filters. Filters (glow, blur, drop shadow) are
## skipped: the reference renderer parses but never draws them either.
func _read_extended(data: PackedByteArray, pos: int, state: PackedFloat32Array, b: int) -> int:
	var filter_flags := data[pos]
	state[b + F_BLEND] = data[pos + 1]
	pos += 4
	if filter_flags & 64:
		var m := PackedFloat32Array()
		m.resize(20)
		for k in 20:
			m[k] = data.decode_float(pos + k * 4)
		pos += 80
		state[b + F_MATRIX_ID] = color_matrices.size()
		color_matrices.append(m)
	var filter_count := data[pos]
	pos += 1
	for i in filter_count:
		var kind := data[pos]
		pos = _align(pos + 1, 4)
		if kind & 1: # drop shadow: rgba(4) + 5 f32 + 3 bools + pad + u32
			pos += 4 + 20 + 4 + 4
		if kind & 2: # blur: 2 f32 + i32
			pos += 12
		if kind & 4: # glow: rgba(4) + 3 f32 + 3 bools + pad + u32
			pos += 4 + 12 + 4 + 4
	return _align(pos, 4)
