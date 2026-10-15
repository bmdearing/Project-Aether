extends Node3D
class_name DamageNumber
## Floating combat text for a hit on an enemy, spawned by Enemy.take_damage().
## Billboarded, drawn on top of geometry, drifts up and fades, then frees
## itself. Colored by damage type (Constants.DAMAGE_TYPE_COLOR).

const FLOAT_HEIGHT := 1.2
const FADE_DURATION := 0.9
const FONT_SIZE := 48
const CRIT_FONT_SIZE := 64
const DOT_FONT_SIZE := 32
const OUTLINE_SIZE := 14
const CRIT_OUTLINE_SIZE := 20
## Crits are outlined in red and pop in from a larger size.
const CRIT_OUTLINE_COLOR := Color(0.9, 0.05, 0.05)
const CRIT_POP_SCALE := 1.5
const CRIT_POP_DURATION := 0.15
## Ward-absorbed amounts pass alpha < 1 and render in the Ward colour.
const WARD_ALPHA := 0.5
const WARD_COLOR := Color(0.55, 0.85, 1.0)

@onready var label: Label3D = $Label3D

## alpha < 1.0 for Ward absorption. Enemy calls mark_crit() afterwards when
## the hit turns out to be a critical strike.
func setup(amount: float, damage_type: Constants.DamageType, is_crit: bool, alpha: float = 1.0, is_dot: bool = false) -> void:
	label.text = str(maxi(1, roundi(amount)))
	var color: Color = Constants.DAMAGE_TYPE_COLOR.get(damage_type, Color.WHITE)
	if alpha < 1.0:
		color = WARD_COLOR
		alpha = 1.0
	color.a = alpha
	label.modulate = color
	label.outline_modulate = Color(0, 0, 0, alpha)
	label.outline_size = OUTLINE_SIZE
	label.font_size = DOT_FONT_SIZE if is_dot else FONT_SIZE
	label.font = AetherStyle.numbers()
	_animate()
	if is_crit:
		mark_crit()

func mark_crit() -> void:
	label.font_size = CRIT_FONT_SIZE
	label.outline_size = CRIT_OUTLINE_SIZE
	label.modulate = Color(label.modulate, 1.0).lightened(0.2)
	label.outline_modulate = CRIT_OUTLINE_COLOR
	label.scale = Vector3.ONE * CRIT_POP_SCALE
	create_tween().tween_property(label, "scale", Vector3.ONE, CRIT_POP_DURATION).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

func _animate() -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "position:y", position.y + FLOAT_HEIGHT, FADE_DURATION).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(label, "modulate:a", 0.0, FADE_DURATION).set_ease(Tween.EASE_IN)
	tween.tween_property(label, "outline_modulate:a", 0.0, FADE_DURATION).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(queue_free)
