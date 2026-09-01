extends Control
class_name HitMarker
## Redesigned 2026-08-31 per user reference image - an 8-state matrix
## instead of the original 3-state (white/gold/nothing) marker. Color
## encodes WHERE the hit landed (white = normal, gold = weakpoint) UNLESS
## it's a KILL, which is always red regardless of where - red then needs
## its own sub-encoding for weakpoint+crit since color alone can no longer
## carry it. Two independent decorations layer onto the base X: a small
## perpendicular TICK on each arm = critical (a roll crit), and a wider
## GAP at the very center = a weakpoint hit - the gap only actually shows
## up on kills, since a non-kill weakpoint already reads via gold color
## and doesn't need the gap too (matches the reference image's own
## white/gold rows only ever needing crit-or-not, while red needs all 4
## combinations of weakpoint x crit).

const NORMAL_COLOR := Color(1.0, 1.0, 1.0, 1.0)
const WEAKPOINT_COLOR := Color(0.85, 0.65, 0.15, 1.0)
const KILL_COLOR := Color(0.9, 0.15, 0.1, 1.0)
const DISPLAY_DURATION := 0.16

const ARM_LENGTH := 9.0
const THICKNESS := 2.0
const NORMAL_GAP := 3.0
const WEAKPOINT_KILL_GAP := 7.0
const TICK_LENGTH := 4.0
const TICK_OFFSET := 5.5  # distance from center along each arm where the crit tick crosses it

const _DIRS: Array[Vector2] = [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]

var _timer: float = 0.0
var _active: bool = false
var _color: Color = NORMAL_COLOR
var _is_critical: bool = false
var _gap: float = NORMAL_GAP

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

func show_hit(is_critical: bool, is_critical_spot: bool, is_kill: bool) -> void:
	if is_kill:
		_color = KILL_COLOR
		_gap = WEAKPOINT_KILL_GAP if is_critical_spot else NORMAL_GAP
	else:
		_color = WEAKPOINT_COLOR if is_critical_spot else NORMAL_COLOR
		_gap = NORMAL_GAP
	_is_critical = is_critical
	_timer = DISPLAY_DURATION
	_active = true
	queue_redraw()

func _process(delta: float) -> void:
	if _active:
		_timer -= delta
		if _timer <= 0.0:
			_active = false
			queue_redraw()

func _draw() -> void:
	if not _active:
		return
	var c := get_viewport_rect().size / 2.0
	for d in _DIRS:
		var dir: Vector2 = d.normalized()
		var inner := c + dir * _gap
		var outer := c + dir * (_gap + ARM_LENGTH)
		draw_line(inner, outer, _color, THICKNESS)
		if _is_critical:
			var tick_center := c + dir * TICK_OFFSET
			var perp := Vector2(-dir.y, dir.x)
			draw_line(tick_center - perp * TICK_LENGTH * 0.5, tick_center + perp * TICK_LENGTH * 0.5, _color, THICKNESS)
