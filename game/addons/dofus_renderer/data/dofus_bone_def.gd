## An animated object definition (one bone bundle): base graphics, the node names
## that skins can customise, and the list of animations (.dat files).
class_name DofusBoneDef
extends RefCounted

var name: String = ""
var is_prop := false
var frame_rate := 30.0
var max_node_count := 0
var exposed_node_names: PackedStringArray = PackedStringArray()
var graphic_stubs: Array = []
## anim name -> Rect2 bounds (or null when the bundle left them undefined)
var animations: Dictionary = {}
var skin: DofusSkinAsset

var _graphics: Dictionary = {}


static func from_json(data: Dictionary, bone_skin: DofusSkinAsset, p_is_prop := false) -> DofusBoneDef:
	var bone := DofusBoneDef.new()
	bone.name = str(data.get("m_Name", ""))
	bone.is_prop = p_is_prop
	bone.frame_rate = maxf(float(data.get("defaultFrameRate", 30)), 1.0)
	bone.max_node_count = int(data.get("maxNodeCount", 0))
	bone.exposed_node_names = PackedStringArray(data.get("exposedNodeNames", []))
	bone.graphic_stubs = data.get("graphics", [])
	for anim: Dictionary in data.get("animations", []):
		var b: Variant = anim.get("bounds")
		var rect: Variant = null
		if b is Dictionary and b.get("width") != null:
			rect = Rect2(b["x"], b["y"], b["width"], b["height"])
		bone.animations[str(anim["name"])] = rect
	bone.skin = bone_skin
	return bone


func graphic_count() -> int:
	return graphic_stubs.size()


## Base graphic `index` compiled against the bone's own skin (cached).
func get_graphic(index: int) -> DofusSkinPart:
	if index < 0 or index >= graphic_stubs.size():
		return null
	var cached: DofusSkinPart = _graphics.get(index)
	if cached == null:
		cached = skin.compile_stub(graphic_stubs[index]["part"])
		_graphics[index] = cached
	return cached


func exposed_name(custom_index: int) -> String:
	if custom_index < 0 or custom_index >= exposed_node_names.size():
		return ""
	return exposed_node_names[custom_index]
