extends Control
class_name StatOrb
## Circular resource gauge (Life/Mana) - a liquid-style fill that drains
## top-to-bottom (empty space grows from the top as the value drops),
## built by drawing the exact circular segment below the waterline
## rather than a shader/mask, matching the project's no-shader
## placeholder-art style. An optional inset Ward strip (Life orb only)
## fills the same top-to-bottom way within a band along the orb's right
## edge - see set_ward_value()/_draw_ward_strip() (user direction,
## 2026-08-30, replacing the previous design's outer ring around the rim).

@export var radius: float = 46.0
@export var fill_color: Color = Color.WHITE
@export var bg_color: Color = Color(0.12, 0.12, 0.14, 0.9)
@export var border_color: Color = Color(0, 0, 0, 0.75)
@export var ward_color: Color = Color.WHITE
@export var label_prefix: String = ""

## User direction (2026-08-30): "Ward should appear as a fill from top to
## bottom covering only 20% of the Life orb, it should be oriented to the
## right." 20% is read as the strip's WIDTH relative to the orb's own
## diameter; "fill from top to bottom" as the same top-drains liquid
## convention _draw_liquid_fill() below already uses, for visual
## consistency between the two fills on the same orb.
const WARD_STRIP_WIDTH_FRACTION := 0.2

var _fraction: float = 1.0
var _ward_fraction: float = 0.0
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

func set_ward_value(current: float, max_value: float) -> void:
	_ward_fraction = clamp(current / max_value, 0.0, 1.0) if max_value > 0.0 else 0.0
	_extra_text = "Ward %.0f/%.0f" % [current, max_value] if max_value > 0.0 else ""
	queue_redraw()

func _draw() -> void:
	var center: Vector2 = size / 2.0
	draw_circle(center, radius, bg_color)
	_draw_liquid_fill(center, radius, _fraction, fill_color)
	if _ward_fraction > 0.0:
		_draw_ward_strip(center, radius, _ward_fraction, ward_color)
	draw_arc(center, radius, 0.0, TAU, 48, border_color, 3.0, true)

## A vertical band along the circle's right edge, WARD_STRIP_WIDTH_FRACTION
## of the orb's diameter wide, filling/draining top-to-bottom exactly like
## _draw_liquid_fill() (same waterline_y formula) but clipped to the
## circle's own curve at every scanline rather than filling a plain
## rectangle - drawn as a stack of thin horizontal rects (this project's
## established no-shader/immediate-draw style) rather than one polygon,
## since the circle clip makes each row's width different.
func _draw_ward_strip(center: Vector2, r: float, fraction: float, color: Color) -> void:
	var strip_left: float = r * (1.0 - 2.0 * WARD_STRIP_WIDTH_FRACTION)
	var waterline_y: float = clamp(r - 2.0 * r * fraction, -r, r)
	var steps := 48
	for i in range(steps):
		var y0: float = -r + (2.0 * r) * i / float(steps)
		var y1: float = -r + (2.0 * r) * (i + 1) / float(steps)
		var y_mid: float = (y0 + y1) * 0.5
		if y_mid < waterline_y:
			continue  # above the waterline - undrawn, same "empty grows from the top" rule as the main fill
		var half_chord: float = sqrt(max(0.0, r * r - y_mid * y_mid))
		var right: float = min(r, half_chord)
		if strip_left >= right:
			continue  # this scanline is above/below the circle's own bulge, no valid band here
		var rect := Rect2(center.x + strip_left, center.y + y0, right - strip_left, y1 - y0 + 0.75)
		draw_rect(rect, color)

## Fills the circular segment below the waterline y = r - 2r*fraction (in
## local, center-relative coordinates), i.e. the portion of the circle at
## or past that height - fraction 0 is an empty waterline at the bottom
## edge, 1 is a full circle. Traced as an arc from the right waterline
## intersection through the bottom point to the left intersection; the
## straight closing edge Godot draws back to the start is the flat
## waterline itself.
func _draw_liquid_fill(center: Vector2, r: float, fraction: float, color: Color) -> void:
	if fraction <= 0.0:
		return
	if fraction >= 1.0:
		draw_circle(center, r, color)
		return
	var waterline_y: float = clamp(r - 2.0 * r * fraction, -r, r)
	var angle_right: float = asin(waterline_y / r)
	var angle_left: float = PI - angle_right
	var sweep: float = angle_left - angle_right
	var segments: int = max(8, int(64 * sweep / TAU))
	var points := PackedVector2Array()
	for i in range(segments + 1):
		var t: float = angle_right + sweep * i / float(segments)
		points.append(center + Vector2(cos(t), sin(t)) * r)
	draw_colored_polygon(points, color)
