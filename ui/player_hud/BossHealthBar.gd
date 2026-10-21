extends Control
class_name BossHealthBar
## Fixed top-center health bar for BOSS-rank enemies, drawn by an animated
## shader on a ColorRect.

const WIDTH := 520.0
const HEIGHT := 18.0
const NAME_HEIGHT := 30.0

## Smooth vertical gradient fill with a pulsing edge glow. Lost health shows
## as white chunks over it (ChunkLayer), the same as EnemyHealthBar.
const SHADER_CODE := """
shader_type canvas_item;

uniform float fill_fraction : hint_range(0.0, 1.0) = 1.0;
uniform float grey : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 uv = UV;
	vec3 bg = vec3(0.035, 0.012, 0.012);
	vec3 fill_col = vec3(0.55, 0.06, 0.05);

	float pulse = 0.5 + 0.5 * sin(TIME * 2.2);
	float edge_glow = smoothstep(fill_fraction - 0.015, fill_fraction, uv.x)
		- smoothstep(fill_fraction, fill_fraction + 0.02, uv.x);

	vec3 col = bg;
	if (uv.x < fill_fraction) {
		float shade = mix(1.18, 0.82, uv.y); // clean vertical gradient, no noise
		col = fill_col * shade;
		col += vec3(0.45, 0.08, 0.03) * edge_glow * (0.6 + 0.5 * pulse);
	}

	float lum = dot(col, vec3(0.3, 0.59, 0.11));
	col = mix(col, vec3(lum * 1.6), grey);
	COLOR = vec4(col, 1.0);
}
"""

var _label: Label
var _shader_mat: ShaderMaterial
var _fraction: float = 1.0
var _chunks: ChunkLayer
var _ward_back: ColorRect
var _ward_fill: ColorRect
var _frame: BarFrame
var _icons: StatusIconRow
var _shatter: BarShatter
var _damage_label: Label
var _damage_boss_id: int = 0
var _damage_last_pool: float = 0.0
var _damage_total: float = 0.0
var _damage_timer: float = 0.0
## Seconds without damage before the running total clears.
const DAMAGE_HOLD := 4.0
const WARD_HEIGHT := 6.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.0
	anchor_bottom = 0.0
	grow_horizontal = 2
	offset_left = -WIDTH / 2.0
	offset_right = WIDTH / 2.0
	offset_top = 46.0  # under the Compass
	offset_bottom = 46.0 + NAME_HEIGHT + HEIGHT

	_ward_back = ColorRect.new()
	_ward_back.color = Color(AetherStyle.AETHER, 0.18)
	_ward_back.position = Vector2(0, NAME_HEIGHT - WARD_HEIGHT - 1.0)
	_ward_back.size = Vector2(WIDTH, WARD_HEIGHT)
	_ward_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ward_back.visible = false
	add_child(_ward_back)
	_ward_fill = ColorRect.new()
	_ward_fill.color = AetherStyle.AETHER
	_ward_fill.size = Vector2(WIDTH, WARD_HEIGHT)
	_ward_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ward_back.add_child(_ward_fill)

	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_override("font", AetherStyle.title())
	_label.add_theme_font_size_override("font_size", 22)
	_label.add_theme_color_override("font_color", AetherStyle.GOLD_BRIGHT)
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	_label.size = Vector2(WIDTH, NAME_HEIGHT)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)

	var bar := ColorRect.new()
	bar.position = Vector2(0, NAME_HEIGHT)
	bar.size = Vector2(WIDTH, HEIGHT)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = SHADER_CODE
	_shader_mat = ShaderMaterial.new()
	_shader_mat.shader = shader
	_shader_mat.set_shader_parameter("fill_fraction", 1.0)
	bar.material = _shader_mat
	bar.color = Color.WHITE
	add_child(bar)
	_chunks = ChunkLayer.new()
	_chunks.position = bar.position
	_chunks.size = bar.size
	_chunks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_chunks)
	_frame = BarFrame.new()
	_frame.position = bar.position
	_frame.size = bar.size
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frame)
	_shatter = BarShatter.new()
	_shatter.position = bar.position
	_shatter.size = bar.size
	add_child(_shatter)
	_icons = StatusIconRow.new()
	_icons.icon_size = 22.0
	_icons.gap = 4.0
	_icons.position = Vector2(0, NAME_HEIGHT + HEIGHT + 6.0)
	_icons.size = Vector2(WIDTH, 26.0)
	add_child(_icons)
	_damage_label = Label.new()
	_damage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_damage_label.add_theme_font_override("font", AetherStyle.serif())
	_damage_label.add_theme_font_size_override("font_size", 15)
	_damage_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.8))
	_damage_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_damage_label.add_theme_constant_override("shadow_offset_x", 1)
	_damage_label.add_theme_constant_override("shadow_offset_y", 1)
	# Above the right end of the bar.
	_damage_label.position = Vector2(WIDTH * 0.7, -6.0)
	_damage_label.size = Vector2(WIDTH * 0.3, 20.0)
	_damage_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_damage_label.visible = false
	add_child(_damage_label)

## Adds up the Life and Ward the boss loses; the total clears after
## DAMAGE_HOLD seconds without damage, or when a different boss takes the bar.
func track_damage(boss_id: int, pool: float) -> void:
	if boss_id != _damage_boss_id:
		_damage_boss_id = boss_id
		_damage_last_pool = pool
		_clear_damage()
		return
	if pool < _damage_last_pool:
		_damage_total += _damage_last_pool - pool
		_damage_timer = DAMAGE_HOLD
		_damage_label.text = _with_commas(roundi(_damage_total))
		_damage_label.visible = true
	_damage_last_pool = pool

