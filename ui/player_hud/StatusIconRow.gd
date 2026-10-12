extends Control
class_name StatusIconRow
## A centred row of status icons (StatusIcons) for one StatusEffectComponent,
## under an enemy or boss health bar: each icon has a thin bar under it
## draining with the effect's remaining time, and a stack count in its
## corner when it stacks. Redraws itself every frame while it has a source.

var icon_size := 16.0
var gap := 3.0
var source: StatusEffectComponent

## effect_id -> the longest time left seen since it last went up, so the
## drain bar shows a share of the full duration.
var _full: Dictionary = {}
var _font: Font

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = AetherStyle.numbers()

func _process(_delta: float) -> void:
	queue_redraw()

func _shown() -> Array[String]:
	var out: Array[String] = []
	if source == null or not is_instance_valid(source):
		return out
	for id in source.active_effects():
		if StatusIcons.has(id):
			out.append(id)
	return out

func _draw() -> void:
	var ids := _shown()
	for id in _full.keys():
		if not ids.has(id):
			_full.erase(id)
	if ids.is_empty():
		return
	var total := ids.size() * icon_size + (ids.size() - 1) * gap
	var x := (size.x - total) / 2.0
	for id in ids:
		var rect := Rect2(x, 0.0, icon_size, icon_size)
		StatusIcons.draw(self, id, rect)
		var left := source.remaining(id)
		if left > float(_full.get(id, 0.0)) + 0.05:
			_full[id] = left
		var full: float = _full.get(id, left)
		if full > 0.0:
			var bar := Rect2(x, icon_size + 1.5, icon_size, 2.0)
			draw_rect(bar, Color(0, 0, 0, 0.6))
			draw_rect(Rect2(bar.position, Vector2(icon_size * clampf(left / full, 0.0, 1.0), 2.0)), StatusIcons.colour_of(id))
		var n := source.stacks(id)
		if n > 1:
			var s := str(n)
			var fs := int(icon_size * 0.6)
			var at := Vector2(x + icon_size - fs * 0.35 * s.length() - 1.0, icon_size - 1.0)
			draw_string_outline(_font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0, 0, 0, 0.9))
			draw_string(_font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
		x += icon_size + gap
