extends Control
## Revolver Active Reload check, under the RELOADING label: a marker sweeps
## the bar over the reload; R inside the gold zone finishes it, inside the
## bright start of the zone is a Perfect. Shows the outcome briefly after.

const SIZE := Vector2(160, 10)
const BACK := Color(0.05, 0.05, 0.06, 0.8)
const ZONE := Color(0.85, 0.68, 0.3, 0.9)
const PERFECT := Color(1.0, 0.95, 0.7, 1.0)
const MARKER := Color(1, 1, 1)
const JAM := Color(0.9, 0.25, 0.2)
const RESULT_TIME := 0.8

var player: Player
var _view: Dictionary = {}
var _result: String = ""
var _result_left: float = 0.0

func _ready() -> void:
	custom_minimum_size = SIZE + Vector2(0, 16)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	EventBus.active_reload_resolved.connect(_on_resolved)

func _on_resolved(result: String) -> void:
	_result = result
	_result_left = RESULT_TIME

func _process(delta: float) -> void:
	if not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as Player
	_view = player.ranged_attack.get_active_reload() if is_instance_valid(player) else {}
	_result_left = maxf(_result_left - delta, 0.0)
	visible = not _view.is_empty() or _result_left > 0.0
	queue_redraw()

func _draw() -> void:
	var x := size.x - SIZE.x
	if not _view.is_empty():
		draw_rect(Rect2(x, 0, SIZE.x, SIZE.y), BACK)
		var start: float = _view["start"]
		if start <= 1.0:
			var perfect: float = _view["perfect"]
			var end: float = _view["end"]
			draw_rect(Rect2(x + SIZE.x * start, 0, SIZE.x * (end - start), SIZE.y), ZONE)
			draw_rect(Rect2(x + SIZE.x * start, 0, SIZE.x * (perfect - start), SIZE.y), PERFECT)
		var mx: float = x + SIZE.x * float(_view["progress"])
		draw_rect(Rect2(mx - 1.5, -3, 3, SIZE.y + 6), JAM if _view["result"] == "jam" else MARKER)
	if _result_left > 0.0:
		var text: String = {"perfect": "PERFECT", "good": "RELOADED", "jam": "JAMMED"}.get(_result, "")
		var color := JAM if _result == "jam" else (PERFECT if _result == "perfect" else ZONE)
		var font := get_theme_default_font()
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		draw_string(font, Vector2(size.x - w, SIZE.y + 15), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(color, minf(_result_left / 0.3, 1.0)))
