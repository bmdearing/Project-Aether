extends Control
class_name StatOrb
## Circular resource gauge (Life/Mana) - a liquid-style fill that drains
## top-to-bottom (empty space grows from the top as the value drops), with
## an optional inset Ward strip (Life orb only) filling the same way
## within a band along the orb's right edge - see set_ward_value().
##
## User request (2026-08-30): "make a shader for the Life orb, Mana orb,
## and Ward shield on the life orb to make them look interesting."
## Previously drawn with Control._draw() (draw_circle/draw_colored_polygon/
## draw_rect, "matching the project's no-shader placeholder-art style" per
## this file's own prior header) - replaced entirely with a single
## ShaderMaterial (ORB_SHADER_CODE below) on a ColorRect sized to exactly
## radius*2 so its UV maps cleanly to the circle. The shader adds real
## motion (an animated wavy waterline, not a flat line), a liquid depth
## gradient, a surface-glow highlight right at the waterline, and a soft
## fresnel rim glow - none of which a flat draw_colored_polygon() fill
## could do. fraction/ward_fraction and every color are plain shader
## uniforms, updated from set_value()/set_ward_value() same as before.

## User request (2026-08-30): "make the orbs a bit larger... that part of
## the UI doesn't match the rest" - bumped from 46 (PlayerHUD.ORB_HEIGHT
## must stay in sync, see that file's own comment on it).
@export var radius: float = 58.0

## Real setters (not plain @export fields) - PlayerHUD sets ward_color
## AFTER _build_orb() already returned (`_life_orb.ward_color = WARD_
## COLOR`, one line below the constructor call), which is also after
## add_child() has already run this node's _ready(). A plain field would
## only get read once, at _ready() time, into the shader uniform - this
## setter pushes to the uniform on every assignment instead, whenever it
## happens to land, so a HUD build order like that one still works.
@export var fill_color: Color = Color.WHITE:
	set(value):
		fill_color = value
		_push_color("fill_color", value)
@export var bg_color: Color = Color(0.12, 0.12, 0.14, 0.9):
	set(value):
		bg_color = value
		_push_color("bg_color", value)
@export var border_color: Color = Color(0, 0, 0, 0.75):
	set(value):
		border_color = value
		_push_color("border_color", value)
@export var ward_color: Color = Color.WHITE:
	set(value):
		ward_color = value
		_push_color("ward_color", value)
@export var label_prefix: String = ""

func _push_color(param: String, value: Color) -> void:
	if _shader_mat:
		_shader_mat.set_shader_parameter(param, value)

## User direction (2026-08-30): "Ward should appear as a fill from top to
## bottom covering only 20% of the Life orb, it should be oriented to the
## right." 20% is read as the strip's WIDTH relative to the orb's own
## diameter.
const WARD_STRIP_WIDTH_FRACTION := 0.2

