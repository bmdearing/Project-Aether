extends Node
class_name StanceAttack
## Charge-and-release stance attacks (Patch v3.4 melee stance table). In
## stance, holding LMB charges the active page's MeleeStanceBehavior (its
## charge_time > 0); releasing fires it, scaled by charge. Releasing RMB or
## being stunned cancels. What each stance does on release is keyed by its
## stance_type; every number lives on the behavior resource.

signal charge_changed(progress: float, full: bool)  # progress: held time / charge_time
signal charge_ended

const LUNGE_SPEED := 18.0           # m/s; sets how long a lunge of a given distance takes
const IMPACT_RING_SCENE := preload("res://entities/effects/ability_range_effect/AbilityRangeEffect.tscn")
const AFTERSHOCK_DELAY := 1.5       # Mace: doc-given
const SHOCKWAVE_SPEED := 22.0
const BLAST_KNOCKBACK := 11.0
const BLAST_LIFT := 5.0
const FULL_CHARGE_KICK := Vector3(0.012, 0.0, 0.0)

## Arm pose held while charging and swung on release.
const POSES := {
	MeleeStanceBehavior.MeleeStanceType.CHARGED_THRUST: PlayerArmRig.PoseSet.DASH_THRUST,
	MeleeStanceBehavior.MeleeStanceType.LUNGE: PlayerArmRig.PoseSet.DASH_THRUST,
	MeleeStanceBehavior.MeleeStanceType.EXECUTE: PlayerArmRig.PoseSet.CLEAVE,
	MeleeStanceBehavior.MeleeStanceType.OVERHEAD_SLAM: PlayerArmRig.PoseSet.CLEAVE,
	MeleeStanceBehavior.MeleeStanceType.DISCHARGE: PlayerArmRig.PoseSet.CLEAVE,
	MeleeStanceBehavior.MeleeStanceType.PRESSURE_BLAST: PlayerArmRig.PoseSet.JAB,
	MeleeStanceBehavior.MeleeStanceType.CRACK: PlayerArmRig.PoseSet.CLEAVE,
}

var is_charging: bool = false
var _behavior: MeleeStanceBehavior
var _held: float = 0.0
var _was_full: bool = false
var _player: Player

func _ready() -> void:
	_player = get_parent()

## Starts charging if the active stance has a charged attack. False means
## the caller should fall back to the instant special.
func begin_charge() -> bool:
	var behavior := _player.weapon_stance.current_behavior as MeleeStanceBehavior
	if behavior == null or behavior.charge_time <= 0.0 or not POSES.has(behavior.stance_type):
		return false
	if not _player.melee_attack.is_idle():
		return true  # swallow the press; a swing is still finishing
	_behavior = behavior
	_held = 0.0
	_was_full = false
	is_charging = true
	if _player.arm_rig:
		_player.arm_rig.enter_ready_pose(POSES[behavior.stance_type], behavior.charge_time, _player.melee_attack.get_special_intensity() * 1.2)
	charge_changed.emit(0.0, false)
	return true

func get_charge_fraction() -> float:
	if _behavior == null:
		return 0.0
	var span := maxf(_behavior.charge_time - _behavior.charge_min_time, 0.01)
	return clampf((_held - _behavior.charge_min_time) / span, 0.0, 1.0)

func is_full() -> bool:
	return is_charging and _held >= _behavior.charge_time

func requires_full_charge() -> bool:
	return _behavior != null and _behavior.require_full_charge

func get_move_speed_multiplier() -> float:
	return _behavior.charge_move_multiplier if is_charging else 1.0

func cancel() -> void:
	if not is_charging:
		return
	is_charging = false
	_behavior = null
	if _player.arm_rig and _player.melee_attack.is_idle():
		_player.arm_rig.exit_ready_pose(0.2)
	charge_ended.emit()

