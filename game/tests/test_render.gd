## Integration tests on extracted content (skipped when content/ is empty).
extends TestCase

const LOOK := "{1|120,2195,3042,3069,3963|1=16777215,2=15335424|56|1@0={1420|||90}}"


func _has_content() -> bool:
	return DofusContent.get_bone("1-static") != null


func test_player_animations_span_bundles() -> void:
	if not _has_content():
		skip("no extracted content")
		return
	var anims := DofusContent.animations_for(1, PackedInt32Array([10]))
	eq(anims.get("AnimStatiqueExplo0_1"), "1-static")
	eq(anims.get("AnimMarche_1"), "1-movement")
	eq(anims.get("AnimAttaque0_1"), "1-combat")


func test_bake_character_frame() -> void:
	if not _has_content():
		skip("no extracted content")
		return
	var look := DofusLook.parse(LOOK)
	var inst := DofusSpriteInstance.new(look)
	check(inst.play("AnimStatiqueExplo0_1"), "play idle")
	var layers := inst.baked.get_layers(0)
	check(not layers.is_empty(), "frame has layers")
	var subs := layers.filter(func(l: Dictionary) -> bool: return l["kind"] == DofusBakedAnim.LayerKind.SUB)
	eq(subs.size(), 1, "pet is mounted once")
	var bounds := inst.baked.get_bounds()
	check(bounds.size.y > 50.0, "character has height")
	check(bounds.position.y < 0.0 and bounds.end.y > 50.0, "feet near origin, body upwards (y up)")
	var pet: DofusSpriteInstance = inst.subs.get("carried_1_0")
	check(pet != null and pet.baked != null, "pet plays a related animation")
	inst.destroy()


func test_resolver_customisation_overrides() -> void:
	if not _has_content():
		skip("no extracted content")
		return
	var bone := DofusContent.get_bone("1-static")
	var r := DofusContent.get_resolver(bone, PackedInt32Array([10, 2012]), PackedStringArray())
	var found_custom := false
	for i in bone.exposed_node_names.size():
		var res := r.node_part(-1, i)
		if res[1] is DofusSkinPart and res[2]:
			found_custom = true
			break
	check(found_custom, "some exposed node resolves to a body/head skin symbol")


func test_missing_bone_falls_back() -> void:
	if not _has_content():
		skip("no extracted content")
		return
	var anims := DofusContent.animations_for(987654321, PackedInt32Array())
	check(not anims.is_empty(), "fallback bone 666 used")
