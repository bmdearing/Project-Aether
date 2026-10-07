extends Control
class_name BarrierBar
## Spear Phalanx's barrier pool (StanceDefense), under the crosshair while
## the stance is held and while it refills.

const BAR_SIZE := Vector2(160, 4)
const OFFSET_BELOW_CENTER := 56.0
const FILL_COLOR := Color(0.55, 0.8, 1.0)
const BACK_COLOR := Color(0, 0, 0, 0.55)
const FADE_SPEED := 4.0

var _player: Player
var _alpha: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_player = get_tree().get_first_node_in_group("player") as Player

func _process(delta: float) -> void:
	if not is_instance_valid(_player) or _player.stance_defense == null:
		return
	var defense := _player.stance_defense
	var max_barrier := defense.get_max_barrier()
	var showing := max_barrier > 0.0 and (defense.is_barrier_up() or defense.barrier < max_barrier)
	_alpha = move_toward(_alpha, 1.0 if showing else 0.0, FADE_SPEED * delta)
	queue_redraw()

func _draw() -> void:
	if _alpha <= 0.0 or not is_instance_valid(_player):
		return
	var defense := _player.stance_defense
	var fraction := clampf(defense.barrier / maxf(defense.get_max_barrier(), 1.0), 0.0, 1.0)
	var origin := size * 0.5 + Vector2(-BAR_SIZE.x * 0.5, OFFSET_BELOW_CENTER)
	draw_rect(Rect2(origin - Vector2(1, 1), BAR_SIZE + Vector2(2, 2)), Color(BACK_COLOR, BACK_COLOR.a * _alpha))
	draw_rect(Rect2(origin, Vector2(BAR_SIZE.x * fraction, BAR_SIZE.y)), Color(FILL_COLOR, _alpha))
