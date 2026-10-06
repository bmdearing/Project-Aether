extends Node
class_name EnemyRangedAttack
## Telegraph + Projectile ranged attack: Idle -> Windup -> Fire -> Cooldown.
## Sibling to EnemyMeleeAttack.gd, but fires Projectile.tscn aimed at the
## player's position when Windup completes - not homing, direction is
## baked in at fire time.
##
## Chasing/kiting distance is Enemy's job; this component only decides
## *when to fire* once the player is within fire_range.

const PROJECTILE_SCENE := preload("res://entities/projectile/Projectile.tscn")

enum State { IDLE, WINDUP, COOLDOWN }

@export var fire_range: float = 9.0
## Holds fire while the player is closer than this (leaves close range to a melee attack).
@export var min_range: float = 0.0
@export var windup_duration: float = 0.5
@export var cooldown_duration: float = 1.3
@export var damage_amount: float = 18.0
@export var damage_type: Constants.DamageType = Constants.DamageType.KINETIC
@export var projectile_speed: float = 18.0

var _state: State = State.IDLE
var _timer: float = 0.0
var _enemy: Enemy
var _player: Player

func _ready() -> void:
	_enemy = get_parent()
	_player = get_tree().get_first_node_in_group("player") as Player

## Counter damage (see EnemyMeleeAttack.is_attacking()'s own comment) -
## Windup is this component's equivalent "committed, mid-attack" window.
func is_attacking() -> bool:
	return _state == State.WINDUP

func _physics_process(delta: float) -> void:
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Player
		return
	if not _enemy.health.is_alive():
		return
	if _enemy.status_effects.is_stunned():
		return  # Electrocute/Freeze pause the state machine, not reset it

	match _state:
		State.IDLE:
			var dist := _enemy.global_position.distance_to(_player.global_position)
			if dist <= fire_range and dist >= min_range and not _sibling_attacking():
				_enter_windup()
		State.WINDUP:
			_timer -= delta
			if _timer <= 0.0:
				_fire()
		State.COOLDOWN:
			_timer -= delta
			if _timer <= 0.0:
				_state = State.IDLE

func _sibling_attacking() -> bool:
	var melee := _enemy.get_node_or_null("MeleeAttack") as EnemyMeleeAttack
	return melee != null and melee.is_attacking()

func _enter_windup() -> void:
	_state = State.WINDUP
	_timer = windup_duration
	_enemy.begin_attack_telegraph(windup_duration)
	EventBus.enemy_attack_telegraphed.emit(_enemy)

func _fire() -> void:
	_state = State.COOLDOWN
	_timer = cooldown_duration
	if not is_instance_valid(_player):
		return

	var origin: Vector3 = _enemy.global_position + Vector3(0, 0.95, 0)
	var target_pos: Vector3 = _player.global_position + Vector3(0, 0.9, 0)
	var dir := (target_pos - origin).normalized()
	# Muzzle offset forward of the enemy's capsule - spawning at `origin`
	# would land inside the shooter's own collision shape.
	var spawn_pos := origin + dir * 0.7

	var projectile: Projectile = PROJECTILE_SCENE.instantiate()
	projectile.damage_amount = damage_amount * _enemy.get_outgoing_damage_multiplier()
	projectile.damage_type = damage_type
	projectile.source = _enemy
	projectile.speed = projectile_speed
	_enemy.get_tree().current_scene.add_child(projectile)
	projectile.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP), spawn_pos)
