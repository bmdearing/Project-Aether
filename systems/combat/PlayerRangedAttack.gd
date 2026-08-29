extends Node
class_name PlayerRangedAttack
## Sidearm-slot ranged attack: spawns a Projectile.tscn instance moving
## forward from WeaponSocket. No windup/strike states like
## PlayerMeleeAttack - there's no swing - just a fire cooldown.

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
	var main_stat: Constants.Stat = Constants.DAMAGE_TYPE_MAIN_STAT.get(damage_type, Constants.Stat.STRENGTH)
	var stat_value: float = _player.stat_sheet.get_stat(main_stat) if _player.stat_sheet else 0.0
	var mastery: float = _player.stat_sheet.get_mastery(damage_type) if _player.stat_sheet else 0.0

	# No Slate/gear stat aggregation into StatSheet yet - same gap flagged
	# on PlayerMeleeAttack._deal_damage(), both pools stay empty for now.
	var result: DamageCalculator.DamageResult = DamageCalculator.calculate(
		weapon.base_damage, base_motion_value, stat_value, weapon.scaling_grade,
		0.5, mastery, [], [], damage_type
	)

	var projectile: Projectile = PROJECTILE_SCENE.instantiate()
	projectile.damage_amount = result.final_damage
	projectile.damage_type = damage_type
	projectile.source = _player
	projectile.speed = projectile_speed
	_player.get_tree().current_scene.add_child(projectile)
	projectile.global_transform = _player.weapon_socket.global_transform
