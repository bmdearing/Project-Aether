extends Node
class_name EnemyMeleeAttack
## Telegraph + Area3D hitbox melee attack: Idle -> Telegraph -> Strike ->
## Recovery. Attach to an Enemy that should threaten the player.
##
## Strike uses a real Area3D (Enemy.attack_hitbox) instead of the distance
## check this used to have - same upgrade PlayerMeleeAttack got. It's a
## static sphere centered on the enemy, not swept through an animation the
## way PlayerMeleeAttack's blade-attached hitbox is, since enemies don't
## move/rotate to face the player yet - there's no swing to attach it to.
## The hitbox radius (Enemy.tscn's AttackHitbox, currently 2.5) is baked
## into the base scene rather than driven by attack_range below per
## instance - mutating a shared .tscn sub-resource's shape at runtime risks
## affecting other enemy instances since sub-resources aren't guaranteed
## distinct per instantiation, so this stays a scene-level constant until
## an archetype actually needs a different reach.
##
## Strike resolves hits by POLLING get_overlapping_bodies() every physics
## frame, not by listening for body_entered. body_entered only fires on a
## fresh overlap transition, but Idle's aggro check uses this same
## attack_range as the hitbox radius, so the player is essentially always
## already standing inside the sphere by the time Strike flips monitoring
## on - there's no "entering" left to detect. A moving/swept hitbox (like
## PlayerMeleeAttack's) doesn't have this problem since it starts outside
## the target and sweeps in; a static sphere centered on a stationary
## target needs an explicit "who's inside right now" check instead.
##
## Idle's proximity check below is aggro range, not hit detection - it was
## never the placeholder being replaced, so it stays a plain distance check.

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
	# Deferred: EnemyMeleeAttack is a CHILD of Enemy, and Godot readies
	# children before parents, so Enemy's own @onready attack_hitbox isn't
	# assigned yet if read here directly - it was silently null for the
	# entire lifetime of this node, which is why Strike could never enable
	# monitoring or find anything to poll. call_deferred runs this after
	# the whole scene tree (including Enemy._ready()) has finished readying.
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
