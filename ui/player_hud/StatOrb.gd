extends Control
class_name StatOrb
## Life/Mana globe: a glass globe with glowing energy inside (ORB_SHADER_CODE) in a gold
## instrument ring with tick marks, the value in the middle and the label
## underneath. The Life orb also shows Ward as a crystalline lattice over
## its right side (see OrbFrame._ward_lattice()), draining from the top
## down as Ward is lost - deliberately not a second fill.

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

// Interior view of a glass globe, seen almost level: each pixel
// enters the sphere (refracted), marches through a slowly turning volume of
// glowing energy filled up to fill_fraction, and ends on the etched back
// wall. The fill's top is a soft surface that breathes with the noise, not
// a waterline. The view and refraction are kept shallow so the fill's
// height on screen matches the value, and a bright line on the glass marks
// the exact level.
uniform float fill_fraction : hint_range(0.0, 1.0) = 1.0;
uniform vec4 fill_color : source_color = vec4(0.8, 0.1, 0.1, 1.0);
uniform vec4 bg_color : source_color = vec4(0.04, 0.05, 0.09, 0.8);
// Offsets the noise so two globes don't move in step.
uniform float seed = 0.0;

const int STEPS = 22;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float total = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 3; i++) {
		total += amp * noise(p);
		p = p * 2.03 + vec3(1.7, 9.2, 3.1);
		amp *= 0.5;
	}
	return total;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r2 = dot(p, p);
	if (r2 > 1.0) {
		discard;
	}
	// 3D with y up; n is the front surface point and its normal.
	vec3 n = vec3(p.x, -p.y, sqrt(1.0 - r2));
	vec3 view = normalize(vec3(0.0, -0.06, -1.0));
	vec3 d = refract(view, n, 1.0 / 1.1);
	float t_exit = -2.0 * dot(n, d);
	float level = fill_fraction * 2.0 - 1.0;
	float spin = TIME * 0.22 + seed;
	float cs = cos(spin);
	float sn = sin(spin);
	float dt = t_exit / float(STEPS);
	vec3 glow = vec3(0.0);
	float trans = 1.0;
	for (int i = 0; i < STEPS; i++) {
		vec3 q = n + d * (dt * (float(i) + 0.5));
		vec3 rq = vec3(cs * q.x - sn * q.z, q.y, sn * q.x + cs * q.z);
		float wisp = fbm(rq * 2.4 + vec3(seed * 3.0, -TIME * 0.3, 0.0));
		// The top of the fill: soft, and lifted or lowered by the wisps.
		float top = level + (wisp - 0.5) * 0.05;
		float inside = smoothstep(top + 0.02, top - 0.03, q.y);
		if (fill_fraction <= 0.001) {
			inside = 0.0;
		}
		float core = 1.0 - smoothstep(0.0, 1.05, length(q));
		float density = inside * (0.3 + wisp * wisp * 1.1) * (0.55 + core);
		// Brighter towards the heart, with hot motes where the wisps peak.
		vec3 emit = fill_color.rgb * (0.45 + 1.7 * core * wisp) + vec3(pow(wisp, 7.0) * 1.4);
		// The skin of the fill glows a little.
		emit += fill_color.rgb * smoothstep(0.08, 0.0, abs(q.y - top)) * inside * 0.9;
		float a = 1.0 - exp(-density * dt * 3.4);
		glow += trans * a * emit;
		trans *= 1.0 - a;
		if (trans < 0.03) {
			break;
		}
	}
	// The inner back wall: dark glass with faint etched meridians and rings,
	// lit by the fill in front of it.
	vec3 back = n + d * t_exit;
	float lat = asin(clamp(back.y, -1.0, 1.0));
	float lon = atan(back.x, back.z);
	float etch = max(smoothstep(0.965, 1.0, abs(sin(lat * 5.0))), smoothstep(0.975, 1.0, abs(sin(lon * 6.0))));
	vec3 wall = bg_color.rgb * 1.3 + fill_color.rgb * etch * (0.06 + 0.22 * fill_fraction);
	vec3 col = glow + trans * wall;
	// The level line on the glass, at exactly fill_fraction of the height.
	if (fill_fraction > 0.001 && fill_fraction < 0.999) {
		float line_dist = abs(n.y - level);
		col += mix(fill_color.rgb, vec3(1.0), 0.55) * smoothstep(0.022, 0.0, line_dist) * 0.9;
		// Above the line the globe reads clearly empty.
		col *= mix(1.0, 0.55, smoothstep(level - 0.01, level + 0.04, n.y));
	}
	// Glass: a fresnel rim, a sharp glint top-left and a faint reflection low right.
	float fresnel = pow(1.0 - n.z, 3.0);
	col += mix(vec3(0.62, 0.68, 0.85), fill_color.rgb, 0.45) * fresnel * 0.6;
	vec3 light = normalize(vec3(-0.55, 0.6, 0.65));
	float spec = pow(max(dot(reflect(-light, n), vec3(0.0, 0.0, 1.0)), 0.0), 48.0);
	col += vec3(spec * 0.6);
	col += vec3(smoothstep(0.9, 0.98, sqrt(r2)) * smoothstep(0.3, 0.9, p.x + p.y) * 0.07);
	COLOR = vec4(col, max(bg_color.a, 1.0 - trans * 0.3));
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
	_shader_mat.set_shader_parameter("seed", float(label_prefix.hash() % 97) * 0.37)
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
