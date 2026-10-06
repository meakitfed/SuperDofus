extends TestCase


func test_parse_basic() -> void:
	var look := DofusLook.parse("{1|120,2195,3042|1=16777215,2=#ff0000|56}")
	eq(look.bone, 1)
	eq(look.skins, PackedInt32Array([120, 2195, 3042]))
	near(look.size, 0.56)
	near((look.colors[1] as Vector3).x, 255.0 / 127.0, 0.0001, "colours are divided by 127")
	near((look.colors[2] as Vector3).x, 255.0 / 127.0)
	near((look.colors[2] as Vector3).y, 0.0)


func test_parse_empty_fields() -> void:
	var look := DofusLook.parse("{2069|||150}")
	eq(look.bone, 2069)
	eq(look.skins.size(), 0)
	eq(look.colors.size(), 0)
	near(look.size, 1.5)


func test_sub_entities_nested_and_multiple() -> void:
	var look := DofusLook.parse("{2013|||100|2@0={2|120,2195|1=255|56|1@0={1420|||90}},6@0={9702|||100}}")
	eq(look.bone, 2013)
	var rider := look.get_sub_entity(DofusSubEntity.Category.MOUNT_DRIVER)
	check(rider != null, "rider parsed")
	eq(rider.bone, 2)
	near(rider.size, 0.56)
	var pet := rider.get_sub_entity(DofusSubEntity.Category.PET)
	check(pet != null, "nested pet parsed")
	eq(pet.bone, 1420)
	eq(look.get_sub_entity(DofusSubEntity.Category.BASE_FOREGROUND).bone, 9702)
	eq(look.sub_entity_keys(), PackedStringArray(["carried_2_0", "carried_6_0"]))


func test_reference_style_subentities_without_separator() -> void:
	# the reference toString joins sub entities without a comma
	var look := DofusLook.parse("{1|120|1=0|56|4@0={9703|||100}6@0={9702|||100}}")
	eq(look.sub_entity_keys(), PackedStringArray(["carried_4_0", "carried_6_0"]))


func test_number_base_header() -> void:
	var look := DofusLook.parse("[1,Z]{1|3c,1ov||1k}")
	eq(look.skins, PackedInt32Array([120, 2191]))
	near(look.size, 0.56)


func test_conditional_look_picks_unconditioned() -> void:
	# `look$index;condition` — the entry with an empty condition is the default one
	var look := DofusLook.parse("{1|10||100}$1;PO=9910,{1|11||100}$2;")
	eq(look.skins, PackedInt32Array([11]))


func test_roundtrip() -> void:
	var src := "{1|120,2195|1=16777215,2=4077879|56|1@0={1420|||90}}"
	var again := DofusLook.parse(str(DofusLook.parse(src)))
	eq(str(again), str(DofusLook.parse(src)))
	eq(DofusLook.rgb_to_int(DofusLook.int_to_rgb(16777215)), 16777215, "colour round trip is lossless")


func test_palette() -> void:
	var look := DofusLook.parse("{1|10|3=8323072|100}")
	var p := look.palette()
	eq(p.size(), 16)
	eq(p[0], Vector3.ONE)
	near(p[3].x, 127.0 / 127.0)
	near(p[3].y, 0.0)


func test_rider_to_mount_colors() -> void:
	var c := DofusLook.rider_to_mount_colors({3: Vector3.ONE, 6: Vector3.ZERO, 1: Vector3(0.5, 0.5, 0.5)})
	eq(c.keys().size(), 2)
	eq(c[1], Vector3.ONE)
	eq(c[4], Vector3.ZERO)
