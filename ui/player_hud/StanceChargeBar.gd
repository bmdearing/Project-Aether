extends Control
class_name StanceChargeBar
## Short bar under the crosshair while a stance attack charges (StanceAttack).
## Dim until a must-fully-charge stance (Execute) is ready; flashes white at full.

const BAR_SIZE := Vector2(110, 5)
const OFFSET_BELOW_CENTER := 32.0
const FILL_COLOR := Color(0.75, 0.85, 1.0)
const NOT_READY_COLOR := Color(0.55, 0.6, 0.7)
const FULL_COLOR := Color(1.0, 1.0, 1.0)
const BACK_COLOR := Color(0, 0, 0, 0.55)

var _player: Player
var _fraction: float = 0.0
var _full: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	_player = get_tree().get_first_node_in_group("player") as Player
	if is_instance_valid(_player) and _player.stance_attack:
		_player.stance_attack.charge_changed.connect(_on_charge_changed)
		_player.stance_attack.charge_ended.connect(func(): visible = false)

func _on_charge_changed(fraction: float, full: bool) -> void:
	_fraction = fraction
	_full = full
	visible = true
	queue_redraw()

func _draw() -> void:
	var origin := size * 0.5 + Vector2(-BAR_SIZE.x * 0.5, OFFSET_BELOW_CENTER)
	var color := FULL_COLOR if _full else (NOT_READY_COLOR if _player.stance_attack.requires_full_charge() else FILL_COLOR)
	draw_rect(Rect2(origin - Vector2(1, 1), BAR_SIZE + Vector2(2, 2)), BACK_COLOR)
	draw_rect(Rect2(origin, Vector2(BAR_SIZE.x * (1.0 if _full else _fraction), BAR_SIZE.y)), color)
