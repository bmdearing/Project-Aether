extends Node
class_name PlayerRangedAttack
## Ranged attack: spawns Projectile.tscn instances moving forward from
## WeaponSocket. No windup/strike states like PlayerMeleeAttack - hit
## registration is still a single instant fire-and-cooldown.
## _play_fire_animation() layers a purely cosmetic recoil clip on
## PlayerArmRig on top of that, via the same play_attack()
## PlayerMeleeAttack itself uses - it doesn't gate or delay the shot.
##
## Implementation Brief v4.2 adds magazines/reloading/fire modes/spread on
## top of that. Rules: the MAGAZINE gates firing (never the reserve - a
## loaded magazine fires until empty); reloading is what pulls from
## AmmoInventory. Arrows (Constants.AmmoType.ARROW) are infinite and bows
## have no magazine. The loaded count lives on the Weapon itself
## (Weapon.current_magazine), so swapping weapon sets neither refills nor
## loses it, and swapping never auto-reloads - it only cancels a reload in
## progress.

const PROJECTILE_SCENE := preload("res://entities/projectile/Projectile.tscn")

## Cosmetic fire reaction on the viewmodel; bows get a slower release.
const FIRE_WINDUP := 0.06
const FIRE_STRIKE := 0.06
const FIRE_RECOVERY := 0.16
const BOW_FIRE_DURATION_MULT := 1.6

@export var fire_cooldown: float = 0.5
## Stands in for a "Basic Shot" skill's motion value - no skill/Tome
## system exists yet (Section 11: motion values live on skills).
@export var base_motion_value: float = 1.0
@export var projectile_speed: float = 25.0

## Right-click-hold aim (WeaponStance) rewards firing with a flat damage
## bonus and halves the weapon's spread; the weapon's RangedStanceBehavior
## (Patch v3.4 table) adds its own mechanic on top - see _stance().
const AIMED_DAMAGE_MULTIPLIER := 1.4
const AIMED_SPREAD_MULTIPLIER := 0.5
const DRY_CLICK_COOLDOWN := 0.3

var _cooldown_remaining: float = 0.0
var _full_auto_timer: float = 0.0
var _cycle_timer: float = 0.0
var _is_cycling: bool = false
var _is_reloading: bool = false
var _reload_timer: float = 0.0
var _reload_weapon: Weapon
var _player: Player

## Aim stance state (RangedStanceBehavior, see _stance()).
const RAIN_TARGET_RANGE := 40.0
const STAGGER_COMPOSURE_DAMAGE := 20.0
var _dump_remaining: int = 0
var _dump_timer: float = 0.0
var _aim_time: float = 0.0
var _brace_spent: bool = false
var _stagger_log: Dictionary = {}   # enemy instance id -> Array of hit msec
var _mark_bonus: float = 0.0

## The aim stance in effect, or null when not aiming / none designed.
func _stance() -> RangedStanceBehavior:
	if not _player.weapon_stance.is_active:
		return null
	return _player.weapon_stance.current_behavior as RangedStanceBehavior

## Marksman: how much the current aim has built up (1.0 = none).
func get_aim_multiplier() -> float:
	var st := _stance()
	if st == null or st.aim_ramp_time <= 0.0:
		return 1.0
	return lerpf(1.0, st.aim_ramp_max_multiplier, clampf(_aim_time / st.aim_ramp_time, 0.0, 1.0))

func _ready() -> void:
	_player = get_parent()
	EventBus.weapon_swapped.connect(_on_weapon_swapped)

## Bows (ARROW) and any weapon with magazine_size 0 have no magazine.
func _uses_magazine(weapon: Weapon) -> bool:
	return weapon.ammo_type != Constants.AmmoType.ARROW and weapon.magazine_size > 0

## Rounds loaded in the active weapon, for the HUD. -1 when it has no magazine.
func get_current_magazine() -> int:
	var weapon: Weapon = _player.get_active_weapon()
	if weapon == null or not weapon.is_ranged or not _uses_magazine(weapon):
		return -1
	return weapon.get_current_magazine()

func is_reloading() -> bool:
	return _is_reloading

func _on_weapon_swapped(_player_node: Node) -> void:
	if _is_reloading and _reload_weapon:
		EventBus.reload_interrupted.emit(_reload_weapon)
	_is_reloading = false
	_is_cycling = false
	_cycle_timer = 0.0
	_reload_weapon = null

