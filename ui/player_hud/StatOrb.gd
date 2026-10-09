extends Control
class_name StatOrb
## Life/Mana globe: an animated liquid (ORB_SHADER_CODE) in a gold
## instrument ring with tick marks, the value in the middle and the label
## underneath. The Life orb also shows Ward as a crystalline lattice over
## its right side (see OrbFrame._ward_lattice()), draining from the top
## down as Ward is lost - deliberately not a second liquid.

@export var radius: float = 64.0
@export var fill_color: Color = Color.WHITE:
	set(value):
		fill_color = value
		if _shader_mat:
			_shader_mat.set_shader_parameter("fill_color", value)
@export var label_prefix: String = ""

## Ward at full covers this much of the globe's width.
const WARD_MAX_WIDTH := 0.45
const FRAME_PAD := 20.0
const LABEL_SPACE := 26.0

const ORB_SHADER_CODE := """
shader_type canvas_item;

uniform float fill_fraction : hint_range(0.0, 1.0) = 1.0;
uniform vec4 fill_color : source_color = vec4(0.8, 0.1, 0.1, 1.0);
uniform vec4 bg_color : source_color = vec4(0.04, 0.05, 0.09, 0.8);

// Waterline in [-1,1] space, rippled by two sine waves at different speeds.
float waterline_y(float p_x, float fraction) {
	float wave = sin(p_x * 10.0 + TIME * 2.0) * 0.025 + sin(p_x * 4.0 - TIME * 1.3) * 0.015;
	return 1.0 - 2.0 * fraction + wave;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float dist = length(p);
	if (dist > 1.0) {
		discard;
	}
	vec3 col = bg_color.rgb;
	float alpha = bg_color.a;
	if (fill_fraction > 0.0) {
		float waterline = waterline_y(p.x, fill_fraction);
		if (p.y > waterline) {
			float depth = clamp((p.y - waterline) / 2.0, 0.0, 1.0);
			col = fill_color.rgb * mix(1.15, 0.65, depth);
			col += vec3(smoothstep(0.06, 0.0, abs(p.y - waterline)) * 0.5);
			alpha = fill_color.a;
		}
	}
	// Glassy rim tinted by the fill, and a soft highlight top-left.
	col += fill_color.rgb * smoothstep(0.8, 1.0, dist) * 0.3;
	float shine = smoothstep(0.42, 0.0, length(p - vec2(-0.35, -0.45))) * 0.18;
	col += vec3(shine);
	COLOR = vec4(col, alpha);
}
"""

var current: float = 0.0
var maximum: float = 0.0
var ward: float = 0.0
var ward_max: float = 0.0
var _visual: ColorRect
var _shader_mat: ShaderMaterial
var _frame: OrbFrame

static func box_size(r: float) -> Vector2:
	return Vector2((r + FRAME_PAD) * 2.0, (r + FRAME_PAD) * 2.0 + LABEL_SPACE)

func _ready() -> void:
	custom_minimum_size = box_size(radius)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_visual = ColorRect.new()
	_visual.color = Color.WHITE
	_visual.size = Vector2(radius, radius) * 2.0
	_visual.position = Vector2(FRAME_PAD, FRAME_PAD)
	_visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = ORB_SHADER_CODE
	_shader_mat = ShaderMaterial.new()
	_shader_mat.shader = shader
	_shader_mat.set_shader_parameter("fill_color", fill_color)
	_shader_mat.set_shader_parameter("bg_color", AetherStyle.GLASS)
	_visual.material = _shader_mat
	add_child(_visual)
	_frame = OrbFrame.new()
	_frame.orb = self
	_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frame)

func centre() -> Vector2:
	return Vector2(radius + FRAME_PAD, radius + FRAME_PAD)

func set_value(value: float, max_value: float) -> void:
	current = value
	maximum = max_value
	if _shader_mat:
		_shader_mat.set_shader_parameter("fill_fraction", value / max_value if max_value > 0.0 else 0.0)
	if _frame:
		_frame.queue_redraw()

func set_ward_value(value: float, max_value: float) -> void:
	ward = value
	ward_max = max_value
	if _frame:
		_frame.queue_redraw()

## The lattice keeps its full width while any Ward is up; the fill drains it top to bottom.
func get_ward_width_fraction() -> float:
	return WARD_MAX_WIDTH if ward_max > 0.0 and ward > 0.0 else 0.0

func get_ward_fill() -> float:
	return clampf(ward / ward_max, 0.0, 1.0) if ward_max > 0.0 else 0.0

