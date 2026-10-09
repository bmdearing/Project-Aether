extends Node3D
class_name StashChest
## Hub interactable: stand in range and press E to open the StashScreen.

@onready var prompt_label: Label3D = $PromptLabel

var _player_in_range := false

func _ready() -> void:
	var area: Area3D = $ProximityArea
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)
	prompt_label.visible = false

func _on_body_entered(body: Node3D) -> void:
	if body is Player:
		_player_in_range = true
		GameSettings.refresh_interact_prompt(prompt_label)
		prompt_label.visible = true

func _on_body_exited(body: Node3D) -> void:
	if body is Player:
		_player_in_range = false
		prompt_label.visible = false

## Looked up on demand - siblings ready in declaration order.
func _get_stash_screen() -> StashScreen:
	return get_tree().get_first_node_in_group("stash_screen") as StashScreen

func _unhandled_input(event: InputEvent) -> void:
	var screen := _get_stash_screen()
	if _player_in_range and event.is_action_pressed("interact") and screen and not screen.is_open():
		get_viewport().set_input_as_handled()
		screen.open()
