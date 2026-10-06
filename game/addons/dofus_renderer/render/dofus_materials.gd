## Shaders and materials for Dofus meshes.
##
## Per-vertex data baked in the frame meshes:
##   COLOR   = node multiplicative colour (x CanvasItem modulate, applied by Godot)
##   CUSTOM0 = node additive colour (rgba float)
##   CUSTOM1 = palette slot (float); 0 = not recoloured
## Uniforms: the look's 16-colour palette, optional Flash colour matrix.
class_name DofusMaterials
extends RefCounted

## Godot blend family used for a Flash blend mode, plus the fragment "keyword" fix-up
## the original renderer applies (MULTIPLY / SCREEN / INVERT).
enum GodotBlend { MIX, ADD, SUB, MUL, PREMUL }
enum Keyword { NONE = 0, MULTIPLY = 1, SCREEN = 2, INVERT = 3, SCREEN_PREMUL = 4 }

const _RENDER_MODES := {
	GodotBlend.MIX: "blend_mix",
	GodotBlend.ADD: "blend_add",
	GodotBlend.SUB: "blend_sub",
	GodotBlend.MUL: "blend_mul",
	GodotBlend.PREMUL: "blend_premul_alpha",
}

const _SHADER_TEMPLATE := """shader_type canvas_item;
render_mode %s;

uniform vec3 palette[16];
uniform int keyword = 0;
uniform bool use_color_matrix = false;
uniform vec4 color_matrix[5];

varying vec4 v_mul;
varying vec4 v_add;

void vertex() {
	int idx = int(CUSTOM1.x + 0.5);
	v_mul = (idx > 0 && idx < 16) ? COLOR * vec4(palette[idx], 1.0) : COLOR;
	v_add = CUSTOM0;
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	if (tex.a < 0.01) discard;
	vec4 c = tex * v_mul + v_add;
	if (use_color_matrix) {
		c = vec4(dot(c, color_matrix[0]), dot(c, color_matrix[1]), dot(c, color_matrix[2]), dot(c, color_matrix[3])) + color_matrix[4];
	}
	if (keyword == 1) {
		c.rgb = c.aaa * (c.rgb - vec3(1.0)) + vec3(1.0);
	} else if (keyword == 2) {
		c.rgb = c.aaa * c.rgb;
	} else if (keyword == 3) {
		c = c.aaaa;
	} else if (keyword == 4) {
		// screen via premultiplied blending: s + d * (1 - max(s)) ~= s + d * (1 - s)
		c.rgb = c.aaa * c.rgb;
		c.a = max(c.r, max(c.g, c.b));
	}
	COLOR = c;
}
"""

static var _shaders: Dictionary = {}


## Flash blend mode -> [GodotBlend, Keyword]. Godot's canvas blend modes are fixed
## (no MIN/MAX equations, no ONE_MINUS_SRC_COLOR), so screen/lighten/darken/invert
## are approximated; normal, add, subtract and multiply are exact.
static func map_blend(flash_blend: int) -> Array:
	match flash_blend:
		DofusAnimClip.Blend.MULTIPLY:
			return [GodotBlend.MUL, Keyword.MULTIPLY]
		DofusAnimClip.Blend.DARKEN:
			return [GodotBlend.MUL, Keyword.MULTIPLY]
		DofusAnimClip.Blend.SCREEN, DofusAnimClip.Blend.LIGHTEN:
			return [GodotBlend.PREMUL, Keyword.SCREEN_PREMUL]
		DofusAnimClip.Blend.ADD:
			return [GodotBlend.ADD, Keyword.NONE]
		DofusAnimClip.Blend.SUBTRACT:
			return [GodotBlend.SUB, Keyword.NONE]
		DofusAnimClip.Blend.INVERT:
			return [GodotBlend.MIX, Keyword.INVERT]
		DofusAnimClip.Blend.PREMULTIPLIED:
			return [GodotBlend.PREMUL, Keyword.NONE]
		DofusAnimClip.Blend.LAYER, DofusAnimClip.Blend.DIFFERENCE, DofusAnimClip.Blend.ALPHA, \
		DofusAnimClip.Blend.ERASE, DofusAnimClip.Blend.OVERLAY, DofusAnimClip.Blend.HARDLIGHT:
			# the reference renderer falls back to LIGHTEN for these
			return [GodotBlend.PREMUL, Keyword.SCREEN_PREMUL]
		_:
			return [GodotBlend.MIX, Keyword.NONE]


static func shader_for(godot_blend: int) -> Shader:
	var shader: Shader = _shaders.get(godot_blend)
	if shader == null:
		shader = Shader.new()
		shader.code = _SHADER_TEMPLATE % _RENDER_MODES[godot_blend]
		_shaders[godot_blend] = shader
	return shader


static func create_material(flash_blend: int, palette: PackedVector3Array, color_matrix := PackedFloat32Array()) -> ShaderMaterial:
	var mapped := map_blend(flash_blend)
	var mat := ShaderMaterial.new()
	mat.shader = shader_for(mapped[0])
	mat.set_shader_parameter("palette", palette)
	mat.set_shader_parameter("keyword", mapped[1])
	if color_matrix.size() == 20:
		mat.set_shader_parameter("use_color_matrix", true)
		var rows: Array[Vector4] = []
		for r in 5:
			rows.append(Vector4(color_matrix[r * 4], color_matrix[r * 4 + 1], color_matrix[r * 4 + 2], color_matrix[r * 4 + 3]))
		mat.set_shader_parameter("color_matrix", rows)
	return mat
