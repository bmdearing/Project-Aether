extends CanvasLayer
class_name PauseMenu
## Owns pause/menu/mouse-mode state exclusively - Player.gd no longer
## touches Input.mouse_mode or listens for ui_cancel itself.

@onready var resume_button: Button = $CenterContainer/VBoxContainer/ResumeButton
@onready var inventory_button: Button = $CenterContainer/VBoxContainer/InventoryButton
@onready var fate_board_button: Button = $CenterContainer/VBoxContainer/FateBoardButton
@onready var quit_button: Button = $CenterContainer/VBoxContainer/QuitButton

var _is_open: bool = false
var _fate_board_editor: FateBoardEditor
var _inventory_screen: InventoryScreen

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_fate_board_editor = get_tree().get_first_node_in_group("fate_board_editor")
	_inventory_screen = get_tree().get_first_node_in_group("inventory_screen")
	resume_button.pressed.connect(close)
	inventory_button.pressed.connect(_on_inventory_pressed)
	fate_board_button.pressed.connect(_on_fate_board_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

func _unhandled_input(event: InputEvent) -> void:
	# P/B work regardless of what's currently open - jump straight to the
	# target screen (closing whatever else was open first), or close it if
	# it's already the one showing. Not gated by the ui_cancel guard below.
	if event.is_action_pressed("open_fate_board"):
		_toggle_screen(_fate_board_editor)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("open_inventory"):
		_toggle_screen(_inventory_screen)
		get_viewport().set_input_as_handled()
		return

	# Other menu screens (FateBoardEditor, InventoryScreen, ...) also listen
	# for ui_cancel globally (process_mode ALWAYS) - don't also toggle the
	# pause menu open when one of them is the one handling Esc, regardless
	# of which node's _unhandled_input runs first. Every such screen joins
	# the "blocking_menu" group and exposes is_open().
	for menu in get_tree().get_nodes_in_group("blocking_menu"):
		if menu.is_open():
			return
	if event.is_action_pressed("ui_cancel"):
		toggle()

## Opens `screen`, closing this pause menu and any other open blocking_menu
## screen first - or closes `screen` if it's already the one open.
func _toggle_screen(screen: Node) -> void:
	if screen == null:
		return
	if screen.is_open():
		screen.close()
		return
	for menu in get_tree().get_nodes_in_group("blocking_menu"):
		if menu != screen and menu.is_open():
			menu.close()
	close()
	screen.open()

func toggle() -> void:
	close() if _is_open else open()

func open() -> void:
	_is_open = true
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func close() -> void:
	_is_open = false
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_inventory_pressed() -> void:
	_toggle_screen(_inventory_screen)

func _on_fate_board_pressed() -> void:
	_toggle_screen(_fate_board_editor)

func _on_quit_pressed() -> void:
	get_tree().quit()
