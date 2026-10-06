extends Node
## World kill plane for every scene. Enemies that fall below KILL_Y die
## (rewards and all); the player is put back on the last ground they stood
## on, losing a slice of life in a map (the Hub's void is free to fall into).

const KILL_Y := -25.0
const PLAYER_FALL_DAMAGE_PERCENT := 0.15
const SAFE_SPOT_INTERVAL_SEC := 0.25
const RESPAWN_LIFT := 0.5

var _safe_position: Vector3 = Vector3.ZERO
var _has_safe_position := false
var _safe_timer := 0.0
var _player: Player

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	get_tree().scene_changed.connect(_on_scene_changed)

func _on_scene_changed() -> void:
	_has_safe_position = false
	_player = null

func _physics_process(delta: float) -> void:
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Player
	if _player:
		_track_player(delta)
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if enemy is Enemy and enemy.global_position.y < KILL_Y and enemy.health.is_alive():
			enemy.health.apply_damage(enemy.health.current_health + 1.0)

func _track_player(delta: float) -> void:
	if _player.global_position.y < KILL_Y:
		_rescue_player()
		return
	_safe_timer -= delta
	if _safe_timer <= 0.0 and _player.is_on_floor():
		_safe_timer = SAFE_SPOT_INTERVAL_SEC
		_safe_position = _player.global_position
		_has_safe_position = true

func _rescue_player() -> void:
	var map := get_tree().get_first_node_in_group("generated_map") as GeneratedMap
	var target := _safe_position if _has_safe_position else (map.last_player_spawn if map else Vector3.ZERO)
	_player.global_position = target + Vector3(0, RESPAWN_LIFT, 0)
	_player.velocity = Vector3.ZERO
	if map and _player.health and _player.health.is_alive():
		_player.health.apply_damage(_player.health.max_health * PLAYER_FALL_DAMAGE_PERCENT)
