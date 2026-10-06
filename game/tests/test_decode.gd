extends TestCase


## Builds a tiny 2-frame / 2-node .dat by hand (layout of the Unity client format).
func _synthetic_dat() -> PackedByteArray:
	var b := StreamPeerBuffer.new() # little endian
	b.put_u16(2) # frames
	b.put_u16(2) # nodes
	b.put_u16(1) # labels
	b.put_u8(0) # combined node state
	b.put_u8(0) # pad to 8
	b.put_u16(1) # label frame
	b.put_u8(3)
	b.put_data("hit".to_utf8_buffer()) # pos 14, aligned 2
	b.put_u16(0) # align 4 -> 16
	b.put_32(24) # frame 0 offset
	b.put_32(68) # frame 1 offset
	# frame 0 — slot 1: sprite + matrix
	b.put_16(1)
	b.put_u8(1 | 16)
	b.put_u8(0) # align 4 -> 28
	b.put_16(5); b.put_16(-1); b.put_16(0)
	b.put_u16(0) # align 4 -> 36
	for v in [2.0, 0.0, 10.0, 0.0, 3.0, -20.0]:
		b.put_float(v)
	# slot 0: multiplicative colour
	b.put_16(0)
	b.put_u8(4)
	b.put_u8(0) # align -> 64
	for v in [127, 0, 0, 127]:
		b.put_8(v)
	# frame 1 — slot 0 unchanged, slot 1 opacity only
	b.put_16(0)
	b.put_u8(0)
	b.put_u8(0) # align -> 72
	b.put_16(1)
	b.put_u8(2)
	b.put_u8(64) # opacity, pos 76 aligned
	return b.data_array


func test_decode_synthetic_clip() -> void:
	var data := _synthetic_dat()
	eq(data.size(), 76, "fixture size")
	var clip := DofusAnimClip.from_bytes(data)
	eq(clip.frame_count, 2)
	eq(clip.node_count, 2)
	eq(clip.labels.get(1), PackedStringArray(["hit"]))
	eq(clip.frames_with_label("hit"), PackedInt32Array([1]))
	eq(clip.orders[0], PackedInt32Array([1, 0]), "frame 0 draw order")
	eq(clip.orders[1], PackedInt32Array([0, 1]), "frame 1 draw order")
	var s := DofusAnimClip.STRIDE
	var f1 := clip.frames[1]
	eq(int(f1[s + DofusAnimClip.F_SPRITE]), 5, "sprite index persists across frames")
	near(f1[s + DofusAnimClip.F_ALPHA], 64.0 / 127.0)
	near(f1[DofusAnimClip.F_MUL + 1], 0.0, 0.0001, "mul colour persists")
	var xf := DofusAnimClip.xform_of(f1, s)
	eq(xf.x, Vector2(2, 0))
	eq(xf.y, Vector2(0, 3))
	eq(xf.origin, Vector2(10, -20))


func test_decode_real_clip_if_extracted() -> void:
	var bone := DofusContent.get_bone("1-static")
	if bone == null:
		skip("no extracted content")
		return
	var clip := DofusContent.get_clip(bone, "AnimStatiqueExplo0_1")
	check(clip != null)
	check(clip.frame_count > 1)
	eq(clip.node_count, clip.orders[0].size())
	for f in clip.frame_count:
		for slot in clip.orders[f]:
			check(slot >= 0 and slot < clip.node_count, "slot in range")


func test_skin_part_entry_matrix() -> void:
	var skin := DofusSkinAsset.new()
	var part := DofusSkinPart.new({"name": "x", "DisplayListEntry": [
		{"symbolId": 0, "entries": 0, "transform": {"rX": 1.0, "uX": 0.5, "rY": 0.25, "uY": 2.0, "tX": 7.0, "tY": 3.0}}],
		"skinChunks": []}, skin)
	var t := part.entry_xforms[0]
	# row-major [[rX, -rY, tX], [-uX, uY, -tY]]
	eq(t * Vector2(1, 0), Vector2(1.0 + 7.0, -0.5 - 3.0))
	eq(t * Vector2(0, 1), Vector2(-0.25 + 7.0, 2.0 - 3.0))


func test_hidden_slots_rules() -> void:
	var gd := DofusGameData.new()
	gd.bodies_by_skin[10] = {"breed": 1, "gender": 0}
	# hat 500 hides hair (id 5) except variant bits 1 and 2 (mask 0b00111 => only bit0 set test)
	gd.slot_rules[500] = {DofusGameData.SlotRuleType.DEFAULT: {0: [{"id": 5, "mask": 0}]}}
	gd.slot_rules[501] = {DofusGameData.SlotRuleType.BREED: {1: [{"id": 3, "mask": 1 | 2 | 4}]},
		DofusGameData.SlotRuleType.DEFAULT: {0: [{"id": 5, "mask": 0}]}}
	var hidden := gd.hidden_slots(PackedInt32Array([10, 2012, 500]))
	for n in ["cheveux_0", "cheveux_1", "cheveux_2", "cheveux_5", "cheveux_6"]:
		check(hidden.has(n), "hides " + n)
	check(not hidden.has("cheveux_3"), "index 3 is never produced")
	var h2 := gd.hidden_slots(PackedInt32Array([10, 2012, 501]))
	check(not h2.has("cheveux_0"), "breed rule wins over default")
	check(not h2.has("Chapeau_0") and not h2.has("Chapeau_1"), "masked bits kept")
	check(h2.has("Chapeau_2") and h2.has("Chapeau_5") and h2.has("Chapeau_6"))
	eq(gd.hidden_slots(PackedInt32Array([10, 2012])).size(), 0, "no equipment, nothing hidden")