## Stops a reload in progress on this weapon (e.g. its magazine was filled
## another way). The HUD hides its RELOADING label via reload_interrupted.
func cancel_reload(weapon: Weapon) -> void:
	if not _is_reloading or _reload_weapon != weapon:
		return
	_is_reloading = false
	_reload_weapon = null
	EventBus.reload_interrupted.emit(weapon)

func try_attack(aimed: bool = false) -> void:
	var weapon: Weapon = _player.get_active_weapon()
	if weapon == null or not weapon.is_ranged:
		return
	if _is_cycling or _cooldown_remaining > 0.0:
		return
	if _is_reloading:
		# Pump shotgun: firing mid-reload stops the reload, if a shell is loaded.
		if weapon.fire_mode == Constants.FireMode.PUMP_ACTION and _uses_magazine(weapon) and weapon.get_current_magazine() > 0:
			interrupt_pump_reload()
		else:
			return
	if _uses_magazine(weapon) and weapon.get_current_magazine() <= 0:
		if AmmoInventory.get_reserve(weapon.ammo_type) > 0:
			_start_reload(weapon)
		else:
			_dry_click()
		return
	if weapon.fire_mode != Constants.FireMode.FULL_AUTO:
		_fire_one(weapon, aimed)  # FULL_AUTO fires from try_attack_held() instead
		var st := _stance() if aimed else null
		if st and st.dump_magazine and _uses_magazine(weapon) and _player.weapon_stance.is_ready(st):
			_player.weapon_stance.start_cooldown(st)
			_dump_remaining = weapon.get_current_magazine()
			_dump_timer = st.shot_interval

## Called every physics frame while the attack input is held.
func try_attack_held(aimed: bool = false) -> void:
	var weapon: Weapon = _player.get_active_weapon()
	if weapon == null or not weapon.is_ranged or weapon.fire_mode != Constants.FireMode.FULL_AUTO:
		return
	if _is_reloading or _is_cycling or _full_auto_timer > 0.0:
		return
	if _uses_magazine(weapon) and weapon.get_current_magazine() <= 0:
		return
	_fire_one(weapon, aimed)
	var interval := 1.0 / weapon.fire_rate if weapon.fire_rate > 0.0 else fire_cooldown
	var st := _stance() if aimed else null
	_full_auto_timer = interval / _player.get_action_speed_multiplier() / (st.fire_rate_multiplier if st else 1.0)

func _dry_click() -> void:
	_cooldown_remaining = DRY_CLICK_COOLDOWN
	AudioManager.play_at(SoundLib.library.dry_click, _player.global_position)

func _fire_one(weapon: Weapon, aimed: bool) -> void:
	if _uses_magazine(weapon):
		weapon.current_magazine = weapon.get_current_magazine() - 1
	# Section 12: Instinct -> "+1% Attack/Cast speed per point" divides the base cooldown.
	var st := _stance() if aimed else null
	_cooldown_remaining = fire_cooldown / _player.get_action_speed_multiplier() / (st.fire_rate_multiplier if st else 1.0)
	_fire(weapon, aimed)

	match weapon.fire_mode:
		Constants.FireMode.BOLT_ACTION, Constants.FireMode.LEVER_ACTION, \
		Constants.FireMode.SINGLE_ACTION, Constants.FireMode.PUMP_ACTION:
			if weapon.cycle_time > 0.0:
				_is_cycling = true
				_cycle_timer = weapon.cycle_time
		Constants.FireMode.SEMI_AUTO:
			var draw := weapon.get_draw_time()  # bows only - 0 for semi-auto guns
			if draw > 0.0:
				_is_cycling = true
				_cycle_timer = draw

	# Rapid Fire / Fan the Hammer: a fixed shot interval replaces draw and cycling.
	if st and st.shot_interval > 0.0:
		_is_cycling = false
		_cycle_timer = 0.0
		_cooldown_remaining = st.shot_interval / _player.get_action_speed_multiplier()

	if _uses_magazine(weapon) and weapon.get_current_magazine() <= 0:
		_dump_remaining = 0
		_start_reload(weapon)
	EventBus.ammo_changed.emit(weapon.ammo_type, AmmoInventory.get_reserve(weapon.ammo_type))