const ORB_SHADER_CODE := """
shader_type canvas_item;

uniform float fill_fraction : hint_range(0.0, 1.0) = 1.0;
uniform float ward_fraction : hint_range(0.0, 1.0) = 0.0;
uniform float ward_strip_width : hint_range(0.0, 1.0) = 0.2;
uniform vec4 fill_color : source_color = vec4(0.8, 0.1, 0.1, 1.0);
uniform vec4 ward_color : source_color = vec4(0.6, 0.75, 0.95, 1.0);
uniform vec4 bg_color : source_color = vec4(0.12, 0.12, 0.14, 0.9);
uniform vec4 border_color : source_color = vec4(0.0, 0.0, 0.0, 0.75);

// waterline in [-1,1] local space for a given fill fraction, rippled by
// two overlaid sine waves (different frequency/speed so it doesn't read
// as a single mechanical oscillation) - fraction 0 -> waterline at the
// bottom (y=1), fraction 1 -> waterline above the top (y=-1).
float waterline_y(float p_x, float fraction, float speed_mult) {
	float wave = sin(p_x * 10.0 + TIME * 2.0 * speed_mult) * 0.025
		+ sin(p_x * 4.0 - TIME * 1.3 * speed_mult) * 0.015;
	return 1.0 - 2.0 * fraction + wave;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float dist = length(p);
	if (dist > 1.0) {
		discard;
	}

	vec3 col = bg_color.rgb;
	float alpha = bg_color.a;

	if (fill_fraction > 0.0) {
		float waterline = waterline_y(p.x, fill_fraction, 1.0);
		if (p.y > waterline) {
			float depth = clamp((p.y - waterline) / 2.0, 0.0, 1.0);
			vec3 liquid = fill_color.rgb * mix(1.15, 0.7, depth);
			float surface_glow = smoothstep(0.06, 0.0, abs(p.y - waterline));
			liquid += vec3(surface_glow * 0.5);
			col = liquid;
			alpha = fill_color.a;
		}
	}

	if (ward_fraction > 0.0) {
		float strip_left = 1.0 - 2.0 * ward_strip_width;
		if (p.x > strip_left) {
			float ward_waterline = waterline_y(p.x, ward_fraction, 1.4);
			if (p.y > ward_waterline) {
				float depth = clamp((p.y - ward_waterline) / 2.0, 0.0, 1.0);
				vec3 liquid = ward_color.rgb * mix(1.2, 0.75, depth);
				float surface_glow = smoothstep(0.06, 0.0, abs(p.y - ward_waterline));
				liquid += vec3(surface_glow * 0.5);
				col = liquid;
				alpha = ward_color.a;
			}
		}
	}

	// Soft fresnel rim glow, tinted by the fill color, so the orb reads
	// as a glassy sphere rather than a flat disc.
	float rim = smoothstep(0.82, 1.0, dist);
	col += fill_color.rgb * rim * 0.35;

	// Border ring.
	float border = smoothstep(0.94, 0.965, dist) - smoothstep(0.965, 1.0, dist);
	col = mix(col, border_color.rgb, border * border_color.a);

	COLOR = vec4(col, alpha);
}
"""

var _fraction: float = 1.0
var _ward_fraction: float = 0.0
var _extra_text: String = ""
var _label: Label
var _visual: ColorRect
var _shader_mat: ShaderMaterial

func _ready() -> void:
	custom_minimum_size = Vector2(radius, radius) * 2.0 + Vector2(16, 16)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_visual = ColorRect.new()
	_visual.color = Color.WHITE  # fully driven by the shader below
	_visual.size = Vector2(radius, radius) * 2.0
	_visual.position = (custom_minimum_size - _visual.size) / 2.0
	_visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = ORB_SHADER_CODE
	_shader_mat = ShaderMaterial.new()
	_shader_mat.shader = shader
	_shader_mat.set_shader_parameter("fill_color", fill_color)
	_shader_mat.set_shader_parameter("bg_color", bg_color)
	_shader_mat.set_shader_parameter("border_color", border_color)
	_shader_mat.set_shader_parameter("ward_color", ward_color)
	_shader_mat.set_shader_parameter("ward_strip_width", WARD_STRIP_WIDTH_FRACTION)
	_visual.material = _shader_mat
	add_child(_visual)

	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_label.add_theme_font_size_override("font_size", 15)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)

func set_value(current: float, max_value: float) -> void:
	_fraction = current / max_value if max_value > 0.0 else 0.0
	_label.text = "%s\n%.0f/%.0f%s" % [label_prefix, current, max_value, ("\n" + _extra_text) if _extra_text != "" else ""]
	if _shader_mat:
		_shader_mat.set_shader_parameter("fill_fraction", _fraction)

func set_ward_value(current: float, max_value: float) -> void:
	_ward_fraction = clamp(current / max_value, 0.0, 1.0) if max_value > 0.0 else 0.0
	_extra_text = "Ward %.0f/%.0f" % [current, max_value] if max_value > 0.0 else ""
	if _shader_mat:
		_shader_mat.set_shader_parameter("ward_fraction", _ward_fraction)
