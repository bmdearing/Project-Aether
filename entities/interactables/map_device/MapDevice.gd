extends Node3D
class_name MapDevice
## PoE-style map device: stand in its ProximityArea and press `interact`
## (E) to roll a fresh MapItem (MapRoller.roll()) and leave the Hub for
## GameState.MAP_SCENE, with the rolled map's modifiers active for
## everything spawned there (see Enemy.gd's _apply_map_modifiers()).
## There's only one map right now (TestArena.tscn, reused as "the Map")
## and no map-selection UI - the device rolls and commits in one step
## rather than letting you inspect/choose from a stash first, since
## there's no map inventory to choose FROM (nothing persists items
## between scenes yet). A proper "roll, inspect the stat card, then
## commit" flow is a natural follow-up.
##
## `map_tier` is a flat exported constant for now, not derived from
## anything (no map-tier progression exists) - every roll from this
## device is the same tier until that changes.
##
## Proximity is tracked via body_entered/body_exited rather than a
## distance poll each frame (unlike EnemyMeleeAttack's Idle check) since
## this is static and doesn't need to reconsider every frame - Area3D's
## enter/exit signals are exactly the right fit for a stationary trigger
## volume a moving Player walks in and out of.

@export var map_tier: int = 1

@onready var prompt_label: Label3D = $PromptLabel

var _player_in_range: bool = false

func _ready() -> void:
	var area: Area3D = $ProximityArea
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)
	prompt_label.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if _player_in_range and event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		GameState.active_map = MapRoller.roll(map_tier)
		SaveManager.save_game()
		get_tree().change_scene_to_file(GameState.MAP_SCENE)

func _on_body_entered(body: Node3D) -> void:
	if body is Player:
		_player_in_range = true
		prompt_label.visible = true

func _on_body_exited(body: Node3D) -> void:
	if body is Player:
		_player_in_range = false
		prompt_label.visible = false