func _start_reload(weapon: Weapon) -> void:
	if not _uses_magazine(weapon) or _is_reloading:
		return
	if AmmoInventory.get_reserve(weapon.ammo_type) <= 0:
		return
	_is_reloading = true
	_reload_weapon = weapon
	_reload_timer = weapon.cycle_time if weapon.reload_per_shell else weapon.reload_time
	EventBus.reload_started.emit(weapon)
	var snd: AudioStream
	match weapon.fire_mode:
		Constants.FireMode.PUMP_ACTION:
			snd = SoundLib.library.shotgun_reload_start
		Constants.FireMode.BOLT_ACTION:
			snd = SoundLib.library.bolt_cycle
		Constants.FireMode.LEVER_ACTION:
			snd = SoundLib.library.lever_cycle
		_:
			snd = SoundLib.get_reload_sound(weapon.ammo_type)
	AudioManager.play_at(snd, _player.global_position)

func _finish_reload(weapon: Weapon) -> void:
	var needed := weapon.magazine_size - weapon.get_current_magazine()
	if weapon.reload_per_shell:
		# One shell per tick of cycle_time until full or the reserve runs out.
		if needed > 0 and AmmoInventory.consume(weapon.ammo_type, 1):
			weapon.current_magazine = weapon.get_current_magazine() + 1
			needed -= 1
			AudioManager.play_at(SoundLib.library.shotgun_shell_insert, _player.global_position)
		if needed <= 0 or AmmoInventory.get_reserve(weapon.ammo_type) <= 0:
			_end_reload(weapon)
			AudioManager.play_at(SoundLib.library.shotgun_reload_finish, _player.global_position)
		else:
			_reload_timer = weapon.cycle_time
		EventBus.ammo_changed.emit(weapon.ammo_type, AmmoInventory.get_reserve(weapon.ammo_type))
		return
	var to_load := mini(needed, AmmoInventory.get_reserve(weapon.ammo_type))
	AmmoInventory.consume(weapon.ammo_type, to_load)
	weapon.current_magazine = weapon.get_current_magazine() + to_load
	_end_reload(weapon)
	EventBus.ammo_changed.emit(weapon.ammo_type, AmmoInventory.get_reserve(weapon.ammo_type))

func _end_reload(weapon: Weapon) -> void:
	_is_reloading = false
	_reload_weapon = null
	EventBus.reload_finished.emit(weapon)

## R key.
func try_manual_reload() -> void:
	var weapon: Weapon = _player.get_active_weapon()
	if weapon == null or not weapon.is_ranged or not _uses_magazine(weapon):
		return
	if _is_reloading or weapon.get_current_magazine() >= weapon.magazine_size:
		return
	_start_reload(weapon)

## Pump shotgun only: stop a shell-by-shell reload so it can fire, if at
## least one shell is in.
func interrupt_pump_reload() -> void:
	if not _is_reloading:
		return
	var weapon: Weapon = _player.get_active_weapon()
	if weapon == null or weapon.fire_mode != Constants.FireMode.PUMP_ACTION:
		return
	if weapon.get_current_magazine() > 0:
		_is_reloading = false
		_reload_weapon = null
		EventBus.reload_interrupted.emit(weapon)

func _physics_process(delta: float) -> void:
	var st := _stance()
	_aim_time = _aim_time + delta if st else 0.0
	if st == null:
		_brace_spent = false
	if _dump_remaining > 0:
		_dump_timer -= delta
		var weapon: Weapon = _player.get_active_weapon()
		if weapon == null or not weapon.is_ranged or _is_reloading:
			_dump_remaining = 0
		elif _dump_timer <= 0.0:
			_dump_remaining -= 1
			_dump_timer = st.shot_interval if st else 0.1
			_fire_one(weapon, true)
	if _cooldown_remaining > 0.0:
		_cooldown_remaining -= delta
	if _full_auto_timer > 0.0:
		_full_auto_timer -= delta
	if _cycle_timer > 0.0:
		_cycle_timer -= delta
		if _cycle_timer <= 0.0:
			_is_cycling = false
	if _is_reloading:
		_reload_timer -= delta
		if _reload_timer <= 0.0 and _reload_weapon:
			_finish_reload(_reload_weapon)