func _process(delta: float) -> void:
	if _damage_timer > 0.0:
		_damage_timer -= delta
		if _damage_timer <= 0.0:
			_clear_damage()

func _clear_damage() -> void:
	_damage_total = 0.0
	_damage_timer = 0.0
	_damage_label.visible = false

static func _with_commas(n: int) -> String:
	var digits := str(n)
	var out := ""
	while digits.length() > 3:
		out = "," + digits.right(3) + out
		digits = digits.left(digits.length() - 3)
	return digits + out

## The statuses to show under the bar.
func set_status_source(source: StatusEffectComponent) -> void:
	_icons.source = source

## Greyed out while hits can't hurt the boss (phase transitions, Earth Wheel).
func set_unhittable(unhittable: bool) -> void:
	_shader_mat.set_shader_parameter("grey", 1.0 if unhittable else 0.0)
	_ward_fill.color = Color(0.6, 0.6, 0.62) if unhittable else AetherStyle.AETHER

## The bar shatters while the boss can be riposted.
func set_riposte_ready(can_riposte: bool) -> void:
	_shatter.set_broken(can_riposte)

func set_boss_name(text: String) -> void:
	_label.text = text

## Orange for an Ascendant, gold for a boss.
func set_name_color(color: Color) -> void:
	_label.add_theme_color_override("font_color", color)

## An Ascendant's affixes, under the bar.
func set_subtitle(text: String) -> void:
	if _subtitle == null:
		_subtitle = Label.new()
		_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_subtitle.add_theme_font_override("font", AetherStyle.serif_italic())
		_subtitle.add_theme_font_size_override("font_size", 17)
		_subtitle.add_theme_color_override("font_color", Color(1.0, 0.72, 0.45))
		_subtitle.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
		_subtitle.position = Vector2(0, NAME_HEIGHT + HEIGHT + 4.0)
		# The status icons move down under the affixes.
		_icons.position.y = NAME_HEIGHT + HEIGHT + 26.0
		_subtitle.size = Vector2(WIDTH, 20)
		_subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_subtitle)
	_subtitle.text = text

var _subtitle: Label

## Diamonds on the frame where the boss changes phase (health fractions).
func set_phase_marks(marks: Array[float]) -> void:
	if _frame.marks != marks:
		_frame.marks = marks
		_frame.queue_redraw()

func set_ward(current: float, max_value: float) -> void:
	_ward_back.visible = max_value > 0.0
	if max_value > 0.0:
		_ward_fill.size.x = WIDTH * clampf(current / max_value, 0.0, 1.0)

func set_health(current: float, max_value: float) -> void:
	var new_fraction: float = clamp(current / max_value, 0.0, 1.0) if max_value > 0.0 else 0.0
	if new_fraction < _fraction:
		_chunks.add(new_fraction, _fraction)
	elif new_fraction > _fraction:
		_chunks.heal_to(new_fraction)
	_fraction = new_fraction
	_shader_mat.set_shader_parameter("fill_fraction", _fraction)
	_shatter.fraction = _fraction

## Each hit's lost slice: white, held for EnemyHealthBar.CHUNK_HOLD, then
## thinning and fading over CHUNK_FADE.
class ChunkLayer extends Control:
	var _chunks: Array[Dictionary] = []  # {"from", "to", "age"}

	func add(from: float, to: float) -> void:
		_chunks.append({"from": from, "to": to, "age": 0.0})
		queue_redraw()

	func heal_to(fraction: float) -> void:
		_chunks = _chunks.filter(func(c: Dictionary) -> bool: return c["from"] >= fraction)
		queue_redraw()

	func _process(delta: float) -> void:
		if _chunks.is_empty():
			return
		for c in _chunks:
			c["age"] += delta
		_chunks = _chunks.filter(func(c: Dictionary) -> bool: return c["age"] < EnemyHealthBar.CHUNK_HOLD + EnemyHealthBar.CHUNK_FADE)
		queue_redraw()

	func _draw() -> void:
		for c in _chunks:
			var k := clampf((float(c["age"]) - EnemyHealthBar.CHUNK_HOLD) / EnemyHealthBar.CHUNK_FADE, 0.0, 1.0)
			var h := size.y * (1.0 - 0.75 * k)
			var x0: float = size.x * c["from"]
			draw_rect(Rect2(x0, (size.y - h) / 2.0, size.x * c["to"] - x0, h), Color(1.0, 1.0, 1.0, 1.0 - k))

## Gold frame with a faint inner line and diamond end caps over the shader bar.
class BarFrame extends Control:
	var marks: Array[float] = []

	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		draw_rect(rect, AetherStyle.GOLD, false, 1.5)
		draw_rect(rect.grow(-3), AetherStyle.GOLD_FAINT, false, 1.0)
		AetherStyle.diamond(self, Vector2(0, size.y / 2.0), 8.0, AetherStyle.GLASS_SOLID, AetherStyle.GOLD)
		AetherStyle.diamond(self, Vector2(size.x, size.y / 2.0), 8.0, AetherStyle.GLASS_SOLID, AetherStyle.GOLD)
		for mark in marks:
			var x := size.x * mark
			draw_line(Vector2(x, 2), Vector2(x, size.y - 2), AetherStyle.GOLD, 1.5)
			AetherStyle.diamond(self, Vector2(x, 0), 4.0, AetherStyle.GOLD_BRIGHT, AetherStyle.GOLD)
