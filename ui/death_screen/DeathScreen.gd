extends CanvasLayer
class_name DeathScreen
## Shown when Player.gd forwards HealthComponent.died -> EventBus.player_died.
## Not a "blocking_menu" screen - nothing to toggle or close, only Return
## to Hub/Main Menu/Quit once dead.
##
## "Return to Hub" (not a same-map restart) matches the Hub/Map-Device
## structure - dying ends the map, same as the pause menu's equivalent
## button, rather than retrying the same map in place.

@onready var restart_button: Button = $CenterContainer/VBoxContainer/RestartButton
@onready var main_menu_button: Button = $CenterContainer/VBoxContainer/MainMenuButton
@onready var quit_button: Button = $CenterContainer/VBoxContainer/QuitButton

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	EventBus.player_died.connect(_on_player_died)
	restart_button.pressed.connect(_on_restart_pressed)
	main_menu_button.pressed.connect(_on_main_menu_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

func _on_player_died() -> void:
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

## get_tree().paused must be cleared before changing scenes, otherwise it
## carries over and leaves the Hub's Player frozen.
func _on_restart_pressed() -> void:
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