func _fire(weapon: Weapon, aimed: bool = false) -> void:
	var damage_type: Constants.DamageType = weapon.infused_damage_type if weapon.infused_damage_type != -1 else weapon.native_damage_type
	var st := _stance() if aimed else null
	var motion_value := base_motion_value * (AIMED_DAMAGE_MULTIPLIER if aimed else 1.0)
	var pellets := maxi(weapon.pellet_count, 1)
	var spread := weapon.pellet_spread_degrees * (AIMED_SPREAD_MULTIPLIER if aimed else 1.0)
	if st:
		motion_value *= st.damage_multiplier * get_aim_multiplier()
		spread = spread * st.spread_multiplier + st.spread_add_degrees
	_aim_time = 0.0
	var socket_transform: Transform3D = _player.weapon_socket.global_transform

	# Steady Aim: increased crit chance for this shot only.
	var original_crit_bonus := _player.stat_sheet.finesse_crit_bonus
	if st and st.crit_chance_increase > 0.0:
		_player.stat_sheet.finesse_crit_bonus = (1.0 + original_crit_bonus) * (1.0 + st.crit_chance_increase) - 1.0

	var cosmetic := false
	if st and st.rain_radius > 0.0 and _player.weapon_stance.is_ready(st):
		_player.weapon_stance.start_cooldown(st)
		_fire_rain(weapon, st, motion_value, damage_type)
		pellets = 0
	elif st and st.braced_cone_shot and not _brace_spent and _player.weapon_stance.is_ready(st):
		_brace_spent = true
		_player.weapon_stance.start_cooldown(st)
		_cone_shot(weapon, st, motion_value, weapon.pellet_spread_degrees * st.spread_multiplier, damage_type)
		cosmetic = true

	# One shot's damage is split across the pellets; each rolls its own crit.
	for i in range(pellets):
		var hit := weapon.roll_damage(motion_value / pellets, _player.stat_sheet)

		var projectile: Projectile = PROJECTILE_SCENE.instantiate()
		projectile.damage_amount = hit["final_damage"]
		projectile.is_critical = hit["is_critical"]
		projectile.damage_type = damage_type
		projectile.source = _player
		projectile.speed = projectile_speed
		projectile.cosmetic = cosmetic
		projectile.damage_modifier = _damage_modifier.bind(st)
		if st:
			projectile.pierce = st.pierce
			projectile.on_hit = _on_projectile_hit.bind(st)
		_player.get_tree().current_scene.add_child(projectile)

		var spawn_transform := socket_transform
		if spread > 0.0:
			var spread_rad := deg_to_rad(spread)
			var fire_dir := (-socket_transform.basis.z).normalized()
			# Point inside an ellipse (full spread sideways, half up/down), so no
			# pellet ever lands outside the weapon's stated half-angle.
			var radius := sqrt(randf())
			var theta := randf() * TAU
			fire_dir = fire_dir.rotated(Vector3.UP, cos(theta) * radius * spread_rad)
			fire_dir = fire_dir.rotated(socket_transform.basis.x.normalized(), sin(theta) * radius * spread_rad * 0.5)
			spawn_transform.basis = Basis.looking_at(fire_dir.normalized(), Vector3.UP)
		projectile.global_transform = spawn_transform

	_player.stat_sheet.finesse_crit_bonus = original_crit_bonus
	AudioManager.play_at(SoundLib.get_fire_sound(weapon.ammo_type), _player.global_position)
	_play_fire_animation(weapon)

## Point Blank by distance, plus Tracer Round's bonus on a marked enemy.
func _damage_modifier(enemy: Enemy, st: RangedStanceBehavior) -> float:
	var multiplier := 1.0
	if st and st.point_blank_max_multiplier > 1.0:
		var distance := enemy.global_position.distance_to(_player.global_position)
		var closeness := clampf((st.point_blank_far - distance) / maxf(st.point_blank_far - st.point_blank_near, 0.01), 0.0, 1.0)
		multiplier *= lerpf(1.0, st.point_blank_max_multiplier, closeness)
	if enemy.status_effects and enemy.status_effects.has_effect("marked"):
		multiplier *= 1.0 + _mark_bonus
	return multiplier

