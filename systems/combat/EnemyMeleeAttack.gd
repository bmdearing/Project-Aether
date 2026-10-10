extends Node
class_name EnemyMeleeAttack
## Telegraph + Area3D hitbox melee attack: Idle -> Telegraph -> Strike ->
## Recovery. Attach to an Enemy that should threaten the player.
##
## The hitbox is a static sphere (Enemy.tscn's AttackHitbox). Strike polls
## get_overlapping_bodies() rather than using body_entered, because the
## player is usually already inside the sphere when monitoring turns on.

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
	if _enemy.status_effects.is_stunned():
		return  # Electrocute/Freeze pause the state machine, not reset it

	match _state:
		State.IDLE:
			if _enemy.global_position.distance_to(_player.global_position) <= attack_range and not _sibling_attacking():
				_enter_telegraph()
		State.TELEGRAPH:
			_timer -= delta
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

func _sibling_attacking() -> bool:
	var ranged := _enemy.get_node_or_null("RangedAttack") as EnemyRangedAttack
	return ranged != null and ranged.is_attacking() or _enemy.is_casting()

func _enter_telegraph() -> void:
	_state = State.TELEGRAPH
	_timer = telegraph_duration / _enemy.get_attack_speed_multiplier()
	_enemy.begin_attack_telegraph(_timer)
	EventBus.enemy_attack_telegraphed.emit(_enemy)

func _enter_strike() -> void:
	_state = State.STRIKE
	_timer = strike_duration / _enemy.get_attack_speed_multiplier()
	_resolved_this_strike = false
	if _hitbox:
		_hitbox.monitoring = true

func _end_strike() -> void:
	if _hitbox:
		_hitbox.monitoring = false
	_enter_recovery()

func _enter_recovery() -> void:
	_state = State.RECOVERY
	_timer = recovery_duration / _enemy.get_attack_speed_multiplier()

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

func interrupt() -> void:
	if _state == State.TELEGRAPH or _state == State.STRIKE:
		if _hitbox:
			_hitbox.monitoring = false
		_enter_recovery()

## Telegraph and Strike both count (used for Counter hits).
func is_attacking() -> bool:
	return _state == State.TELEGRAPH or _state == State.STRIKE

func _resolve_hit(player: Player) -> void:
	var parried: bool = player.parry_handler and player.parry_handler.attempt_parry(_enemy, player.ward)
	# A shield block, like a parry, takes no damage and triggers no retaliation.
	if not parried and player.try_block_melee_hit():
		EventBus.enemy_attack_resolved.emit(_enemy, player, false, false)
		return
	if not parried:
		var dealt := _enemy.roll_crit(damage_amount * _enemy.get_outgoing_damage_multiplier())
		player.take_damage(dealt, _enemy.convert_attack_type(damage_type), _enemy, Player.HitKind.ATTACK, true)
		if _enemy.rarity_component:
			_enemy.rarity_component.on_hit_player(player, dealt)
		# Frost Armor retaliates only against landed hits.
		if player.ability_cast:
			player.ability_cast.trigger_frost_armor_retaliation(_enemy)
	EventBus.enemy_attack_resolved.emit(_enemy, player, true, parried)
