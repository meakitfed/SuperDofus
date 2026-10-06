## Renders a Dofus 3 map (Content/Maps/<id>.json + Maps/Gfx/<gfxId>.webp, see
## tools/extractor/maps.py) in the renderer's screen space: cell 0 centre at (0, 0),
## 86 x 43 cells. This node draws the background layer; the caller provides:
##   sort_parent  a y-sorted node shared with the entities: sortable elements and
##                animated props are inserted there, ordered like the client (cellId,
##                then inner order), always behind entities standing on the same row;
##   fg_parent    a node drawn above the entities, for the foreground layer.
class_name DofusMapNode
extends Node2D

const MAPS := "Content/Maps"
const ROW_H := 21.5

static var _textures := {} # gfxId -> Texture2D (null = missing)
static var _defs := {}
static var _add_material: CanvasItemMaterial
static var _mul_material: ShaderMaterial
## Unity blend (DstColor, OneMinusSrcAlpha) with premultiplied colour = dst * mix(1, src, a):
## a multiply that respects alpha (Godot's plain MUL ignores it: transparent texels would tint)
const MUL_SHADER := """
shader_type canvas_item;
render_mode blend_mul;
void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	COLOR = vec4(mix(vec3(1.0), c.rgb, c.a), 1.0);
}
"""

var map_id := 0
var def: Dictionary = {}
var _sortables: Node2D
var _foreground: Node2D


static func has_map(id: int) -> bool:
	return id > 0 and DofusContent.get_provider().exists("%s/%d.json" % [MAPS, id])


static func load_def(id: int) -> Dictionary:
	if not _defs.has(id):
		var d: Variant = DofusContent.get_provider().read_json("%s/%d.json" % [MAPS, id])
		_defs[id] = d if d is Dictionary else {}
	return _defs[id]


## Builds the map; false if its visuals were not extracted.
func build(id: int, sort_parent: Node2D, fg_parent: Node2D) -> bool:
	clear()
	def = load_def(id)
	if def.is_empty():
		return false
	map_id = id
	var layers: Dictionary = def["layers"]
	for e: Dictionary in layers["background"]:
		_add_element(self, e)
	_sortables = Node2D.new()
	_sortables.name = "MapSortables"
	_sortables.y_sort_enabled = true
	sort_parent.add_child(_sortables)
	for e: Dictionary in layers["sortable"]:
		var holder := Node2D.new()
		holder.position.y = sort_y(int(e.get("cell", 0)), int(e.get("o", 0)))
		_sortables.add_child(holder)
		_add_element(holder, e)
	for e: Dictionary in def.get("animated", []):
		var holder := Node2D.new()
		holder.position.y = sort_y(int(e.get("cell", 0)), int(e.get("o", 0)))
		_sortables.add_child(holder)
		_add_prop(holder, e)
	_foreground = Node2D.new()
	_foreground.name = "MapForeground"
	fg_parent.add_child(_foreground)
	for e: Dictionary in layers["foreground"]:
		_add_element(_foreground, e)
	return true


func clear() -> void:
	for c in get_children():
		c.queue_free()
	if _sortables != null:
		_sortables.queue_free()
		_sortables = null
	if _foreground != null:
		_foreground.queue_free()
		_foreground = null
	map_id = 0
	def = {}


## Map background colour (ARGB in the data).
func background_color() -> Color:
	return _argb(int(def.get("bg", 0xff000000)), 255.0)


## Sort key of an element on `cell`: cellId order, just above the previous row and
## below any entity whose feet are on this row (entities sort by their feet y).
static func sort_y(cell: int, order: int) -> float:
	return (cell / 14) * ROW_H - 0.9 + (cell % 14) * 0.05 + mini(order, 9) * 0.004


func _add_element(parent: Node2D, e: Dictionary) -> void:
	var tex := _texture(int(e["g"]))
	if tex == null:
		return
	var s := Sprite2D.new()
	s.texture = tex
	var t: Array = e["t"]
	s.transform = Transform2D(Vector2(t[0], t[1]), Vector2(t[2], t[3]), Vector2(t[4], t[5] - parent.position.y))
	s.modulate = _argb(int(e["c"]), 128.0)
	match str(e.get("m", "")):
		"add":
			s.material = _material(CanvasItemMaterial.BLEND_MODE_ADD)
		"mul":
			s.material = _material(CanvasItemMaterial.BLEND_MODE_MUL)
	parent.add_child(s)


func _add_prop(parent: Node2D, e: Dictionary) -> void:
	var sprite := DofusSprite.new()
	sprite.is_prop = true
	sprite.bone_name = str(int(e["g"])) # JSON numbers are floats
	var t: Array = e["t"]
	sprite.transform = Transform2D(Vector2(t[0], t[1]), Vector2(t[2], t[3]), Vector2(t[4], t[5] - parent.position.y))
	sprite.modulate = _argb(int(e["c"]), 128.0)
	sprite.playing = int(e.get("play", 1)) != 0
	parent.add_child(sprite)
	sprite.look_string = "{%d}" % int(e["g"])


static func _argb(v: int, rgb_scale: float) -> Color:
	return Color(((v >> 16) & 255) / rgb_scale, ((v >> 8) & 255) / rgb_scale, (v & 255) / rgb_scale, ((v >> 24) & 255) / 255.0)


static func _texture(gfx: int) -> Texture2D:
	if not _textures.has(gfx):
		var img := DofusContent.get_provider().load_image("%s/Gfx/%d" % [MAPS, gfx])
		_textures[gfx] = ImageTexture.create_from_image(img) if img != null else null
	return _textures[gfx]


static func _material(mode: CanvasItemMaterial.BlendMode) -> Material:
	if mode == CanvasItemMaterial.BLEND_MODE_ADD:
		if _add_material == null:
			_add_material = CanvasItemMaterial.new()
			_add_material.blend_mode = mode
		return _add_material
	if _mul_material == null:
		var sh := Shader.new()
		sh.code = MUL_SHADER
		_mul_material = ShaderMaterial.new()
		_mul_material.shader = sh
	return _mul_material
