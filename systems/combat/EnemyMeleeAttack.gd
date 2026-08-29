extends Node
class_name EnemyMeleeAttack
## Telegraph + Area3D hitbox melee attack: Idle -> Telegraph -> Strike ->
## Recovery. Attach to an Enemy that should threaten the player.
##
## Strike's hitbox is a static sphere centered on the enemy (Enemy.tscn's
## AttackHitbox, radius baked into the scene) rather than a swept hitbox -
## enemies don't move/rotate to face the player yet, so there's no swing
## to attach one to.
##
## Strike resolves hits by POLLING get_overlapping_bodies() every physics
## frame instead of listening for body_entered: Idle's aggro check already
## uses attack_range as the hitbox radius, so the player is typically
## already inside the sphere when Strike enables monitoring - there's no
## "entering" transition left for body_entered to catch.

enum State { IDLE, TELEGRAPH, STRIKE, RECOVERY }

@export var attack_range: float = 2.5
@export var telegraph_duration: float = 1.0
@export var strike_duration: float = 0.15
@export var recovery_duration: float = 1.2
@export var damage_amount: float = 20.0
@export var damage_type: Constants.DamageType = Constants.DamageType.KINETIC

var _state: State = State.IDLE
var _timer: float = 0.0
var _enemy: Enemy
var _player: Player
var _hitbox: Area3D
var _resolved_this_strike: bool = false

func _ready() -> void:
	_enemy = get_parent()
	_player = get_tree().get_first_node_in_group("player") as Player
	# Deferred: children ready before parents, so Enemy's @onready attack_hitbox
	# isn't assigned yet if read directly here.
	call_deferred("_setup_hitbox")

func _setup_hitbox() -> void:
	_hitbox = _enemy.attack_hitbox
	if _hitbox:
		_hitbox.monitoring = false

func _physics_process(delta: float) -> void:
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Player
		return
	if not _enemy.health.is_alive():
		return

	match _state:
		State.IDLE:
			if _enemy.global_position.distance_to(_player.global_position) <= attack_range:
				_enter_telegraph()
		State.TELEGRAPH:
			_timer -= delta
			var progress := 1.0 - (_timer / telegraph_duration) if telegraph_duration > 0.0 else 1.0
			_enemy.update_attack_telegraph(progress)
			if _timer <= 0.0:
				_enter_strike()
		State.STRIKE:
			_timer -= delta
			_poll_hitbox()
			if _timer <= 0.0:
				_end_strike()
		State.RECOVERY:
			_timer -= delta
			if _timer <= 0.0:
				_state = State.IDLE

func _enter_telegraph() -> void:
	_state = State.TELEGRAPH
	_timer = telegraph_duration
	_enemy.begin_attack_telegraph()
	EventBus.enemy_attack_telegraphed.emit(_enemy)

func _enter_strike() -> void:
	_state = State.STRIKE
	_timer = strike_duration
	_enemy.end_attack_telegraph()
	_resolved_this_strike = false
	if _hitbox:
		_hitbox.monitoring = true

func _end_strike() -> void:
	if _hitbox:
		_hitbox.monitoring = false
	_enter_recovery()

func _enter_recovery() -> void:
	_state = State.RECOVERY
	_timer = recovery_duration

func _poll_hitbox() -> void:
	if _resolved_this_strike or not _hitbox:
		return
	for body in _hitbox.get_overlapping_bodies():
		var player := body as Player
		if player:
			_resolved_this_strike = true
			_hitbox.monitoring = false
			_resolve_hit(player)
			return

func _resolve_hit(player: Player) -> void:
	var parried: bool = player.parry_handler and player.parry_handler.attempt_parry(_enemy, player.ward)
	if not parried:
		player.take_damage(damage_amount * _enemy.get_outgoing_damage_multiplier(), damage_type, _enemy)
	EventBus.enemy_attack_resolved.emit(_enemy, player, true, parried)