func _physics_process(delta: float) -> void:
	if not is_charging:
		return
	if not _player.weapon_stance.is_active or _player.status_effects.is_stunned() or _player.shield_block.is_raised:
		cancel()
		return
	_held += delta
	var full := is_full()
	if full and not _was_full:
		_kick(FULL_CHARGE_KICK)
	_was_full = full
	charge_changed.emit(clampf(_held / _behavior.charge_time, 0.0, 1.0), full)

func release() -> void:
	if not is_charging:
		return
	var behavior := _behavior
	var full := is_full()
	var f := get_charge_fraction()
	is_charging = false
	_behavior = null
	charge_ended.emit()
	if behavior.require_full_charge and not full:
		if _player.arm_rig:
			_player.arm_rig.exit_ready_pose(0.25)
		return
	var params := {
		"pose": POSES[behavior.stance_type],
		"intensity": _player.melee_attack.get_special_intensity() * (1.0 + 0.3 * f),
		"windup": 0.08,
		"motion_mult": lerpf(behavior.motion_value_min, behavior.motion_value_max, f),
		"recovery_mult": lerpf(1.0, behavior.recovery_multiplier_max, f),
	}
	var reach := lerpf(behavior.reach_min, behavior.reach_max, f)
	match behavior.stance_type:
		MeleeStanceBehavior.MeleeStanceType.CHARGED_THRUST, MeleeStanceBehavior.MeleeStanceType.LUNGE:
			_release_lunge(params, reach)
		MeleeStanceBehavior.MeleeStanceType.EXECUTE, MeleeStanceBehavior.MeleeStanceType.OVERHEAD_SLAM:
			params["no_step"] = true
			params["on_contact"] = _slam.bind(behavior, reach, behavior.stance_type == MeleeStanceBehavior.MeleeStanceType.OVERHEAD_SLAM)
		MeleeStanceBehavior.MeleeStanceType.DISCHARGE:
			params["no_step"] = true
			params["on_contact"] = _discharge.bind(behavior, reach)
		MeleeStanceBehavior.MeleeStanceType.PRESSURE_BLAST:
			params["on_contact"] = _blast.bind(behavior, reach)
			params["on_hit"] = _on_blast_hit.bind(behavior)
		MeleeStanceBehavior.MeleeStanceType.CRACK:
			params["shape"] = {"reach": reach, "half_angle": behavior.half_angle, "splash": 0.0, "max_targets": 1}
			params["on_hit"] = _on_crack_hit
	_player.melee_attack.release_stance_attack(params)

func _forward() -> Vector3:
	var forward := -_player.camera.global_transform.basis.z
	forward.y = 0.0
	return forward.normalized() if forward.length() > 0.01 else -_player.global_transform.basis.z

## Rapier Charged Thrust / Spear Lunge: travel `distance`, thrust at the end.
func _release_lunge(params: Dictionary, distance: float) -> void:
	var duration := distance / LUNGE_SPEED
	params["windup"] = maxf(duration * 0.75, 0.08)
	params["no_step"] = true
	_player.lunge(_forward(), distance, duration)

## Greatsword Execute / Mace Overhead Slam: area hit `reach` m ahead.
func _slam(behavior: MeleeStanceBehavior, reach: float, aftershock: bool) -> void:
	var center := _player.global_position + _forward() * reach
	_ring(center, behavior.radius, Color(1.0, 0.85, 0.6))
	_kick(Vector3(-0.05, 0.0, 0.0))
	var melee := _player.melee_attack
	melee.hit_targets(melee.enemies_in_radius(center, behavior.radius))
	if aftershock:
		var weapon := _player.get_active_weapon()
		var motion: float = melee._effective_motion_value(weapon) * melee._attack_type_motion_multiplier()
		var damage: float = weapon.roll_damage(motion, _player.stat_sheet)["final_damage"]
		var damage_type: Constants.DamageType = weapon.infused_damage_type if weapon.infused_damage_type != -1 else weapon.native_damage_type
		get_tree().create_timer(AFTERSHOCK_DELAY, false).timeout.connect(_aftershock.bind(center, behavior.radius, damage, damage_type))

