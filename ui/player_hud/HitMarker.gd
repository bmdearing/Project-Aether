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

## Grey word under the cross when a hit is evaded or blocked.
const CALLOUT_COLOR := Color(0.72, 0.72, 0.72, 1.0)
const CALLOUT_DURATION := 0.6
const CALLOUT_FONT_SIZE := 15
const CALLOUT_OFFSET_Y := 26.0

const _DIRS: Array[Vector2] = [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]

var _timer: float = 0.0
var _active: bool = false
var _color: Color = NORMAL_COLOR
var _is_critical: bool = false
var _gap: float = NORMAL_GAP
var _callout: String = ""
var _callout_timer: float = 0.0

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

func show_callout(text: String) -> void:
	_callout = text
	_callout_timer = CALLOUT_DURATION
	queue_redraw()

func _process(delta: float) -> void:
	if _callout_timer > 0.0:
		_callout_timer -= delta
		queue_redraw()
	if _active:
		_timer -= delta
		if _timer <= 0.0:
			_active = false
			queue_redraw()

func _draw() -> void:
	var c := get_viewport_rect().size / 2.0
	if _callout_timer > 0.0:
		var font := AetherStyle.numbers()
		var fade := clampf(_callout_timer / (CALLOUT_DURATION * 0.4), 0.0, 1.0)
		var width := 200.0
		draw_string_outline(font, Vector2(c.x - width * 0.5, c.y + CALLOUT_OFFSET_Y), _callout, HORIZONTAL_ALIGNMENT_CENTER, width, CALLOUT_FONT_SIZE, 4, Color(0, 0, 0, 0.8 * fade))
		draw_string(font, Vector2(c.x - width * 0.5, c.y + CALLOUT_OFFSET_Y), _callout, HORIZONTAL_ALIGNMENT_CENTER, width, CALLOUT_FONT_SIZE, Color(CALLOUT_COLOR, fade))
	if not _active:
		return
	for d in _DIRS:
		var dir: Vector2 = d.normalized()
		var inner := c + dir * _gap
		var outer := c + dir * (_gap + ARM_LENGTH)
		draw_line(inner, outer, _color, THICKNESS)
		if _is_critical:
			var tick_center := c + dir * TICK_OFFSET
			var perp := Vector2(-dir.y, dir.x)
			draw_line(tick_center - perp * TICK_LENGTH * 0.5, tick_center + perp * TICK_LENGTH * 0.5, _color, THICKNESS)
