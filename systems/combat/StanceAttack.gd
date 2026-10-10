extends Node
class_name StanceAttack
## Stance attacks (Patch v3.4 melee stance table). In stance, LMB on a
## stance with charge_time > 0 charges, and releasing fires it scaled by
## charge (releasing RMB or being stunned cancels); any other stance fires
## on the press (try_instant()). What each does is keyed by its
## stance_type; every number lives on the MeleeStanceBehavior resource.
## Also owns Dagger's Stealth state, which enemies read for detection.

signal charge_changed(progress: float, full: bool)  # progress: held time / charge_time
signal charge_ended

## Base chance a stance ailment rider (Whip Bleed, Repulse Electrocute) lands, before gear.
const STANCE_AILMENT_CHANCE := 0.5
const LUNGE_SPEED := 18.0           # m/s; sets how long a lunge of a given distance takes
const IMPACT_RING_SCENE := preload("res://entities/effects/ability_range_effect/AbilityRangeEffect.tscn")
const AFTERSHOCK_DELAY := 1.5       # Mace: doc-given
const SHOCKWAVE_SPEED := 22.0
const BLAST_KNOCKBACK := 11.0
const BLAST_LIFT := 5.0
const FULL_CHARGE_KICK := Vector3(0.012, 0.0, 0.0)
const SLASH_HEIGHT := 1.2
const HOOK_STOP_DISTANCE := 1.4      # where a hooked enemy ends up
const REPULSE_LIFT := 2.0
const FLURRY_WINDUP := 0.05
const FLURRY_STRIKE := 0.07
const FLURRY_RECOVERY := 0.05
const ENTANGLE_COLOR := Color(0.45, 0.75, 0.3, 0.7)

## Stances with a charged attack, and the viewmodel clip played on release.
const POSES := {
	MeleeStanceBehavior.MeleeStanceType.CHARGED_THRUST: PlayerArmRig.Attack.CHARGED,
	MeleeStanceBehavior.MeleeStanceType.LUNGE: PlayerArmRig.Attack.CHARGED,
	MeleeStanceBehavior.MeleeStanceType.EXECUTE: PlayerArmRig.Attack.CHARGED,
	MeleeStanceBehavior.MeleeStanceType.OVERHEAD_SLAM: PlayerArmRig.Attack.CHARGED,
	MeleeStanceBehavior.MeleeStanceType.DISCHARGE: PlayerArmRig.Attack.CHARGED,
	MeleeStanceBehavior.MeleeStanceType.PRESSURE_BLAST: PlayerArmRig.Attack.CHARGED,
	MeleeStanceBehavior.MeleeStanceType.CRACK: PlayerArmRig.Attack.CHARGED,
	MeleeStanceBehavior.MeleeStanceType.EARTHQUAKE: PlayerArmRig.Attack.CHARGED,
	MeleeStanceBehavior.MeleeStanceType.SHATTER: PlayerArmRig.Attack.CHARGED,
}

var is_charging: bool = false
var _behavior: MeleeStanceBehavior
var _held: float = 0.0
var _was_full: bool = false
var _player: Player
var _flurry_left: int = 0
var _flurry_behavior: MeleeStanceBehavior
## Stealth's bonus is spent by the first attack; re-entering stance restores it.
var _stealth_spent: bool = false
## Charged stances charge from holding RMB alone: set while RMB is held in
## one and its charge hasn't started (a swing was still finishing) or fired.
var _wants_charge: bool = false
## Letting go of RMB sooner than this cancels instead of firing, so a tap
## into stance doesn't throw a lunge.
const MIN_HOLD_TO_FIRE := 0.2

func _ready() -> void:
	_player = get_parent()

## Rapier, Greatsword, Mace and the other charged stances: holding RMB
## charges, a full charge fires by itself, and letting go early fires a
## partial charge where the stance allows one.
func is_charged_stance() -> bool:
	var behavior := _player.weapon_stance.current_behavior as MeleeStanceBehavior
	return behavior != null and behavior.charge_time > 0.0 and POSES.has(behavior.stance_type)

## Connected by Player._ready() (WeaponStance isn't resolved yet in ours).
func _on_stance_entered() -> void:
	_wants_charge = false
	if not is_charged_stance():
		return
	var behavior := _player.weapon_stance.current_behavior
	if not _player.weapon_stance.is_ready(behavior):
		_on_cooldown(behavior)
		return
	begin_charge()
	_wants_charge = not is_charging  # a swing is still finishing: start once it ends

