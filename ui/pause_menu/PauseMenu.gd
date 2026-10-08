extends CanvasLayer
class_name PauseMenu
## Owns pause/menu/mouse-mode state exclusively - Player.gd no longer
## touches Input.mouse_mode or listens for ui_cancel itself.
##
## Inventory/Fate Board/Abilities/Character/Map are deliberately
## NOT buttons here - user preference: they're hotkey-only (P/B/N/C/M),
## same as they always partly were (P/B worked from anywhere even before
## this), just no longer duplicated as buttons too.

## Hub.tscn's PauseMenu instance sets this false - "Return to Hub" is
## meaningless (and slightly confusing) while already standing in the Hub.
@export var show_return_to_hub: bool = true

@onready var resume_button: Button = $CenterContainer/VBoxContainer/ResumeButton
@onready var return_to_hub_button: Button = $CenterContainer/VBoxContainer/ReturnToHubButton
@onready var main_menu_button: Button = $CenterContainer/VBoxContainer/MainMenuButton
@onready var quit_button: Button = $CenterContainer/VBoxContainer/QuitButton

var _is_open: bool = false
var _settings_center: CenterContainer
var _fate_board_editor: FateBoardEditor
var _inventory_screen: InventoryScreen
var _abilities_screen: AbilitiesScreen
var _character_screen: CharacterScreen
var _map_screen: MapScreen

func _ready() -> void:
	layer = AetherStyle.SCREEN_LAYER  # above the HUD
	AetherStyle.style_screen(self)
	add_to_group("full_screen_menu")
	AetherStyle.wrap_in_plate($CenterContainer/VBoxContainer, 28)
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_fate_board_editor = get_tree().get_first_node_in_group("fate_board_editor")
	_inventory_screen = get_tree().get_first_node_in_group("inventory_screen")
	_abilities_screen = get_tree().get_first_node_in_group("abilities_screen")
	_character_screen = get_tree().get_first_node_in_group("character_screen")
	_map_screen = get_tree().get_first_node_in_group("map_screen")
	resume_button.pressed.connect(close)
	return_to_hub_button.pressed.connect(_on_return_to_hub_pressed)
	return_to_hub_button.visible = show_return_to_hub
	main_menu_button.pressed.connect(_on_main_menu_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	_build_settings()

func _build_settings() -> void:
	var settings_button := Button.new()
	settings_button.text = "Settings"
	settings_button.pressed.connect(_show_settings.bind(true))
	var menu := resume_button.get_parent()
	menu.add_child(settings_button)
	menu.move_child(settings_button, return_to_hub_button.get_index() + 1)
	_settings_center = CenterContainer.new()
	_settings_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings_center.visible = false
	add_child(_settings_center)
	var panel := SettingsPanel.new()
	panel.back_pressed.connect(_show_settings.bind(false))
	_settings_center.add_child(panel)

func _show_settings(open_settings: bool) -> void:
	_settings_center.visible = open_settings
	resume_button.get_parent().get_parent().visible = not open_settings

func _unhandled_input(event: InputEvent) -> void:
	# P/B/N/C/M jump straight to the target screen (closing whatever else
	# was open), or close it if already showing. Not gated by ui_cancel below.
	if event.is_action_pressed("open_fate_board"):
		_toggle_screen(_fate_board_editor)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("open_inventory"):
		# Opened from the character sheet, it keeps the stats on the left.
		var with_stats := _character_screen != null and _character_screen.is_open()
		_toggle_screen(_inventory_screen)
		if with_stats and _inventory_screen.is_open():
			_inventory_screen.toggle_stats()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("open_abilities"):
		_toggle_screen(_abilities_screen)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("open_character"):
		if _inventory_screen and _inventory_screen.is_open():
			_inventory_screen.toggle_stats()
		else:
			_toggle_screen(_character_screen)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("open_map"):
		_toggle_screen(_map_screen)
		get_viewport().set_input_as_handled()
		return
	if show_return_to_hub and event.is_action_pressed("return_to_hub"):
		get_viewport().set_input_as_handled()
		var map := get_tree().current_scene as GeneratedMap
		if map:
			map.open_portal()
		else:
			_on_return_to_hub_pressed()
		return

	# Other menu screens also listen for ui_cancel globally - don't toggle
	# the pause menu open when one of them is handling Esc. Every such
	# screen joins "blocking_menu" and exposes is_open().
	for menu in get_tree().get_nodes_in_group("blocking_menu"):
		if menu.is_open():
			return
	if event.is_action_pressed("ui_cancel"):
		if _is_open and _settings_center.visible:
			_show_settings(false)
			get_viewport().set_input_as_handled()
			return
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
	_show_settings(false)
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
## scene's Player/Enemies frozen.
func _on_return_to_hub_pressed() -> void:
	var map := get_tree().current_scene as GeneratedMap
	if map:
		# Same as stepping through a portal on the spot - the map stays open.
		map.open_portal()
		map.leave_through_portal()
		return
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
