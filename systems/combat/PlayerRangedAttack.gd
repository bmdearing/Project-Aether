extends Node
class_name PlayerRangedAttack
## Ranged attack: spawns Projectile.tscn instances moving forward from
## WeaponSocket. No windup/strike states like PlayerMeleeAttack - hit
## registration is still a single instant fire-and-cooldown.
## _play_fire_animation() layers a purely cosmetic pose tween on
## PlayerArmRig on top of that, via the same play_attack_swing()
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

## Same minimal-table-plus-DEFAULT convention as PlayerMeleeAttack's own
## per-weapon-type dicts - Bow gets a fuller draw-then-release motion,
## anything unmapped (Service Pistol) gets a sharp recoil kick instead.
const WEAPON_TYPE_FIRE_POSE := {
	"Bow": PlayerArmRig.PoseSet.BOW_RELEASE,
}
const DEFAULT_FIRE_POSE := PlayerArmRig.PoseSet.RECOIL
const WEAPON_TYPE_FIRE_DURATION_MULT := {
	"Bow": 1.6,
}
const FIRE_WINDUP := 0.06
const FIRE_STRIKE := 0.06
const FIRE_RECOVERY := 0.16
const WEAPON_TYPE_FIRE_INTENSITY := {
	"Bow": 1.1,
}
const DEFAULT_FIRE_INTENSITY := 0.8

@export var fire_cooldown: float = 0.4
## Stands in for a "Basic Shot" skill's motion value - no skill/Tome
## system exists yet (Section 11: motion values live on skills).
@export var base_motion_value: float = 1.0
@export var projectile_speed: float = 25.0

## Right-click-hold aim (WeaponStance) rewards firing with a flat damage
## bonus, and now also halves the weapon's spread.
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
	_full_auto_timer = interval / _player.get_action_speed_multiplier()

func _dry_click() -> void:
	_cooldown_remaining = DRY_CLICK_COOLDOWN
	AudioManager.play_at(SoundLib.library.dry_click, _player.global_position)

func _fire_one(weapon: Weapon, aimed: bool) -> void:
	if _uses_magazine(weapon):
		weapon.current_magazine = weapon.get_current_magazine() - 1
	# Section 12: Instinct -> "+1% Attack/Cast speed per point" divides the base cooldown.
	_cooldown_remaining = fire_cooldown / _player.get_action_speed_multiplier()
	_fire(weapon, aimed)

	match weapon.fire_mode:
		Constants.FireMode.BOLT_ACTION, Constants.FireMode.LEVER_ACTION, \
		Constants.FireMode.SINGLE_ACTION, Constants.FireMode.PUMP_ACTION:
			if weapon.cycle_time > 0.0:
				_is_cycling = true
				_cycle_timer = weapon.cycle_time

	if _uses_magazine(weapon) and weapon.get_current_magazine() <= 0:
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
	var motion_value := base_motion_value * (AIMED_DAMAGE_MULTIPLIER if aimed else 1.0)
	var pellets := maxi(weapon.pellet_count, 1)
	var spread := weapon.pellet_spread_degrees * (AIMED_SPREAD_MULTIPLIER if aimed else 1.0)
	var socket_transform: Transform3D = _player.weapon_socket.global_transform

	# One shot's damage is split across the pellets; each rolls its own crit.
	for i in range(pellets):
		var hit := weapon.roll_damage(motion_value / pellets, _player.stat_sheet)

		var projectile: Projectile = PROJECTILE_SCENE.instantiate()
		projectile.damage_amount = hit["final_damage"]
		projectile.is_critical = hit["is_critical"]
		projectile.damage_type = damage_type
		projectile.source = _player
		projectile.speed = projectile_speed
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

	AudioManager.play_at(SoundLib.get_fire_sound(weapon.ammo_type), _player.global_position)
	_play_fire_animation(weapon)

func _play_fire_animation(weapon: Weapon) -> void:
	var rig := _player.arm_rig
	if rig == null:
		return
	var pose_set: PlayerArmRig.PoseSet = WEAPON_TYPE_FIRE_POSE.get(weapon.weapon_type, DEFAULT_FIRE_POSE)
	var duration_mult: float = WEAPON_TYPE_FIRE_DURATION_MULT.get(weapon.weapon_type, 1.0)
	var intensity: float = WEAPON_TYPE_FIRE_INTENSITY.get(weapon.weapon_type, DEFAULT_FIRE_INTENSITY)
	var action_speed := _player.get_action_speed_multiplier()
	rig.play_attack_swing(
		pose_set,
		FIRE_WINDUP * duration_mult / action_speed,
		FIRE_STRIKE * duration_mult / action_speed,
		FIRE_RECOVERY * duration_mult / action_speed,
		intensity
	)