class OrbFrame extends Control:
	var orb: StatOrb
	var _time: float = 0.0

	func _process(delta: float) -> void:
		if orb.ward > 0.0:
			_time += delta
			queue_redraw()  # the lattice facets shimmer

	func _draw() -> void:
		var c := orb.centre()
		var r := orb.radius
		var serif := AetherStyle.serif()
		var numbers := AetherStyle.numbers()
		var width_fraction := orb.get_ward_width_fraction()
		if width_fraction > 0.0:
			_ward_lattice(c, r, width_fraction, orb.get_ward_fill())
		draw_arc(c, r, 0, TAU, 64, AetherStyle.GOLD, 2.5, true)
		draw_arc(c, r + 3.0, 0, TAU, 64, AetherStyle.GOLD_FAINT, 1.0, true)
		AetherStyle.ticks(self, c, r + 4.0, 60, 5, AetherStyle.GOLD_DIM)
		var value_y := c.y + 8.0
		# With Ward up, the numbers centre in the clear part left of the lattice.
		var text_right := c.x + r
		if width_fraction > 0.0:
			var edge_x := c.x + r - 2.0 * r * width_fraction
			text_right = edge_x - 2.0
			AetherStyle.text(self, numbers, Vector2(edge_x, c.y - r * 0.42), "%d" % roundi(orb.ward), 15, Color(0.85, 0.98, 1.0), HORIZONTAL_ALIGNMENT_CENTER, c.x + r - edge_x)
		AetherStyle.text(self, numbers, Vector2(c.x - r, value_y), "%d" % roundi(orb.current), 30, AetherStyle.TEXT, HORIZONTAL_ALIGNMENT_CENTER, text_right - (c.x - r))
		AetherStyle.text(self, numbers, Vector2(c.x - r, value_y + 20.0), "/ %d" % roundi(orb.maximum), 15, AetherStyle.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, text_right - (c.x - r))
		AetherStyle.text(self, AetherStyle.title(), Vector2(c.x - r, c.y + r + 36.0), AetherStyle.spaced(orb.label_prefix), 13, AetherStyle.GOLD, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0)

	## Triangular lattice over the right side of the globe: a few lit
	## facets that shimmer. Its width is fixed; it drains from the top down
	## as Ward is lost, with a hard top edge and node diamonds.
	func _ward_lattice(c: Vector2, r: float, width_fraction: float, fill: float) -> void:
		var edge_x := c.x + r - 2.0 * r * width_fraction
		var t := acos(clampf((edge_x - c.x) / r, -1.0, 1.0))
		var half := sin(t) * r
		var top_y := c.y + half - 2.0 * half * fill
		var inside := func(p: Vector2) -> bool: return p.distance_to(c) <= r - 2.0 and p.x >= edge_x and p.y >= top_y
		var cap := PackedVector2Array()
		for i in 49:
			var a := -t + 2.0 * t * i / 48.0
			cap.append(c + Vector2(cos(a), sin(a)) * (r - 1.0))
		var clip := PackedVector2Array([Vector2(edge_x - 1.0, top_y), Vector2(c.x + r + 2.0, top_y), Vector2(c.x + r + 2.0, c.y + r + 2.0), Vector2(edge_x - 1.0, c.y + r + 2.0)])
		for poly in Geometry2D.intersect_polygons(cap, clip):
			draw_colored_polygon(poly, Color(0.25, 0.75, 1.0, 0.22))
		var s := 11.0
		var row_h := s * 0.866
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		var origin := c - Vector2(r, r)
		for j in int(2.0 * r / row_h) + 2:
			for i in int(2.0 * r / s) + 2:
				var p := origin + Vector2(i * s + (j % 2) * s * 0.5, j * row_h)
				var down_l := p + Vector2(-s * 0.5, row_h)
				var down_r := p + Vector2(s * 0.5, row_h)
				var lit := rng.randf() < 0.32
				var phase := rng.randf() * TAU
				if lit and inside.call(p) and inside.call(down_l) and inside.call(down_r):
					var a := 0.12 + 0.2 * (0.5 + 0.5 * sin(_time * 1.6 + phase))
					draw_colored_polygon(PackedVector2Array([p, down_l, down_r]), Color(0.55, 0.92, 1.0, a))
				for q in [p + Vector2(s, 0), down_l, down_r]:
					if inside.call(p) and inside.call(q):
						draw_line(p, q, Color(0.55, 0.9, 1.0, 0.42), 1.0, true)
		# Hard top edge, from the lattice's inner side to the globe's rim.
		var rim_x := c.x + sqrt(maxf(r * r - pow(top_y - c.y, 2.0), 0.0)) - 2.0
		if rim_x > edge_x:
			draw_line(Vector2(edge_x, top_y - 2), Vector2(rim_x, top_y - 2), Color(1.0, 0.3, 0.9, 0.25), 1.0, true)
			draw_line(Vector2(edge_x, top_y), Vector2(rim_x, top_y), Color(0.75, 0.97, 1.0, 0.95), 1.6, true)
			var nx := edge_x + 6.0
			while nx < rim_x - 4.0:
				AetherStyle.diamond(self, Vector2(nx, top_y), 2.2, Color(0.8, 0.98, 1.0), Color(0, 0, 0, 0))
				nx += 14.0
		draw_line(Vector2(edge_x, maxf(top_y, c.y - half + 2)), Vector2(edge_x, c.y + half - 2), Color(0.6, 0.95, 1.0, 0.45), 1.0, true)