func _on_stance_exited() -> void:
	_wants_charge = false
	if not is_charging:
		return
	if _held >= maxf(_behavior.charge_min_time, MIN_HOLD_TO_FIRE) and not _behavior.require_full_charge:
		release()
	else:
		cancel()

func _active_behavior() -> MeleeStanceBehavior:
	return _player.weapon_stance.current_behavior as MeleeStanceBehavior if _player.weapon_stance.is_active else null

## Dagger Stealth: stance held, bonus unspent, moving no faster than stealth_max_speed.
func is_stealthed() -> bool:
	var b := _active_behavior()
	if b == null or b.stance_type != MeleeStanceBehavior.MeleeStanceType.STEALTH or _stealth_spent:
		return false
	return Vector2(_player.velocity.x, _player.velocity.z).length() <= b.stealth_max_speed

func get_detection_multiplier() -> float:
	if not is_stealthed():
		return 1.0
	# "increased Stealth effect" gear shrinks detection range further.
	return _active_behavior().stealth_detection_multiplier / (1.0 + _player.stat_sheet.get_misc_bonus("stealth_effect") / 100.0)

func is_flurrying() -> bool:
	return _flurry_left > 0

## Starts charging if the active stance has a charged attack. False means
## the caller should fall back to the instant special.
func begin_charge() -> bool:
	var behavior := _player.weapon_stance.current_behavior as MeleeStanceBehavior
	if behavior == null or behavior.charge_time <= 0.0 or not POSES.has(behavior.stance_type):
		return false
	if not _player.weapon_stance.is_ready(behavior):
		_on_cooldown(behavior)
		return true
	if not _player.melee_attack.is_idle():
		return true  # swallow the press; a swing is still finishing
	_behavior = behavior
	_held = 0.0
	_was_full = false
	is_charging = true
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
	_hide_preview()
	_behavior = null
	charge_ended.emit()

func _physics_process(delta: float) -> void:
	if not _player.weapon_stance.is_active:
		_stealth_spent = false
	if _flurry_left > 0:
		_continue_flurry()
	if _wants_charge and not is_charging and _player.weapon_stance.is_active and _player.melee_attack.is_idle():
		_wants_charge = false
		begin_charge()
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
	_update_preview()
	if full:
		release()

var _preview: StancePreview

## While charging, outlines on the ground where the attack will land at the
## current charge (the reach grows with it).
func _update_preview() -> void:
	if not is_charging or _behavior == null:
		_hide_preview()
		return
	var shapes := preview_shapes(_behavior, get_charge_fraction())
	if shapes.is_empty():
		_hide_preview()
		return
	if _preview == null or not is_instance_valid(_preview):
		_preview = StancePreview.new()
		_player.add_child(_preview)
	_preview.visible = true
	_preview.draw(shapes)

func _hide_preview() -> void:
	if _preview and is_instance_valid(_preview):
		_preview.visible = false

## StancePreview shapes for a stance released at charge fraction f.
func preview_shapes(behavior: MeleeStanceBehavior, f: float) -> Dictionary:
	var reach := lerpf(behavior.reach_min, behavior.reach_max, f)
	var origin := _player.global_position
	var forward := _forward()
	match behavior.stance_type:
		MeleeStanceBehavior.MeleeStanceType.CHARGED_THRUST, MeleeStanceBehavior.MeleeStanceType.LUNGE:
			# The path and the spot you'll end up.
			return {"strip": [origin, forward, reach, 0.5], "circle": [origin + forward * reach, 0.7]}
		MeleeStanceBehavior.MeleeStanceType.EXECUTE, MeleeStanceBehavior.MeleeStanceType.OVERHEAD_SLAM, MeleeStanceBehavior.MeleeStanceType.EARTHQUAKE:
			return {"circle": [origin + forward * reach, behavior.radius]}
		MeleeStanceBehavior.MeleeStanceType.DISCHARGE:
			return {"strip": [origin + forward * 0.8, forward, reach, behavior.radius * 2.0]}
		MeleeStanceBehavior.MeleeStanceType.PRESSURE_BLAST, MeleeStanceBehavior.MeleeStanceType.CRACK, MeleeStanceBehavior.MeleeStanceType.SHATTER:
			return {"cone": [origin, forward, reach, behavior.half_angle]}
	return {}

