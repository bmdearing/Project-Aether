extends Control
class_name ComposureBar
## Thin bar under the crosshair showing the raised shield's Composure (see
## ShieldBlock). Shows while blocking and while refilling; flashes red on a
## guard break.

const BAR_SIZE := Vector2(160, 6)
const OFFSET_BELOW_CENTER := 46.0
const FILL_COLOR := Color(0.92, 0.82, 0.55)
const LOW_COLOR := Color(0.95, 0.45, 0.3)
const BROKEN_COLOR := Color(1.0, 0.2, 0.15)
const BACK_COLOR := Color(0, 0, 0, 0.55)
const LOW_FRACTION := 0.3
const FADE_SPEED := 4.0
const BREAK_FLASH_SEC := 0.6

var _player: Player
var _alpha: float = 0.0
var _flash: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_player = get_tree().get_first_node_in_group("player") as Player
	if is_instance_valid(_player) and _player.shield_block:
		_player.shield_block.guard_broken.connect(func(): _flash = BREAK_FLASH_SEC)

func _process(delta: float) -> void:
	if not is_instance_valid(_player) or _player.shield_block == null:
		return
	var block := _player.shield_block
	var showing := block.is_raised or block.composure < block.get_max_composure() or _flash > 0.0
	_alpha = move_toward(_alpha, 1.0 if showing else 0.0, FADE_SPEED * delta)
	_flash = maxf(_flash - delta, 0.0)
	queue_redraw()

func _draw() -> void:
	if _alpha <= 0.0 or not is_instance_valid(_player):
		return
	var block := _player.shield_block
	var fraction := clampf(block.composure / maxf(block.get_max_composure(), 1.0), 0.0, 1.0)
	var origin := size * 0.5 + Vector2(-BAR_SIZE.x * 0.5, OFFSET_BELOW_CENTER)
	var color := FILL_COLOR if fraction > LOW_FRACTION else LOW_COLOR
	if _flash > 0.0:
		color = BROKEN_COLOR
	draw_rect(Rect2(origin - Vector2(1, 1), BAR_SIZE + Vector2(2, 2)), Color(BACK_COLOR, BACK_COLOR.a * _alpha))
	draw_rect(Rect2(origin, Vector2(BAR_SIZE.x * fraction, BAR_SIZE.y)), Color(color, _alpha))
