extends CanvasLayer
class_name PauseMenu
## Owns pause/menu/mouse-mode state exclusively - Player.gd no longer
## touches Input.mouse_mode or listens for ui_cancel itself.
##
## Inventory/Fate Board/Abilities/Character are deliberately NOT buttons
## here - user preference: they're hotkey-only (P/B/N/C), same as they
## always partly were (P/B worked from anywhere even before this), just
## no longer duplicated as buttons too.

## Hub.tscn's PauseMenu instance sets this false - "Return to Hub" is
## meaningless (and slightly confusing) while already standing in the Hub.
@export var show_return_to_hub: bool = true

@onready var resume_button: Button = $CenterContainer/VBoxContainer/ResumeButton
@onready var return_to_hub_button: Button = $CenterContainer/VBoxContainer/ReturnToHubButton
@onready var main_menu_button: Button = $CenterContainer/VBoxContainer/MainMenuButton
@onready var quit_button: Button = $CenterContainer/VBoxContainer/QuitButton

var _is_open: bool = false
var _fate_board_editor: FateBoardEditor
var _inventory_screen: InventoryScreen
var _abilities_screen: AbilitiesScreen
var _character_screen: CharacterScreen

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_fate_board_editor = get_tree().get_first_node_in_group("fate_board_editor")
	_inventory_screen = get_tree().get_first_node_in_group("inventory_screen")
	_abilities_screen = get_tree().get_first_node_in_group("abilities_screen")
	_character_screen = get_tree().get_first_node_in_group("character_screen")
	resume_button.pressed.connect(close)
	return_to_hub_button.pressed.connect(_on_return_to_hub_pressed)
	return_to_hub_button.visible = show_return_to_hub
	main_menu_button.pressed.connect(_on_main_menu_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

func _unhandled_input(event: InputEvent) -> void:
	# P/B/N/C work regardless of what's currently open - jump straight to
	# the target screen (closing whatever else was open first), or close
	# it if it's already the one showing. Not gated by the ui_cancel guard
	# below.
	if event.is_action_pressed("open_fate_board"):
		_toggle_screen(_fate_board_editor)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("open_inventory"):
		_toggle_screen(_inventory_screen)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("open_abilities"):
		_toggle_screen(_abilities_screen)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("open_character"):
		_toggle_screen(_character_screen)
		get_viewport().set_input_as_handled()
		return
	if show_return_to_hub and event.is_action_pressed("return_to_hub"):
		get_viewport().set_input_as_handled()
		_on_return_to_hub_pressed()
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

## get_tree().paused must be cleared before changing scenes - it's a
## SceneTree-level flag that otherwise carries over and leaves the next
## scene's Player/Enemies frozen (same gotcha DeathScreen's restart has).
## SaveManager.save_game() first - see its header for why this project
## saves at transition points rather than on a timer.
func _on_return_to_hub_pressed() -> void:
	SaveManager.save_game()
	get_tree().paused = false
	get_tree().change_scene_to_file(GameState.HUB_SCENE)

func _on_main_menu_pressed() -> void:
	SaveManager.save_game()
	get_tree().paused = false
	get_tree().change_scene_to_file(GameState.MAIN_MENU_SCENE)

func _on_quit_pressed() -> void:
	SaveManager.save_game()
	get_tree().quit()
