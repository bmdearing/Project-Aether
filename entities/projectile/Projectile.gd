extends Area3D
class_name Projectile
## Straight-line moving projectile - no gravity/arc. Spawned by
## PlayerRangedAttack or EnemyRangedAttack, which set damage_amount/
## damage_type/source/speed BEFORE add_child() so _ready() sees them,
## then align global_transform to the muzzle after.
##
## Damage is computed once at fire time by the spawner - a weapon swap
## mid-flight can't retroactively change an already-fired shot.
##
## `source` decides what it can hurt: a Player-fired shot damages the
## first Enemy it touches, an Enemy-fired shot damages the Player (and
## can be parried, same as EnemyMeleeAttack's Strike).

@export var speed: float = 25.0
@export var lifetime: float = 3.0

var damage_amount: float = 0.0
var damage_type: Constants.DamageType = Constants.DamageType.KINETIC
var source: Node
## True for a projectile that is a spell rather than an attack (Evasion:
## spells can't be Dodged, only Deflected). Nothing sets it yet - enemies
## have no spells, only the ranged attack, which spawns attack projectiles.
var is_spell_projectile: bool = false
var is_critical: bool = false  # set by PlayerRangedAttack._fire() - enemy-fired shots leave this false
## Aim stance hooks (player shots): extra enemies to pass through, a damage
## multiplier read at impact (enemy -> float), an after-hit callback
## (enemy, damage), and cosmetic pellets that never hit anything.
var pierce: int = 0
var damage_modifier: Callable
var on_hit: Callable
var cosmetic: bool = false
var _pierced: Dictionary = {}

@onready var mesh: MeshInstance3D = $MeshInstance3D

func _ready() -> void:
	monitoring = true
	body_entered.connect(_on_body_entered)
	get_tree().create_timer(lifetime).timeout.connect(queue_free)
	if mesh:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Constants.DAMAGE_TYPE_COLOR.get(damage_type, Color.WHITE)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mesh.material_override = mat

func _physics_process(delta: float) -> void:
	global_position += -global_transform.basis.z * speed * delta

func _on_body_entered(body: Node3D) -> void:
	if cosmetic:
		queue_free()
		return
	if body is Enemy and _pierced.has(body.get_instance_id()):
		return
	AudioManager.play_at(SoundLib.get_impact_sound(_get_surface_type(body)), global_position, -3.0)
	if source is Player:
		_hit_enemy(body as Enemy)
	else:
		_hit_player(body as Player)
	if body is Enemy and _pierced.size() <= pierce:
		_pierced[body.get_instance_id()] = true
		if _pierced.size() <= pierce:
			return
	queue_free()

func _hit_enemy(enemy: Enemy) -> void:
	if enemy == null:
		return
	# Implementation Brief v3.4 Section 3 - this projectile IS the
	# attacking Area3D resolving the hit, checked against the target's
	# HeadZone for overlap (see Enemy.is_critical_spot_hit()'s own header).
	var is_critical_spot := enemy.is_critical_spot_hit(self)
	var final_amount := damage_amount * enemy.critical_spot_multiplier if is_critical_spot else damage_amount
	if damage_modifier.is_valid():
		final_amount *= damage_modifier.call(enemy)
	if not enemy.take_damage(final_amount, damage_type, false, true):
		return  # dodged
	if enemy.stance:
		enemy.stance.apply_attack_stance_damage(final_amount, damage_type)
	EventBus.damage_dealt.emit(source, enemy, final_amount, damage_type, false, is_critical)
	if on_hit.is_valid():
		on_hit.call(enemy, final_amount)
	if source is Player:
		EventBus.hit_landed.emit(is_critical, is_critical_spot, not enemy.health.is_alive())

func _hit_player(player: Player) -> void:
	if player == null:
		return
	var parried: bool = player.parry_handler and player.parry_handler.attempt_parry(source, player.ward)
	if not parried:
		player.take_damage(damage_amount, damage_type, source, Player.HitKind.SPELL if is_spell_projectile else Player.HitKind.ATTACK)
	EventBus.enemy_attack_resolved.emit(source, player, true, parried)

## Which impact sound set to use. Enemies/the player are "flesh"; any
## other body can opt in by joining a "surface_metal"/"surface_wood" group,
## and everything else (level geometry) defaults to stone.
func _get_surface_type(body: Node) -> String:
	if body is Enemy or body is Player:
		return "flesh"
	for surface in ["metal", "wood"]:
		if body.is_in_group("surface_" + surface):
			return surface
	return "stone"
