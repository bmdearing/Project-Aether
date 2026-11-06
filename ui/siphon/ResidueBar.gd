extends VBoxContainer
class_name ResidueBar
## One residue pool as a glass capsule of glowing liquid (residue_bar.gdshader),
## with its name and amount under it. The liquid eases to the new level and
## brightens briefly whenever the pool changes. set_pending() marks how much a
## craft would spend from it: that slice glows and the label shows the cost.

const SHADER := preload("res://shaders/residue_bar.gdshader")
const COLORS := {
	&"residue_physical": Color(0.95, 0.55, 0.22),
	&"residue_elemental": Color(0.25, 0.75, 1.0),
	&"residue_esoteric": Color(0.7, 0.35, 1.0),
	&"residue_boss": Color(0.95, 0.2, 0.25),
}
const FILL_EASE := 6.0
const PULSE_FADE := 2.5

var pool: StringName
var compact := false
var _capsule: ColorRect
var _label: Label
var _material: ShaderMaterial
var _shown := -1.0
var _pulse := 0.0
var _pending := 0

## The pool's colour for text (its liquid, lightened to read on dark panels).
static func text_color(p_pool: StringName) -> Color:
	return (COLORS.get(p_pool, Color.WHITE) as Color).lightened(0.35)

static func create(p_pool: StringName, p_compact: bool = false) -> ResidueBar:
	var bar := ResidueBar.new()
	bar.pool = p_pool
	bar.compact = p_compact
	return bar

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_theme_constant_override("separation", 2)
	_capsule = ColorRect.new()
	_capsule.custom_minimum_size = Vector2(120, 14) if compact else Vector2(200, 22)
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter("liquid_color", COLORS.get(pool, Color.WHITE))
	_capsule.material = _material
	_capsule.resized.connect(func(): _material.set_shader_parameter("rect_size", _capsule.size))
	add_child(_capsule)
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 11 if compact else 13)
	_label.add_theme_color_override("font_color", text_color(pool))
	add_child(_label)
	EventBus.residue_changed.connect(_on_residue_changed)
	refresh()

func refresh() -> void:
	if _label == null:
		return
	var amount := Residue.amount(pool)
	var cap := Residue.cap(pool)
	var pool_name := CurrencyText.name_of(pool)
	if compact:
		pool_name = pool_name.get_slice(" ", 0)
	_label.text = "%s  %d / %d" % [pool_name, amount, cap]
	if _pending > 0:
		_label.text += "   -%d" % _pending
	var base := text_color(pool)
	_label.add_theme_color_override("font_color", base.lightened(0.5) if _pending > 0 else base)
	if _shown < 0.0:
		_shown = _target()
	_material.set_shader_parameter("fill", _shown)
	_update_spend()

## Residue the selected craft would take from this pool (0 = none).
func set_pending(amount: int) -> void:
	amount = maxi(amount, 0)
	if amount == _pending:
		return
	_pending = amount
	refresh()

func pending() -> int:
	return _pending

func _update_spend() -> void:
	var share := 0.0
	if _pending > 0 and _shown > 0.0:
		share = minf(float(_pending) / maxf(float(Residue.cap(pool)), 1.0), _shown)
	_material.set_shader_parameter("spend", share)

func _target() -> float:
	return clampf(float(Residue.amount(pool)) / maxf(float(Residue.cap(pool)), 1.0), 0.0, 1.0)

func _on_residue_changed(changed: StringName, _delta: int, _total: int) -> void:
	if changed == pool and is_inside_tree():
		_pulse = 1.0
		refresh()

func _process(delta: float) -> void:
	if _material == null:
		return
	var target := _target()
	if absf(_shown - target) > 0.0005:
		_shown = lerpf(_shown, target, 1.0 - exp(-FILL_EASE * delta))
		_material.set_shader_parameter("fill", _shown)
		_update_spend()
	if _pulse > 0.0:
		_pulse = maxf(_pulse - PULSE_FADE * delta, 0.0)
		_material.set_shader_parameter("pulse", _pulse)
