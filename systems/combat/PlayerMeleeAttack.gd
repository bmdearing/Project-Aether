extends Node
class_name PlayerMeleeAttack
## Player-driven melee attack: Idle -> Windup -> Strike -> Recovery.
## Hit detection is a real Area3D (Player.attack_hitbox, sweeps with the
## blade mesh) - body_entered against the "enemy" group. Swing/camera
## shake are procedural Tweens, not baked animation.

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

## Called from Player._physics_process on the "attack" action. Player's
## @onready vars (weapon_socket/camera/etc.) aren't touched until an
## actual attack, well after children ready before their parent.
func try_attack() -> void:
	if _state != State.IDLE:
		return
	if _player.get_active_weapon() == null:
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

## Section 12: Instinct -> "+1% Attack/Cast speed per point" divides the
## base duration rather than mutating windup_duration/etc. directly.
func _effective_duration(base: float) -> float:
	return base / _player.get_action_speed_multiplier()

func _enter_windup() -> void:
	_state = State.WINDUP
	_timer = _effective_duration(windup_duration)
	_play_swing()

func _enter_strike() -> void:
	_state = State.STRIKE
	_timer = _effective_duration(strike_duration)
	_resolved_this_swing = false
	if _hitbox:
		_hitbox.monitoring = true

func _end_strike() -> void:
	if _hitbox:
		_hitbox.monitoring = false
	_enter_recovery()

func _enter_recovery() -> void:
	_state = State.RECOVERY
	_timer = _effective_duration(recovery_duration)

## Rest rotation is assumed Vector3.ZERO (WeaponSocket's default). The
## out-swing spans the full windup so the blade arrives at full extension
## exactly as Strike begins and monitoring turns on.
func _play_swing() -> void:
	var socket := _player.weapon_socket
	if socket == null:
		return
	var rest_rotation := Vector3.ZERO
	var swing_rotation := Vector3(deg_to_rad(-40.0), deg_to_rad(20.0), deg_to_rad(-10.0))
	var tween := create_tween()
	tween.tween_property(socket, "rotation", swing_rotation, _effective_duration(windup_duration)) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(socket, "rotation", rest_rotation, _effective_duration(strike_duration + recovery_duration)) \
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
	var weapon: Weapon = _player.get_active_weapon()
	var damage_type: Constants.DamageType = weapon.infused_damage_type if weapon.infused_damage_type != -1 else weapon.native_damage_type
	var hit := weapon.roll_damage(base_motion_value, _player.stat_sheet)
	var final_damage: float = hit["final_damage"]
	var is_critical: bool = hit["is_critical"]

	target.take_damage(final_damage, damage_type)
	if target.stance:
		target.stance.apply_attack_stance_damage(final_damage, damage_type)
	EventBus.damage_dealt.emit(_player, target, final_damage, damage_type, false, is_critical)

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
