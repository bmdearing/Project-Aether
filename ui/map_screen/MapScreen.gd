extends CanvasLayer
class_name MapScreen
## Top-down schematic of the current generated Map's room graph - user-
## requested ("Map function, hit M to see a map of the current area").
## Reads GeneratedMap.graph directly, the same MapGraph data already used
## to build the real geometry - one source of truth, no re-derivation.
## Hub/TestArena are static hand-built scenes with no such graph, so this
## shows a "No map data" message there instead of erroring. Hotkey-only
## (M / open_map), same pattern as Inventory/Abilities/Character/Fate
## Board (P/B/N/C) - dispatched centrally from PauseMenu.gd.

@onready var view: MapView = $CenterContainer/VBox/MapPanel/MapView
@onready var no_data_label: Label = $CenterContainer/VBox/MapPanel/NoDataLabel
@onready var close_button: Button = $CenterContainer/VBox/CloseButton

var _is_open: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	add_to_group("map_screen")
	add_to_group("blocking_menu")
	close_button.pressed.connect(close)

func is_open() -> bool:
	return _is_open

func open() -> void:
	_is_open = true
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh()

func close() -> void:
	_is_open = false
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

func _refresh() -> void:
	var scene := get_tree().current_scene
	var has_data := scene is GeneratedMap
	view.visible = has_data
	no_data_label.visible = not has_data
	if not has_data:
		return
	var map := scene as GeneratedMap
	var player := get_tree().get_first_node_in_group("player") as Player
	var player_cell := Vector2i(-999, -999)
	if player:
		player_cell = Vector2i(
			roundi(player.global_position.x / map.CELL_SIZE),
			roundi(player.global_position.z / map.CELL_SIZE),
		)
	view.render(map.graph, player_cell)
