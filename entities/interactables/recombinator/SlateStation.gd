extends Node3D
class_name SlateStation
## Hub station that opens the SlateBenchScreen in its mode: the Recombinator
## (two Slates into one) or the Slate Splitter (one into two).

@export var mode: SlateBenchScreen.Mode = SlateBenchScreen.Mode.RECOMBINE

@onready var prompt_label: Label3D = $PromptLabel

var _player_in_range: bool = false

func _ready() -> void:
	var area: Area3D = $ProximityArea
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)
	prompt_label.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if _player_in_range and event.is_action_pressed("interact") and not get_tree().paused:
		get_viewport().set_input_as_handled()
		SlateBenchScreen.open_for(get_tree(), mode)

func _on_body_entered(body: Node3D) -> void:
	if body is Player:
		_player_in_range = true
		GameSettings.refresh_interact_prompt(prompt_label)
		prompt_label.visible = true

func _on_body_exited(body: Node3D) -> void:
	if body is Player:
		_player_in_range = false
		prompt_label.visible = false
