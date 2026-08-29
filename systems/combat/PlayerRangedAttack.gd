extends Node
class_name PlayerRangedAttack
## Sidearm-slot ranged attack: spawns a Projectile.tscn instance moving
## forward from WeaponSocket. No windup/strike states like
## PlayerMeleeAttack - there's no swing - just a fire cooldown.
##
## _fire() calls Weapon.predict_damage() rather than wiring
## DamageCalculator itself (used to inline the exact same call) - same
## centralization Ability.predict_damage() does, so CharacterScreen's
## "Predicted Ranged Damage" readout can't drift from what firing
## actually deals.

const PROJECTILE_SCENE := preload("res://entities/projectile/Projectile.tscn")

@export var fire_cooldown: float = 0.4
## Stands in for a "Basic Shot" skill's motion value - same reasoning as
## PlayerMeleeAttack.base_motion_value (Section 11: motion values live on
## skills, no skill/Tome system exists yet).
@export var base_motion_value: float = 1.0
@export var projectile_speed: float = 25.0

var _cooldown_remaining: float = 0.0
var _player: Player

func _ready() -> void:
	_player = get_parent()

func try_attack() -> void:
	if _cooldown_remaining > 0.0:
		return
	var weapon: Weapon = _player.equipment.sidearm_weapon if _player.equipment else null
	if weapon == null:
		return
	_cooldown_remaining = fire_cooldown
	_fire(weapon)

func _physics_process(delta: float) -> void:
	if _cooldown_remaining > 0.0:
		_cooldown_remaining -= delta

func _fire(weapon: Weapon) -> void:
	var damage_type: Constants.DamageType = weapon.infused_damage_type if weapon.infused_damage_type != -1 else weapon.native_damage_type
	var final_damage: float = weapon.predict_damage(base_motion_value, _player.stat_sheet)

	var projectile: Projectile = PROJECTILE_SCENE.instantiate()
	projectile.damage_amount = final_damage
	projectile.damage_type = damage_type
	projectile.source = _player
	projectile.speed = projectile_speed
	_player.get_tree().current_scene.add_child(projectile)
	projectile.global_transform = _player.weapon_socket.global_transform
