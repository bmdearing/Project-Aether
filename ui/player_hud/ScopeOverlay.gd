extends ColorRect
class_name ScopeOverlay
## Full-screen sniper scope: black outside a round lens, a fine crosshair
## and a dark rim. Shown by WeaponStance while a scoped rifle is aimed.

const SHADER_CODE := """
shader_type canvas_item;
uniform float aspect = 1.7778;
uniform float radius = 0.44;
void fragment() {
	vec2 p = (UV - 0.5) * vec2(aspect, 1.0);
	float d = length(p);
	float outside = smoothstep(radius, radius + 0.004, d);
	float rim = smoothstep(radius - 0.07, radius, d) * 0.75;
	float thin = (abs(p.x) < 0.0012 || abs(p.y) < 0.0012) ? 1.0 : 0.0;
	float thick = ((abs(p.x) < 0.004 && abs(p.y) > 0.16) || (abs(p.y) < 0.004 && abs(p.x) > 0.16)) ? 1.0 : 0.0;
	float reticle = max(thin, thick) * step(d, radius);
	COLOR = vec4(0.0, 0.0, 0.0, max(max(outside, rim), reticle * 0.9));
}
"""

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	color = Color.WHITE
	var shader := Shader.new()
	shader.code = SHADER_CODE
	var mat := ShaderMaterial.new()
	mat.shader = shader
	material = mat
	resized.connect(_update_aspect)
	_update_aspect()

func _update_aspect() -> void:
	if size.y > 0.0:
		(material as ShaderMaterial).set_shader_parameter("aspect", size.x / size.y)
