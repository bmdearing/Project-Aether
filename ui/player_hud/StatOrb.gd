extends Control
class_name StatOrb
## Circular resource gauge (Life/Mana) - radial pie fill (like a cooldown
## wheel, sweeping clockwise from the top) rather than a shader-based
## liquid fill, matching the project's no-shader placeholder-art style.
## An optional outer ring (Ward on the Life orb) draws around the rim.

@export var radius: float = 46.0
@export var fill_color: Color = Color.WHITE
@export var bg_color: Color = Color(0.12, 0.12, 0.14, 0.9)
@export var border_color: Color = Color(0, 0, 0, 0.75)
@export var ring_color: Color = Color.WHITE
@export var label_prefix: String = ""

var _fraction: float = 1.0
var _ring_fraction: float = 0.0
var _extra_text: String = ""
var _label: Label

func _ready() -> void:
	custom_minimum_size = Vector2(radius, radius) * 2.0 + Vector2(16, 16)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_label.add_theme_font_size_override("font_size", 13)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)

func set_value(current: float, max_value: float) -> void:
	_fraction = current / max_value if max_value > 0.0 else 0.0
	_label.text = "%s\n%.0f/%.0f%s" % [label_prefix, current, max_value, ("\n" + _extra_text) if _extra_text != "" else ""]
	queue_redraw()

func set_ring_value(current: float, max_value: float) -> void:
	_ring_fraction = clamp(current / max_value, 0.0, 1.0) if max_value > 0.0 else 0.0
	_extra_text = "Ward %.0f/%.0f" % [current, max_value] if max_value > 0.0 else ""
	queue_redraw()

func _draw() -> void:
	var center: Vector2 = size / 2.0
	draw_circle(center, radius, bg_color)
	_draw_pie(center, radius, _fraction, fill_color)
	draw_arc(center, radius, 0.0, TAU, 48, border_color, 3.0, true)
	if _ring_fraction > 0.0:
		var ring_radius: float = radius + 6.0
		var start_angle: float = -PI / 2.0
		var end_angle: float = start_angle + TAU * _ring_fraction
		var segments: int = max(8, int(48 * _ring_fraction))
		draw_arc(center, ring_radius, start_angle, end_angle, segments, ring_color, 5.0, true)

func _draw_pie(center: Vector2, r: float, fraction: float, color: Color) -> void:
	if fraction <= 0.0:
		return
	if fraction >= 1.0:
		draw_circle(center, r, color)
		return
	var start_angle: float = -PI / 2.0
	var end_angle: float = start_angle + TAU * fraction
	var segments: int = max(8, int(64 * fraction))
	var points := PackedVector2Array()
	points.append(center)
	for i in range(segments + 1):
		var t: float = start_angle + (end_angle - start_angle) * i / float(segments)
		points.append(center + Vector2(cos(t), sin(t)) * r)
	draw_colored_polygon(points, color)
