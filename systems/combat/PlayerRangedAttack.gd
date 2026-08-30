extends Node
class_name PlayerRangedAttack
## Ranged attack: spawns a Projectile.tscn instance moving forward from
## WeaponSocket. No windup/strike states like PlayerMeleeAttack - hit
## registration is still a single instant fire-and-cooldown, unchanged.
## _play_fire_animation() (2026-08-30 later still, user feedback: "the
## animations are all the same for all of the weapons" - ranged weapons
## had NO animation at all before this) layers a purely cosmetic pose
## tween on PlayerArmRig on top of that, via the same play_attack_swing()
## PlayerMeleeAttack itself uses - it doesn't gate or delay the shot.

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

## User request (2026-08-30): "This will also work for ranged weapons to
## aim their weapons" - WeaponStance's right-click hold zooms the camera
## (see WeaponStance.gd) and this rewards actually firing while aimed,
## same "preps you for heavier... attacks" framing as the melee specials.
## No spread/accuracy system exists to tighten instead (PlayerRangedAttack
## already fires a perfectly straight shot every time), so this is a flat
## damage bonus rather than a real precision mechanic.
const AIMED_DAMAGE_MULTIPLIER := 1.4

var _cooldown_remaining: float = 0.0
var _player: Player

func _ready() -> void:
	_player = get_parent()

func try_attack(aimed: bool = false) -> void:
	if _cooldown_remaining > 0.0:
		return
	var weapon: Weapon = _player.get_active_weapon()
	if weapon == null:
		return
	# Section 12: Instinct -> "+1% Attack/Cast speed per point" divides the base cooldown.
	_cooldown_remaining = fire_cooldown / _player.get_action_speed_multiplier()
	_fire(weapon, aimed)

func _physics_process(delta: float) -> void:
	if _cooldown_remaining > 0.0:
		_cooldown_remaining -= delta

func _fire(weapon: Weapon, aimed: bool = false) -> void:
	var damage_type: Constants.DamageType = weapon.infused_damage_type if weapon.infused_damage_type != -1 else weapon.native_damage_type
	var motion_value := base_motion_value * (AIMED_DAMAGE_MULTIPLIER if aimed else 1.0)
	var hit := weapon.roll_damage(motion_value, _player.stat_sheet)

	var projectile: Projectile = PROJECTILE_SCENE.instantiate()
	projectile.damage_amount = hit["final_damage"]
	projectile.is_critical = hit["is_critical"]
	projectile.damage_type = damage_type
	projectile.source = _player
	projectile.speed = projectile_speed
	_player.get_tree().current_scene.add_child(projectile)
	projectile.global_transform = _player.weapon_socket.global_transform

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
