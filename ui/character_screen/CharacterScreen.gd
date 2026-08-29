extends CanvasLayer
class_name CharacterScreen
## Read-only character sheet (`C`). All 6 stats now come from gear only
## (Section 12 - see StatSheet.gd), so this just displays live totals via
## StatSummaryBuilder (shared with InventoryScreen's own stats column).

@onready var offense_list: VBoxContainer = $CenterContainer/VBox/Columns/OffenseColumn/OffenseList
@onready var defense_list: VBoxContainer = $CenterContainer/VBox/Columns/DefenseColumn/DefenseList
@onready var misc_list: VBoxContainer = $CenterContainer/VBox/Columns/MiscColumn/MiscList
@onready var close_button: Button = $CenterContainer/VBox/CloseButton

var _is_open: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	add_to_group("character_screen")
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
	var player := get_tree().get_first_node_in_group("player") as Player
	StatSummaryBuilder.refresh(offense_list, defense_list, misc_list, player)
