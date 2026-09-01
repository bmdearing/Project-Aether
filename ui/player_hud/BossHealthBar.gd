extends Control
class_name BossHealthBar
## User request (2026-08-31): "Pinnacle bosses and uber bosses should have
## a special health bar that stays at the very top of the screen,
## stylized and menacing." Distinct from the floating per-enemy bars
## (EnemyHealthBar) - fixed at top-center regardless of the boss's own
## screen position, wider, and driven by its own animated shader (same
## "canvas_item ShaderMaterial on a ColorRect" technique StatOrb.gd
## already established this session) rather than a plain _draw() fill,
## since "stylized and menacing" is explicitly a visual-quality ask.
## Triggered by Enemy.rank == Constants.EnemyRank.BOSS - the only boss-
## tier concept that exists in this project (added 2026-08-30 for loot
## gating); "Pinnacle boss" and "uber boss" both read as that same rank
## for now, not a further split tier, since nothing in this project
## distinguishes them from each other yet.

const WIDTH := 520.0
const HEIGHT := 26.0
const NAME_HEIGHT := 22.0

## User feedback (2026-08-31): "I like where you started it. But let's
## make the fill more clean." The original fill multiplied in a blocky
## hash-noise "vein" pattern per-pixel - replaced with a smooth vertical
## gradient (still gives the fill some depth/roundness, just no grain/
## noise) - the pulsing glow right at the fill edge stayed, that read as
## a good "menacing" touch rather than noise. Also gained the same
## damage-trail concept EnemyHealthBar has (trailing_fraction, a lighter
## shade between it and fill_fraction) - driven from GDScript exactly
## like that file (_process(delta), not a Tween - see EnemyHealthBar's
## own header for why), just fed into the shader as a second uniform
## instead of drawn as a second rect.
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

	float border = step(uv.y, 0.07) + step(0.93, uv.y) + step(uv.x, 0.007) + step(0.993, uv.x);
	col = mix(col, vec3(0.85, 0.55, 0.15), border * 0.6);

	COLOR = vec4(col, 1.0);
}
"""

const DAMAGE_TRAIL_DURATION := 0.45

var _label: Label
var _shader_mat: ShaderMaterial
var _fraction: float = 1.0
var _trailing_fraction: float = 1.0
var _trail_speed: float = 0.0  # fraction/sec, set whenever a new trail starts

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

	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 20)
	_label.add_theme_color_override("font_color", Color(0.95, 0.75, 0.6))
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

func set_boss_name(text: String) -> void:
	_label.text = text

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
