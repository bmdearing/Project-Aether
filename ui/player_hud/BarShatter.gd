extends Control
class_name BarShatter
## Laid over a health bar: while its enemy can be riposted (Composure
## broken) the filled part of the bar shatters like a struck window. Cracks
## race out from an impact point, a web of rings joins them, a few chips
## fall away, and a glint runs along the glass until the window closes.
## Only the filled share (`fraction`) cracks.

const GROW_SEC := 0.14
const CHIP_SEC := 0.7
const RAYS := 7

var fraction := 1.0
var broken := false

var _age := 0.0
## Each ray: PackedVector2Array of points from the impact outward.
var _rays: Array[PackedVector2Array] = []
var _rings: Array[PackedVector2Array] = []
var _impact := Vector2.ZERO
## Falling chips: {"poly": PackedVector2Array, "vel": Vector2, "spin": float}
var _chips: Array[Dictionary] = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_broken(value: bool) -> void:
	if value == broken:
		return
	broken = value
	if broken:
		_age = 0.0
		_build()
	queue_redraw()

func _process(delta: float) -> void:
	if not broken:
		return
	_age += delta
	queue_redraw()

func _build() -> void:
	var w := maxf(size.x * fraction, 8.0)
	var h := size.y
	_impact = Vector2(w * randf_range(0.35, 0.75), h * randf_range(0.3, 0.7))
	_rays.clear()
	_rings.clear()
	var reach := maxf(w, h) * 1.2
	var start := randf() * TAU
	for i in RAYS:
		var a := start + TAU * i / RAYS + randf_range(-0.25, 0.25)
		var pts := PackedVector2Array([_impact])
		var p := _impact
		var steps := 6
		for s in steps:
			a += randf_range(-0.35, 0.35)
			p += Vector2(cos(a), sin(a) * 0.55) * reach / steps
			pts.append(p)
		_rays.append(pts)
	# The web: each ring joins neighbouring rays at the same step.
	for step in [1, 3]:
		var ring := PackedVector2Array()
		for ray in _rays:
			ring.append(ray[step])
		ring.append(_rays[0][step])
		_rings.append(ring)
	_chips.clear()
	for i in 4:
		var c := _impact + Vector2(randf_range(-6, 6), randf_range(-2, 2))
		var s := randf_range(2.0, 4.0)
		_chips.append({
			"poly": PackedVector2Array([c + Vector2(-s, -s * 0.6), c + Vector2(s, -s * 0.2), c + Vector2(0, s)]),
			"vel": Vector2(randf_range(-30, 30), randf_range(-25, 5)),
			"spin": randf_range(-6, 6),
		})

func _clamp_pts(pts: PackedVector2Array, grow: float) -> PackedVector2Array:
	var w := size.x * fraction
	var out := PackedVector2Array()
	var count := maxi(2, int(ceil(pts.size() * grow)))
	for i in mini(count, pts.size()):
		out.append(Vector2(clampf(pts[i].x, 0.0, w), clampf(pts[i].y, 0.0, size.y)))
	return out

func _draw() -> void:
	if not broken or fraction <= 0.0:
		return
	var w := size.x * fraction
	var grow := clampf(_age / GROW_SEC, 0.0, 1.0)
	# The cracked pane goes a shade paler and colder.
	draw_rect(Rect2(0, 0, w, size.y), Color(0.85, 0.92, 1.0, 0.16))
	var thick := clampf(size.y * 0.09, 1.0, 1.8)
	for ray in _rays:
		var pts := _clamp_pts(ray, grow)
		if pts.size() >= 2:
			draw_polyline(pts, Color(0, 0, 0, 0.55), thick + 1.2, true)
			draw_polyline(pts, Color(1.0, 1.0, 1.0, 0.95), thick, true)
	if grow >= 1.0:
		for ring in _rings:
			var pts := _clamp_pts(ring, 1.0)
			draw_polyline(pts, Color(1.0, 1.0, 1.0, 0.6), maxf(thick * 0.7, 1.0), true)
	# A bright star where it was struck.
	draw_circle(_impact.clamp(Vector2.ZERO, Vector2(w, size.y)), maxf(size.y * 0.18, 1.5), Color(1, 1, 1, 0.9))
	# A glint sweeping across the glass.
	var gx := fmod(_age * 140.0, w + 40.0) - 20.0
	var glint := PackedVector2Array()
	for v in [Vector2(gx, 0), Vector2(gx + 8, 0), Vector2(gx + 2, size.y), Vector2(gx - 6, size.y)]:
		glint.append(Vector2(clampf(v.x, 0.0, w), v.y))
	if glint[1].x - glint[0].x > 0.5 or glint[2].x - glint[3].x > 0.5:
		draw_colored_polygon(glint, Color(1, 1, 1, 0.25))
	# Chips falling away from the impact.
	if _age < CHIP_SEC:
		var t := _age
		var k := 1.0 - t / CHIP_SEC
		for chip in _chips:
			var offset: Vector2 = chip["vel"] * t + Vector2(0, 160.0 * t * t)
			var poly: PackedVector2Array = chip["poly"]
			var moved := PackedVector2Array()
			var c := _impact
			for p in poly:
				moved.append(c + (p - c).rotated(float(chip["spin"]) * t) + offset)
			draw_colored_polygon(moved, Color(0.9, 0.95, 1.0, 0.85 * k))