func _aftershock(center: Vector3, radius: float, damage: float, damage_type: Constants.DamageType) -> void:
	if not is_instance_valid(_player):
		return
	_ring(center, radius, Color(1.0, 0.6, 0.3))
	for enemy in _player.melee_attack.enemies_in_radius(center, radius):
		_hit(enemy, damage, damage_type)

## Shock Lance Discharge: a Lightning wave running along the ground.
func _discharge(behavior: MeleeStanceBehavior, length: float) -> void:
	var weapon := _player.get_active_weapon()
	var melee := _player.melee_attack
	var motion: float = melee._effective_motion_value(weapon) * melee._attack_type_motion_multiplier()
	var wave := StanceShockwave.new()
	get_tree().current_scene.add_child(wave)
	wave.global_position = _player.global_position + _forward() * 0.8
	wave.launch(_forward(), length, behavior.radius, SHOCKWAVE_SPEED, _on_wave_hit.bind(weapon, motion))
	_kick(Vector3(-0.03, 0.0, 0.0))

func _on_wave_hit(enemy: Enemy, weapon: Weapon, motion: float) -> void:
	if not is_instance_valid(_player):
		return
	_hit(enemy, weapon.roll_damage(motion, _player.stat_sheet)["final_damage"], Constants.DamageType.LIGHTNING)

## Pressure Fist Pressure Blast: point-blank cone, heavy stagger, launch.
func _blast(behavior: MeleeStanceBehavior, reach: float) -> void:
	var forward := _forward()
	var targets: Array[Enemy] = []
	for enemy in _player.melee_attack.enemies_in_radius(_player.global_position, reach):
		var to_enemy := enemy.global_position - _player.global_position
		to_enemy.y = 0.0
		if to_enemy.length() < 0.3 or rad_to_deg(forward.angle_to(to_enemy.normalized())) <= behavior.half_angle:
			targets.append(enemy)
	_player.melee_attack.hit_targets(targets)
	_kick(Vector3(-0.04, 0.0, 0.03))

func _on_blast_hit(enemy: Enemy, damage: float, behavior: MeleeStanceBehavior) -> void:
	if enemy.stance:
		enemy.stance.apply_attack_stance_damage(damage * (behavior.stance_damage_multiplier - 1.0), Constants.DamageType.EXPLOSIVE)
	var push := enemy.global_position - _player.global_position
	push.y = 0.0
	if push.length() > 0.01:
		enemy.apply_knockback(push.normalized() * BLAST_KNOCKBACK + Vector3.UP * BLAST_LIFT)

## Whip Crack: Bleed and an interrupt on whatever it reaches.
func _on_crack_hit(enemy: Enemy, damage: float) -> void:
	if enemy.status_effects:
		enemy.status_effects.apply_effect("bleed", _player, damage)
	enemy.interrupt_attack()

## A hit outside the swing (aftershock, shockwave): no crit, no riposte.
func _hit(enemy: Enemy, damage: float, damage_type: Constants.DamageType) -> void:
	if not is_instance_valid(enemy) or not enemy.health.is_alive():
		return
	if not enemy.take_damage(damage, damage_type, false, true):
		return
	if enemy.stance:
		enemy.stance.apply_attack_stance_damage(damage, damage_type)
	enemy.flash_hit()
	EventBus.damage_dealt.emit(_player, enemy, damage, damage_type, false, false)
	EventBus.hit_landed.emit(false, false, not enemy.health.is_alive())

func _ring(center: Vector3, radius: float, color: Color) -> void:
	var ring := IMPACT_RING_SCENE.instantiate()
	get_tree().current_scene.add_child(ring)
	ring.global_position = center + Vector3.UP * 0.05
	ring.play(radius, color)

func _kick(amount: Vector3) -> void:
	var sway: CameraSway = _player.camera.get_node_or_null("CameraSway")
	if sway:
		sway.kick(amount)
