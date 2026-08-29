extends CanvasLayer
class_name DeathScreen
## Shown when Player.gd forwards HealthComponent.died -> EventBus.player_died.
## Not a "blocking_menu" screen (PauseMenu/FateBoardEditor/InventoryScreen) -
## there's nothing to toggle or close, only Restart/Quit once you're dead.
##
## Restart reloads the current scene wholesale - simplest possible "run
## reset" for a vertical slice with no save/load or persistence layer.
## GameState/EventBus/Constants are autoloads and survive a scene reload
## untouched, which is fine here since none of them hold cross-run state
## that would need clearing (GameState's player_stat_sheet/fate_board/
## player_equipment all just get overwritten by the new Player._ready()).

@onready var restart_button: Button = $CenterContainer/VBoxContainer/RestartButton
@onready var quit_button: Button = $CenterContainer/VBoxContainer/QuitButton

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	EventBus.player_died.connect(_on_player_died)
	restart_button.pressed.connect(_on_restart_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

func _on_player_died() -> void:
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _on_restart_pressed() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()

func _on_quit_pressed() -> void:
	get_tree().quit()
