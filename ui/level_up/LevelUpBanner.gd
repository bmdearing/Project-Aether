extends CanvasLayer
class_name LevelUpBanner
## Level-up screen effect: a gold flash around the screen edges and a
## "LEVEL 24" banner whose changed digits roll down like a clock to the new
## level (the old digit drops and fades, the new one comes down from above).
## Player.play() shows one per XP grant, however many levels it gave.

const LAYER := 40
const FONT_SIZE := 72
const ROLL_AT := 0.6
const ROLL_TIME := 0.38
## Each digit to the left starts rolling this much later (ones first).
const ROLL_STAGGER := 0.09
const HOLD_UNTIL := 2.8
const FADE_OUT := 0.6
const EDGE_SHADER := "shader_type canvas_item;
render_mode blend_add;
uniform vec4 tint : source_color;
uniform float strength = 0.0;
void fragment() {
	vec2 d = (UV - 0.5) * vec2(1.7, 1.0);
	float edge = smoothstep(0.32, 0.78, length(d));
	COLOR = vec4(tint.rgb * edge * strength * tint.a, 1.0);
}"
const BAND_SHADER := "shader_type canvas_item;
render_mode blend_add;
uniform vec4 tint : source_color;
uniform float strength = 0.0;
void fragment() {
	float x = 1.0 - abs(UV.x - 0.5) * 2.0;
	float y = 1.0 - abs(UV.y - 0.5) * 2.0;
	COLOR = vec4(tint.rgb * x * x * y * strength * tint.a, 1.0);
}"

var _from := 1
var _to := 1
var _edge_mat: ShaderMaterial
var _band_mat: ShaderMaterial
var _banner: Control

## Replaces any banner already showing on `host`.
static func play(host: Node, from_level: int, to_level: int) -> LevelUpBanner:
	for child in host.get_children():
		if child is LevelUpBanner:
			child.queue_free()
	var banner := LevelUpBanner.new()
	banner._from = from_level
	banner._to = to_level
	host.add_child(banner)
	return banner

func _ready() -> void:
	layer = LAYER
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_edge_mat = _overlay(root, EDGE_SHADER, Control.PRESET_FULL_RECT)
	var band := ColorRect.new()
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.anchor_left = 0.15
	band.anchor_right = 0.85
	band.anchor_top = 0.2
	band.anchor_bottom = 0.36
	_band_mat = _shader_material(BAND_SHADER)
	band.material = _band_mat
	root.add_child(band)

	_banner = HBoxContainer.new()
	_banner.alignment = BoxContainer.ALIGNMENT_CENTER
	_banner.add_theme_constant_override("separation", 0)
	_banner.anchor_left = 0.0
	_banner.anchor_right = 1.0
	_banner.anchor_top = 0.2
	_banner.anchor_bottom = 0.36
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.modulate.a = 0.0
	root.add_child(_banner)
	_banner.add_child(_label("LEVEL "))
	var old_text := str(_from)
	var new_text := str(_to)
	var slots := new_text.length()
	old_text = old_text.lpad(slots) if old_text.length() < slots else old_text.right(slots)
	for i in slots:
		var slot := _digit_slot(old_text[i])
		_banner.add_child(slot)
		if old_text[i] != new_text[i]:
			var from_right := slots - 1 - i
			_roll(slot, new_text[i], ROLL_AT + ROLL_STAGGER * from_right)
	_animate()

func _overlay(parent: Control, code: String, preset: int) -> ShaderMaterial:
	var rect := ColorRect.new()
	rect.set_anchors_preset(preset)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := _shader_material(code)
	rect.material = mat
	parent.add_child(rect)
	return mat

func _shader_material(code: String) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = code
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("tint", Color(AetherStyle.GOLD_BRIGHT, 0.85))
	mat.set_shader_parameter("strength", 0.0)
	return mat

func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", AetherStyle.title())
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_color", AetherStyle.GOLD_BRIGHT)
	label.add_theme_color_override("font_outline_color", Color(0.12, 0.07, 0.02))
	label.add_theme_constant_override("outline_size", 12)
	label.add_theme_color_override("font_shadow_color", Color(1.0, 0.65, 0.2, 0.45))
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", 0)
	label.add_theme_constant_override("shadow_outline_size", 30)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return label

## A clipped cell one digit wide, so a rolling digit vanishes at its edges.
func _digit_slot(digit: String) -> Control:
	var font := AetherStyle.title()
	var slot := Control.new()
	slot.clip_contents = true
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.custom_minimum_size = Vector2(font.get_string_size("0", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x + 8.0, font.get_height(FONT_SIZE) + 24.0)
	slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var label := _label(digit)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	slot.add_child(label)
	return slot

func _roll(slot: Control, new_digit: String, at: float) -> void:
	var old_label := slot.get_child(0) as Label
	var new_label := _label(new_digit)
	new_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	new_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	new_label.modulate.a = 0.0
	slot.add_child(new_label)
	var h := slot.custom_minimum_size.y
	new_label.position.y = -h
	var t := create_tween().set_parallel(true)
	t.tween_property(old_label, "position:y", h, ROLL_TIME).set_delay(at).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_property(old_label, "modulate:a", 0.0, ROLL_TIME * 0.8).set_delay(at)
	t.tween_property(new_label, "position:y", 0.0, ROLL_TIME).set_delay(at + 0.06).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(new_label, "modulate:a", 1.0, ROLL_TIME * 0.6).set_delay(at + 0.06)

func _animate() -> void:
	var t := create_tween().set_parallel(true)
	t.tween_property(_edge_mat, "shader_parameter/strength", 1.0, 0.12)
	t.tween_property(_edge_mat, "shader_parameter/strength", 0.0, 1.5).set_delay(0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(_band_mat, "shader_parameter/strength", 0.55, 0.25)
	t.tween_property(_band_mat, "shader_parameter/strength", 0.0, FADE_OUT + 0.4).set_delay(HOLD_UNTIL - 0.4)
	t.tween_property(_banner, "modulate:a", 1.0, 0.25)
	t.tween_property(_banner, "modulate:a", 0.0, FADE_OUT).set_delay(HOLD_UNTIL)
	t.chain().tween_callback(queue_free)

## The level the banner ends on (tests).
func target_level() -> int:
	return _to
