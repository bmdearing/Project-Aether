extends Area3D
class_name Projectile
## Moving projectile, straight unless `drop_gravity` is set (arrows arc). Spawned by
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
## Downward pull in m/s^2; the shot turns to face its flight path.
var drop_gravity: float = 0.0
var _velocity := Vector3.ZERO
var _launched := false

var damage_amount: float = 0.0
var damage_type: Constants.DamageType = Constants.DamageType.KINETIC
var source: Node
## True for a projectile that is a spell rather than an attack (Evasion:
## spells can't be Dodged, only Deflected). Nothing sets it yet - enemies
## have no spells, only the ranged attack, which spawns attack projectiles.
var is_spell_projectile: bool = false
var is_critical: bool = false  # set by PlayerRangedAttack._fire() - enemy-fired shots leave this false
## Crit damage multiplier, applied when a non-crit player shot hits the head.
var crit_multiplier: float = 1.0
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
## Thrown grenades and pressure javelins: on striking anything, the hit
## goes off as a blast that damages every enemy within blast_radius.
var blast_radius: float = 0.0
## A thrown weapon's own model, carried in place of the bolt mesh, turning
## end over end at spin radians/s.
var model: Node3D
var spin: float = 0.0

@onready var mesh: MeshInstance3D = $MeshInstance3D

func _ready() -> void:
	if model:
		add_child(model)
		if mesh:
			mesh.visible = false
	if hitscan_range > 0.0:
		if mesh:
			mesh.visible = false
	else:
		monitoring = true
		body_entered.connect(_on_body_entered)
		body_exited.connect(_on_body_exited)
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
	var from := global_position
	_move(delta)
	if model and spin != 0.0:
		model.rotate_object_local(Vector3.RIGHT, -spin * delta)
	# Over a staircase, only its drawn steps stop the shot, not the walking ramp.
	if is_instance_valid(_stairs):
		var t := stairs_hit_fraction(_stairs, from, global_position)
		if t >= 0.0:
			global_position = from.lerp(global_position, t)
			if blast_radius > 0.0 and source is Player:
				_blast()
			elif not cosmetic:
				_play_impact_sound(_stairs)
			queue_free()

func _move(delta: float) -> void:
	if drop_gravity <= 0.0:
		global_position += -global_transform.basis.z * speed * delta
		return
	if not _launched:
		_launched = true
		_velocity = -global_transform.basis.z * speed
	_velocity.y -= drop_gravity * delta
	global_position += _velocity * delta
	if absf(_velocity.normalized().y) < 0.99:
		look_at(global_position + _velocity, Vector3.UP)

## The staircase being flown over (its hidden ramp overlapped), if any.
var _stairs: Node3D = null

func _on_body_exited(body: Node3D) -> void:
	if body == _stairs:
		_stairs = null

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group(&"stairs"):
		_stairs = body
		return
	if cosmetic:
		queue_free()
		return
	if body is Enemy and _pierced.has(body.get_instance_id()):
		return
	if not is_instance_valid(source):
		source = null  # the shooter died while this was in flight
	if blast_radius > 0.0 and source is Player:
		_blast()
		queue_free()
		return
	_play_impact_sound(body)
	if source is Player:
		_hit_enemy(body as Enemy)
		if body is CrackedWall:
			(body as CrackedWall).strike()
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
	# A head hit always crits.
	var crit := is_critical
	if is_critical_spot and not crit and source is Player:
		final_amount *= crit_multiplier
		crit = true
	if damage_modifier.is_valid():
		final_amount *= damage_modifier.call(enemy)
	if not enemy.take_damage(final_amount, damage_type, false, true):
		return  # dodged
	if enemy.stance:
		enemy.stance.apply_attack_stance_damage(final_amount, damage_type)
	EventBus.damage_dealt.emit(source, enemy, final_amount, damage_type, false, crit)
	if enemy.status_effects:
		enemy.status_effects.roll_gear_ailments(source, final_amount, damage_type)
	if on_hit.is_valid():
		on_hit.call(enemy, final_amount)
	if source is Player:
		EventBus.hit_landed.emit(crit, is_critical_spot, not enemy.health.is_alive())
		if not is_spell_projectile:
			BloodFx.hit(enemy, -global_transform.basis.z, 0.6 * (1.5 if is_critical_spot else 1.0), not enemy.health.is_alive())

func _blast() -> void:
	var at := global_position
	var scene := get_tree().current_scene
	var color: Color = Constants.DAMAGE_TYPE_COLOR.get(damage_type, Color(1.0, 0.6, 0.2))
	SpellFx.flash(scene, at, Color(1.6, 1.1, 0.6), blast_radius * 0.9, 0.25)
	SpellFx.burst(scene, at, color, 40, Vector2(3.0, 7.0), 0.55, Vector2(0.08, 0.2), 180.0, -6.0)
	SpellFx.light_pop(scene, at + Vector3.UP * 0.5, Color(1.0, 0.7, 0.35), 4.0, blast_radius * 2.5, 0.35)
	SpellFx.shockwave(scene, at, blast_radius, color)
	AudioManager.play_at(SoundLib.pick_random(SoundLib.library.explosion) if SoundLib.library else null, at)
	for node in get_tree().get_nodes_in_group("enemy"):
		var enemy := node as Enemy
		if enemy and enemy.health.is_alive() and enemy.distance_to_body(at) <= blast_radius:
			_hit_enemy(enemy)

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

## How far past a staircase's ramp a hitscan ray checks for steps.
const STAIRS_PROBE := 8.0

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
		if body and body.is_in_group(&"stairs"):
			# The hidden ramp: carry on until the ray meets a drawn step, if it does.
			var ray_end := hitscan_origin + dir * hitscan_range
			var probe_end: Vector3 = hit["position"] + dir * STAIRS_PROBE
			var t := stairs_hit_fraction(body, hit["position"], probe_end)
			if t < 0.0:
				exclude.append((body as CollisionObject3D).get_rid())
				end = ray_end
				continue
			hit["position"] = (hit["position"] as Vector3).lerp(probe_end, t)
		global_position = hit["position"]
		end = hit["position"]
		if body == null or cosmetic:
			break
		_play_impact_sound(body)
		if source is Player:
			_hit_enemy(body as Enemy, dir)
			if body is CrackedWall:
				(body as CrackedWall).strike()
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

## True when `point` is inside one of a staircase's drawn steps (or the
## raised floor behind its foot), not just under the hidden walking ramp.
## Reads the step layout GeneratedMap._build_stairs() leaves in meta.
static func stairs_solid_at(stairs: Node3D, point: Vector3) -> bool:
	var out: Vector3 = stairs.get_meta(&"out", Vector3.FORWARD)
	var rise := float(stairs.get_meta(&"rise", 0.0))
	var steps := int(stairs.get_meta(&"steps", 1))
	var run := float(stairs.get_meta(&"run", 0.4))
	var local := point - stairs.global_position
	var along := local.dot(out)
	if along < 0.0:
		return local.y <= rise
	if along >= steps * run:
		return false
	return local.y <= (steps - floorf(along / run)) * rise / steps

## The first point from `from` to `to` inside a drawn step, as a fraction of
## the way (sampled every few cm), or -1 when the segment clears them.
static func stairs_hit_fraction(stairs: Node3D, from: Vector3, to: Vector3) -> float:
	var samples := maxi(ceili(from.distance_to(to) / 0.04), 1)
	for i in samples + 1:
		var t := float(i) / samples
		if stairs_solid_at(stairs, from.lerp(to, t)):
			return t
	return -1.0
