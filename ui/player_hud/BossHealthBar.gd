extends Control
class_name BossHealthBar
## Fixed top-center health bar for BOSS-rank enemies, drawn by an animated
## shader on a ColorRect.

const WIDTH := 520.0
const HEIGHT := 18.0
const NAME_HEIGHT := 30.0

## Smooth vertical gradient fill with a pulsing edge glow, plus a damage
## trail (trailing_fraction) driven from _process() like EnemyHealthBar.
const SHADER_CODE := """
shader_type canvas_item;

uniform float fill_fraction : hint_range(0.0, 1.0) = 1.0;
uniform float trailing_fraction : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec2 uv = UV;
	vec3 bg = vec3(0.035, 0.012, 0.012);
	vec3 fill_col = vec3(0.55, 0.06, 0.05);
	vec3 trail_col = vec3(0.85, 0.4, 0.35);

	float pulse = 0.5 + 0.5 * sin(TIME * 2.2);
	float edge_glow = smoothstep(fill_fraction - 0.015, fill_fraction, uv.x)
		- smoothstep(fill_fraction, fill_fraction + 0.02, uv.x);

	vec3 col = bg;
	if (uv.x < fill_fraction) {
		float shade = mix(1.18, 0.82, uv.y); // clean vertical gradient, no noise
		col = fill_col * shade;
		col += vec3(0.45, 0.08, 0.03) * edge_glow * (0.6 + 0.5 * pulse);
	} else if (uv.x < trailing_fraction) {
		col = trail_col;
	}

	COLOR = vec4(col, 1.0);
}
"""

const DAMAGE_TRAIL_DURATION := 0.45

var _label: Label
var _shader_mat: ShaderMaterial
var _fraction: float = 1.0
var _trailing_fraction: float = 1.0
var _trail_speed: float = 0.0  # fraction/sec, set whenever a new trail starts
var _ward_back: ColorRect
var _ward_fill: ColorRect
var _frame: BarFrame
const WARD_HEIGHT := 6.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.0
	anchor_bottom = 0.0
	grow_horizontal = 2
	offset_left = -WIDTH / 2.0
	offset_right = WIDTH / 2.0
	offset_top = 14.0
	offset_bottom = 14.0 + NAME_HEIGHT + HEIGHT

	_ward_back = ColorRect.new()
	_ward_back.color = Color(AetherStyle.AETHER, 0.18)
	_ward_back.position = Vector2(0, NAME_HEIGHT - WARD_HEIGHT - 1.0)
	_ward_back.size = Vector2(WIDTH, WARD_HEIGHT)
	_ward_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ward_back.visible = false
	add_child(_ward_back)
	_ward_fill = ColorRect.new()
	_ward_fill.color = AetherStyle.AETHER
	_ward_fill.size = Vector2(WIDTH, WARD_HEIGHT)
	_ward_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ward_back.add_child(_ward_fill)

	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_override("font", AetherStyle.title())
	_label.add_theme_font_size_override("font_size", 22)
	_label.add_theme_color_override("font_color", AetherStyle.GOLD_BRIGHT)
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	_label.size = Vector2(WIDTH, NAME_HEIGHT)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)

	var bar := ColorRect.new()
	bar.position = Vector2(0, NAME_HEIGHT)
	bar.size = Vector2(WIDTH, HEIGHT)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = SHADER_CODE
	_shader_mat = ShaderMaterial.new()
	_shader_mat.shader = shader
	_shader_mat.set_shader_parameter("fill_fraction", 1.0)
	bar.material = _shader_mat
	bar.color = Color.WHITE
	add_child(bar)
	_frame = BarFrame.new()
	_frame.position = bar.position
	_frame.size = bar.size
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frame)

func set_boss_name(text: String) -> void:
	_label.text = text

## Orange for an Ascendant, gold for a boss.
func set_name_color(color: Color) -> void:
	_label.add_theme_color_override("font_color", color)

## An Ascendant's affixes, under the bar.
func set_subtitle(text: String) -> void:
	if _subtitle == null:
		_subtitle = Label.new()
		_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_subtitle.add_theme_font_override("font", AetherStyle.serif_italic())
		_subtitle.add_theme_font_size_override("font_size", 15)
		_subtitle.add_theme_color_override("font_color", Color(1.0, 0.72, 0.45))
		_subtitle.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
		_subtitle.position = Vector2(0, NAME_HEIGHT + HEIGHT + 4.0)
		_subtitle.size = Vector2(WIDTH, 20)
		_subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_subtitle)
	_subtitle.text = text

var _subtitle: Label

## Diamonds on the frame where the boss changes phase (health fractions).
func set_phase_marks(marks: Array[float]) -> void:
	if _frame.marks != marks:
		_frame.marks = marks
		_frame.queue_redraw()

func set_ward(current: float, max_value: float) -> void:
	_ward_back.visible = max_value > 0.0
	if max_value > 0.0:
		_ward_fill.size.x = WIDTH * clampf(current / max_value, 0.0, 1.0)

func set_health(current: float, max_value: float) -> void:
	var new_fraction: float = clamp(current / max_value, 0.0, 1.0) if max_value > 0.0 else 0.0
	if new_fraction < _fraction:
		_trailing_fraction = _fraction
		_fraction = new_fraction
		_trail_speed = (_trailing_fraction - _fraction) / DAMAGE_TRAIL_DURATION
	else:
		_fraction = new_fraction
		_trailing_fraction = new_fraction
		_trail_speed = 0.0
	_shader_mat.set_shader_parameter("fill_fraction", _fraction)
	_shader_mat.set_shader_parameter("trailing_fraction", _trailing_fraction)

func _process(delta: float) -> void:
	if _trailing_fraction > _fraction:
		_trailing_fraction = max(_fraction, _trailing_fraction - _trail_speed * delta)
		_shader_mat.set_shader_parameter("trailing_fraction", _trailing_fraction)

## Gold frame with a faint inner line and diamond end caps over the shader bar.
class BarFrame extends Control:
	var marks: Array[float] = []

	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		draw_rect(rect, AetherStyle.GOLD, false, 1.5)
		draw_rect(rect.grow(-3), AetherStyle.GOLD_FAINT, false, 1.0)
		AetherStyle.diamond(self, Vector2(0, size.y / 2.0), 8.0, AetherStyle.GLASS_SOLID, AetherStyle.GOLD)
		AetherStyle.diamond(self, Vector2(size.x, size.y / 2.0), 8.0, AetherStyle.GLASS_SOLID, AetherStyle.GOLD)
		for mark in marks:
			var x := size.x * mark
			draw_line(Vector2(x, 2), Vector2(x, size.y - 2), AetherStyle.GOLD, 1.5)
			AetherStyle.diamond(self, Vector2(x, 0), 4.0, AetherStyle.GOLD_BRIGHT, AetherStyle.GOLD)
