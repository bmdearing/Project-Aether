extends Node
class_name PlayerRangedAttack
## Ranged attack: spawns a Projectile.tscn instance moving forward from
## WeaponSocket. No windup/strike states like PlayerMeleeAttack - just a
## fire cooldown.

const PROJECTILE_SCENE := preload("res://entities/projectile/Projectile.tscn")

@export var fire_cooldown: float = 0.4
## Stands in for a "Basic Shot" skill's motion value - no skill/Tome
## system exists yet (Section 11: motion values live on skills).
@export var base_motion_value: float = 1.0
@export var projectile_speed: float = 25.0

var _cooldown_remaining: float = 0.0
var _player: Player

func _ready() -> void:
	_player = get_parent()

func try_attack() -> void:
	if _cooldown_remaining > 0.0:
		return
	var weapon: Weapon = _player.get_active_weapon()
	if weapon == null:
		return
	# Section 12: Instinct -> "+1% Attack/Cast speed per point" divides the base cooldown.
	_cooldown_remaining = fire_cooldown / _player.get_action_speed_multiplier()
	_fire(weapon)

func _physics_process(delta: float) -> void:
	if _cooldown_remaining > 0.0:
		_cooldown_remaining -= delta

func _fire(weapon: Weapon) -> void:
	var damage_type: Constants.DamageType = weapon.infused_damage_type if weapon.infused_damage_type != -1 else weapon.native_damage_type
	var hit := weapon.roll_damage(base_motion_value, _player.stat_sheet)

	var projectile: Projectile = PROJECTILE_SCENE.instantiate()
	projectile.damage_amount = hit["final_damage"]
	projectile.is_critical = hit["is_critical"]
	projectile.damage_type = damage_type
	projectile.source = _player
	projectile.speed = projectile_speed
	_player.get_tree().current_scene.add_child(projectile)
	projectile.global_transform = _player.weapon_socket.global_transform
