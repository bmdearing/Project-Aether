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
## Bullets ricochet off walls; arrows and bolts thunk; anything else (spells,
## enemy bolts) makes no wall sound.
enum ImpactSound { NONE, BULLET, ARROW }
var impact_sound: ImpactSound = ImpactSound.NONE
var damage_modifier: Callable
var on_hit: Callable
var cosmetic: bool = false
var _pierced: Dictionary = {}
## Hitscan shots (Weapon.is_hitscan()) resolve on their first physics frame:
## a ray from hitscan_origin (the camera) along the shot's direction, then a
## tracer from the muzzle to whatever it struck.
var hitscan_range: float = 0.0
var hitscan_origin: Vector3
const TRACER_TIME := 0.09

@onready var mesh: MeshInstance3D = $MeshInstance3D

func _ready() -> void:
	if hitscan_range > 0.0:
		if mesh:
			mesh.visible = false
	else:
		monitoring = true
		body_entered.connect(_on_body_entered)
	get_tree().create_timer(lifetime).timeout.connect(queue_free)
	if mesh:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Constants.DAMAGE_TYPE_COLOR.get(damage_type, Color.WHITE)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mesh.material_override = mat

func _physics_process(delta: float) -> void:
	if hitscan_range > 0.0:
		_resolve_hitscan()
		return
	global_position += -global_transform.basis.z * speed * delta

func _on_body_entered(body: Node3D) -> void:
	if cosmetic:
		queue_free()
		return
	if body is Enemy and _pierced.has(body.get_instance_id()):
		return
	_play_impact_sound(body)
	if not is_instance_valid(source):
		source = null  # the shooter died while this was in flight
	if source is Player:
		_hit_enemy(body as Enemy)
	else:
		_hit_player(body as Player)
	if body is Enemy and _pierced.size() <= pierce:
		_pierced[body.get_instance_id()] = true
		if _pierced.size() <= pierce:
			return
	queue_free()

func _hit_enemy(enemy: Enemy, aim_dir: Vector3 = Vector3.ZERO) -> void:
	if enemy == null:
		return
	var is_critical_spot := enemy.is_critical_spot_point(global_position)
	if not is_critical_spot and aim_dir != Vector3.ZERO:
		is_critical_spot = enemy.is_critical_spot_aimed(hitscan_origin, aim_dir)
	var final_amount := damage_amount * enemy.critical_spot_multiplier if is_critical_spot else damage_amount
	if damage_modifier.is_valid():
		final_amount *= damage_modifier.call(enemy)
	if not enemy.take_damage(final_amount, damage_type, false, true):
		return  # dodged
	if enemy.stance:
		enemy.stance.apply_attack_stance_damage(final_amount, damage_type)
	EventBus.damage_dealt.emit(source, enemy, final_amount, damage_type, false, is_critical)
	if enemy.status_effects:
		enemy.status_effects.roll_gear_ailments(source, final_amount, damage_type)
	if on_hit.is_valid():
		on_hit.call(enemy, final_amount)
	if source is Player:
		EventBus.hit_landed.emit(is_critical, is_critical_spot, not enemy.health.is_alive())

func _hit_player(player: Player) -> void:
	if player == null:
		return
	var parried: bool = source != null and player.parry_handler and player.parry_handler.attempt_parry(source, player.ward)
	if not parried:
		player.take_damage(damage_amount, damage_type, source, Player.HitKind.SPELL if is_spell_projectile else Player.HitKind.ATTACK)
		if is_instance_valid(source) and source is Enemy and (source as Enemy).rarity_component:
			(source as Enemy).rarity_component.on_hit_player(player, damage_amount)
	EventBus.enemy_attack_resolved.emit(source, player, true, parried)

func _play_impact_sound(body: Node) -> void:
	var surface := _get_surface_type(body)
	if surface != "flesh":
		match impact_sound:
			ImpactSound.NONE:
				return
			ImpactSound.ARROW:
				surface = "wood"
	AudioManager.play_at(SoundLib.get_impact_sound(surface), global_position, -3.0)

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

func _resolve_hitscan() -> void:
	var dir := -global_transform.basis.z.normalized()
	var space := get_world_3d().direct_space_state
	var exclude: Array[RID] = []
	if is_instance_valid(source) and source is CollisionObject3D:
		exclude.append((source as CollisionObject3D).get_rid())
	var end := hitscan_origin + dir * hitscan_range
	var muzzle := global_position
	# Walks the ray through pierced enemies until something stops it.
	while true:
		var query := PhysicsRayQueryParameters3D.create(hitscan_origin, end, collision_mask)
		query.exclude = exclude
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			break
		var body := hit["collider"] as Node3D
		global_position = hit["position"]
		end = hit["position"]
		if body == null or cosmetic:
			break
		_play_impact_sound(body)
		if source is Player:
			_hit_enemy(body as Enemy, dir)
		if body is Enemy and _pierced.size() < pierce:
			_pierced[body.get_instance_id()] = true
			exclude.append((body as Enemy).get_rid())
			end = hitscan_origin + dir * hitscan_range
			continue
		break
	_spawn_tracer(muzzle, end)
	queue_free()

func _spawn_tracer(from: Vector3, to: Vector3) -> void:
	var length := from.distance_to(to)
	if length < 0.05:
		return
	var tracer := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.025, 0.025, length)
	tracer.mesh = box
	tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var color: Color = Constants.DAMAGE_TYPE_COLOR.get(damage_type, Color.WHITE)
	mat.albedo_color = Color(color.r, color.g, color.b, 0.9).lerp(Color(1, 0.95, 0.8, 0.9), 0.5)
	tracer.material_override = mat
	get_tree().current_scene.add_child(tracer)
	tracer.global_position = (from + to) * 0.5
	tracer.look_at_from_position(tracer.global_position, to, Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.RIGHT)
	var tween := tracer.create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, TRACER_TIME)
	tween.tween_callback(tracer.queue_free)
