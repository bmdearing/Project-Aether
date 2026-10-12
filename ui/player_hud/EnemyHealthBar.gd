extends Control
class_name EnemyHealthBar
## Floating bar over an enemy (hovered, or in combat): the name in its
## rarity colour, a thin gold-framed health bar, and a cyan Ward strip above
## while the enemy has Ward. Positioned every frame by PlayerHUD.
## Each hit's lost slice of the bar turns white, holds for a moment, then
## fades and thins away (Borderlands style); quick hits stack as separate chunks.
## Status icons (StatusIconRow) sit under the bar, and the bar shatters
## (BarShatter) while the enemy can be riposted.

const WIDTH := 150.0
const HEIGHT := 6.0
const BAR_TOP := 26.0
const WARD_HEIGHT := 3.0
const WARD_GAP := 3.0
const CHUNK_HOLD := 0.14
const CHUNK_FADE := 0.4

var _fraction: float = 1.0
## Lost slices still showing: {"from", "to" (bar fractions), "age" (s)}.
var _chunks: Array[Dictionary] = []
var _ward_fraction: float = 0.0
var _has_ward: bool = false
var _name_label: Label
var _icons: StatusIconRow
var _shatter: BarShatter

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(WIDTH, BAR_TOP + HEIGHT)
	size = custom_minimum_size
	_name_label = Label.new()
	_name_label.add_theme_font_override("font", AetherStyle.serif())
	_name_label.add_theme_font_size_override("font_size", 14)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_name_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_name_label.add_theme_constant_override("shadow_offset_x", 1)
	_name_label.add_theme_constant_override("shadow_offset_y", 1)
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_name_label)
	_shatter = BarShatter.new()
	_shatter.position = Vector2(0, BAR_TOP)
	_shatter.size = Vector2(WIDTH, HEIGHT)
	add_child(_shatter)
	_icons = StatusIconRow.new()
	_icons.icon_size = 14.0
	_icons.position = Vector2(0, BAR_TOP + HEIGHT + 5.0)
	_icons.size = Vector2(WIDTH, 18.0)
	add_child(_icons)

## The statuses to show under the bar.
func set_status_source(source: StatusEffectComponent) -> void:
	_icons.source = source

## The bar shatters while the enemy can be riposted.
func set_riposte_ready(can_riposte: bool) -> void:
	_shatter.set_broken(can_riposte)

func set_enemy_name(text: String) -> void:
	_name_label.text = text

## Rare affixes ("Swift  ·  Searing") in small type above the name.
func set_affix_text(text: String) -> void:
	if text == "" and _affix_label == null:
		return
	if _affix_label == null:
		_affix_label = Label.new()
		_affix_label.add_theme_font_override("font", AetherStyle.serif_italic())
		_affix_label.add_theme_font_size_override("font_size", 12)
		_affix_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.95))
		_affix_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
		_affix_label.add_theme_constant_override("shadow_offset_x", 1)
		_affix_label.add_theme_constant_override("shadow_offset_y", 1)
		_affix_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_affix_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
		_affix_label.position.y = -16.0
		_affix_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_affix_label)
	_affix_label.text = text

var _affix_label: Label

## Elite/Champion/Ascendant names show in blue/yellow/orange.
func set_name_color(color: Color) -> void:
	_name_label.add_theme_color_override("font_color", color)

func set_health(current: float, max_value: float) -> void:
	var new_fraction: float = clamp(current / max_value, 0.0, 1.0) if max_value > 0.0 else 0.0
	if new_fraction < _fraction:
		_chunks.append({"from": new_fraction, "to": _fraction, "age": 0.0})
	elif new_fraction > _fraction:
		# Healing covers any chunk under the new fill.
		_chunks = _chunks.filter(func(c: Dictionary) -> bool: return c["from"] >= new_fraction)
	_fraction = new_fraction
	_shatter.fraction = _fraction
	queue_redraw()

## Ward shows as a thin strip above the health bar while the enemy has any pool.
func set_ward(current: float, max_value: float) -> void:
	var has_ward := max_value > 0.0
	var fraction := clampf(current / max_value, 0.0, 1.0) if has_ward else 0.0
	if has_ward != _has_ward or not is_equal_approx(fraction, _ward_fraction):
		_has_ward = has_ward
		_ward_fraction = fraction
		queue_redraw()

func _process(delta: float) -> void:
	if _chunks.is_empty():
		return
	for c in _chunks:
		c["age"] += delta
	_chunks = _chunks.filter(func(c: Dictionary) -> bool: return c["age"] < CHUNK_HOLD + CHUNK_FADE)
	queue_redraw()

func _draw() -> void:
	if _has_ward:
		var ward := Rect2(12.0, BAR_TOP - WARD_HEIGHT - WARD_GAP, WIDTH - 24.0, WARD_HEIGHT)
		draw_rect(ward, Color(AetherStyle.AETHER, 0.18))
		if _ward_fraction > 0.0:
			draw_rect(Rect2(ward.position, Vector2(ward.size.x * _ward_fraction, WARD_HEIGHT)), AetherStyle.AETHER)
	var bar := Rect2(0, BAR_TOP, WIDTH, HEIGHT)
	AetherStyle.bar(self, bar, _fraction, AetherStyle.LIFE.lightened(0.1))
	if _chunks.is_empty():
		return
	var centre_y := BAR_TOP + HEIGHT / 2.0
	for c in _chunks:
		var age: float = c["age"]
		var k := clampf((age - CHUNK_HOLD) / CHUNK_FADE, 0.0, 1.0)
		var h := HEIGHT * (1.0 - 0.75 * k)
		var x0: float = WIDTH * c["from"]
		# A white flash, then thinning and fading to nothing.
		draw_rect(Rect2(x0, centre_y - h / 2.0, WIDTH * c["to"] - x0, h), Color(1.0, 1.0, 1.0, 1.0 - k))
	# The frame stays on top of the chunks.
	draw_rect(bar, AetherStyle.GOLD_DIM, false, 1.0)
	AetherStyle.diamond(self, bar.position + Vector2(0, HEIGHT / 2.0), 4.5, AetherStyle.GLASS, AetherStyle.GOLD)
	AetherStyle.diamond(self, bar.position + Vector2(WIDTH, HEIGHT / 2.0), 4.5, AetherStyle.GLASS, AetherStyle.GOLD)