func release() -> void:
	if not is_charging:
		return
	var behavior := _behavior
	var full := is_full()
	var f := get_charge_fraction()
	is_charging = false
	_hide_preview()
	_behavior = null
	charge_ended.emit()
	if behavior.require_full_charge and not full:
		return
	_player.weapon_stance.start_cooldown(behavior)
	var params := {
		"kind": POSES[behavior.stance_type],
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
		MeleeStanceBehavior.MeleeStanceType.EARTHQUAKE:
			params["no_step"] = true
			params["on_contact"] = _earthquake.bind(behavior, reach, params["motion_mult"])
		MeleeStanceBehavior.MeleeStanceType.SHATTER:
			params["no_step"] = true
			params["shape"] = {"reach": reach, "half_angle": behavior.half_angle, "splash": 1.0, "max_targets": 8}
			params["on_hit"] = _on_shatter_hit.bind(behavior)
	_player.melee_attack.release_stance_attack(params)

## Feedback for pressing a special that isn't ready - same channel spells use.
func _on_cooldown(behavior: StanceBehavior) -> void:
	EventBus.stance_on_cooldown.emit(_player, _player.weapon_stance.get_cooldown_remaining(behavior))

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
		var damage_type := weapon.get_damage_type()
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
		enemy.status_effects.try_apply("bleed", _player, damage, STANCE_AILMENT_CHANCE)
	enemy.interrupt_attack()

## Stances that fire on the LMB press. False: no instant attack here, so
## the caller falls back to the generic special.
func try_instant() -> bool:
	var b := _active_behavior()
	if b == null or b.charge_time > 0.0:
		return false
	if not _player.melee_attack.is_idle() or _flurry_left > 0:
		return true  # swallow the press; a swing is still finishing
	if not _player.weapon_stance.is_ready(b):
		_on_cooldown(b)
		return true
	_player.weapon_stance.start_cooldown(b)
	var params := {"motion_mult": b.motion_value_min}
	match b.stance_type:
		MeleeStanceBehavior.MeleeStanceType.WATER_SLICES:
			params["kind"] = PlayerArmRig.Attack.HEAVY
			params["no_step"] = true
			params["on_contact"] = _water_slice.bind(b)
		MeleeStanceBehavior.MeleeStanceType.SWEEP:
			params["kind"] = PlayerArmRig.Attack.CHARGED
			params["shape"] = {"reach": b.reach_min, "half_angle": b.half_angle, "splash": 1.0, "max_targets": 8}
			params["on_hit"] = _push_away.bind(b.knockback)
		MeleeStanceBehavior.MeleeStanceType.ARMOR_PIERCE:
			params["kind"] = PlayerArmRig.Attack.HEAVY
			params["ignore_armor"] = true
			params["on_hit"] = _shred.bind(b.armor_shred_stacks)
		MeleeStanceBehavior.MeleeStanceType.HOOKING_STRIKE:
			params["kind"] = PlayerArmRig.Attack.LIGHT
			params["shape"] = {"reach": b.reach_min, "half_angle": b.half_angle, "splash": 0.0, "max_targets": 1}
			params["no_push"] = true
			params["no_step"] = true
			params["on_hit"] = _hook
		MeleeStanceBehavior.MeleeStanceType.ENTANGLE:
			params["kind"] = PlayerArmRig.Attack.HEAVY
			params["on_contact"] = _entangle.bind(b)
		MeleeStanceBehavior.MeleeStanceType.REPULSE:
			params["kind"] = PlayerArmRig.Attack.LIGHT
			params["no_step"] = true
			params["on_contact"] = _repulse.bind(b)
		MeleeStanceBehavior.MeleeStanceType.SLICE_AND_DICE:
			_flurry_behavior = b
			_flurry_left = maxi(b.hits, 1)
			_continue_flurry()
			return true
		MeleeStanceBehavior.MeleeStanceType.STEALTH:
			params["kind"] = PlayerArmRig.Attack.CHARGED
			params["shape"] = {"reach": b.reach_min, "half_angle": b.half_angle, "splash": 0.0, "max_targets": 1}
			if is_stealthed():
				params["motion_mult"] = b.motion_value_min * b.stealth_damage_multiplier
			_stealth_spent = true
		_:
			return false
	_player.melee_attack.release_stance_attack(params)
	return true

## Slice and Dice: one quick hit per call while the flurry lasts; the last
## hit of a completed flurry gets finisher_multiplier. Leaving stance or
## being stunned ends it early, finisher lost.
func _continue_flurry() -> void:
	if not _player.weapon_stance.is_active or _player.status_effects.is_stunned():
		_flurry_left = 0
		return
	if not _player.melee_attack.is_idle():
		return
	var b := _flurry_behavior
	var last := _flurry_left == 1
	var params := {
		"kind": PlayerArmRig.Attack.CHARGED if last else PlayerArmRig.Attack.LIGHT,
		"motion_mult": b.motion_value_min * (b.finisher_multiplier if last else 1.0),
		"windup": FLURRY_WINDUP * (2.0 if last else 1.0),
		"strike": FLURRY_STRIKE,
		"recovery": FLURRY_RECOVERY * (4.0 if last else 1.0),
		"no_step": not last,
	}
	_flurry_left -= 1
	_player.melee_attack.release_stance_attack(params)

## Cutlass Water Slices: the swing throws a slash that pierces a few enemies.
func _water_slice(b: MeleeStanceBehavior) -> void:
	var weapon := _player.get_active_weapon()
	var melee := _player.melee_attack
	var motion: float = melee._effective_motion_value(weapon) * melee._attack_type_motion_multiplier()
	var slash := StanceSlash.new()
	get_tree().current_scene.add_child(slash)
	var forward := -_player.camera.global_transform.basis.z
	slash.global_position = _player.global_position + Vector3.UP * SLASH_HEIGHT + forward * 0.6
	slash.launch(forward, b.reach_min, b.radius, b.projectile_speed, b.projectile_pierce, _on_slash_hit.bind(weapon, motion, b.gain_as_cold))

func _on_slash_hit(enemy: Enemy, weapon: Weapon, motion: float, cold_share: float) -> void:
	if not is_instance_valid(_player):
		return
	var damage_type := weapon.get_damage_type()
	var damage: float = weapon.roll_damage(motion, _player.stat_sheet)["final_damage"]
	if _hit(enemy, damage, damage_type) and cold_share > 0.0:
		_hit(enemy, damage * cold_share, Constants.DamageType.COLD)

## Halberd Sweep: extra shove on top of the normal hit reaction.
func _push_away(enemy: Enemy, _damage: float, force: float) -> void:
	var push := enemy.global_position - _player.global_position
	push.y = 0.0
	if push.length() > 0.01:
		enemy.apply_knockback(push.normalized() * force)

func _shred(enemy: Enemy, _damage: float, stacks: int) -> void:
	if enemy.status_effects:
		for i in stacks:
			enemy.status_effects.apply_effect("armor_shred", _player)

## War Pick Hooking Strike: drags the target to just in front of you.
func _hook(enemy: Enemy, _damage: float) -> void:
	var pull := _player.global_position - enemy.global_position
	pull.y = 0.0
	var distance := pull.length() - HOOK_STOP_DISTANCE
	if distance > 0.0:
		enemy.apply_knockback(pull.normalized() * sqrt(2.0 * Enemy.KNOCKBACK_FRICTION * distance))
	enemy.interrupt_attack()

## Whip Entangle: roots the first enemy in line. No damage.
func _entangle(b: MeleeStanceBehavior) -> void:
	var target := _first_in_line(b.reach_min, b.half_angle)
	if target == null or target.status_effects == null:
		return
	target.status_effects.apply_timed_effect("entangle", b.status_duration)
	target.flash_hit()
	var ring := _vine_ring()
	target.add_child(ring)
	get_tree().create_timer(b.status_duration, false).timeout.connect(ring.queue_free)

## Shock Lance Repulse: shoves everything nearby away and Electrocutes it.
func _repulse(b: MeleeStanceBehavior) -> void:
	_ring(_player.global_position, b.radius, Color(0.6, 0.8, 1.0))
	_kick(Vector3(-0.02, 0.0, 0.02))
	for enemy in _player.melee_attack.enemies_in_radius(_player.global_position, b.radius):
		var push := enemy.global_position - _player.global_position
		push.y = 0.0
		var direction := push.normalized() if push.length() > 0.01 else _forward()
		enemy.apply_knockback(direction * b.knockback + Vector3.UP * REPULSE_LIFT)
		if enemy.status_effects:
			enemy.status_effects.try_apply("electrocute", _player, 0.0, STANCE_AILMENT_CHANCE)
		enemy.flash_hit()

func _first_in_line(reach: float, half_angle: float) -> Enemy:
	var origin := _player.camera.global_position
	var forward := _forward()
	var best: Enemy = null
	var best_distance := INF
	for node in get_tree().get_nodes_in_group("enemy"):
		var enemy := node as Enemy
		if enemy == null or not enemy.health.is_alive():
			continue
		var to_enemy := enemy.global_position - _player.global_position
		to_enemy.y = 0.0
		var distance := to_enemy.length()
		if distance - 0.5 > reach or distance >= best_distance:
			continue
		if distance > 0.5 and rad_to_deg(forward.angle_to(to_enemy / distance)) > half_angle + rad_to_deg(atan2(0.5, distance)):
			continue
		if not _player.melee_attack._has_line_of_sight(origin, enemy.global_position + Vector3.UP, enemy):
			continue
		best = enemy
		best_distance = distance
	return best

func _vine_ring() -> MeshInstance3D:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.45
	torus.outer_radius = 0.6
	ring.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = ENTANGLE_COLOR
	ring.material_override = mat
	ring.position = Vector3(0.0, 0.3, 0.0)
	ring.scale = Vector3(1.0, 2.5, 1.0)
	return ring

## A hit outside the swing (aftershock, shockwave): no crit, no riposte.
func _hit(enemy: Enemy, damage: float, damage_type: Constants.DamageType) -> bool:
	if not is_instance_valid(enemy) or not enemy.health.is_alive():
		return false
	if not enemy.take_damage(damage, damage_type, false, true):
		return false
	if enemy.stance:
		enemy.stance.apply_attack_stance_damage(damage, damage_type)
	enemy.flash_hit()
	EventBus.damage_dealt.emit(_player, enemy, damage, damage_type, false, false)
	EventBus.hit_landed.emit(false, false, not enemy.health.is_alive())
	return true

func _ring(center: Vector3, radius: float, color: Color) -> void:
	var ring := IMPACT_RING_SCENE.instantiate()
	get_tree().current_scene.add_child(ring)
	ring.global_position = center + Vector3.UP * 0.05
	ring.play(radius, color)

func _kick(amount: Vector3) -> void:
	var sway: CameraSway = _player.camera.get_node_or_null("CameraSway")
	if sway:
		sway.kick(amount)

## Greataxe Earthquake: the slam, plus a field twice its radius that ruptures
## for 60% of the slam when you leave it or Warcry (EarthquakeField).
const EARTHQUAKE_FIELD_SCALE := 2.0

func _earthquake(behavior: MeleeStanceBehavior, reach: float, motion_mult: float) -> void:
	var center := _player.global_position + _forward() * reach
	_slam(behavior, reach, false)
	var weapon := _player.get_active_weapon()
	var melee := _player.melee_attack
	var motion: float = melee._effective_motion_value(weapon) * motion_mult
	var damage: float = weapon.roll_damage(motion, _player.stat_sheet)["final_damage"]
	var damage_type := weapon.get_damage_type()
	EarthquakeField.spawn(get_tree().current_scene, Vector3(center.x, _player.global_position.y, center.z), behavior.radius * EARTHQUAKE_FIELD_SCALE, damage, damage_type, _player)

## Greataxe Shatter: shreds Armour; a kill bursts into shards around the body.
const SHATTER_BURST_SHARE := 0.4
const SHATTER_BURST_RADIUS := 3.0

func _on_shatter_hit(enemy: Enemy, damage: float, behavior: MeleeStanceBehavior) -> void:
	_shred(enemy, damage, behavior.armor_shred_stacks)
	if enemy.health.is_alive():
		return
	_ring(enemy.global_position, SHATTER_BURST_RADIUS, Color(0.75, 0.85, 1.0))
	var weapon := _player.get_active_weapon()
	var damage_type := weapon.get_damage_type()
	for other in _player.melee_attack.enemies_in_radius(enemy.global_position, SHATTER_BURST_RADIUS):
		if other != enemy:
			_hit(other, damage * SHATTER_BURST_SHARE, damage_type)
