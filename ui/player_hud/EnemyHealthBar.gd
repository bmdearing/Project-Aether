extends Control
class_name EnemyHealthBar
## Floating bar over an enemy (hovered, or in combat): the name in its
## rarity colour, a thin gold-framed health bar with a lighter "just lost"
## trail that drains to catch up, and a cyan Ward strip above while the
## enemy has Ward. Positioned every frame by PlayerHUD.

const WIDTH := 150.0
const HEIGHT := 6.0
const BAR_TOP := 26.0
const WARD_HEIGHT := 3.0
const WARD_GAP := 3.0
const DAMAGE_TRAIL_DURATION := 0.45

var _fraction: float = 1.0
var _trailing_fraction: float = 1.0
var _trail_speed: float = 0.0  # fraction/sec, set whenever a new trail starts
var _ward_fraction: float = 0.0
var _has_ward: bool = false
var _name_label: Label

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(WIDTH, BAR_TOP + HEIGHT)
	size = custom_minimum_size
	_name_label = Label.new()
	_name_label.add_theme_font_override("font", AetherStyle.serif())
	_name_label.add_theme_font_size_override("font_size", 14)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_name_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_name_label.add_theme_constant_override("shadow_offset_x", 1)
	_name_label.add_theme_constant_override("shadow_offset_y", 1)
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_name_label)

func set_enemy_name(text: String) -> void:
	_name_label.text = text

## Elite/Champion/Ascendant names show in blue/yellow/orange.
func set_name_color(color: Color) -> void:
	_name_label.add_theme_color_override("font_color", color)

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
	queue_redraw()

## Ward shows as a thin strip above the health bar while the enemy has any pool.
func set_ward(current: float, max_value: float) -> void:
	var has_ward := max_value > 0.0
	var fraction := clampf(current / max_value, 0.0, 1.0) if has_ward else 0.0
	if has_ward != _has_ward or not is_equal_approx(fraction, _ward_fraction):
		_has_ward = has_ward
		_ward_fraction = fraction
		queue_redraw()

func _process(delta: float) -> void:
	if _trailing_fraction > _fraction:
		_trailing_fraction = max(_fraction, _trailing_fraction - _trail_speed * delta)
		queue_redraw()

func _draw() -> void:
	if _has_ward:
		var ward := Rect2(12.0, BAR_TOP - WARD_HEIGHT - WARD_GAP, WIDTH - 24.0, WARD_HEIGHT)
		draw_rect(ward, Color(AetherStyle.AETHER, 0.18))
		if _ward_fraction > 0.0:
			draw_rect(Rect2(ward.position, Vector2(ward.size.x * _ward_fraction, WARD_HEIGHT)), AetherStyle.AETHER)
	AetherStyle.bar(self, Rect2(0, BAR_TOP, WIDTH, HEIGHT), _fraction, AetherStyle.LIFE.lightened(0.1), _trailing_fraction)
