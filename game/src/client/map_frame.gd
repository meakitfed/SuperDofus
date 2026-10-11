## While the mouse points at a way out (an exit arrow, MapHover), what lies outside the
## playable cells (scenery overflowing the 14 x 20 grid, the background colour) fades into a
## light blur: the edge of the map, where a click changes map, shows for a moment. Nothing
## otherwise. Drawn above the map and the entities (it reads the screen behind it), below the HUD.
class_name MapFrame
extends Node2D

## iso coords -> texel (OFFSET + ix, OFFSET + iy) of the mask (MapGeometry.from_iso)
const OFFSET := 16 # iso x: 0..33, iso y: -13..19
const SIZE := 64
## fade in / out (per second)
const FADE_IN := 8.0
const FADE_OUT := 4.0
const SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform sampler2D cells : filter_nearest;
uniform vec2 cell_size;
uniform float offset;
uniform vec2 origin; // the rect's position: VERTEX is local to it
uniform float blur_px = 0.9;
uniform float darken = 0.12;
uniform float amount = 0.0;
varying vec2 world;

void vertex() {
	world = VERTEX + origin;
}

void fragment() {
	// the iso cell of this point (IsoGrid.world_to_cell), then the mask of the map's cells
	vec2 c = world / (cell_size * 0.5);
	ivec2 iso = ivec2(round(vec2(c.y + c.x, c.y - c.x) * 0.5));
	ivec2 t = iso + ivec2(int(offset));
	bool inside = all(greaterThanEqual(t, ivec2(0))) && all(lessThan(t, textureSize(cells, 0))) && texelFetch(cells, t, 0).r > 0.5;
	if (inside) {
		discard;
	}
	vec3 sum = vec3(0.0);
	float n = 0.0;
	for (int x = -2; x <= 2; x++) {
		for (int y = -2; y <= 2; y++) {
			sum += texture(screen_tex, SCREEN_UV + vec2(float(x), float(y)) * blur_px * SCREEN_PIXEL_SIZE).rgb;
			n += 1.0;
		}
	}
	COLOR = vec4(sum / n * (1.0 - darken), amount);
}
"""

static var _mask: ImageTexture
var _rect: ColorRect
## set by MapHover each frame: an exit arrow shows
var shown := false
var _amount := 0.0


func _ready() -> void:
	var copy := BackBufferCopy.new()
	copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	add_child(copy)
	var mat := ShaderMaterial.new()
	mat.shader = Shader.new()
	mat.shader.code = SHADER
	mat.set_shader_parameter("cells", mask())
	mat.set_shader_parameter("cell_size", Vector2(IsoGrid.CELL_W, IsoGrid.CELL_H))
	mat.set_shader_parameter("offset", float(OFFSET))
	_rect = ColorRect.new()
	_rect.material = mat
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var b := MapGeometry.screen_bounds().grow(4000.0) # far past any zoom
	_rect.position = b.position
	mat.set_shader_parameter("origin", b.position)
	_rect.size = b.size
	add_child(_rect)
	visible = false


func _process(delta: float) -> void:
	var to := 1.0 if shown else 0.0
	if is_equal_approx(_amount, to) and visible == shown:
		return
	_amount = move_toward(_amount, to, delta * (FADE_IN if shown else FADE_OUT))
	visible = _amount > 0.0
	(_rect.material as ShaderMaterial).set_shader_parameter("amount", _amount)


func amount() -> float:
	return _amount


## One texel per iso cell: white = a cell of the map.
static func mask() -> ImageTexture:
	if _mask == null:
		var img := Image.create(SIZE, SIZE, false, Image.FORMAT_L8)
		for cell in MapGeometry.CELL_COUNT:
			var iso := MapGeometry.to_iso(cell) + Vector2i(OFFSET, OFFSET)
			img.set_pixelv(iso, Color.WHITE)
		_mask = ImageTexture.create_from_image(img)
	return _mask