## Suppression stacks, Full Auto Burst stagger, Tracer Round marking.
func _on_projectile_hit(enemy: Enemy, _damage: float, st: RangedStanceBehavior) -> void:
	if not is_instance_valid(enemy) or enemy.status_effects == null:
		return
	for i in st.slow_stacks_per_hit:
		enemy.status_effects.apply_effect("suppressed", _player)
	if st.stagger_hits > 0:
		var id := enemy.get_instance_id()
		var now := Time.get_ticks_msec()
		var recent: Array = _stagger_log.get(id, []).filter(func(t): return now - t <= st.stagger_window * 1000.0)
		recent.append(now)
		if recent.size() >= st.stagger_hits:
			recent.clear()
			enemy.interrupt_attack()
			if enemy.stance:
				enemy.stance.apply_parry_damage(STAGGER_COMPOSURE_DAMAGE)
		_stagger_log[id] = recent
	if st.mark_duration > 0.0 and not _has_live_mark():
		enemy.status_effects.apply_timed_effect("marked", st.mark_duration)
		_mark_bonus = st.mark_damage_bonus

func _has_live_mark() -> bool:
	for node in get_tree().get_nodes_in_group("enemy"):
		var enemy := node as Enemy
		if enemy and enemy.health.is_alive() and enemy.status_effects and enemy.status_effects.has_effect("marked"):
			return true
	return false

## Pump Brace: the braced shot hits every enemy in its cone (spread_multiplier
## times the hip-fire spread - "double spread width") for full damage.
func _cone_shot(weapon: Weapon, st: RangedStanceBehavior, motion_value: float, half_angle: float, damage_type: Constants.DamageType) -> void:
	var origin := _player.camera.global_position
	var forward := -_player.camera.global_transform.basis.z
	for node in get_tree().get_nodes_in_group("enemy"):
		var enemy := node as Enemy
		if enemy == null or not enemy.health.is_alive():
			continue
		var to_enemy := enemy.global_position + Vector3.UP - origin
		if to_enemy.length() > st.cone_range or rad_to_deg(forward.angle_to(to_enemy.normalized())) > half_angle + 5.0:
			continue
		if not _player.melee_attack._has_line_of_sight(origin, enemy.global_position + Vector3.UP, enemy):
			continue
		var hit := weapon.roll_damage(motion_value, _player.stat_sheet)
		_direct_hit(enemy, hit["final_damage"], damage_type, hit["is_critical"])

## Longbow Rain of Arrows: volleys on the spot under the crosshair.
func _fire_rain(weapon: Weapon, st: RangedStanceBehavior, motion_value: float, damage_type: Constants.DamageType) -> void:
	var origin := _player.camera.global_position
	var forward := -_player.camera.global_transform.basis.z
	var space := _player.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(origin, origin + forward * RAIN_TARGET_RANGE)
	query.exclude = [_player.get_rid()]
	var hit := space.intersect_ray(query)
	var target: Vector3 = hit["position"] if not hit.is_empty() else origin + forward * RAIN_TARGET_RANGE
	var ground := space.intersect_ray(PhysicsRayQueryParameters3D.create(target + Vector3.UP, target + Vector3.DOWN * 30.0))
	if not ground.is_empty():
		target = ground["position"]
	var rain := ArrowRain.new()
	_player.get_tree().current_scene.add_child(rain)
	rain.global_position = target
	rain.launch(st.rain_radius, st.rain_waves, _on_rain_hit.bind(weapon, motion_value, damage_type))

func _on_rain_hit(enemy: Enemy, weapon: Weapon, motion_value: float, damage_type: Constants.DamageType) -> void:
	if not is_instance_valid(_player):
		return
	var hit := weapon.roll_damage(motion_value, _player.stat_sheet)
	_direct_hit(enemy, hit["final_damage"], damage_type, hit["is_critical"])

func _direct_hit(enemy: Enemy, amount: float, damage_type: Constants.DamageType, is_critical: bool) -> void:
	if not enemy.take_damage(amount, damage_type, false, true):
		return
	if enemy.stance:
		enemy.stance.apply_attack_stance_damage(amount, damage_type)
	enemy.flash_hit()
	EventBus.damage_dealt.emit(_player, enemy, amount, damage_type, false, is_critical)
	enemy.status_effects.roll_gear_ailments(_player, amount)
	EventBus.hit_landed.emit(is_critical, false, not enemy.health.is_alive())

func _play_fire_animation(_weapon: Weapon) -> void:
	var rig := _player.arm_rig
	if rig == null:
		return
	var mult := (BOW_FIRE_DURATION_MULT if rig.get_family() == &"bow" else 1.0) / _player.get_action_speed_multiplier()
	rig.play_attack(PlayerArmRig.Attack.FIRE, FIRE_WINDUP * mult, FIRE_STRIKE * mult, FIRE_RECOVERY * mult)
