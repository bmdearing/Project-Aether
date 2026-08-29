extends Node
class_name EnemyRangedAttack
## Telegraph + Projectile ranged attack: Idle -> Windup -> Fire -> Cooldown.
## Sibling to EnemyMeleeAttack.gd (same Idle-proximity/telegraph shape,
## same begin/update/end_attack_telegraph() calls on Enemy), but fires
## entities/projectile/Projectile.tscn - the same scene PlayerRangedAttack
## uses - aimed at the player's position at the moment Windup completes,
## rather than resolving a hitbox overlap. Not homing: the direction is
## baked into the projectile's transform at fire time, same "no
## retroactive changes after the shot leaves" design Projectile already
## has.
##
## Chasing/kiting distance is Enemy's job (chase_range/stop_distance/
## retreat_distance) - this component only decides *when to fire* once
## the player is within fire_range, same decoupling EnemyMeleeAttack has
## from Enemy's movement.

const PROJECTILE_SCENE := preload("res://entities/projectile/Projectile.tscn")

enum State { IDLE, WINDUP, COOLDOWN }

@export var fire_range: float = 9.0
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

func _physics_process(delta: float) -> void:
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Player
		return
	if not _enemy.health.is_alive():
		return

	match _state:
		State.IDLE:
			if _enemy.global_position.distance_to(_player.global_position) <= fire_range:
				_enter_windup()
		State.WINDUP:
			_timer -= delta
			var progress := 1.0 - (_timer / windup_duration) if windup_duration > 0.0 else 1.0
			_enemy.update_attack_telegraph(progress)
			if _timer <= 0.0:
				_fire()
		State.COOLDOWN:
			_timer -= delta
			if _timer <= 0.0:
				_state = State.IDLE

func _enter_windup() -> void:
	_state = State.WINDUP
	_timer = windup_duration
	_enemy.begin_attack_telegraph()
	EventBus.enemy_attack_telegraphed.emit(_enemy)

func _fire() -> void:
	_enemy.end_attack_telegraph()
	_state = State.COOLDOWN
	_timer = cooldown_duration
	if not is_instance_valid(_player):
		return

	var origin: Vector3 = _enemy.global_position + Vector3(0, 0.95, 0)
	var target_pos: Vector3 = _player.global_position + Vector3(0, 0.9, 0)
	var dir := (target_pos - origin).normalized()
	# Muzzle offset forward of the enemy's own capsule (radius 0.45) - unlike
	# PlayerRangedAttack, which fires from WeaponSocket (already ahead of
	# Player's capsule), spawning at `origin` would land inside the
	# shooter's own collision shape and self-trigger body_entered.
	var spawn_pos := origin + dir * 0.7

	var projectile: Projectile = PROJECTILE_SCENE.instantiate()
	projectile.damage_amount = damage_amount * _enemy.get_outgoing_damage_multiplier()
	projectile.damage_type = damage_type
	projectile.source = _enemy
	projectile.speed = projectile_speed
	_enemy.get_tree().current_scene.add_child(projectile)
	projectile.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP), spawn_pos)
