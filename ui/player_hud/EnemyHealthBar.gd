extends Control
class_name EnemyHealthBar
## User request (2026-08-31): a health bar on hover, hanging while the
## enemy is in combat, showing its name - see Enemy.is_in_combat()/
## get_display_name(). Positioned every frame by PlayerHUD (world-to-
## screen projection via Camera3D.unproject_position()) rather than a
## Label3D/SubViewport, matching this project's established _draw()-based
## HUD convention (StatOrb/Crosshair/HitMarker) - one instance per enemy
## currently qualifying, pooled/reused by PlayerHUD rather than
## recreated every frame.

const WIDTH := 90.0
const HEIGHT := 7.0
const BAR_TOP := 16.0
const BG_COLOR := Color(0.08, 0.08, 0.08, 0.85)
const FILL_COLOR := Color(0.78, 0.15, 0.15, 1.0)
const BORDER_COLOR := Color(0, 0, 0, 0.85)

## User request (2026-08-31): "tween with damage on the health bars, with
## the damaged portions being a lighter color." The main fill drops
## instantly to the new (lower) value; a wider, lighter "trailing" sliver
## stays behind at the OLD value and drains down to catch up with it over
## DAMAGE_TRAIL_TWEEN_DURATION - the classic WoW-style health bar "white
## sliver" reads as "this much was JUST lost." A heal (or the very
## first set_health() call) snaps both values together instead - there's
## no damage to trail behind on a heal. Driven by _process(delta) rather
## than a Tween - matches HitMarker.gd's own timer-in-_process() pattern
## right next to this file, and sidesteps a real Tween.tween_method()
## callback that mysteriously never fired when tried first (created
## successfully, reported valid, but never once ticked across 400 frames
## in a scratch test - not chased further since this delta-based approach
## is simpler AND already this project's established convention here).
const TRAIL_COLOR := Color(0.95, 0.55, 0.5, 1.0)
const DAMAGE_TRAIL_DURATION := 0.45

var _fraction: float = 1.0
var _trailing_fraction: float = 1.0
var _trail_speed: float = 0.0  # fraction/sec, set whenever a new trail starts
var _name_label: Label

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(WIDTH, BAR_TOP + HEIGHT)
	size = custom_minimum_size
	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 13)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_name_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_name_label.add_theme_constant_override("shadow_offset_x", 1)
	_name_label.add_theme_constant_override("shadow_offset_y", 1)
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_name_label)

func set_enemy_name(text: String) -> void:
	_name_label.text = text

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

func _process(delta: float) -> void:
	if _trailing_fraction > _fraction:
		_trailing_fraction = max(_fraction, _trailing_fraction - _trail_speed * delta)
		queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(0, BAR_TOP, WIDTH, HEIGHT), BG_COLOR)
	if _trailing_fraction > _fraction:
		draw_rect(Rect2(0, BAR_TOP, WIDTH * _trailing_fraction, HEIGHT), TRAIL_COLOR)
	if _fraction > 0.0:
		draw_rect(Rect2(0, BAR_TOP, WIDTH * _fraction, HEIGHT), FILL_COLOR)
	draw_rect(Rect2(0, BAR_TOP, WIDTH, HEIGHT), BORDER_COLOR, false, 1.0)
