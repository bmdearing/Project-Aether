extends Node
class_name PlayerMeleeAttack
## Player-driven melee attack: Idle -> Windup -> Strike -> Recovery, the
## input-triggered counterpart to EnemyMeleeAttack.gd's state shape. First
## thing that actually calls DamageCalculator with a real equipped Weapon +
## StatSheet, and the first thing to exercise
## StanceComponent.apply_attack_stance_damage(), which existed unused since
## it was written.
##
## Hit detection is a real Area3D (Player.attack_hitbox, child of the blade
## mesh so it sweeps through the swing arc with it) - body_entered against
## the "enemy" group, filtered by an Enemy cast rather than new collision
## layers (nothing else in the project uses custom layers yet, everything
## defaults to layer 1, so a type check is the minimal-diff way to ignore
## the floor/self). Swing/camera shake are procedural Tweens, not baked
## AnimationPlayer keyframes - easier to author correctly without the
## visual editor, same player-facing result.

enum State { IDLE, WINDUP, STRIKE, RECOVERY }

@export var windup_duration: float = 0.2
@export var strike_duration: float = 0.15
@export var recovery_duration: float = 0.3
## Stands in for a "Basic Attack" skill's motion value - no skill/Tome
## system exists yet to grant one (Section 11: motion values live on
## individual skills, never a bare weapon).
@export var base_motion_value: float = 1.0

@export var hitstop_time_scale: float = 0.05
@export var hitstop_duration: float = 0.06
@export var shake_strength: float = 0.05
@export var shake_duration: float = 0.15

var _state: State = State.IDLE
var _timer: float = 0.0
var _player: Player
var _hitbox: Area3D
var _resolved_this_swing: bool = false

func _ready() -> void:
	_player = get_parent()

## Called from Player._physics_process on the "attack" action. Deferred
## member access (weapon_socket/camera/equipment/attack_hitbox) is
## intentional - Player's own @onready vars aren't guaranteed set yet
## during THIS node's _ready() (children ready before their parent), so
## nothing above touches them until an actual attack is attempted, well
## after the tree has settled.
func try_attack() -> void:
	if _state != State.IDLE:
		return
	if _player.equipment == null or _player.equipment.primary_weapon == null:
		return
	if _hitbox == null:
		_hitbox = _player.attack_hitbox
		if _hitbox:
			_hitbox.monitoring = false
			_hitbox.body_entered.connect(_on_hitbox_body_entered)
	_enter_windup()

func _physics_process(delta: float) -> void:
	match _state:
		State.WINDUP:
			_timer -= delta
			if _timer <= 0.0:
				_enter_strike()
		State.STRIKE:
			_timer -= delta
			if _timer <= 0.0:
				_end_strike()
		State.RECOVERY:
			_timer -= delta
			if _timer <= 0.0:
				_state = State.IDLE

func _enter_windup() -> void:
	_state = State.WINDUP
	_timer = windup_duration
	_play_swing()

func _enter_strike() -> void:
	_state = State.STRIKE
	_timer = strike_duration
	_resolved_this_swing = false
	if _hitbox:
		_hitbox.monitoring = true

func _end_strike() -> void:
	if _hitbox:
		_hitbox.monitoring = false
	_enter_recovery()

func _enter_recovery() -> void:
	_state = State.RECOVERY
	_timer = recovery_duration

## Rest local rotation is assumed Vector3.ZERO (Player.tscn's WeaponSocket
## default) - swings out and back relative to that, not a cached value, so
## this doesn't depend on read order either. The out-swing spans the full
## windup so the blade (and its hitbox) arrives at full extension exactly
## as Strike begins and monitoring turns on, instead of already retracting.
func _play_swing() -> void:
	var socket := _player.weapon_socket
	if socket == null:
		return
	var rest_rotation := Vector3.ZERO
	var swing_rotation := Vector3(deg_to_rad(-40.0), deg_to_rad(20.0), deg_to_rad(-10.0))
	var tween := create_tween()
	tween.tween_property(socket, "rotation", swing_rotation, windup_duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(socket, "rotation", rest_rotation, strike_duration + recovery_duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

func _on_hitbox_body_entered(body: Node3D) -> void:
	if _state != State.STRIKE or _resolved_this_swing:
		return
	var enemy := body as Enemy
	if enemy == null:
		return
	_resolved_this_swing = true
	if _hitbox:
		_hitbox.monitoring = false
	_deal_damage(enemy)

func _deal_damage(target: Enemy) -> void:
	var weapon: Weapon = _player.equipment.primary_weapon
	var damage_type: Constants.DamageType = weapon.infused_damage_type if weapon.infused_damage_type != -1 else weapon.native_damage_type
	var main_stat: Constants.Stat = Constants.DAMAGE_TYPE_MAIN_STAT.get(damage_type, Constants.Stat.STRENGTH)
	var stat_value: float = _player.stat_sheet.get_stat(main_stat) if _player.stat_sheet else 0.0
	var mastery: float = _player.stat_sheet.get_mastery(damage_type) if _player.stat_sheet else 0.0

	# No Slate/gear stat aggregation into StatSheet yet (EquipmentComponent's
	# own header comment flags the same gap) - both pools stay empty for now.
	var result: DamageCalculator.DamageResult = DamageCalculator.calculate(
		weapon.base_damage, base_motion_value, stat_value, weapon.scaling_grade,
		0.5, mastery, [], [], damage_type
	)

	target.take_damage(result.final_damage, damage_type)
	if target.stance:
		target.stance.apply_attack_stance_damage(result.final_damage, damage_type)
	EventBus.damage_dealt.emit(_player, target, result.final_damage, damage_type, false)

	_trigger_hit_feedback()

func _trigger_hit_feedback() -> void:
	Engine.time_scale = hitstop_time_scale
	get_tree().create_timer(hitstop_duration, true, false, true).timeout.connect(_end_hitstop)

	var camera := _player.camera
	if camera == null:
		return
	var base_pos: Vector3 = camera.position
	var offset := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), 0.0) * shake_strength
	var tween := create_tween()
	tween.tween_property(camera, "position", base_pos + offset, shake_duration * 0.3).set_trans(Tween.TRANS_SINE)
	tween.tween_property(camera, "position", base_pos, shake_duration * 0.7).set_trans(Tween.TRANS_SINE)

func _end_hitstop() -> void:
	Engine.time_scale = 1.0
